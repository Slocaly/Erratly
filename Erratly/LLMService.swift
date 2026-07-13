//
//  LLMService.swift
//  Erratly
//
//  Created by Lucas Audart on 28/06/2026.
//

import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import Tokenizers

actor LLMService {
    static let shared = LLMService()
    static let modelName = "Qwen2.5-3B-Instruct-4bit"

    private var modelContainer: ModelContainer?

    func loadModel() async throws {
        print("🤖 Loading model...")
        // MLX's GPU cache defaults to the memory limit, which lets freed
        // buffers pile up unreclaimed across corrections. Capping it keeps
        // resident memory close to what the model actually needs.
        MLX.GPU.set(cacheLimit: 20 * 1024 * 1024)
        let config = ModelConfiguration(id: "mlx-community/\(LLMService.modelName)")
        modelContainer = try await LLMModelFactory.shared.loadContainer(configuration: config)
        print("✅ Model loaded!")
    }
    
    func correctText(_ text: String, language: String?, examples: [CorrectionPair]) async throws -> String {
        guard let container = modelContainer else {
            throw NSError(domain: "LLMService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Model not loaded"])
        }

        let systemPrompt: String = {
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
        }()

        let output = try await container.perform { context in
            let input = try await context.processor.prepare(
                input: UserInput(chat: [
                    .system(systemPrompt),
                    .user(text)
                ])
            )
            var result = ""
            let _ = try MLXLMCommon.generate(
                input: input,
                parameters: GenerateParameters(temperature: 0.0),
                context: context
            ) { tokens in
                result = context.tokenizer.decode(tokens: tokens)
                return .more
            }
            return result
        }

        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
