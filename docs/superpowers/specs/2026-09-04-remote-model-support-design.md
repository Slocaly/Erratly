# Remote model support (bring-your-own API key)

## Goal

Let the user choose between the existing on-device local model (Qwen 2.5 3B
via MLX) and a remote LLM reached over an OpenAI-compatible HTTP API, using
their own API key. This covers OpenAI itself as well as any
OpenAI-compatible endpoint (OpenRouter, Groq, a local Ollama/LM Studio
server, etc.) since the user configures base URL, API key, and model name
directly rather than picking from a fixed provider list.

## Provider abstraction

Introduce a protocol that both backends conform to:

```swift
protocol CorrectionProvider {
    func prepare() async throws           // load/validate, called once before first use
    func correctText(_ text: String, language: String?, examples: [CorrectionPair]) async throws -> String
}
```

- **`LocalCorrectionProvider`** (actor) — today's `LLMService` body, moved
  as-is: `prepare()` loads the MLX model (current `loadModel()` logic),
  `correctText` is unchanged.
- **`RemoteCorrectionProvider`** (actor) — new. `prepare()` validates that
  base URL, API key, and model name are all non-empty (throws otherwise, no
  network call needed to "load"). `correctText` performs the HTTP call
  described below.

Both providers use one shared system-prompt builder (extracted from the
current `correctText` in `LLMService.swift`) so the correction rules
(spelling/grammar only, no rephrasing, language hint, style examples) stay
byte-for-byte identical regardless of backend.

`LLMService` (kept as the name other files already reference) becomes a thin
coordinator/facade:

```swift
actor LLMService {
    static let shared = LLMService()
    private var activeProvider: CorrectionProvider?

    func loadModel() async throws {
        let provider: CorrectionProvider = AppSettings.shared.backend == .local
            ? LocalCorrectionProvider()
            : RemoteCorrectionProvider()
        try await provider.prepare()
        activeProvider = provider
    }

    func correctText(...) async throws -> String {
        guard let provider = activeProvider else { throw ... }
        return try await provider.correctText(...)
    }
}
```

`ErratlyApp.swift`'s call sites (`LLMService.shared.loadModel()` at launch,
`LLMService.shared.correctText(...)` in `handleSelectedText`) are unchanged.

## Settings storage

New `AppSettings` (mirrors the existing `UserDefaults`-backed computed
properties already on `AppDelegate`, e.g. `selectedLanguage`):

- `backend: Backend` (`enum Backend: String { case local, remote }`) —
  `UserDefaults`, default `.local`.
- `remoteBaseURL: String` — `UserDefaults`, default
  `"https://api.openai.com/v1"`.
- `remoteModelName: String` — `UserDefaults`, default `""`.
- `remoteAPIKey: String?` — via a new `KeychainHelper` (generic
  get/set/delete for a `String` under a fixed account name
  `"erratly-remote-api-key"`), **not** `UserDefaults`. The app's sandbox is
  disabled (`ENABLE_APP_SANDBOX = NO`), so plain Keychain Services calls work
  with no entitlement changes.

`prepare()` on `RemoteCorrectionProvider` reads these via `AppSettings` at
call time (not cached at init), so a settings change takes effect the next
time the backend is (re)loaded.

## Settings UI

New `SettingsWindow.swift`: an `NSWindowController` built the same manual
AppKit way as `DiffPanel.swift` (no SwiftUI in this codebase). Contents:

- Two radio buttons: "Local (on-device)" / "Remote API".
- Three text fields, enabled only when Remote is selected: Base URL
  (`NSTextField`), API Key (`NSSecureTextField`), Model Name
  (`NSTextField`).
- Cancel / Save buttons. Save writes to `AppSettings` + `KeychainHelper`,
  closes the window, and — if the backend selection or remote config
  actually changed — calls `LLMService.shared.loadModel()` again in a
  `Task`, driving the same `.loading` → `.ready`/`.error` status transitions
  `ErratlyApp.swift` already does at launch.

`MenuBar.swift` gains a new item, "Settings…" (added to the `Strings`
struct and translated for all existing languages, same as the other menu
strings), opening the settings window. The existing "Model: …" line shows
`LLMService.modelName` when local is active, or the configured
`remoteModelName` when remote is active.

## Remote request/response

`RemoteCorrectionProvider.correctText`:

- `POST {baseURL}/chat/completions`
- Headers: `Authorization: Bearer <apiKey>`, `Content-Type: application/json`
- Body: `{"model": <remoteModelName>, "temperature": 0, "messages": [{"role": "system", "content": <sharedSystemPrompt>}, {"role": "user", "content": <text>}]}`
- Parse `choices[0].message.content` from the JSON response, trim whitespace
  (matches today's local-provider return value shape).
- Any failure — non-2xx status, malformed/missing JSON fields, network
  error, or a `URLSession` timeout — throws an `NSError` the same shape as
  today's `"Model not loaded"` error.

## Error handling

No fallback between backends. A `RemoteCorrectionProvider` failure is caught
by `ErratlyApp.swift`'s existing `catch` block in `handleSelectedText`
exactly like a local-model failure today: clipboard is restored to its
pre-capture contents, status goes to `.error`, error is printed. The user
fixes their settings (via the new Settings window) and retries.

## Startup / backend-switch loading behavior

- App launch: `LLMService.shared.loadModel()` is called once, as today. It
  now instantiates whichever provider `AppSettings.shared.backend` points
  to. If `.local`, MLX loads eagerly (unchanged from today). If `.remote`,
  no local model is loaded at all — `prepare()` just validates settings and
  returns, so startup is fast and MLX's memory footprint is never paid.
- Switching backends via the Settings window triggers a fresh
  `loadModel()` call (see above), which lazily loads whatever wasn't
  already active. Switching from remote to local for the first time in a
  session shows the `.loading` status while MLX loads, same as a cold
  start today.

## Out of scope

- No provider-specific presets or model picker/dropdown — base URL, API
  key, and model name are free-text fields the user fills in themselves.
- No automatic fallback from remote to local on failure.
- No usage/cost tracking for remote calls.
- Settings window content is not localized (matches `DiffPanel`, which is
  also English-only); only the new "Settings…" menu item string is
  translated.

## Testing

No test suite exists in this repo (per `CLAUDE.md`). Verify manually in
Xcode:

1. Local backend (default): behavior is unchanged from before this change.
2. Remote backend with a valid OpenAI key/URL/model: text is corrected via
   the network call.
3. Remote backend with an invalid key or unreachable URL: app surfaces
   `.error` status without crashing, clipboard is left untouched.
4. API key persists across an app restart (Keychain) and does not appear in
   `~/Library/Preferences/*.plist` (UserDefaults).
5. Switching backend in Settings while the app is running correctly
   transitions status (`.loading` if local needs to load) and subsequent
   corrections use the newly selected backend.
