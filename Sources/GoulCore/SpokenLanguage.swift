import Foundation
import NaturalLanguage

/// The languages Goul transcribes. Both engines handle both; the user never picks.
public enum SpokenLanguage: String, Codable, Sendable, CaseIterable, Hashable {
    case english, french

    /// BCP-47 locale handed to Apple's `SpeechTranscriber`.
    public var localeIdentifier: String {
        switch self { case .english: "en-US"; case .french: "fr-FR" }
    }
    public var displayName: String {
        switch self { case .english: "English"; case .french: "Français" }
    }
    /// Two-letter badge for the HUD and the log.
    public var code: String {
        switch self { case .english: "EN"; case .french: "FR" }
    }
    var nlLanguage: NLLanguage {
        switch self { case .english: .english; case .french: .french }
    }
    init?(_ language: NLLanguage) {
        switch language {
        case .english: self = .english
        case .french: self = .french
        default: return nil
        }
    }
}

/// One detection result: which language, and how sure the recogniser was.
public struct LanguageGuess: Sendable, Equatable {
    public let language: SpokenLanguage
    /// 0…1, the recogniser's probability for `language` among the supported set.
    public let confidence: Double
    public init(language: SpokenLanguage, confidence: Double) {
        self.language = language
        self.confidence = confidence
    }
}

/// On-device language identification over transcript text, constrained to English/French.
///
/// Text-based on purpose: neither engine exposes an acoustic language ID. Parakeet v3 is
/// multilingual and simply writes whatever it heard, so identifying the text is the only
/// signal there is — and it is a strong one, because a transcript in the wrong language
/// reads as gibberish in the right one. Uses `NLLanguageRecognizer`, which runs entirely
/// on the Mac. Stateless and cheap enough to run on every partial result.
public struct LanguageDetector: Sendable {
    /// Below this many letters a guess is noise ("ok", "yes", "oui") — callers get nil
    /// and should fall back to their previous or default language.
    public static let minimumLetters = 3
    public init() {}

    /// The dominant language of `text`, or nil when there isn't enough text to tell.
    public func detect(_ text: String) -> LanguageGuess? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.unicodeScalars.filter(CharacterSet.letters.contains).count >= Self.minimumLetters else {
            return nil
        }
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = SpokenLanguage.allCases.map(\.nlLanguage)
        // Push-to-talk utterances are short; a mild prior keeps single ambiguous words
        // from flipping the guess while leaving any real sentence free to override it.
        recognizer.languageHints = [.english: 0.5, .french: 0.5]
        recognizer.processString(trimmed)
        let hypotheses = recognizer.languageHypotheses(withMaximum: SpokenLanguage.allCases.count)
        let scored = SpokenLanguage.allCases.map { ($0, hypotheses[$0.nlLanguage] ?? 0) }
        guard let best = scored.max(by: { $0.1 < $1.1 }), best.1 > 0 else { return nil }
        return LanguageGuess(language: best.0, confidence: best.1)
    }

    /// One locked-locale engine's output for a single utterance.
    public struct Candidate: Sendable {
        public let language: SpokenLanguage
        public let text: String
        /// The engine's own mean confidence in `text`, 0…1, when it reports one. Apple's
        /// `SpeechTranscriber` does; Parakeet doesn't need it because it isn't locked.
        public let engineConfidence: Double?
        public init(language: SpokenLanguage, text: String, engineConfidence: Double? = nil) {
            self.language = language
            self.text = text
            self.engineConfidence = engineConfidence
        }
    }

    /// Given several transcripts of the *same* audio, each produced by an engine locked
    /// to one language, pick the one that is actually written in its own language.
    ///
    /// This is how Apple's single-locale `SpeechTranscriber` gets automatic detection:
    /// run an English and a French transcriber side by side and let the outputs decide.
    /// Two signals are multiplied: how strongly the text reads as the engine's own
    /// language, and the engine's own confidence when it reports one. The second matters
    /// because a French transcriber fed English still emits *real French words* — text
    /// alone can't always tell, but the engine knows it was guessing.
    /// Ties and unreadable output fall back to `fallback` (English by default), which
    /// also covers a stray tap of the key where neither produced anything.
    public func choose(among candidates: [Candidate], fallback: SpokenLanguage = .english) -> SpokenLanguage {
        var bestLanguage = fallback
        var bestScore = -1.0
        for candidate in candidates {
            guard let guess = detect(candidate.text) else { continue }
            let textScore = guess.language == candidate.language ? guess.confidence : 1 - guess.confidence
            let score = textScore * (candidate.engineConfidence ?? 1)
            if score > bestScore || (score == bestScore && candidate.language == fallback) {
                bestScore = score
                bestLanguage = candidate.language
            }
        }
        return bestLanguage
    }
}
