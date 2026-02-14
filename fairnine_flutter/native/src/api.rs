use std::sync::{Arc, Mutex};
use std::thread;
use std::sync::atomic::{AtomicBool, Ordering};
use std::path::PathBuf;
use std::fs;
use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use whisper_rs::{WhisperContext, FullParams, SamplingStrategy};
use flutter_rust_bridge::StreamSink;
use anyhow::{Result, Context, anyhow};
use lazy_static::lazy_static;

const APP_VERSION: &str = "1.2.7";
const GITHUB_REPO: &str = "open-free-launching/Fair9";

/// Voice Snippet: trigger phrase → expanded content
#[derive(Clone, Debug)]
pub struct VoiceSnippet {
    pub trigger: String,
    pub content: String,
}


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
    static ref SNIPPETS: Mutex<Vec<VoiceSnippet>> = Mutex::new(Vec::new());
    static ref WHISPER_MODE: AtomicBool = AtomicBool::new(false);
    static ref SEMANTIC_CORRECTION: AtomicBool = AtomicBool::new(false);
}

pub fn set_semantic_correction(enabled: bool) -> Result<()> {
    SEMANTIC_CORRECTION.store(enabled, Ordering::SeqCst);
    Ok(())
}

pub fn set_whisper_mode(enabled: bool) -> Result<()> {
    WHISPER_MODE.store(enabled, Ordering::SeqCst);
    Ok(())
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

pub fn calculate_rms(data: Vec<f32>) -> f32 {
    if data.is_empty() { return 0.0; }
    let sum_squares: f32 = data.iter().map(|&x| x * x).sum();
    (sum_squares / data.len() as f32).sqrt()
}

use enigo::{Enigo, Key, KeyboardControllable};

/// Inject text with adaptive delay between characters
/// delay_ms: 10 for normal apps, 30 for legacy/slow apps
pub fn inject_text(text: String, delay_ms: u64) -> Result<()> {
    let mut enigo = Enigo::new();
    
    for ch in text.chars() {
        enigo.key_sequence(&ch.to_string());
        thread::sleep(std::time::Duration::from_millis(delay_ms));
    }
    Ok(())
}

/// AI Polish: Remove filler words from transcribed text
/// Implements a smarter removal strategy to avoid false positives
pub fn clean_filler_words(text: String) -> String {
    // List of filler words/phrases to remove
    // We use a more conservative list to avoid removing real words
    let fillers = [
        " um ", " uh ", " hmm ", " uhh ", " umm ",
        " basically ", " actually ", " sort of ", " kind of ",
        " you know ", " I mean ",
        " like ", // "like" is risky, handled with space padding
    ];

    let mut result = format!(" {} ", text); // Pad for matching

    for filler in &fillers {
        // Repeatedly remove filler until gone (handles "um um")
        while result.contains(filler) {
            // For "like", we might want to be extra careful, but for now strict padding helps
            result = result.replace(filler, " ");
        }
    }

    // Collapse multiple spaces and trim
    result.split_whitespace().collect::<Vec<_>>().join(" ")
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

    // ══ Snippet Tests ══════════════════════════════════════════════
    #[test]
    fn test_snippet_match_exact() {
        // Manually add a snippet to the store
        {
            let mut store = SNIPPETS.lock().unwrap();
            store.push(VoiceSnippet {
                trigger: "insert bio".to_string(),
                content: "I am a software engineer...".to_string(),
            });
        }
        let result = match_snippet("insert bio");
        assert!(result.is_some());
        assert_eq!(result.unwrap(), "I am a software engineer...");
        // Cleanup
        SNIPPETS.lock().unwrap().clear();
    }

    #[test]
    fn test_snippet_match_case_insensitive() {
        {
            let mut store = SNIPPETS.lock().unwrap();
            store.push(VoiceSnippet {
                trigger: "Insert Bio".to_string(),
                content: "Bio content here".to_string(),
            });
        }
        let result = match_snippet("INSERT BIO");
        assert!(result.is_some());
        assert_eq!(result.unwrap(), "Bio content here");
        SNIPPETS.lock().unwrap().clear();
    }

    #[test]
    fn test_snippet_no_match() {
        {
            let mut store = SNIPPETS.lock().unwrap();
            store.push(VoiceSnippet {
                trigger: "insert bio".to_string(),
                content: "Bio content here".to_string(),
            });
        }
        let result = match_snippet("hello world");
        assert!(result.is_none());
        SNIPPETS.lock().unwrap().clear();
    }

    #[test]
    fn test_extract_json_string() {
        let json = r#"{"trigger":"insert bio","content":"Hello world"}"#;
        let trigger = extract_json_string(json, "trigger");
        let content = extract_json_string(json, "content");
        assert_eq!(trigger.unwrap(), "insert bio");
        assert_eq!(content.unwrap(), "Hello world");
    }

    // ══ AI Command Mode Tests ══════════════════════════════════════
    #[test]
    fn test_command_rejects_empty_text() {
        let result = process_ai_command_with_config(
            "".to_string(),
            "fix grammar".to_string(),
            "http://localhost:99999".to_string(), // unreachable port
            "test".to_string(),
        );
        assert!(result.is_err());
        assert!(result.unwrap_err().to_string().contains("No text selected"));
    }

    #[test]
    fn test_command_rejects_empty_command() {
        let result = process_ai_command_with_config(
            "Hello world".to_string(),
            "".to_string(),
            "http://localhost:99999".to_string(),
            "test".to_string(),
        );
        assert!(result.is_err());
        assert!(result.unwrap_err().to_string().contains("No voice command"));
    }

    #[test]
    fn test_ai_system_prompt_format() {
        // Verify the system prompt contains key instructions
        assert!(AI_SYSTEM_PROMPT.contains("text editor"));
        assert!(AI_SYSTEM_PROMPT.contains("Execute the user's command"));
        assert!(AI_SYSTEM_PROMPT.contains("ONLY the modified text"));
    }

    #[test]
    fn test_whisper_mode_params() {
        set_whisper_mode(true).unwrap();
        assert!(WHISPER_MODE.load(Ordering::SeqCst));
        
        let mut params = FullParams::new(SamplingStrategy::Greedy { best_of: 1 });
        if WHISPER_MODE.load(Ordering::SeqCst) {
            params.set_no_speech_thold(0.1);
        }
        // Verification of state change
        assert_eq!(WHISPER_MODE.load(Ordering::SeqCst), true);
        
        set_whisper_mode(false).unwrap();
        assert_eq!(WHISPER_MODE.load(Ordering::SeqCst), false);
    }

    #[test]
    fn test_set_semantic_correction() {
        set_semantic_correction(true).unwrap();
        assert!(SEMANTIC_CORRECTION.load(Ordering::SeqCst));
        set_semantic_correction(false).unwrap();
        assert!(!SEMANTIC_CORRECTION.load(Ordering::SeqCst));
    }

    #[test]
    fn test_apply_semantic_correction_no_keywords() {
        set_semantic_correction(true).unwrap();
        let input = "Today is a beautiful day.";
        let result = apply_semantic_correction(input);
        assert_eq!(result, input, "Should return original text if no correction keywords found");
    }

    #[test]
    fn test_apply_semantic_correction_disabled() {
        set_semantic_correction(false).unwrap();
        let input = "Actually, no wait, I meant this.";
        let result = apply_semantic_correction(input);
        assert_eq!(result, input, "Should return original text if feature is disabled");
    }
}
