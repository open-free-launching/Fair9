# 🗣️ Fair9 — Community Model Guide

> A list of compatible Whisper models for Fair9, with download links and benchmarks.

## Quick Start

Fair9 uses [whisper.cpp](https://github.com/ggerganov/whisper.cpp) models in GGML format.
Place your model in: `%APPDATA%\OpenFL\Fair9\models\`

## Recommended Models

| Model | Size | RAM | Speed | Accuracy | Best For |
|-------|------|-----|-------|----------|----------|
| **tiny.en (q8_0)** ⭐ | 42 MB | ~200 MB | ⚡ Instant | ★★★☆☆ | Daily dictation, quick notes |
| **base.en (q8_0)** | 82 MB | ~350 MB | ⚡ Fast | ★★★★☆ | Professional writing |
| **small.en** | 466 MB | ~1 GB | 🔄 Medium | ★★★★★ | Content creation, accuracy-first |
| **tiny (multilingual)** | 75 MB | ~250 MB | ⚡ Instant | ★★★☆☆ | Multi-language support |

## Download Links (Hugging Face)

```
# Quantized (recommended — 50% less RAM)
https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.en-q8_0.bin
https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en-q8_0.bin
https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en-q8_0.bin

# Full precision (higher accuracy, more RAM)
https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.en.bin
https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin
https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin
```

## Custom Models

You can use any fine-tuned Whisper model converted to GGML format:

1. Convert your model: `python convert-pt-to-ggml.py`
2. Quantize (optional): `./quantize model.bin model-q8_0.bin q8_0`
3. Drop the `.bin` file into `%APPDATA%\OpenFL\Fair9\models\`
4. Restart Fair9

## Community Contributions

Have a fine-tuned model for a specific language or domain?
Open a PR to add it to this list!

| Model | Language | Domain | Contributor | Link |
|-------|----------|--------|-------------|------|
| *your model here* | | | | |

---

*Built with ❤️ by [Open FL](https://github.com/open-free-launching)*
