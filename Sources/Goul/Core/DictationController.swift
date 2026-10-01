import MurmurDictionary
import GoulCore
import AVFoundation
import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class DictationController {
    enum State: Equatable {
        case idle, starting, listening, finishing
        /// Text is ready and shown; Escape within `cancelWindow` discards it.
        case reviewing
        case error(String)
        var isActive: Bool {
            switch self { case .starting, .listening, .finishing, .reviewing: true; default: false }
        }
    }
    /// What the held key means for this utterance.
    enum Mode: Equatable {
        /// Speak, release, text is inserted.
        case dictation
        /// Speak an instruction; the selection is rewritten (or text is generated).
        case command
    }
    /// How long the final text is shown before insertion, giving Escape a chance.
    /// Every dictation pays this — chosen short enough not to feel like lag.
    static let cancelWindow: Duration = .milliseconds(700)
    /// A press shorter than this is a tap, not an utterance. Discarded without asking the
    /// engine: Apple's finalizer takes seconds on near-empty audio, which read as a hang.
    static let minimumHold: TimeInterval = 0.3

    /// Fires synchronously on every state change, in order, with nothing skipped — the
    /// HUD is driven from here rather than from `withObservationTracking`, which only
    /// reports the first change after each registration and lost transitions when two
    /// arrived in one run-loop turn (the HUD then never appeared, or never left).
    var onStateChange: ((State) -> Void)?
    private(set) var state: State = .idle { didSet { if oldValue != state { onStateChange?(state) } } }
    private(set) var mode: Mode = .dictation
    private(set) var transcript = ""
    /// Language of the current or most recent dictation, as the engine detected it.
    /// Informational only: nothing asks the user to confirm or change it.
    private(set) var detectedLanguage: SpokenLanguage?
    private(set) var level: Float = 0
    private(set) var isPreparing = false
    private(set) var setupMessage = "Start with Prepare to enable your microphone and check the speech model. English and French are detected automatically."
    private let hotkey = HotkeyMonitor()
    private let capture = AudioCapture()
    private var gate = SessionGate()
    private var currentID: UUID?
    private var engine: (any TranscriptionEngine)?
    private var startTask: Task<Void, Never>?
    private var finishTask: Task<Void, Never>?
    private var consumeTask: Task<Void, Never>?
    private var feedTask: Task<Void, Never>?
    private var audioContinuation: AsyncStream<AudioChunk>.Continuation?
    private var target: TextInjector.Target?
    /// Command Mode: the text selected when the key went down.
    private var selection: String?
    private var isTest = false
    private var startedAt = Date()
    /// When capture actually began (after engine start), for the too-short check.
    private var listeningSince = Date()
    private var engineName = ""

    var statusTitle: String {
        if isPreparing { return "Preparing your ship…" }
        switch state {
        case .idle: return "Ready when you are"
        case .starting: return "Preparing microphone…"
        case .listening: return mode == .command ? "Listening for your command…" : "Listening…"
        case .finishing: return mode == .command ? "Rewriting…" : "Writing your words…"
        case .reviewing: return "Inserting… press Escape to discard"
        case .error: return "Needs your attention"
        }
    }
    private func makeEngine() -> any TranscriptionEngine {
        switch Settings.shared.engine {
        case .apple: AutoLanguageAppleEngine()
        case .parakeet: ParakeetEngine()
        }
    }
    @discardableResult func activate() -> Bool {
        let settings = Settings.shared
        var bindings = [HotkeyMonitor.Binding(
            key: settings.pushToTalkKey,
            onPress: { [weak self] in self?.beginDictation(test: false, mode: .dictation) },
            onRelease: { [weak self] in self?.endDictation() })]
        // A command key equal to the dictation key would fire both; dictation wins.
        if settings.commandModeEnabled, settings.commandKey != settings.pushToTalkKey {
            bindings.append(HotkeyMonitor.Binding(
                key: settings.commandKey,
                onPress: { [weak self] in self?.beginDictation(test: false, mode: .command) },
                onRelease: { [weak self] in self?.endDictation() }))
        }
        hotkey.bindings = bindings
        hotkey.onCancel = { [weak self] in self?.cancelDictation() }
        return hotkey.start()
    }
    func deactivate() { hotkey.stop(); cancelDictation() }
    /// While the user records a new shortcut in Settings, the global tap must not fire.
    func pauseHotkey() { cancelDictation(); hotkey.stop() }
    @discardableResult func reloadHotkey() -> Bool {
        cancelDictation()
        hotkey.stop()
        return activate()
    }
    func prepare() {
        guard !isPreparing, !state.isActive else { return }
        isPreparing = true
        setupMessage = "Checking microphone and speech assets for English and French. First-time downloads can take a few minutes."
        Permissions.promptForAccessibility()
        Task { @MainActor in
            defer { isPreparing = false }
            guard await Permissions.requestMicrophone() else {
                setupMessage = "Enable Goul in System Settings → Privacy & Security → Microphone, then try again."
                return
            }
            let prepared = makeEngine()
            do {
                _ = try await prepared.start()
                await prepared.cancel()
                let armed = activate()
                setupMessage = armed
                    ? "All set. Test the microphone here, or hold \(Settings.shared.pushToTalkKey.displayName) in another app. Escape cancels."
                    : "Microphone and model ready. Enable Goul in Accessibility to use the global shortcut. You can test here now."
            } catch {
                await prepared.cancel()
                setupMessage = error.localizedDescription
            }
        }
    }
    func startButtonRecording() { beginDictation(test: true, mode: .dictation) }
    func stopButtonRecording() { endDictation() }
    private func beginDictation(test: Bool, mode: Mode) {
        guard !state.isActive, !isPreparing else { return }
        if mode == .command {
            guard CommandRewriter.isAvailable else {
                setupMessage = CommandRewriter.unavailableReason ?? "Command Mode needs Apple Intelligence."
                return
            }
        }
        let id = gate.begin()
        currentID = id
        isTest = test
        self.mode = mode
        selection = nil
        target = test ? nil : TextInjector.captureTarget()
        if mode == .command, target == nil {
            Log.app.info("command: no target — ignoring")
            gate.cancel(); currentID = nil
            setupMessage = "Command Mode works in another app's text field. Select text there, then hold \(Settings.shared.commandKey.displayName)."
            return
        }
        startedAt = Date()
        engineName = Settings.shared.engine.displayName
        transcript = ""
        detectedLanguage = nil
        state = .starting
        let speech = makeEngine()
        engine = speech
        startTask = Task { @MainActor in
            do {
                guard await Permissions.requestMicrophone() else {
                    throw GoulError.message("Microphone access is off. Open Settings in Goul to enable it.")
                }
                guard gate.accepts(id) else { return }
                if mode == .command, let target {
                    // Before the engine starts, so a ⌘C fallback can't collide with audio setup.
                    selection = await TextInjector.captureSelection(in: target)
                    guard gate.accepts(id), !Task.isCancelled else { return }
                }
                let chunks = try await speech.start()
                guard gate.accepts(id), !Task.isCancelled else { await speech.cancel(); return }
                guard let format = await speech.preferredInputFormat() else { throw TranscriptionError.noAudioFormat }
                guard gate.accepts(id), !Task.isCancelled else { await speech.cancel(); return }
                let (audio, continuation) = AsyncStream<AudioChunk>.makeStream(bufferingPolicy: .bufferingNewest(128))
                audioContinuation = continuation
                feedTask = Task {
                    for await chunk in audio {
                        guard !Task.isCancelled else { break }
                        await speech.feed(chunk)
                    }
                }
                consumeTask = Task { @MainActor in
                    do {
                        for try await chunk in chunks {
                            guard gate.accepts(id), !Task.isCancelled else { return }
                            transcript = chunk.text
                            if let language = chunk.language { detectedLanguage = language }
                        }
                    } catch { fail(error.localizedDescription, id: id) }
                }
                try capture.start(outputFormat: format, onBuffer: { continuation.yield($0) }, onLevel: { value in
                    Task { @MainActor in
                        guard self.gate.accepts(id) else { return }
                        self.level = value
                    }
                })
                state = .listening
                listeningSince = Date()
                setupMessage = switch (test, mode) {
                case (true, _): "Test mode: text stays in your log. Click Finish when you are done."
                case (false, .command): selection == nil
                    ? "No selection: say what to write, then release."
                    : "Say what to do with the selection, then release."
                case (false, .dictation): "Release your shortcut to insert. Escape cancels."
                }
                if Settings.shared.soundEnabled { NSSound(named: "Tink")?.play() }
            } catch {
                await speech.cancel()
                fail(error.localizedDescription, id: id)
            }
        }
    }
    private func endDictation() {
        if state == .starting { cancelDictation(); return }
        guard state == .listening, let id = currentID, let speech = engine else { return }
        let held = Date().timeIntervalSince(listeningSince)
        if !isTest, held < Self.minimumHold {
            Log.app.info("dictation: press too short (\(Int(held * 1000)) ms) — discarded")
            let key = (mode == .command ? Settings.shared.commandKey : Settings.shared.pushToTalkKey).displayName
            cancelDictation()
            setupMessage = "That was a tap. Hold \(key) while you speak, then release."
            return
        }
        state = .finishing
        capture.stop()
        level = 0
        audioContinuation?.finish()
        audioContinuation = nil
        let feeder = feedTask
        let consumer = consumeTask
        let destination = target
        let test = isTest
        let duration = Date().timeIntervalSince(startedAt)
        let released = Date()
        finishTask = Task { @MainActor in
            await feeder?.value
            guard gate.accepts(id) else { return }
            await speech.finish()
            await consumer?.value
            guard gate.accepts(id), !Task.isCancelled else { return }
            let raw = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else {
                Log.app.info("dictation: empty transcript")
                setupMessage = "No words heard. Try again closer to the microphone."
                complete(id)
                return
            }
            // Engines that can't say (a stray Parakeet result too short to classify) get a
            // text-based guess here; still nil means "too short to tell", shown as nothing.
            let language = detectedLanguage ?? LanguageDetector().detect(raw)?.language
            detectedLanguage = language
            let output: String
            var corrections: [AppliedCorrection] = []
            var engineLabel = engineName
            if mode == .command {
                engineLabel = "Command · " + engineName
                setupMessage = "Applying: “\(raw)”"
                guard let rewritten = await CommandRewriter().run(instruction: raw, selection: selection, language: language) else {
                    guard gate.accepts(id) else { return }
                    setupMessage = "Couldn't apply “\(raw)”. Nothing was changed."
                    complete(id)
                    return
                }
                output = rewritten
            } else {
                let formatted: String
                if Settings.shared.cleanupEnabled {
                    // Apple Intelligence when it's on; rules otherwise. The model formatter
                    // already falls back to the rules on timeout or a rejected answer.
                    formatted = FoundationModelFormatter.isAvailable
                        ? await FoundationModelFormatter(language: language ?? .english).format(raw)
                        : await RuleBasedFormatter(language: language ?? .english).format(raw)
                } else {
                    formatted = raw
                }
                guard gate.accepts(id), !Task.isCancelled else { return }
                (output, corrections) = DictionaryStore.shared.corrector.apply(to: formatted)
            }
            guard gate.accepts(id), !Task.isCancelled else { return }

            // The cancel window. The final text is on screen; Escape cancels `finishTask`,
            // which throws out of this sleep, and nothing below runs.
            if !test {
                transcript = output
                state = .reviewing
                do { try await Task.sleep(for: Self.cancelWindow) } catch { return }
                guard gate.accepts(id), !Task.isCancelled else { return }
            }

            RunLog.record(DictationRun(date: released, engine: engineLabel, audioSeconds: duration,
                processSeconds: Date().timeIntervalSince(released), text: output, corrections: corrections,
                language: language?.code))
            if test {
                setupMessage = "Test complete. Your words are in the log below; use Copy whenever you need them."
            } else if let destination {
                let sent = await TextInjector.insert(output, into: destination)
                guard gate.accepts(id) else { return }
                setupMessage = switch (sent, mode) {
                case (true, .command): "Done. The selection was replaced; ⌘Z in that app undoes it."
                case (true, .dictation): "Paste sent. Your transcript is also available in the log."
                case (false, _): "The destination changed or is unavailable. Copy your transcript from the log."
                }
            } else {
                Log.app.info("dictation: no target captured at key-down")
                setupMessage = "Could not verify a text field. Copy your transcript from the log."
            }
            guard gate.accepts(id) else { return }
            if Settings.shared.soundEnabled { NSSound(named: "Pop")?.play() }
            complete(id)
        }
    }
    func cancelDictation() {
        guard state.isActive else { return }
        gate.cancel()
        currentID = nil
        startTask?.cancel()
        finishTask?.cancel()
        capture.stop()
        audioContinuation?.finish()
        audioContinuation = nil
        feedTask?.cancel()
        consumeTask?.cancel()
        let old = engine
        engine = nil
        Task { await old?.cancel() }
        state = .idle
        transcript = ""
        level = 0
        setupMessage = "Canceled. No text was inserted."
    }
    func interrupted() {
        guard state == .listening else { return }
        cancelDictation()
        setupMessage = "Recording stopped because the audio device or system state changed. Please try again."
    }
    private func complete(_ id: UUID) {
        guard gate.accepts(id) else { return }
        gate.complete(id)
        currentID = nil
        engine = nil
        consumeTask = nil
        feedTask = nil
        state = .idle
        transcript = ""
    }
    private func fail(_ message: String, id: UUID) {
        guard gate.accepts(id) else { return }
        cancelDictation()
        state = .error(message)
    }
}
private enum GoulError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
