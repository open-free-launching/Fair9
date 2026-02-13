![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)
![Version](https://img.shields.io/badge/version-1.0-green.svg)
![Platform](https://img.shields.io/badge/platform-windows%20%7C%20macos-lightgrey.svg)

# Fair9

**The Open Source, Ultra-Low Latency Voice Assistant.**

Fair9 is a next-generation voice interface built with **Flutter** (UI) and **Rust** (Engine) to deliver instantaneous transcription and command execution. All processing runs locally — no cloud, no API keys, complete privacy.

## Features
- 🎙️ **Zero-Latency Transcription** — Powered by `cpal` and `whisper-rs` in Rust.
- 🪟 **Glassmorphic HUD** — A beautiful, frameless overlay that floats on your desktop.
- 🔒 **Privacy First** — 100% local inference. Your voice never leaves your machine.
- ✍️ **Smart Formatting** — Context-aware punctuation and capitalization.
- 🧠 **Voice Activity Detection** — Only processes audio when you're speaking.
- 🔄 **Auto-Update** — Checks GitHub for new releases and notifies you in the HUD.

## Tech Stack
| Layer | Technology |
|-------|-----------|
| UI | Flutter (Windows Desktop) |
| Engine | Rust (`cpal`, `whisper-rs`) |
| Bridge | `flutter_rust_bridge` |
| Models | Whisper GGML (quantized q8_0) |

## Getting Started
1. Download the latest installer from [Releases](https://github.com/open-free-launching/Fair9/releases).
2. Run the installer — Fair9 will automatically download the speech model on first launch.
3. Press the hotkey to start dictating!

## Credits
**Lead Developer**: [Saleem7x3](https://github.com/Saleem7x3)

## License
Licensed under the [GNU General Public License v3.0](LICENSE).
