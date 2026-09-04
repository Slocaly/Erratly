//
//  LLMService.swift
//  Erratly
//

import Foundation

actor LLMService {
    static let shared = LLMService()
    private init() {}

    private var activeProvider: CorrectionProvider?

    func loadModel() async throws {
        let provider: CorrectionProvider = AppSettings.shared.backend == .local
            ? LocalCorrectionProvider()
            : RemoteCorrectionProvider()
        activeProvider = nil
        try await provider.prepare()
        activeProvider = provider
    }

    func correctText(_ text: String, language: String?, examples: [CorrectionPair]) async throws -> String {
        guard let provider = activeProvider else {
            throw NSError(domain: "LLMService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Model not loaded"])
        }
        return try await provider.correctText(text, language: language, examples: examples)
    }
}
