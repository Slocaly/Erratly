//
//  LLMService.swift
//  Erratly
//

import Foundation

actor LLMService {
    static let shared = LLMService()
    private init() {}

    private var activeProvider: CorrectionProvider?
    private var loadGeneration = 0

    /// Throws CancellationError if another load started while this one was
    /// running (e.g. the user switched backend mid-download), so a stale
    /// provider never replaces the newer one.
    func loadModel(progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws {
        let provider: CorrectionProvider = AppSettings.shared.backend == .local
            ? LocalCorrectionProvider()
            : RemoteCorrectionProvider()
        loadGeneration += 1
        let generation = loadGeneration
        activeProvider = nil
        try await provider.prepare(progress: progress)
        guard generation == loadGeneration else { throw CancellationError() }
        activeProvider = provider
    }

    func correctText(_ text: String, language: String?, examples: [CorrectionPair]) async throws -> String {
        guard let provider = activeProvider else {
            throw NSError(domain: "LLMService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Model not loaded"])
        }
        return try await provider.correctText(text, language: language, examples: examples)
    }
}
