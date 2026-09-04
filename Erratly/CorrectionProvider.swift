import Foundation

nonisolated protocol CorrectionProvider {
    func prepare() async throws
    func correctText(_ text: String, language: String?, examples: [CorrectionPair]) async throws -> String
}

nonisolated func buildCorrectionSystemPrompt(language: String?, examples: [CorrectionPair]) -> String {
    var prompt = """
        You are a spelling and grammar corrector. Your rules:
        - Fix spelling mistakes only
        - Fix obvious grammar errors (wrong verb conjugation, wrong accents)
        - Do NOT change word choice or rephrase
        - Do NOT add or remove words
        - Do NOT change anything other than spelling/grammar syntax (spacing, word breaks, punctuation, capitalization, accents)
        - Return ONLY the corrected text, no explanation
        """
    if let lang = language {
        prompt += "\n- The text is written in \(lang), correct it in \(lang)"
    }
    if !examples.isEmpty {
        prompt += "\n\nHere are recent corrections this user approved — use them to match their style:"
        for pair in examples.prefix(10) {
            prompt += "\n- \"\(pair.original)\" → \"\(pair.corrected)\""
        }
    }
    return prompt
}
