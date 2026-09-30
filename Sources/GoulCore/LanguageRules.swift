import Foundation

/// Per-language vocabulary for the rule-based cleanup pass.
///
/// Lives here rather than in the formatter so the lists are unit-tested and so the
/// formatter is told which language it is cleaning instead of guessing. Stripping "um"
/// from French is harmless; stripping "ben" from English would eat a name.
public enum LanguageRules {
    /// Standalone hesitation sounds, matched as whole words only.
    public static func fillers(for language: SpokenLanguage) -> [String] {
        switch language {
        case .english: ["um", "uh", "erm", "uhm", "hmm", "mhm"]
        case .french: ["euh", "euuh", "hum", "hmm", "ben", "bah"]
        }
    }

    /// Spoken punctuation people actually say mid-dictation, in match order.
    ///
    /// Only phrases that are unambiguous as speech are here. "point" and "period" are
    /// deliberately absent: "le point projet" and "a period of time" are ordinary words,
    /// and turning them into "." would corrupt more sentences than it would punctuate.
    /// Longer phrases come first so "point d'interrogation" isn't eaten by a shorter match.
    public static func spokenPunctuation(for language: SpokenLanguage) -> [(phrase: String, replacement: String)] {
        switch language {
        case .english:
            [("new paragraph", "\n\n"), ("new line", "\n"),
             ("open paren", " ("), ("close paren", ") "),
             ("question mark", "?"), ("exclamation mark", "!"), ("exclamation point", "!"),
             ("semicolon", ";"), ("comma", ",")]
        case .french:
            [("nouveau paragraphe", "\n\n"), ("à la ligne", "\n"), ("a la ligne", "\n"), ("nouvelle ligne", "\n"),
             ("ouvrez la parenthèse", " ("), ("fermez la parenthèse", ") "),
             ("point d'interrogation", "?"), ("point d'exclamation", "!"),
             ("point-virgule", ";"), ("point virgule", ";"), ("deux points", ":"), ("virgule", ",")]
        }
    }

    /// Applies `spokenPunctuation` to `text`: the phrase is replaced as a whole word,
    /// case-insensitively, and any space before a punctuation mark is removed.
    public static func applySpokenPunctuation(to text: String, language: SpokenLanguage) -> String {
        var result = text
        for (phrase, replacement) in spokenPunctuation(for: language) {
            let pattern = "(?i)(?<![\\p{L}])" + NSRegularExpression.escapedPattern(for: phrase) + "(?![\\p{L}])"
            result = result.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        return result
            .replacingOccurrences(of: " *\\n *", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: " +([,;:?!])", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "([,;:?!])(?=\\p{L})", with: "$1 ", options: .regularExpression)
    }
}
