import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import Tokenizers

actor LocalCorrectionProvider: CorrectionProvider {
    static let modelName = "Qwen2.5-3B-Instruct-4bit"

    private var modelContainer: ModelContainer?

    /// Whether the weights are already in MLX's download cache
    /// (defaultHubApi → Caches/models/<repo id>), so loading needs no download.
    nonisolated static var isDownloaded: Bool {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return false }
        let repo = caches.appending(path: "models/mlx-community/\(modelName)")
        let files = (try? FileManager.default.contentsOfDirectory(atPath: repo.path(percentEncoded: false))) ?? []
        return files.contains { $0.hasSuffix(".safetensors") }
    }

    func prepare(progress: @escaping @Sendable (Double) -> Void) async throws {
        print("🤖 Loading model...")
        // MLX's GPU cache defaults to the memory limit, which lets freed
        // buffers pile up unreclaimed across corrections. Capping it keeps
        // resident memory close to what the model actually needs.
        MLX.GPU.set(cacheLimit: 20 * 1024 * 1024)
        let config = ModelConfiguration(id: "mlx-community/\(LocalCorrectionProvider.modelName)")
        modelContainer = try await LLMModelFactory.shared.loadContainer(configuration: config) { progress($0.fractionCompleted) }
        print("✅ Model loaded!")
    }

    func correctText(_ text: String, language: String?, examples: [CorrectionPair]) async throws -> String {
        guard let container = modelContainer else {
            throw NSError(domain: "LocalCorrectionProvider", code: 0, userInfo: [NSLocalizedDescriptionKey: "Model not loaded"])
        }

        let systemPrompt = buildCorrectionSystemPrompt(language: language, examples: examples)

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
