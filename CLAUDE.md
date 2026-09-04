# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Erratly is a macOS menu bar app that corrects spelling and grammar in any text field system-wide. It listens for a double-tap of the Control key, captures the selected text, runs it through a local LLM, and replaces the original text with the corrected version — all without leaving the current app.

## Build & Run

Open and build in Xcode:
```
open Erratly.xcodeproj
```

Or build from the command line:
```bash
xcodebuild -project Erratly.xcodeproj -scheme Erratly -configuration Debug build
```

There are no tests. The app must be run on Apple Silicon (MLX requires it).

## Prerequisites

- **Accessibility permission**: The app prompts on first launch via `AXIsProcessTrustedWithOptions`. Without it, text capture and replacement silently fail.
- **Local model** (only required for the Local backend, the default): Qwen 2.5 3B, downloaded automatically from Hugging Face on first launch. The app will load into `.error` status if it can't be loaded.
- **Remote backend**: requires a base URL, model name, and API key, configured via the menu bar's "Settings…" window. The API key is stored in the macOS Keychain, never in `UserDefaults`.

## Architecture

The app has two source files:

**`Erratly/ErratlyApp.swift`** — Entry point and all system interaction logic.
- `SpellFixApp` / `AppDelegate`: Manages the NSStatusBar icon and global Control key event monitor.
- The double-tap detection window is 400ms (`lastControlPressTime` comparison).
- Text capture tries Accessibility API (`kAXSelectedTextAttribute`) first; falls back to simulating Cmd+C and reading the clipboard.
- Text replacement tries AX (`kAXSelectedTextAttribute` write) first; falls back to writing to clipboard and simulating Cmd+V.
- Both fallback paths save and restore the user's clipboard contents.
- `handleSelectedText` drives the async LLM call and updates the status icon (⏳ loading → ✦ ready → ⟳ processing → ⚠️ error).

**`Erratly/LLMService.swift`** — Thin coordinator that holds whichever `CorrectionProvider` is active (local or remote) and exposes `loadModel()` / `correctText()` to the rest of the app.
- **`Erratly/CorrectionProvider.swift`** — the `CorrectionProvider` protocol both backends conform to, plus the shared system prompt builder (spelling/grammar-only rules, language hint, style examples).
- **`Erratly/LocalCorrectionProvider.swift`** — the on-device MLX model.
- **`Erratly/RemoteCorrectionProvider.swift`** — calls an OpenAI-compatible `/chat/completions` endpoint using the base URL / API key / model name from `AppSettings`.
- **`Erratly/AppSettings.swift`** — `UserDefaults`-backed backend selection and remote config; the API key itself lives in the macOS Keychain via `Erratly/KeychainHelper.swift`.
- **`Erratly/SettingsWindow.swift`** — the "Settings…" window (menu bar) for choosing local vs. remote and entering remote config.

## Dependencies

Managed via Swift Package Manager inside Xcode (see `Package.resolved`):
- `mlx-swift` + `mlx-swift-examples` — Apple's MLX on-device inference; provides `MLXLLM` and `MLXLMCommon`.
- `swift-transformers` + `swift-jinja` — Hugging Face tokenizer support.

SPM dependencies are resolved automatically when opening the project in Xcode.
