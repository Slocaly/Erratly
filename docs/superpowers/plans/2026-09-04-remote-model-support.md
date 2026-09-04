# Remote Model Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user choose between the existing on-device local model and a remote LLM reached over an OpenAI-compatible HTTP API, using their own API key.

**Architecture:** Extract a `CorrectionProvider` protocol with two conformers (`LocalCorrectionProvider` wrapping today's MLX code, `RemoteCorrectionProvider` doing a `/chat/completions` HTTP call). `LLMService` becomes a thin coordinator that loads whichever provider is selected. A new `AppSettings` singleton persists the backend choice and remote config in `UserDefaults`, with the API key kept in the Keychain via a new `KeychainHelper`. A new `SettingsWindow` (opened from a new "Settings…" menu item) is the only UI surface for configuring any of this.

**Tech Stack:** Swift 5, AppKit (Cocoa), Foundation `URLSession`, Security framework (Keychain Services), MLX (`mlx-swift`, `mlx-swift-examples`) for the existing local backend. No SwiftUI, no third-party HTTP client.

**Spec:** `docs/superpowers/specs/2026-09-04-remote-model-support-design.md`

## Global Constraints

- No automated test target exists in the Xcode project (it has a single native target, "Erratly", confirmed via `project.pbxproj`). Verify Foundation-only code (no MLX, no AppKit windowing) by running it as a standalone `swift` script; verify everything else — anything importing MLX/MLXLLM/MLXLMCommon/Tokenizers, or building an `NSWindow` — with `xcodebuild -project Erratly.xcodeproj -scheme Erratly -configuration Debug build`, run from the `app/` directory.
- New files dropped into `Erratly/` are auto-added to the Xcode target — the project uses `PBXFileSystemSynchronizedRootGroup`. Never hand-edit `project.pbxproj`.
- App Sandbox is disabled (`ENABLE_APP_SANDBOX = NO`). No entitlements file changes are needed for network access or Keychain use.
- The remote API key must never be stored in `UserDefaults` — Keychain only, via `Erratly/KeychainHelper.swift`.
- No fallback from remote to local on failure. A remote error surfaces the `.error` status exactly like a local-model error does today (clipboard restored, no retry).
- The Settings window's own content (labels, buttons) is English-only, matching the existing `DiffPanel` (also unlocalized). Only the new "Settings…" *menu item* string is localized, added to `Erratly/AppStatus.swift`'s `Strings` struct for all 13 languages + the default.
- Commit messages follow this repo's existing style: a single gitmoji-prefixed line (see `git log --oneline -5` for examples, e.g. `✨ add remote correction provider`).
- Standalone `swift` script tests are throwaway — write them to your scratchpad directory (never into the `Erratly/` source tree), and run the real project source file(s) alongside them, e.g. `swift Erratly/KeychainHelper.swift <scratchpad>/main.swift`. Don't copy project code into the scratch file.

---

### Task 1: KeychainHelper

**Files:**
- Create: `Erratly/KeychainHelper.swift`
- Test: `<scratchpad>/main.swift` (throwaway, not committed)

**Interfaces:**
- Produces: `enum KeychainHelper { static func set(_ value: String, forAccount account: String); static func get(forAccount account: String) -> String?; static func delete(forAccount account: String) }`

- [ ] **Step 1: Write the failing test script**

Create `<scratchpad>/main.swift`:

```swift
import Foundation

let account = "erratly-test-account-\(UUID().uuidString)"

KeychainHelper.set("hello-world", forAccount: account)
guard KeychainHelper.get(forAccount: account) == "hello-world" else {
    print("FAIL: expected stored value to round-trip")
    exit(1)
}

KeychainHelper.delete(forAccount: account)
guard KeychainHelper.get(forAccount: account) == nil else {
    print("FAIL: expected value to be gone after delete")
    exit(1)
}

print("PASS")
```

- [ ] **Step 2: Run it to verify it fails**

Run (from `app/`): `swift <scratchpad>/main.swift`
Expected: compile error, `cannot find 'KeychainHelper' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Erratly/KeychainHelper.swift`:

```swift
import Foundation
import Security

enum KeychainHelper {
    private static let service = "com.erratly.app"

    static func set(_ value: String, forAccount account: String) {
        let data = Data(value.utf8)
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(baseQuery as CFDictionary)
        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func get(forAccount account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(forAccount account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
```

- [ ] **Step 4: Run it to verify it passes**

Run: `swift Erratly/KeychainHelper.swift <scratchpad>/main.swift`
Expected: prints `PASS`.

- [ ] **Step 5: Commit**

```bash
git add Erratly/KeychainHelper.swift
git commit -m "🔑 add Keychain helper for storing secrets"
```

---

### Task 2: AppSettings

**Files:**
- Create: `Erratly/AppSettings.swift`
- Test: `<scratchpad>/main.swift` (overwrite the previous one)

**Interfaces:**
- Consumes: `KeychainHelper.set/get/delete` (Task 1)
- Produces: `enum Backend: String { case local, remote }`; `final class AppSettings { static let shared: AppSettings; var backend: Backend; var remoteBaseURL: String; var remoteModelName: String; var remoteAPIKey: String? }`

- [ ] **Step 1: Write the failing test script**

Overwrite `<scratchpad>/main.swift`:

```swift
import Foundation

UserDefaults.standard.removeObject(forKey: "backend")
UserDefaults.standard.removeObject(forKey: "remoteBaseURL")
UserDefaults.standard.removeObject(forKey: "remoteModelName")

guard AppSettings.shared.backend == .local else {
    print("FAIL: default backend should be .local")
    exit(1)
}
guard AppSettings.shared.remoteBaseURL == "https://api.openai.com/v1" else {
    print("FAIL: unexpected default base URL")
    exit(1)
}

AppSettings.shared.backend = .remote
AppSettings.shared.remoteBaseURL = "https://example.com/v1"
AppSettings.shared.remoteModelName = "test-model"
AppSettings.shared.remoteAPIKey = "sk-test-123"

guard AppSettings.shared.backend == .remote,
      AppSettings.shared.remoteBaseURL == "https://example.com/v1",
      AppSettings.shared.remoteModelName == "test-model",
      AppSettings.shared.remoteAPIKey == "sk-test-123" else {
    print("FAIL: settings did not round-trip")
    exit(1)
}

AppSettings.shared.remoteAPIKey = nil
guard AppSettings.shared.remoteAPIKey == nil else {
    print("FAIL: expected api key to be cleared")
    exit(1)
}

print("PASS")
```

- [ ] **Step 2: Run it to verify it fails**

Run: `swift Erratly/KeychainHelper.swift <scratchpad>/main.swift`
Expected: compile error, `cannot find 'AppSettings' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Erratly/AppSettings.swift`:

```swift
import Foundation

enum Backend: String {
    case local
    case remote
}

final class AppSettings {
    static let shared = AppSettings()
    private init() {}

    private let apiKeyAccount = "erratly-remote-api-key"

    var backend: Backend {
        get {
            guard let raw = UserDefaults.standard.string(forKey: "backend"),
                  let value = Backend(rawValue: raw) else { return .local }
            return value
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "backend") }
    }

    var remoteBaseURL: String {
        get { UserDefaults.standard.string(forKey: "remoteBaseURL") ?? "https://api.openai.com/v1" }
        set { UserDefaults.standard.set(newValue, forKey: "remoteBaseURL") }
    }

    var remoteModelName: String {
        get { UserDefaults.standard.string(forKey: "remoteModelName") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "remoteModelName") }
    }

    var remoteAPIKey: String? {
        get { KeychainHelper.get(forAccount: apiKeyAccount) }
        set {
            if let key = newValue, !key.isEmpty {
                KeychainHelper.set(key, forAccount: apiKeyAccount)
            } else {
                KeychainHelper.delete(forAccount: apiKeyAccount)
            }
        }
    }
}
```

- [ ] **Step 4: Run it to verify it passes**

Run: `swift Erratly/KeychainHelper.swift Erratly/AppSettings.swift <scratchpad>/main.swift`
Expected: prints `PASS`.

- [ ] **Step 5: Commit**

```bash
git add Erratly/AppSettings.swift
git commit -m "⚙️ add AppSettings for backend/remote config"
```

---

### Task 3: CorrectionProvider protocol + shared system prompt

**Files:**
- Create: `Erratly/CorrectionProvider.swift`
- Test: `<scratchpad>/main.swift` (overwrite)

**Interfaces:**
- Consumes: `CorrectionPair` (existing, `Erratly/CorrectionHistory.swift`)
- Produces: `protocol CorrectionProvider { func prepare() async throws; func correctText(_ text: String, language: String?, examples: [CorrectionPair]) async throws -> String }`; `func buildCorrectionSystemPrompt(language: String?, examples: [CorrectionPair]) -> String`

- [ ] **Step 1: Write the failing test script**

Overwrite `<scratchpad>/main.swift`:

```swift
import Foundation

let base = buildCorrectionSystemPrompt(language: nil, examples: [])
guard base.contains("Fix spelling mistakes only"), !base.contains("The text is written in") else {
    print("FAIL: base prompt missing rules or unexpectedly mentions language")
    exit(1)
}

let withLanguage = buildCorrectionSystemPrompt(language: "French", examples: [])
guard withLanguage.contains("The text is written in French") else {
    print("FAIL: language hint missing")
    exit(1)
}

let withExamples = buildCorrectionSystemPrompt(language: nil, examples: [CorrectionPair(original: "teh", corrected: "the")])
guard withExamples.contains("\"teh\" → \"the\"") else {
    print("FAIL: example pair missing from prompt")
    exit(1)
}

print("PASS")
```

- [ ] **Step 2: Run it to verify it fails**

Run: `swift Erratly/CorrectionHistory.swift <scratchpad>/main.swift`
Expected: compile error, `cannot find 'buildCorrectionSystemPrompt' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Erratly/CorrectionProvider.swift`:

```swift
import Foundation

protocol CorrectionProvider {
    func prepare() async throws
    func correctText(_ text: String, language: String?, examples: [CorrectionPair]) async throws -> String
}

func buildCorrectionSystemPrompt(language: String?, examples: [CorrectionPair]) -> String {
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
```

- [ ] **Step 4: Run it to verify it passes**

Run: `swift Erratly/CorrectionHistory.swift Erratly/CorrectionProvider.swift <scratchpad>/main.swift`
Expected: prints `PASS`.

- [ ] **Step 5: Commit**

```bash
git add Erratly/CorrectionProvider.swift
git commit -m "🔌 add CorrectionProvider protocol and shared prompt builder"
```

---

### Task 4: LocalCorrectionProvider

**Files:**
- Create: `Erratly/LocalCorrectionProvider.swift`

**Interfaces:**
- Consumes: `CorrectionProvider`, `buildCorrectionSystemPrompt` (Task 3); `CorrectionPair` (existing)
- Produces: `actor LocalCorrectionProvider: CorrectionProvider { static let modelName: String; func prepare() async throws; func correctText(...) async throws -> String }`

This moves the existing MLX-backed logic out of `LLMService.swift` unchanged (aside from delegating prompt construction to `buildCorrectionSystemPrompt`). It imports MLX, so it can't be run as a standalone `swift` script — verify with a full Xcode build instead. `Erratly/LLMService.swift` still exists unmodified at this point (its own `correctText`/`modelName` still work), so this task is purely additive and the app's behavior doesn't change yet.

- [ ] **Step 1: Write the implementation**

Create `Erratly/LocalCorrectionProvider.swift`:

```swift
import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import Tokenizers

actor LocalCorrectionProvider: CorrectionProvider {
    static let modelName = "Qwen2.5-3B-Instruct-4bit"

    private var modelContainer: ModelContainer?

    func prepare() async throws {
        print("🤖 Loading model...")
        // MLX's GPU cache defaults to the memory limit, which lets freed
        // buffers pile up unreclaimed across corrections. Capping it keeps
        // resident memory close to what the model actually needs.
        MLX.GPU.set(cacheLimit: 20 * 1024 * 1024)
        let config = ModelConfiguration(id: "mlx-community/\(LocalCorrectionProvider.modelName)")
        modelContainer = try await LLMModelFactory.shared.loadContainer(configuration: config)
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
```

- [ ] **Step 2: Build to verify it compiles**

Run (from `app/`): `xcodebuild -project Erratly.xcodeproj -scheme Erratly -configuration Debug build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add Erratly/LocalCorrectionProvider.swift
git commit -m "📦 extract LocalCorrectionProvider from LLMService"
```

---

### Task 5: RemoteAPIFormat + RemoteCorrectionProvider

**Files:**
- Create: `Erratly/RemoteCorrectionProvider.swift`
- Test: `<scratchpad>/main.swift` (overwrite)

**Interfaces:**
- Consumes: `CorrectionProvider`, `buildCorrectionSystemPrompt` (Task 3), `CorrectionPair` (existing), `AppSettings.shared` (Task 2)
- Produces: `enum RemoteAPIError: Error, LocalizedError { case missingSettings, invalidURL, httpError(Int), malformedResponse }`; `enum RemoteAPIFormat { static func buildRequestBody(model: String, systemPrompt: String, userText: String) -> [String: Any]; static func parseContent(from data: Data) throws -> String }`; `actor RemoteCorrectionProvider: CorrectionProvider`

The test below only exercises `RemoteAPIFormat`'s pure request/response logic (no network call) — that's the part that's meaningfully testable without hitting a real API.

- [ ] **Step 1: Write the failing test script**

Overwrite `<scratchpad>/main.swift`:

```swift
import Foundation

let body = RemoteAPIFormat.buildRequestBody(model: "gpt-4o-mini", systemPrompt: "SYS", userText: "helo wrold")
guard let model = body["model"] as? String, model == "gpt-4o-mini" else {
    print("FAIL: model missing from request body")
    exit(1)
}
guard let messages = body["messages"] as? [[String: String]], messages.count == 2,
      messages[0]["role"] == "system", messages[0]["content"] == "SYS",
      messages[1]["role"] == "user", messages[1]["content"] == "helo wrold" else {
    print("FAIL: messages malformed")
    exit(1)
}

let goodJSON = """
{"choices":[{"message":{"role":"assistant","content":"hello world"}}]}
""".data(using: .utf8)!
guard try RemoteAPIFormat.parseContent(from: goodJSON) == "hello world" else {
    print("FAIL: did not parse valid response")
    exit(1)
}

let badJSON = "{}".data(using: .utf8)!
do {
    _ = try RemoteAPIFormat.parseContent(from: badJSON)
    print("FAIL: expected malformedResponse error")
    exit(1)
} catch RemoteAPIError.malformedResponse {
    // expected
} catch {
    print("FAIL: wrong error type: \(error)")
    exit(1)
}

print("PASS")
```

- [ ] **Step 2: Run it to verify it fails**

Run: `swift Erratly/CorrectionHistory.swift Erratly/KeychainHelper.swift Erratly/AppSettings.swift Erratly/CorrectionProvider.swift <scratchpad>/main.swift`
Expected: compile error, `cannot find 'RemoteAPIFormat' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Erratly/RemoteCorrectionProvider.swift`:

```swift
import Foundation

enum RemoteAPIError: Error, LocalizedError {
    case missingSettings
    case invalidURL
    case httpError(Int)
    case malformedResponse

    var errorDescription: String? {
        switch self {
        case .missingSettings: return "Remote API settings are incomplete"
        case .invalidURL: return "Remote API base URL is invalid"
        case .httpError(let code): return "Remote API returned HTTP \(code)"
        case .malformedResponse: return "Remote API returned an unexpected response"
        }
    }
}

enum RemoteAPIFormat {
    static func buildRequestBody(model: String, systemPrompt: String, userText: String) -> [String: Any] {
        [
            "model": model,
            "temperature": 0,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userText]
            ]
        ]
    }

    static func parseContent(from data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw RemoteAPIError.malformedResponse
        }
        return content
    }
}

actor RemoteCorrectionProvider: CorrectionProvider {
    func prepare() async throws {
        let settings = AppSettings.shared
        guard !settings.remoteBaseURL.isEmpty,
              !settings.remoteModelName.isEmpty,
              let key = settings.remoteAPIKey, !key.isEmpty else {
            throw RemoteAPIError.missingSettings
        }
    }

    func correctText(_ text: String, language: String?, examples: [CorrectionPair]) async throws -> String {
        let settings = AppSettings.shared
        guard let apiKey = settings.remoteAPIKey, !apiKey.isEmpty else {
            throw RemoteAPIError.missingSettings
        }
        guard let url = URL(string: "\(settings.remoteBaseURL)/chat/completions") else {
            throw RemoteAPIError.invalidURL
        }

        let systemPrompt = buildCorrectionSystemPrompt(language: language, examples: examples)
        let body = RemoteAPIFormat.buildRequestBody(model: settings.remoteModelName, systemPrompt: systemPrompt, userText: text)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw RemoteAPIError.httpError(code)
        }

        let content = try RemoteAPIFormat.parseContent(from: data)
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```

- [ ] **Step 4: Run it to verify it passes**

Run: `swift Erratly/CorrectionHistory.swift Erratly/KeychainHelper.swift Erratly/AppSettings.swift Erratly/CorrectionProvider.swift Erratly/RemoteCorrectionProvider.swift <scratchpad>/main.swift`
Expected: prints `PASS`.

- [ ] **Step 5: Build the whole target to verify the actor itself compiles cleanly**

Run: `xcodebuild -project Erratly.xcodeproj -scheme Erratly -configuration Debug build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add Erratly/RemoteCorrectionProvider.swift
git commit -m "🌐 add RemoteCorrectionProvider for OpenAI-compatible APIs"
```

---

### Task 6: LLMService coordinator

**Files:**
- Modify: `Erratly/LLMService.swift` (full rewrite)
- Modify: `Erratly/MenuBar.swift:12` (the "Model: …" menu item line)

**Interfaces:**
- Consumes: `CorrectionProvider`, `LocalCorrectionProvider` (Task 4), `RemoteCorrectionProvider` (Task 5), `AppSettings.shared.backend` (Task 2)
- Produces: `actor LLMService { static let shared: LLMService; func loadModel() async throws; func correctText(_ text: String, language: String?, examples: [CorrectionPair]) async throws -> String }` — same public interface as before, so `Erratly/ErratlyApp.swift`'s call sites (`LLMService.shared.loadModel()`, `LLMService.shared.correctText(...)`) need no changes.

This removes `LLMService.modelName`, which `MenuBar.swift:12` currently reads directly — that line must be updated in this same task or the build breaks.

- [ ] **Step 1: Rewrite the coordinator**

Replace the full contents of `Erratly/LLMService.swift`:

```swift
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
```

- [ ] **Step 2: Update the menu's model-name line**

In `Erratly/MenuBar.swift`, replace:

```swift
        let modelItem = NSMenuItem(title: "\(s.modelPrefix): \(LLMService.modelName)", action: nil, keyEquivalent: "")
```

with:

```swift
        let modelName: String = AppSettings.shared.backend == .local
            ? LocalCorrectionProvider.modelName
            : AppSettings.shared.remoteModelName
        let modelItem = NSMenuItem(title: "\(s.modelPrefix): \(modelName)", action: nil, keyEquivalent: "")
```

- [ ] **Step 3: Build to verify it compiles**

Run: `xcodebuild -project Erratly.xcodeproj -scheme Erratly -configuration Debug build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add Erratly/LLMService.swift Erratly/MenuBar.swift
git commit -m "♻️ turn LLMService into a local/remote coordinator"
```

---

### Task 7: SettingsWindow

**Files:**
- Create: `Erratly/SettingsWindow.swift`

**Interfaces:**
- Consumes: `AppSettings.shared`, `Backend` (Task 2)
- Produces: `final class SettingsWindow: NSWindowController { init(onSave: @escaping (_ backendOrConfigChanged: Bool) -> Void) }`

This is pure AppKit UI with no automated test harness in this project (no XCTest target, and a windowed UI can't be driven from a headless `swift` script). It isn't wired into the menu yet, so this task alone changes nothing the user can see — verify with a build only; the full interactive check happens once Task 8 wires it up.

- [ ] **Step 1: Write the implementation**

Create `Erratly/SettingsWindow.swift`:

```swift
import Cocoa

final class SettingsWindow: NSWindowController {
    private let onSave: (Bool) -> Void

    private var localRadio: NSButton!
    private var remoteRadio: NSButton!
    private var baseURLField: NSTextField!
    private var apiKeyField: NSSecureTextField!
    private var modelNameField: NSTextField!

    private let initialBackend: Backend
    private let initialBaseURL: String
    private let initialModelName: String
    private let initialAPIKey: String?

    init(onSave: @escaping (Bool) -> Void) {
        self.onSave = onSave
        self.initialBackend = AppSettings.shared.backend
        self.initialBaseURL = AppSettings.shared.remoteBaseURL
        self.initialModelName = AppSettings.shared.remoteModelName
        self.initialAPIKey = AppSettings.shared.remoteAPIKey

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Erratly Settings"
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }
        let padding: CGFloat = 20
        let fieldWidth: CGFloat = 360 - padding * 2
        let rowGap: CGFloat = 8
        let groupGap: CGFloat = 16
        let labelFieldGap: CGFloat = 4
        var y: CGFloat = 300 - padding

        y -= 20
        let localRadio = NSButton(radioButtonWithTitle: "Local (on-device)", target: self, action: #selector(backendChanged))
        localRadio.frame = NSRect(x: padding, y: y, width: fieldWidth, height: 20)
        contentView.addSubview(localRadio)
        self.localRadio = localRadio
        y -= rowGap

        y -= 20
        let remoteRadio = NSButton(radioButtonWithTitle: "Remote API", target: self, action: #selector(backendChanged))
        remoteRadio.frame = NSRect(x: padding, y: y, width: fieldWidth, height: 20)
        contentView.addSubview(remoteRadio)
        self.remoteRadio = remoteRadio
        y -= groupGap

        y -= 16
        let baseURLLabel = NSTextField(labelWithString: "Base URL")
        baseURLLabel.frame = NSRect(x: padding, y: y, width: fieldWidth, height: 16)
        contentView.addSubview(baseURLLabel)
        y -= labelFieldGap

        y -= 24
        let baseURLField = NSTextField(frame: NSRect(x: padding, y: y, width: fieldWidth, height: 24))
        baseURLField.placeholderString = "https://api.openai.com/v1"
        contentView.addSubview(baseURLField)
        self.baseURLField = baseURLField
        y -= groupGap

        y -= 16
        let apiKeyLabel = NSTextField(labelWithString: "API Key")
        apiKeyLabel.frame = NSRect(x: padding, y: y, width: fieldWidth, height: 16)
        contentView.addSubview(apiKeyLabel)
        y -= labelFieldGap

        y -= 24
        let apiKeyField = NSSecureTextField(frame: NSRect(x: padding, y: y, width: fieldWidth, height: 24))
        contentView.addSubview(apiKeyField)
        self.apiKeyField = apiKeyField
        y -= groupGap

        y -= 16
        let modelNameLabel = NSTextField(labelWithString: "Model Name")
        modelNameLabel.frame = NSRect(x: padding, y: y, width: fieldWidth, height: 16)
        contentView.addSubview(modelNameLabel)
        y -= labelFieldGap

        y -= 24
        let modelNameField = NSTextField(frame: NSRect(x: padding, y: y, width: fieldWidth, height: 24))
        modelNameField.placeholderString = "gpt-4o-mini"
        contentView.addSubview(modelNameField)
        self.modelNameField = modelNameField

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelAction))
        cancelButton.frame = NSRect(x: 360 - padding - 160, y: padding, width: 75, height: 24)
        cancelButton.keyEquivalent = "\u{1B}"
        contentView.addSubview(cancelButton)

        let saveButton = NSButton(title: "Save", target: self, action: #selector(saveAction))
        saveButton.frame = NSRect(x: 360 - padding - 80, y: padding, width: 80, height: 24)
        saveButton.keyEquivalent = "\r"
        contentView.addSubview(saveButton)

        localRadio.state = initialBackend == .local ? .on : .off
        remoteRadio.state = initialBackend == .remote ? .on : .off
        baseURLField.stringValue = initialBaseURL
        apiKeyField.stringValue = initialAPIKey ?? ""
        modelNameField.stringValue = initialModelName
        updateFieldsEnabled()
    }

    private func updateFieldsEnabled() {
        let remoteEnabled = remoteRadio.state == .on
        baseURLField.isEnabled = remoteEnabled
        apiKeyField.isEnabled = remoteEnabled
        modelNameField.isEnabled = remoteEnabled
    }

    @objc private func backendChanged() {
        updateFieldsEnabled()
    }

    @objc private func cancelAction() {
        window?.close()
    }

    @objc private func saveAction() {
        let newBackend: Backend = remoteRadio.state == .on ? .remote : .local
        let newBaseURL = baseURLField.stringValue
        let newModelName = modelNameField.stringValue
        let newAPIKey = apiKeyField.stringValue

        let changed = newBackend != initialBackend
            || (newBackend == .remote && (newBaseURL != initialBaseURL || newModelName != initialModelName || newAPIKey != (initialAPIKey ?? "")))

        AppSettings.shared.backend = newBackend
        AppSettings.shared.remoteBaseURL = newBaseURL
        AppSettings.shared.remoteModelName = newModelName
        AppSettings.shared.remoteAPIKey = newAPIKey.isEmpty ? nil : newAPIKey

        window?.close()
        onSave(changed)
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild -project Erratly.xcodeproj -scheme Erratly -configuration Debug build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add Erratly/SettingsWindow.swift
git commit -m "🪟 add Settings window for backend/remote config"
```

---

### Task 8: Wire Settings into the menu

**Files:**
- Modify: `Erratly/AppStatus.swift` (add `settings` to `Strings`)
- Modify: `Erratly/ErratlyApp.swift` (add `settingsWindow` property)
- Modify: `Erratly/MenuBar.swift` (add the menu item + action)

**Interfaces:**
- Consumes: `SettingsWindow` (Task 7), `LLMService.shared.loadModel()` (Task 6)
- Produces: `AppDelegate.settingsWindow: SettingsWindow?`; `AppDelegate.openSettings()` (menu action)

- [ ] **Step 1: Add the `settings` string**

In `Erratly/AppStatus.swift`, add `let settings: String` to the `Strings` struct definition (after `clearHistory`) and add a `settings:` argument to every `Strings(...)` call in `forLanguage(_:)`. Replace the whole `Strings` struct with:

```swift
struct Strings {
    let loading: String
    let ready: String
    let processing: String
    let error: String
    let modelPrefix: String
    let language: String
    let autoDetect: String
    let reviewBeforeApplying: String
    let clearHistory: String
    let settings: String
    let quit: String

    func label(for status: AppStatus) -> String {
        switch status {
        case .loading: return loading
        case .ready: return ready
        case .processing: return processing
        case .error: return error
        }
    }

    static func forLanguage(_ language: String?) -> Strings {
        switch language {
        case "French":
            return Strings(loading: "Chargement du modèle...", ready: "Erratly est prêt", processing: "Correction en cours...", error: "Impossible de charger le modèle", modelPrefix: "Modèle", language: "Langue", autoDetect: "Détection automatique", reviewBeforeApplying: "Vérifier avant d'appliquer", clearHistory: "Effacer l'historique", settings: "Réglages…", quit: "Quitter Erratly")
        case "Spanish":
            return Strings(loading: "Cargando modelo...", ready: "Erratly está listo", processing: "Corrigiendo texto...", error: "Error al cargar el modelo", modelPrefix: "Modelo", language: "Idioma", autoDetect: "Detección automática", reviewBeforeApplying: "Revisar antes de aplicar", clearHistory: "Borrar historial", settings: "Ajustes…", quit: "Salir de Erratly")
        case "German":
            return Strings(loading: "Modell wird geladen...", ready: "Erratly ist bereit", processing: "Text wird korrigiert...", error: "Modell konnte nicht geladen werden", modelPrefix: "Modell", language: "Sprache", autoDetect: "Automatisch erkennen", reviewBeforeApplying: "Vor dem Anwenden überprüfen", clearHistory: "Verlauf löschen", settings: "Einstellungen…", quit: "Erratly beenden")
        case "Italian":
            return Strings(loading: "Caricamento modello...", ready: "Erratly è pronto", processing: "Correzione in corso...", error: "Impossibile caricare il modello", modelPrefix: "Modello", language: "Lingua", autoDetect: "Rilevamento automatico", reviewBeforeApplying: "Rivedi prima di applicare", clearHistory: "Cancella cronologia", settings: "Impostazioni…", quit: "Esci da Erratly")
        case "Portuguese":
            return Strings(loading: "Carregando modelo...", ready: "Erratly está pronto", processing: "Corrigindo texto...", error: "Falha ao carregar o modelo", modelPrefix: "Modelo", language: "Idioma", autoDetect: "Detecção automática", reviewBeforeApplying: "Revisar antes de aplicar", clearHistory: "Limpar histórico", settings: "Configurações…", quit: "Sair do Erratly")
        case "Dutch":
            return Strings(loading: "Model wordt geladen...", ready: "Erratly is klaar", processing: "Tekst wordt gecorrigeerd...", error: "Laden van model mislukt", modelPrefix: "Model", language: "Taal", autoDetect: "Automatisch detecteren", reviewBeforeApplying: "Bekijk voor het toepassen", clearHistory: "Geschiedenis wissen", settings: "Instellingen…", quit: "Erratly afsluiten")
        case "Polish":
            return Strings(loading: "Ładowanie modelu...", ready: "Erratly jest gotowy", processing: "Korygowanie tekstu...", error: "Nie udało się załadować modelu", modelPrefix: "Model", language: "Język", autoDetect: "Automatyczne wykrywanie", reviewBeforeApplying: "Sprawdź przed zastosowaniem", clearHistory: "Wyczyść historię", settings: "Ustawienia…", quit: "Zamknij Erratly")
        case "Russian":
            return Strings(loading: "Загрузка модели...", ready: "Erratly готов к работе", processing: "Исправление текста...", error: "Не удалось загрузить модель", modelPrefix: "Модель", language: "Язык", autoDetect: "Автоопределение", reviewBeforeApplying: "Просмотреть перед применением", clearHistory: "Очистить историю", settings: "Настройки…", quit: "Выйти из Erratly")
        case "Japanese":
            return Strings(loading: "モデルを読み込み中...", ready: "Erratly は使用可能です", processing: "テキストを修正中...", error: "モデルの読み込みに失敗しました", modelPrefix: "モデル", language: "言語", autoDetect: "自動検出", reviewBeforeApplying: "適用前に確認", clearHistory: "履歴を消去", settings: "設定…", quit: "Erratly を終了")
        case "Chinese":
            return Strings(loading: "正在加载模型...", ready: "Erratly 已就绪", processing: "正在纠正文本...", error: "模型加载失败", modelPrefix: "模型", language: "语言", autoDetect: "自动检测", reviewBeforeApplying: "应用前预览", clearHistory: "清除历史", settings: "设置…", quit: "退出 Erratly")
        case "Korean":
            return Strings(loading: "모델 로딩 중...", ready: "Erratly 사용 준비 완료", processing: "텍스트 수정 중...", error: "모델 로드 실패", modelPrefix: "모델", language: "언어", autoDetect: "자동 감지", reviewBeforeApplying: "적용 전 검토", clearHistory: "기록 지우기", settings: "설정…", quit: "Erratly 종료")
        case "Arabic":
            return Strings(loading: "جارٍ تحميل النموذج...", ready: "Erratly جاهز للاستخدام", processing: "جارٍ تصحيح النص...", error: "فشل في تحميل النموذج", modelPrefix: "النموذج", language: "اللغة", autoDetect: "الكشف التلقائي", reviewBeforeApplying: "مراجعة قبل التطبيق", clearHistory: "مسح السجل", settings: "الإعدادات…", quit: "إنهاء Erratly")
        default:
            return Strings(loading: "Model is downloading...", ready: "Erratly is ready to use", processing: "Correcting text...", error: "Failed to load model", modelPrefix: "Model", language: "Language", autoDetect: "Auto-detect", reviewBeforeApplying: "Review before applying", clearHistory: "Clear correction history", settings: "Settings…", quit: "Quit Erratly")
        }
    }
}
```

- [ ] **Step 2: Add the `settingsWindow` property**

In `Erratly/ErratlyApp.swift`, add a property next to `diffPanel`:

```swift
    var diffPanel: DiffPanel?
    var settingsWindow: SettingsWindow?
```

- [ ] **Step 3: Add the menu item and action**

In `Erratly/MenuBar.swift`'s `updateMenu`, add the item right after `modelItem` is added:

```swift
        menu.addItem(modelItem)

        let settingsItem = NSMenuItem(title: s.settings, action: #selector(openSettings), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())
```

(This replaces the standalone `menu.addItem(.separator())` that previously followed `modelItem` directly.)

Add the action method to the same extension as `toggleDiffPanel` / `clearCorrectionHistory`:

```swift
    @objc func openSettings() {
        settingsWindow?.window?.close()
        settingsWindow = SettingsWindow(onSave: { [weak self] configChanged in
            guard let self else { return }
            self.updateMenu(status: self.currentStatus)
            guard configChanged else { return }
            self.setStatus(.loading)
            Task {
                do {
                    try await LLMService.shared.loadModel()
                    self.setStatus(.ready)
                } catch {
                    print("❌ Failed to reload backend: \(error)")
                    self.setStatus(.error)
                }
            }
        })
        settingsWindow?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
```

- [ ] **Step 4: Build to verify it compiles**

Run: `xcodebuild -project Erratly.xcodeproj -scheme Erratly -configuration Debug build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Manual verification in Xcode**

No automated harness covers the end-to-end flow, so run it by hand:

1. `open Erratly.xcodeproj`, run the app (default Local backend). Select some misspelled text somewhere, double-tap Control, confirm it's corrected exactly as before this change.
2. Click the menu bar icon → Settings…. Switch to "Remote API", fill in a real base URL (e.g. `https://api.openai.com/v1`), an API key, and a model name (e.g. `gpt-4o-mini`). Save. Confirm the status icon shows ⏳ briefly then ✦, and the menu's "Model: …" line now shows the remote model name.
3. Correct some text again — confirm it's corrected via the network call (check for outbound activity or correctness of a fix a local 3B model would likely miss).
4. Open Settings again, deliberately break the API key (e.g. add a character) or set an unreachable base URL, Save, then trigger a correction. Confirm the status goes to ⚠️, and the clipboard/selection is left untouched (not replaced with garbage).
5. Quit and relaunch the app. Confirm the backend is still "Remote API" and the model name field still shows what you entered (settings persisted), and that `~/Library/Preferences/<bundle-id>.plist` does not contain the API key (only `backend`, `remoteBaseURL`, `remoteModelName` should appear there — the key must only be in Keychain).

- [ ] **Step 6: Commit**

```bash
git add Erratly/AppStatus.swift Erratly/ErratlyApp.swift Erratly/MenuBar.swift
git commit -m "🔗 wire Settings window into the menu bar"
```

---

### Task 9: Update docs

**Files:**
- Modify: `CLAUDE.md`
- Modify: `README.md`

- [ ] **Step 1: Update `CLAUDE.md`**

Replace the `Prerequisites` section's local-model bullet:

```markdown
- **Local model**: Qwen 2.5 3B must be present at `~/Documents/models/qwen2.5-3b`. The app will load into `.error` status if the model is missing.
```

with:

```markdown
- **Local model** (only required for the Local backend, the default): Qwen 2.5 3B, downloaded automatically from Hugging Face on first launch. The app will load into `.error` status if it can't be loaded.
- **Remote backend**: requires a base URL, model name, and API key, configured via the menu bar's "Settings…" window. The API key is stored in the macOS Keychain, never in `UserDefaults`.
```

Replace the `LLMService.swift` bullet in `Architecture` (and everything under it):

```markdown
**`Erratly/LLMService.swift`** — Singleton wrapping the local MLX model.
- Loads a `ModelConfiguration` from a local directory path (not a remote download).
- `correctText` builds a strict prompt instructing the model to fix spelling/grammar only — no rephrasing, no word addition/removal — and returns `temperature: 0.0` output.
```

with:

```markdown
**`Erratly/LLMService.swift`** — Thin coordinator that holds whichever `CorrectionProvider` is active (local or remote) and exposes `loadModel()` / `correctText()` to the rest of the app.
- **`Erratly/CorrectionProvider.swift`** — the `CorrectionProvider` protocol both backends conform to, plus the shared system prompt builder (spelling/grammar-only rules, language hint, style examples).
- **`Erratly/LocalCorrectionProvider.swift`** — the on-device MLX model.
- **`Erratly/RemoteCorrectionProvider.swift`** — calls an OpenAI-compatible `/chat/completions` endpoint using the base URL / API key / model name from `AppSettings`.
- **`Erratly/AppSettings.swift`** — `UserDefaults`-backed backend selection and remote config; the API key itself lives in the macOS Keychain via `Erratly/KeychainHelper.swift`.
- **`Erratly/SettingsWindow.swift`** — the "Settings…" window (menu bar) for choosing local vs. remote and entering remote config.
```

- [ ] **Step 2: Update `README.md`**

Replace:

```markdown
All corrections run locally on your machine using a small language model — nothing is sent to the cloud.
```

with:

```markdown
By default, corrections run locally on your machine using a small language model — nothing leaves your Mac. You can optionally connect a remote API (OpenAI, or any OpenAI-compatible endpoint) with your own API key instead.
```

Add a new section after `## Model`:

```markdown

## Remote API (optional)

Click the menu bar icon → **Settings…**, choose **Remote API**, and enter a base URL, model name, and your API key. The key is stored in the macOS Keychain — it's never written to disk in plain text. Once saved, corrections run against that API instead of the local model.
```

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md README.md
git commit -m "📝 document remote model support"
```

## Self-Review

**Spec coverage:**
- Provider abstraction (protocol + shared prompt) → Task 3.
- Local provider unchanged behavior → Task 4.
- Remote provider, request/response format, error types → Task 5.
- Coordinator lazy-loading based on `AppSettings.backend` → Task 6.
- Settings storage (`UserDefaults` + Keychain) → Tasks 1–2.
- Settings UI (radio + 3 fields + Cancel/Save) → Task 7.
- Menu wiring, "Settings…" localization, model-name display → Tasks 6, 8.
- Error handling / no fallback → built into Task 5's `RemoteCorrectionProvider` (throws, no retry) and confirmed manually in Task 8 step 5.4.
- Startup/backend-switch loading behavior → Task 6 (`loadModel()`), Task 8 (`openSettings`'s conditional reload).
- Manual test plan from the spec's Testing section → Task 8 step 5 (all 5 items covered).
- Docs → Task 9.

No gaps found.

**Placeholder scan:** No TBD/TODO markers; every step has literal code or an exact command.

**Type consistency:** `CorrectionProvider`, `AppSettings`/`Backend`, `KeychainHelper`, `RemoteAPIFormat`/`RemoteAPIError`, `LocalCorrectionProvider.modelName`, and `LLMService`'s public interface are used with the same names and signatures everywhere they're referenced across tasks.

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-09-04-remote-model-support.md`. Two execution options:

1. **Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration
2. **Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

Which approach?
