import Foundation
import FoundationModels
import GoulCore

/// Command Mode's brain: applies a spoken instruction to the selected text, or writes
/// text from the instruction when nothing is selected. Apple's on-device model, so the
/// selection never leaves the Mac.
///
/// Unlike `FoundationModelFormatter` there is no "invented words" guard here — rewriting
/// is *supposed* to invent words. The guards that remain are a timeout (a stalled model
/// must not hold the user's selection hostage) and a check that the model didn't start
/// chatting instead of editing.
struct CommandRewriter: Sendable {
    /// Generation can legitimately be longer than cleanup (a whole email), hence generous.
    static let timeout: Duration = .seconds(12)

    static var isAvailable: Bool { FoundationModelFormatter.isAvailable }
    static var unavailableReason: String? { FoundationModelFormatter.unavailableReason }

    /// - Returns: the text to insert in place of the selection, or nil when the model
    ///   failed, timed out, or answered instead of editing.
    func run(instruction: String, selection: String?, language: SpokenLanguage?) async -> String? {
        let instruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty, Self.isAvailable else { return nil }

        do {
            let result = try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask { try await Self.generate(instruction: instruction, selection: selection, language: language) }
                group.addTask {
                    try await Task.sleep(for: Self.timeout)
                    throw RewriteError.timedOut
                }
                guard let first = try await group.next() else { throw RewriteError.timedOut }
                group.cancelAll()
                return first
            }
            guard Self.looksLikeText(result) else {
                Log.speech.info("command: model output rejected (chatty)")
                return nil
            }
            return result
        } catch {
            Log.speech.error("command failed: \(error.localizedDescription)")
            return nil
        }
    }

    private static func generate(instruction: String, selection: String?, language: SpokenLanguage?) async throws -> String {
        let languageHint = language.map { " The user spoke in \($0.displayName)." } ?? ""
        let session = LanguageModelSession(instructions: """
            You are the editing engine of a dictation tool. The user speaks an instruction.\(languageHint)

            If a SELECTED TEXT is provided: apply the instruction to it and return the \
            resulting text, and nothing else. Keep its language unless the instruction asks \
            to translate. Keep its formatting (line breaks, lists) unless asked otherwise.

            If no selected text is provided: write the text the instruction asks for, in \
            the language the instruction was spoken in, and return only that text.

            Never explain, never add a preamble, never wrap the result in quotes, never ask \
            a question back. Your whole reply is inserted verbatim into the user's document.
            """)
        let prompt: String
        if let selection, !selection.isEmpty {
            prompt = "Instruction: \(instruction)\n\nSELECTED TEXT:\n\(selection)"
        } else {
            prompt = "Instruction: \(instruction)\n\n(no selected text)"
        }
        let response = try await session.respond(
            to: prompt,
            options: GenerationOptions(temperature: 0.3, maximumResponseTokens: 2_000)
        )
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func looksLikeText(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        let lowered = text.lowercased()
        let tells = ["sure,", "certainly", "here's", "here is", "voici", "bien sûr", "i cannot", "i can't", "as an ai", "je ne peux pas"]
        return !tells.contains { lowered.hasPrefix($0) }
    }

    private enum RewriteError: LocalizedError {
        case timedOut
        var errorDescription: String? { "on-device rewrite timed out" }
    }
}
