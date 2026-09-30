import AVFoundation
import Foundation
import GoulCore

/// Automatic English/French detection on top of Apple's single-locale `SpeechTranscriber`.
///
/// Apple's API takes one locale per transcriber and offers no language identification, so
/// this runs one `AppleSpeechEngine` per supported language on the **same** microphone
/// stream and lets `LanguageDetector.choose` pick the transcript that is actually written
/// in its engine's language. The cost is two recognisers' worth of CPU while the key is
/// held; on Apple silicon that is still well under one core.
///
/// Live text: while listening, the HUD shows whichever candidate currently reads best in
/// its own language, so a French speaker sees French partials rather than English soup.
/// The decision is only final on release.
///
/// If the French model isn't available (unsupported locale, download refused) the engine
/// degrades to English-only and logs it, rather than failing dictation outright.
actor AutoLanguageAppleEngine: TranscriptionEngine {
    /// How long to wait for the transcribers to drain after `finish()`. Normal utterances
    /// finalize in well under a second; near-silent ones have been measured at 4–12 s,
    /// which the user experiences as a hang. Past this we take what has been committed.
    static let drainTimeout: Duration = .milliseconds(2500)

    private let detector = LanguageDetector()
    private var engines: [AppleSpeechEngine] = []
    private var latest: [SpokenLanguage: String] = [:]
    private var mergeTasks: [Task<Void, Never>] = []
    private var continuation: AsyncThrowingStream<TranscriptionChunk, Error>.Continuation?
    private var pendingFinals = 0

    func preferredInputFormat() async -> AVAudioFormat? {
        // Same module type in every engine, so any one of them answers for all.
        let engine = engines.first ?? AppleSpeechEngine(language: .english)
        return await engine.preferredInputFormat()
    }

    func start() async throws -> AsyncThrowingStream<TranscriptionChunk, Error> {
        latest = [:]
        engines = []
        mergeTasks = []

        let (stream, continuation) = AsyncThrowingStream<TranscriptionChunk, Error>.makeStream()
        self.continuation = continuation

        var streams: [(SpokenLanguage, AsyncThrowingStream<TranscriptionChunk, Error>)] = []
        var firstError: Error?
        for language in SpokenLanguage.allCases {
            let engine = AppleSpeechEngine(language: language)
            do {
                let chunks = try await engine.start()
                engines.append(engine)
                streams.append((language, chunks))
            } catch {
                Log.speech.error("Apple \(language.code, privacy: .public) unavailable: \(error.localizedDescription)")
                if firstError == nil { firstError = error }
            }
        }
        // Nothing started at all: surface the real reason instead of a silent dead mic.
        guard !engines.isEmpty else { throw firstError ?? TranscriptionError.notRunning }
        pendingFinals = engines.count

        for (language, chunks) in streams {
            mergeTasks.append(Task { [weak self] in
                do {
                    for try await chunk in chunks {
                        guard let self else { return }
                        await self.absorb(chunk, from: language)
                    }
                } catch {
                    Log.speech.error("Apple \(language.code, privacy: .public) stream failed: \(error.localizedDescription)")
                }
                await self?.engineFinished()
            })
        }
        return stream
    }

    func feed(_ chunk: AudioChunk) async {
        // The buffer is freshly allocated per chunk and never mutated after hand-off, so
        // several analyzers may read it concurrently.
        for engine in engines { await engine.feed(chunk) }
    }

    func cancel() async {
        for task in mergeTasks { task.cancel() }
        for engine in engines { await engine.cancel() }
        continuation?.finish()
        continuation = nil
        engines = []
        mergeTasks = []
    }

    func finish() async {
        // Finish every engine so each commits its final text; the merge tasks then count
        // down and `engineFinished` emits the arbitrated result — unless they take too
        // long, in which case we cut them off and emit what's committed.
        await withTaskGroup(of: Void.self) { group in
            for engine in engines { group.addTask { await engine.finish() } }
        }
        let tasks = mergeTasks
        let drained = await withTaskGroup(of: Bool.self) { group in
            group.addTask { for task in tasks { await task.value }; return true }
            group.addTask { try? await Task.sleep(for: Self.drainTimeout); return false }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
        guard !drained else { return }
        Log.speech.error("Apple auto-language: transcribers didn't drain in \(Self.drainTimeout.description, privacy: .public) — cutting off")
        for task in tasks { task.cancel() }
        for engine in engines { await engine.cancel() }
        await engineFinished(force: true)
    }

    // MARK: - Merging

    private func absorb(_ chunk: TranscriptionChunk, from language: SpokenLanguage) {
        latest[language] = chunk.text
        guard !chunk.isFinal else { return }
        // Provisional winner for the live HUD; cheap enough to recompute per partial.
        let leader = detector.choose(among: latest.map { .init(language: $0.key, text: $0.value) })
        continuation?.yield(TranscriptionChunk(text: latest[leader] ?? "", isFinal: false, language: leader))
    }

    private func engineFinished(force: Bool = false) async {
        if !force {
            pendingFinals -= 1
            guard pendingFinals == 0 else { return }
        }
        // A late merge task after a forced cut-off (or a cancel) must not emit twice.
        guard continuation != nil else { return }

        var candidates: [LanguageDetector.Candidate] = []
        for engine in engines {
            candidates.append(.init(
                language: engine.language,
                text: await engine.committedText,
                engineConfidence: await engine.meanConfidence
            ))
        }
        let winner = detector.choose(among: candidates)
        let summary = candidates.map { "\($0.language.code)=\($0.engineConfidence.map { String(format: "%.2f", $0) } ?? "–")" }
        Log.speech.info("Apple auto-language: \(winner.code, privacy: .public) (\(summary.joined(separator: " "), privacy: .public))")

        let text = candidates.first { $0.language == winner }?.text ?? ""
        continuation?.yield(TranscriptionChunk(text: text, isFinal: true, language: winner))
        continuation?.finish()
        continuation = nil
        engines = []
        mergeTasks = []
    }
}
