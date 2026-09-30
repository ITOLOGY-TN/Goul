import MurmurDictionary
import Foundation
import Observation

/// One completed dictation.
struct DictationRun: Codable, Sendable, Identifiable {
    /// Stable identity, so a single run can be deleted without matching on its text.
    ///
    /// Decoded leniently: runs written before this existed have no `id` field, and failing
    /// their whole line would throw away the user's history to add a delete button. Those
    /// get a fresh id on load, which is then persisted the next time the file is rewritten.
    var id: UUID = UUID()

    let date: Date
    let engine: String
    /// How long the key was held.
    let audioSeconds: Double
    /// Release → final text ready. This is the latency you actually feel.
    let processSeconds: Double
    let text: String
    /// Shared by every engine that processed the same recording, so the dashboard can
    /// present them as one side-by-side comparison instead of unrelated rows.
    var group: String?

    /// Dictionary corrections that fired on this transcript. Recorded so history can show
    /// whether the dictionary is actually doing anything, rather than leaving it to faith.
    ///
    /// Optional for backwards compatibility: runs recorded before the dictionary existed
    /// decode with this nil rather than failing the whole line.
    var corrections: [AppliedCorrection]?

    /// Detected language code ("EN"/"FR"). Optional: older runs predate detection.
    var language: String?

    var realtimeFactor: Double { audioSeconds / max(processSeconds, 0.0001) }
    var characters: Int { text.count }

    init(
        id: UUID = UUID(),
        date: Date,
        engine: String,
        audioSeconds: Double,
        processSeconds: Double,
        text: String,
        group: String? = nil,
        corrections: [AppliedCorrection]? = nil,
        language: String? = nil
    ) {
        self.id = id
        self.date = date
        self.engine = engine
        self.audioSeconds = audioSeconds
        self.processSeconds = processSeconds
        self.text = text
        self.group = group
        self.corrections = corrections
        self.language = language
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        date = try container.decode(Date.self, forKey: .date)
        engine = try container.decode(String.self, forKey: .engine)
        audioSeconds = try container.decode(Double.self, forKey: .audioSeconds)
        processSeconds = try container.decode(Double.self, forKey: .processSeconds)
        text = try container.decode(String.self, forKey: .text)
        group = try container.decodeIfPresent(String.self, forKey: .group)
        corrections = try container.decodeIfPresent([AppliedCorrection].self, forKey: .corrections)
        language = try container.decodeIfPresent(String.self, forKey: .language)
    }
}

/// In-memory by default. Persistent history is explicitly enabled in Settings.
@MainActor
enum RunLog {
    private static var memory: [DictationRun] = []
    private static var loaded = false
    private static var runsURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Goul/runs.json")
    }
    static func load() -> [DictationRun] {
        if !loaded {
            loaded = true
            if Settings.shared.historyEnabled, let data = try? Data(contentsOf: runsURL),
               let records = try? JSONDecoder().decode([DictationRun].self, from: data) { memory = records }
        }
        return memory
    }
    static func record(_ run: DictationRun) {
        _ = load()
        memory.append(run)
        // Bound the session log, including when history is disabled.
        if memory.count > 200 { memory.removeFirst(memory.count - 200) }
        save()
        RunStore.shared.reload()
    }
    static func delete(_ run: DictationRun) {
        memory.removeAll { $0.id == run.id }
        save()
        RunStore.shared.reload()
    }
    static func clear() {
        memory = []
        try? FileManager.default.removeItem(at: runsURL)
        RunStore.shared.reload()
    }
    static func persistenceChanged(enabled: Bool) {
        if enabled { save() }
        else { try? FileManager.default.removeItem(at: runsURL) }
    }
    private static func save() {
        guard Settings.shared.historyEnabled else { return }
        do {
            try FileManager.default.createDirectory(at: runsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(memory).write(to: runsURL, options: .atomic)
        } catch { Log.app.error("Could not save local history: \(error.localizedDescription)") }
    }
}

@MainActor @Observable
final class RunStore {
    static let shared = RunStore()
    private(set) var runs: [DictationRun] = []
    private init() { reload() }
    func reload() { runs = RunLog.load() }
}
