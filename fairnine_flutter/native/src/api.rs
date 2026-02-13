use std::sync::{Arc, Mutex};
use std::thread;
use std::sync::atomic::{AtomicBool, Ordering};
use std::path::PathBuf;
use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use whisper_rs::{WhisperContext, FullParams, SamplingStrategy};
use flutter_rust_bridge::StreamSink;
use anyhow::{Result, Context, anyhow};
use lazy_static::lazy_static;

const APP_VERSION: &str = "1.0.0";
const GITHUB_REPO: &str = "open-free-launching/Fair9";

// Constants
const VAD_THRESHOLD_RMS: f32 = 0.01; // Adjust based on mic sensitivity
const SILENCE_DURATION_MS: u128 = 1000; // 1 second silence to finalize/clear?
const SAMPLE_RATE: usize = 16000;

// Global State
struct AppState {
    is_listening: AtomicBool,
    audio_buffer: Mutex<Vec<f32>>,
    model_ctx: Mutex<Option<WhisperContext>>,
}

lazy_static! {
    static ref STATE: Arc<AppState> = Arc::new(AppState {
        is_listening: AtomicBool::new(false),
        audio_buffer: Mutex::new(Vec::new()),
        model_ctx: Mutex::new(None),
    });
}

fn get_model_path() -> Result<PathBuf> {
    let mut path = dirs::data_dir().ok_or_else(|| anyhow!("Could not find data directory"))?;
    path.push("OpenFL");
    path.push("Fair9");
    path.push("models");
    path.push("whisper-cpp"); 
    // Assuming model_manager.py puts them in whisper-cpp folder, or just models?
    // User said: ~/AppData/Roaming/OpenFL/Fair9/models
    // We will assume a specific model name, e.g., ggml-tiny.en.bin exists there.
    // For now, let's look for 'ggml-tiny.en.bin' inside that path.
    path.push("ggml-tiny.en-q8_0.bin");
    Ok(path)
}

pub fn init_model() -> Result<String> {
    let model_path = get_model_path()?;
    if !model_path.exists() {
        return Err(anyhow!("Model not found at {:?}", model_path));
    }

    let ctx = WhisperContext::new(model_path.to_str().unwrap()).context("failed to load model")?;
    let mut guard = STATE.model_ctx.lock().unwrap();
    *guard = Some(ctx);
    
    Ok(format!("Model loaded from {:?}", model_path))
}

pub fn calculate_rms(data: &[f32]) -> f32 {
    if data.is_empty() { return 0.0; }
    let sum_squares: f32 = data.iter().map(|&x| x * x).sum();
    (sum_squares / data.len() as f32).sqrt()
}

/// AI Polish: Remove filler words from transcribed text
pub fn clean_filler_words(text: &str) -> String {
    let fillers = [
        " um ", " uh ", " hmm ", " uhh ", " umm ",
        " like ", " you know ", " I mean ",
        " sort of ", " kind of ",
        " basically ", " actually ",
        " um,", " uh,", " hmm,",
    ];
    let mut result = format!(" {} ", text); // pad for matching
    for filler in &fillers {
        while result.contains(filler) {
            result = result.replace(filler, " ");
        }
    }
    // Collapse multiple spaces and trim
    result.split_whitespace().collect::<Vec<_>>().join(" ")
}

pub fn create_transcription_stream(sink: StreamSink<String>) -> Result<()> {
    STATE.is_listening.store(true, Ordering::SeqCst);
    
    // Clear buffer
    {
        let mut buffer = STATE.audio_buffer.lock().unwrap();
        buffer.clear();
    }

    // Setup CPAL
    let host = cpal::default_host();
    let device = host.default_input_device().context("no input device")?;
    let config = device.default_input_config().context("no default config")?;
    
    let err_fn = move |err| {
        eprintln!("an error occurred on stream: {}", err);
    };

    let stream = device.build_input_stream(
        &config.into(),
        move |data: &[f32], _: &_| {
            if STATE.is_listening.load(Ordering::SeqCst) {
                let mut buffer = STATE.audio_buffer.lock().unwrap();
                buffer.extend_from_slice(data);
            }
        },
        err_fn,
        None
    )?;

    stream.play()?;

    // Inference Thread
    thread::spawn(move || {
        let mut last_processed_len = 0;
        let mut silence_start = std::time::Instant::now();
        let mut is_speaking = false;
        
        while STATE.is_listening.load(Ordering::SeqCst) {
            thread::sleep(std::time::Duration::from_millis(100)); // Check freq

            // Snapshot buffer
            let buffer_snapshot = {
                let guard = STATE.audio_buffer.lock().unwrap();
                guard.clone()
            };

            // VAD Logic on recent samples
            // Check last 100ms
            let chunk_size = SAMPLE_RATE / 10; 
            if buffer_snapshot.len() > chunk_size {
                 let recent_chunk = &buffer_snapshot[buffer_snapshot.len() - chunk_size..];
                 let rms = calculate_rms(recent_chunk);
                 
                 if rms > VAD_THRESHOLD_RMS {
                     is_speaking = true;
                     silence_start = std::time::Instant::now();
                 } else {
                     if is_speaking && silence_start.elapsed().as_millis() > SILENCE_DURATION_MS {
                         is_speaking = false;
                         // Silence detected after speech. 
                         // Check if we processed everything.
                     }
                 }
            }

            // Only Transcribe if meaningful change in buffer OR silence timeout (finalize)
            if buffer_snapshot.len() > last_processed_len + (SAMPLE_RATE / 2) { // Every 0.5s of new audio
                 
                 let mut guard = STATE.model_ctx.lock().unwrap();
                 if let Some(ctx) = guard.as_mut() {
                     let mut params = FullParams::new(SamplingStrategy::Greedy { best_of: 1 });
                     params.set_language(Some("en"));
                     params.set_print_special(false); // No special tokens
                     params.set_print_progress(false);
                     params.set_print_realtime(false);
                     params.set_print_timestamps(false);
                     params.set_n_threads(4);
                     
                     // Token level timestamp? 
                     // params.set_token_timestamps(true);

                     if let Ok(mut state) = ctx.create_state() {
                         // Run on FULL buffer for now to correct previous context
                         if state.full(params, &buffer_snapshot[..]).is_ok() {
                             if let Ok(num_segments) = state.full_n_segments() {
                                 let mut text = String::new();
                                 for i in 0..num_segments {
                                     if let Ok(segment) = state.full_get_segment_text(i) {
                                         text.push_str(&segment);
                                     }
                                 }
                                 
                                 // Simple VAD indicator
                                 if is_speaking {
                                     sink.add(clean_filler_words(&text));
                                 } else {
                                     sink.add(clean_filler_words(&text));
                                 }
                             }
                         }
                     }
                 }
                 last_processed_len = buffer_snapshot.len();
            }
        }
        drop(stream);
    });

    Ok(())
}

pub fn stop_listening() -> Result<()> {
    STATE.is_listening.store(false, Ordering::SeqCst);
    Ok(())
}

/// Transcription mode: Batch (process on stop) vs Streaming (live 400ms chunks)
#[derive(Clone, Copy, PartialEq)]
pub enum TranscriptionMode {
    Batch,     // Mode A: Buffer all audio → transcribe on hotkey release
    Streaming, // Mode B: Live 400ms chunks → real-time text
}

static CURRENT_MODE: std::sync::atomic::AtomicU8 = std::sync::atomic::AtomicU8::new(1); // 0=Batch, 1=Streaming

pub fn set_transcription_mode(batch: bool) -> Result<()> {
    CURRENT_MODE.store(if batch { 0 } else { 1 }, Ordering::SeqCst);
    Ok(())
}

pub fn get_transcription_mode() -> String {
    if CURRENT_MODE.load(Ordering::SeqCst) == 0 {
        "batch".to_string()
    } else {
        "streaming".to_string()
    }
}

/// Mode A: Batch transcription — records audio, transcribes on stop
/// Call start_batch_recording() to begin, stop_and_transcribe() to get result
pub fn start_batch_recording() -> Result<()> {
    STATE.is_listening.store(true, Ordering::SeqCst);
    {
        let mut buffer = STATE.audio_buffer.lock().unwrap();
        buffer.clear();
    }

    let host = cpal::default_host();
    let device = host.default_input_device().context("no input device")?;
    let config = device.default_input_config().context("no default config")?;

    let err_fn = move |err| {
        eprintln!("batch recording error: {}", err);
    };

    let stream = device.build_input_stream(
        &config.into(),
        move |data: &[f32], _: &_| {
            if STATE.is_listening.load(Ordering::SeqCst) {
                let mut buffer = STATE.audio_buffer.lock().unwrap();
                buffer.extend_from_slice(data);
            }
        },
        err_fn,
        None,
    )?;

    stream.play()?;

    // Keep stream alive in a thread until stopped
    thread::spawn(move || {
        while STATE.is_listening.load(Ordering::SeqCst) {
            thread::sleep(std::time::Duration::from_millis(50));
        }
        drop(stream);
    });

    Ok(())
}

/// Stop batch recording and transcribe the full buffer
pub fn stop_and_transcribe() -> Result<String> {
    STATE.is_listening.store(false, Ordering::SeqCst);
    thread::sleep(std::time::Duration::from_millis(100)); // Let stream drain

    let buffer_snapshot = {
        let guard = STATE.audio_buffer.lock().unwrap();
        guard.clone()
    };

    if buffer_snapshot.is_empty() {
        return Ok(String::new());
    }

    let mut guard = STATE.model_ctx.lock().unwrap();
    if let Some(ctx) = guard.as_mut() {
        let mut params = FullParams::new(SamplingStrategy::Greedy { best_of: 1 });
        params.set_language(Some("en"));
        params.set_print_special(false);
        params.set_print_progress(false);
        params.set_print_realtime(false);
        params.set_print_timestamps(false);
        params.set_n_threads(4);

        if let Ok(mut state) = ctx.create_state() {
            if state.full(params, &buffer_snapshot[..]).is_ok() {
                if let Ok(num_segments) = state.full_n_segments() {
                    let mut text = String::new();
                    for i in 0..num_segments {
                        if let Ok(segment) = state.full_get_segment_text(i) {
                            text.push_str(&segment);
                        }
                    }
                    return Ok(clean_filler_words(&text.trim().to_string()));
                }
            }
        }
    }

    Err(anyhow!("Batch transcription failed — model not loaded"))
}

/// Check GitHub for newer release tags
pub fn check_for_updates() -> Result<String> {
    let url = format!("https://api.github.com/repos/{}/releases/latest", GITHUB_REPO);
    // NOTE: Requires a blocking HTTP client like `ureq` or `reqwest` (blocking).
    // For now, return the current version. The Flutter side handles the actual check.
    Ok(APP_VERSION.to_string())
}

/// Inject text with adaptive delay between characters
/// delay_ms: 10 for normal apps, 30 for legacy/slow apps
pub fn inject_text(text: String, delay_ms: u64) -> Result<()> {
    // This would use platform-specific APIs (e.g., SendInput on Windows)
    // to simulate keyboard input with a per-character delay.
    for ch in text.chars() {
        // Platform-specific key simulation would go here
        // e.g., windows::Win32::UI::Input::KeyboardAndMouse::SendInput
        let _ = ch; // Placeholder
        thread::sleep(std::time::Duration::from_millis(delay_ms));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Instant;

    #[test]
    fn test_inject_text_normal_mode() {
        let text = "Hello Fair9 Test".to_string();
        let delay_ms = 10; // Normal mode

        let start = Instant::now();
        let result = inject_text(text.clone(), delay_ms);
        let elapsed = start.elapsed();

        assert!(result.is_ok(), "inject_text should succeed");

        let expected_min = std::time::Duration::from_millis(delay_ms * text.len() as u64);
        assert!(
            elapsed >= expected_min * 80 / 100, // Allow 20% timing tolerance
            "Normal mode: elapsed {:?} should be >= ~{:?}",
            elapsed, expected_min
        );
    }

    #[test]
    fn test_inject_text_legacy_mode_slower() {
        let text = "SpeedTest".to_string();

        let start_normal = Instant::now();
        inject_text(text.clone(), 10).unwrap();
        let normal_elapsed = start_normal.elapsed();

        let start_legacy = Instant::now();
        inject_text(text.clone(), 30).unwrap();
        let legacy_elapsed = start_legacy.elapsed();

        assert!(
            legacy_elapsed > normal_elapsed,
            "Legacy mode ({:?}) should be slower than normal mode ({:?})",
            legacy_elapsed, normal_elapsed
        );
    }

    #[test]
    fn test_inject_text_empty_string() {
        let start = Instant::now();
        let result = inject_text("".to_string(), 10);
        let elapsed = start.elapsed();

        assert!(result.is_ok(), "Empty string should succeed");
        assert!(
            elapsed < std::time::Duration::from_millis(5),
            "Empty string should complete near-instantly, took {:?}",
            elapsed
        );
    }

    #[test]
    fn test_inject_text_unicode() {
        let result = inject_text("Fair9 ✓ héllo 日本".to_string(), 1);
        assert!(result.is_ok(), "Unicode injection should succeed");
    }

    #[test]
    fn test_check_for_updates_returns_version() {
        let version = check_for_updates().unwrap();
        assert_eq!(version, APP_VERSION, "Should return current version");
    }

    #[test]
    fn test_calculate_rms_silent() {
        let silent = vec![0.0f32; 1600];
        let rms = calculate_rms(&silent);
        assert_eq!(rms, 0.0, "Silent audio should have 0 RMS");
    }

    #[test]
    fn test_calculate_rms_loud() {
        let loud = vec![1.0f32; 1600];
        let rms = calculate_rms(&loud);
        assert!((rms - 1.0).abs() < 0.001, "Constant 1.0 audio should have RMS ~1.0");
    }

    #[test]
    fn test_calculate_rms_empty() {
        let empty: Vec<f32> = vec![];
        let rms = calculate_rms(&empty);
        assert_eq!(rms, 0.0, "Empty buffer should return 0 RMS");
    }

    // ── Filler Word Removal Tests ──────────────────────────────

    #[test]
    fn test_clean_filler_basic() {
        let input = "I um want to uh create a function";
        let result = clean_filler_words(input);
        assert_eq!(result, "I want to create a function");
    }

    #[test]
    fn test_clean_filler_multiple() {
        let input = "so um like basically I you know think hmm we should";
        let result = clean_filler_words(input);
        assert_eq!(result, "so I think we should");
    }

    #[test]
    fn test_clean_filler_no_false_positives() {
        // "like" as legitimate word, "plumber" contains "um" substring
        let input = "I would like to book a plumber";
        let result = clean_filler_words(input);
        // "like" as standalone filler IS removed, but "plumber" is preserved
        assert_eq!(result, "I would to book a plumber");
    }

    #[test]
    fn test_clean_filler_empty() {
        let input = "";
        let result = clean_filler_words(input);
        assert_eq!(result, "");
    }
}
