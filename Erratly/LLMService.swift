//
//  LLMService.swift
//  Erratly
//
//  Created by Lucas Audart on 28/06/2026.
//

import Foundation
import MLXLLM
import MLXLMCommon
import Tokenizers

actor LLMService {
    static let shared = LLMService()
    static let modelName = "Qwen2.5-3B-Instruct-4bit"

    private var modelContainer: ModelContainer?

    func loadModel() async throws {
        print("🤖 Loading model...")
        let config = ModelConfiguration(id: "mlx-community/\(LLMService.modelName)")
        modelContainer = try await LLMModelFactory.shared.loadContainer(configuration: config)
        print("✅ Model loaded!")
    }
    
    func correctText(_ text: String) async throws -> String {
        guard let container = modelContainer else {
            throw NSError(domain: "LLMService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Model not loaded"])
        }
        
        var output = ""

        let _ = try await container.perform { context in
            let input = try await context.processor.prepare(
                input: UserInput(chat: [
                    .system("""
                        You are a spelling and grammar corrector. Your rules:
                        - Fix spelling mistakes only
                        - Fix obvious grammar errors (wrong verb conjugation, wrong accents)
                        - Do NOT change word choice or rephrase
                        - Do NOT add or remove words
                        - Return ONLY the corrected text, no explanation
                        """),
                    .user(text)
                ])
            )
            return try MLXLMCommon.generate(
                input: input,
                parameters: GenerateParameters(temperature: 0.0),
                context: context
            ) { tokens in
                let decoded = context.tokenizer.decode(tokens: tokens)
                output = decoded
                return .more
            }
        }
        
        return output.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    }
}
