import Foundation
import Testing
@testable import GoulCore

struct LanguageDetectionTests {
    let detector = LanguageDetector()

    @Test func englishSentenceIsEnglish() {
        let guess = detector.detect("Please send me the report before the meeting tomorrow morning.")
        #expect(guess?.language == .english)
        #expect((guess?.confidence ?? 0) > 0.8)
    }

    @Test func frenchSentenceIsFrench() {
        let guess = detector.detect("Peux-tu m'envoyer le rapport avant la réunion de demain matin ?")
        #expect(guess?.language == .french)
        #expect((guess?.confidence ?? 0) > 0.8)
    }

    /// Parakeet and Apple both emit proper accents; the recogniser must not need them.
    @Test func frenchWithoutAccentsIsStillFrench() {
        #expect(detector.detect("je voudrais reserver une table pour deux personnes ce soir")?.language == .french)
    }

    @Test func frenchWithAccentsAndLigatures() {
        #expect(detector.detect("Le cœur a ses raisons que la raison ne connaît point, ça c'est sûr.")?.language == .french)
    }

    /// macOS hands back decomposed strings (e + combining acute). Same answer either way.
    @Test func decomposedAccentsMatchPrecomposed() {
        let precomposed = "Écoute, on va déjeuner à côté du théâtre après la répétition."
        let decomposed = precomposed.decomposedStringWithCanonicalMapping
        #expect(detector.detect(precomposed)?.language == .french)
        #expect(detector.detect(decomposed)?.language == .french)
    }

    @Test func englishWithFrenchLoanwordsIsEnglish() {
        #expect(detector.detect("We had a rendezvous at the café near the boulevard and ordered a croissant.")?.language == .english)
    }

    @Test func tooShortToTellIsNil() {
        #expect(detector.detect("ok") == nil)
        #expect(detector.detect("   ") == nil)
        #expect(detector.detect("") == nil)
        #expect(detector.detect("12 34") == nil)
    }

    /// One push-to-talk utterance that switches language mid-way resolves to the
    /// language most of it was spoken in — the whole text is inserted regardless.
    @Test func mixedUtteranceFollowsTheDominantLanguage() {
        let mostlyFrench = "Bonjour à tous, aujourd'hui on va parler du nouveau projet, and then we stop."
        let mostlyEnglish = "Today we are going to talk about the new project timeline, et voilà."
        #expect(detector.detect(mostlyFrench)?.language == .french)
        #expect(detector.detect(mostlyEnglish)?.language == .english)
    }

    /// Two consecutive dictations in different languages are independent.
    @Test func languageSwitchesBetweenUtterances() {
        let runs = [
            "Can you book the meeting room for Thursday afternoon?",
            "Est-ce que tu peux réserver la salle pour jeudi après-midi ?",
            "Thanks, that works for everyone on the team.",
        ]
        #expect(runs.map { detector.detect($0)?.language } == [.english, .french, .english])
    }

    // MARK: - Choosing between locked-locale transcribers

    typealias Candidate = LanguageDetector.Candidate

    /// A locked French transcriber hearing English emits real French words, so the text
    /// alone reads as French. The engine's low confidence is what breaks the tie.
    @Test func engineConfidenceOutweighsPlausibleLookingSoup() {
        let chosen = detector.choose(among: [
            Candidate(language: .english, text: "I would like to book a table for two tonight please", engineConfidence: 0.92),
            Candidate(language: .french, text: "aïe oule d'ail que tout bouc à tables fort tout tonight plie", engineConfidence: 0.31),
        ])
        #expect(chosen == .english)
    }

    @Test func picksFrenchWhenTheEnglishTranscriberProducedSoup() {
        let chosen = detector.choose(among: [
            Candidate(language: .english, text: "shoe voodoo ray reserve a on tabla pour do person suh swa"),
            Candidate(language: .french, text: "je voudrais réserver une table pour deux personnes ce soir"),
        ])
        #expect(chosen == .french)
    }

    @Test func textAloneDecidesWhenConfidenceIsUnavailable() {
        let chosen = detector.choose(among: [
            Candidate(language: .english, text: "can you book the meeting room for thursday afternoon"),
            Candidate(language: .french, text: "quand you bouc de mit ting roume fort sers d'aie afternoon"),
        ])
        #expect(chosen == .english)
    }

    @Test func nothingHeardFallsBackToEnglish() {
        #expect(detector.choose(among: [Candidate(language: .english, text: ""), Candidate(language: .french, text: "")]) == .english)
        #expect(detector.choose(among: []) == .english)
    }

    @Test func fallbackIsRespectedWhenOnlyOneCandidateSpoke() {
        #expect(detector.choose(among: [Candidate(language: .french, text: "")], fallback: .french) == .french)
    }

    // MARK: - Cleanup vocabulary

    @Test func frenchSpokenPunctuationIsApplied() {
        let out = LanguageRules.applySpokenPunctuation(
            to: "bonjour virgule tu viens jeudi point d'interrogation on verra deux points lundi ou mardi",
            language: .french)
        #expect(out == "bonjour, tu viens jeudi? on verra: lundi ou mardi")
    }

    /// "point" on its own is a real word and must survive.
    @Test func bareFrenchPointIsNotPunctuation() {
        let out = LanguageRules.applySpokenPunctuation(to: "on fait le point projet à la ligne demain", language: .french)
        #expect(out == "on fait le point projet\ndemain")
    }

    @Test func englishSpokenPunctuationIsApplied() {
        let out = LanguageRules.applySpokenPunctuation(to: "send it today comma not tomorrow question mark", language: .english)
        #expect(out == "send it today, not tomorrow?")
    }

    @Test func spokenPunctuationDoesNotMatchInsideWords() {
        #expect(LanguageRules.applySpokenPunctuation(to: "the commander arrived", language: .english) == "the commander arrived")
    }

    @Test func fillerListsAreLanguageSpecific() {
        #expect(LanguageRules.fillers(for: .english).contains("um"))
        #expect(!LanguageRules.fillers(for: .english).contains("euh"))
        #expect(LanguageRules.fillers(for: .french).contains("euh"))
        #expect(LanguageRules.spokenPunctuation(for: .french).contains { $0.phrase == "à la ligne" })
    }
}
