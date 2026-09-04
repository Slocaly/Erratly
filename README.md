<div align="center">
  <img src="icon.png" width="128" alt="Erratly icon" />
  <h1>Erratly</h1>
  <p>Fix spelling and grammar anywhere on your Mac — without leaving your app.</p>
</div>

---

## How it works

Select any text, double-tap <kbd>Control</kbd>, and Erratly silently corrects spelling and grammar in place. It works in any app: Notes, Slack, your browser, your IDE.

By default, corrections run locally on your machine using a small language model — nothing leaves your Mac. You can optionally connect a remote API (OpenAI, or any OpenAI-compatible endpoint) with your own API key instead.

## Requirements

- macOS 13 or later
- Apple Silicon (M1 or newer)
- ~2 GB of free disk space (for the model, downloaded automatically on first launch)

## Installation

1. Download the latest release and move `Erratly.app` to your Applications folder.
2. Launch the app — the `✦` icon appears in your menu bar.
3. On first launch, the model downloads automatically (~1.8 GB). The icon shows ⏳ while this happens.
4. Grant Accessibility permission when prompted — this is required to read and replace text in other apps.

Once the icon shows `✦`, Erratly is ready.

## Usage

| Action | Result |
|---|---|
| Double-tap <kbd>Control</kbd> | Corrects the selected text in-place |
| Click the menu bar icon | Shows current status and model info |

Erratly launches automatically at login after the first run.

## What it fixes

- Spelling mistakes
- Wrong verb conjugations
- Incorrect accents

It does **not** rephrase, rewrite, or change your word choices — only fixes clear errors.

## Model

Erratly uses [Qwen2.5-3B-Instruct](https://huggingface.co/mlx-community/Qwen2.5-3B-Instruct-4bit) (4-bit quantized), running locally via [MLX](https://github.com/ml-explore/mlx-swift). The model is downloaded from Hugging Face on first launch and cached on your machine — no internet connection is needed after that.

## Remote API (optional)

Click the menu bar icon → **Settings…**, choose **Remote API**, and enter a base URL, model name, and your API key. The key is stored in the macOS Keychain — it's never written to disk in plain text. Once saved, corrections run against that API instead of the local model.
