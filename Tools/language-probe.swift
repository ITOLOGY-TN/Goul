// Standalone check for the Apple auto-language arbiter (AutoLanguageAppleEngine).
//
// Runs an en-US and an fr-FR SpeechTranscriber over the same audio files and prints each
// transcript, its mean confidence and the text-language probabilities — the exact signals
// LanguageDetector.choose multiplies. No microphone needed:
//
//   say -v Samantha -o en.aiff "Can you book the meeting room for Thursday afternoon"
//   say -v Thomas   -o fr.aiff "Est-ce que tu peux réserver la salle pour jeudi après-midi"
//   say -v Thomas   -o mixed.aiff "Bonjour à tous, aujourd'hui on va parler du nouveau projet"
//   swiftc -parse-as-library Tools/language-probe.swift -o /tmp/probe && (cd <dir with aiff> && /tmp/probe)
//
// Measured 2026-09-30 on macOS 26: wrong-locale transcribers score 0.23–0.37 confidence on
// the other language (or code-switch into it), the right one 0.98–1.00.

import AVFoundation
import NaturalLanguage
import Speech

@main struct Probe {
    static func transcribe(_ url: URL, locale: String) async throws -> (String, Double) {
        let t = SpeechTranscriber(locale: Locale(identifier: locale), transcriptionOptions: [], reportingOptions: [], attributeOptions: [.transcriptionConfidence])
        let analyzer = SpeechAnalyzer(modules: [t])
        let file = try AVAudioFile(forReading: url)
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [t]) else { fatalError("no format") }
        let (stream, cont) = AsyncStream<AnalyzerInput>.makeStream()
        let collector = Task { () -> (String, Double) in
            var text = ""; var confs: [Double] = []
            for try await r in t.results where r.isFinal {
                text += String(r.text.characters)
                for run in r.text.runs { if let c = run.transcriptionConfidence { confs.append(c) } }
            }
            return (text.trimmingCharacters(in: .whitespaces), confs.isEmpty ? -1 : confs.reduce(0,+)/Double(confs.count))
        }
        try await analyzer.start(inputSequence: stream)
        let whole = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: whole)
        print("  read \(whole.frameLength) frames @\(file.processingFormat.sampleRate) -> \(format)")
        let conv = AVAudioConverter(from: file.processingFormat, to: format)!
        let ratio = format.sampleRate / file.processingFormat.sampleRate
        let outBuf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(Double(whole.frameLength) * ratio) + 4096)!
        var done = false
        var err: NSError?
        let status = conv.convert(to: outBuf, error: &err) { _, st in
            if done { st.pointee = .endOfStream; return nil }
            done = true; st.pointee = .haveData; return whole
        }
        if let err { print("  convert error", err, status.rawValue) }
        cont.yield(AnalyzerInput(buffer: outBuf))
        cont.finish()
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        return try await collector.value
    }
    static func main() async throws {
        for name in ["en", "fr", "mixed"] {
            let url = URL(fileURLWithPath: name + ".aiff")
            print("== \(name)")
            for locale in ["en-US", "fr-FR"] {
                let (text, conf) = try await transcribe(url, locale: locale)
                let rec = NLLanguageRecognizer(); rec.languageConstraints = [.english, .french]; rec.processString(text)
                let hyp = rec.languageHypotheses(withMaximum: 2)
                print(String(format: "  %@  conf=%.2f  P(en)=%.2f P(fr)=%.2f  %@", locale, conf, hyp[.english] ?? 0, hyp[.french] ?? 0, text))
            }
        }
    }
}
