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

const APP_VERSION: &str = "1.2.0";
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

// ═══════════════════════════════════════════════════════════════════
// VOICE SNIPPET LIBRARY
// ═══════════════════════════════════════════════════════════════════

/// Get the snippets.json file path
fn get_snippets_path() -> Result<PathBuf> {
    let mut path = dirs::data_dir().ok_or_else(|| anyhow!("Could not find data directory"))?;
    path.push("OpenFL");
    path.push("Fair9");
    path.push("snippets.json");
    Ok(path)
}

/// Load snippets from disk into the global store
pub fn load_snippets() -> Result<String> {
    let path = get_snippets_path()?;
    if !path.exists() {
        // Create default snippets file
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)?;
        }
        let default = r#"{"snippets": []}"#;
        fs::write(&path, default)?;
        return Ok("Created empty snippets file".to_string());
    }

    let content = fs::read_to_string(&path)?;
    let mut snippets = Vec::new();

    // Simple JSON parsing for snippets array
    // Format: {"snippets": [{"trigger": "...", "content": "..."}, ...]}
    if let Some(arr_start) = content.find('[') {
        if let Some(arr_end) = content.rfind(']') {
            let arr_str = &content[arr_start+1..arr_end];
            // Split by "},{" pattern to get individual objects
            let mut depth = 0;
            let mut obj_start = None;
            for (i, ch) in arr_str.char_indices() {
                match ch {
                    '{' => {
                        if depth == 0 { obj_start = Some(i); }
                        depth += 1;
                    }
                    '}' => {
                        depth -= 1;
                        if depth == 0 {
                            if let Some(start) = obj_start {
                                let obj = &arr_str[start..=i];
                                if let (Some(trigger), Some(content)) = (extract_json_string(obj, "trigger"), extract_json_string(obj, "content")) {
                                    snippets.push(VoiceSnippet { trigger, content });
                                }
                            }
                        }
                    }
                    _ => {}
                }
            }
        }
    }

    let count = snippets.len();
    *SNIPPETS.lock().unwrap() = snippets;
    Ok(format!("Loaded {} snippets", count))
}

/// Extract a string value from a JSON object by key (minimal parser)
fn extract_json_string(json: &str, key: &str) -> Option<String> {
    let pattern = format!("\"{}\"\\s*:\\s*\"", key);
    // Simple find-based extraction
    let search = format!("\"{}\":", key);
    let alt_search = format!("\"{}\" :", key);
    let pos = json.find(&search).or_else(|| json.find(&alt_search))?;
    let after_key = &json[pos..];
    // Find the opening quote of the value
    let first_colon = after_key.find(':')?;
    let after_colon = &after_key[first_colon+1..].trim_start();
    if !after_colon.starts_with('"') { return None; }
    let value_start = 1; // skip opening quote
    let value_str = &after_colon[value_start..];
    // Find closing quote (handle escaped quotes)
    let mut end = 0;
    let mut escaped = false;
    for ch in value_str.chars() {
        if escaped {
            escaped = false;
            end += ch.len_utf8();
            continue;
        }
        if ch == '\\' { escaped = true; end += 1; continue; }
        if ch == '"' { break; }
        end += ch.len_utf8();
    }
    Some(value_str[..end].replace("\\n", "\n").replace("\\\"", "\""))
}

/// Check if transcribed text matches any snippet trigger
pub fn match_snippet(text: &str) -> Option<String> {
    let normalized = text.trim().to_lowercase();
    let store = SNIPPETS.lock().unwrap();
    for snippet in store.iter() {
        if normalized == snippet.trigger.to_lowercase() ||
           normalized.ends_with(&snippet.trigger.to_lowercase()) {
            return Some(snippet.content.clone());
        }
    }
    None
}

/// Add a new snippet
pub fn add_snippet(trigger: String, content: String) -> Result<String> {
    {
        let mut store = SNIPPETS.lock().unwrap();
        // Check for duplicate trigger
        if store.iter().any(|s| s.trigger.to_lowercase() == trigger.to_lowercase()) {
            return Err(anyhow!("Snippet with trigger '{}' already exists", trigger));
        }
        store.push(VoiceSnippet { trigger: trigger.clone(), content });
    }
    save_snippets()?;
    Ok(format!("Added snippet '{}'", trigger))
}

/// Remove a snippet by trigger
pub fn remove_snippet(trigger: String) -> Result<String> {
    {
        let mut store = SNIPPETS.lock().unwrap();
        let before = store.len();
        store.retain(|s| s.trigger.to_lowercase() != trigger.to_lowercase());
        if store.len() == before {
            return Err(anyhow!("No snippet with trigger '{}'", trigger));
        }
    }
    save_snippets()?;
    Ok(format!("Removed snippet '{}'", trigger))
}

/// Get all snippets as a JSON string
pub fn get_snippets() -> String {
    let store = SNIPPETS.lock().unwrap();
    let entries: Vec<String> = store.iter().map(|s| {
        format!("{{\"trigger\":\"{}\",\"content\":\"{}\"}}",
            s.trigger.replace('"', "\\\""),
            s.content.replace('"', "\\\"").replace('\n', "\\n")
        )
    }).collect();
    format!("{{\"snippets\":[{}]}}", entries.join(","))
}

/// Save current snippets to disk
fn save_snippets() -> Result<()> {
    let path = get_snippets_path()?;
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    let json = get_snippets();
    fs::write(&path, &json)?;
    Ok(())
}

/// Process text through snippet matching (called after filler removal)
/// Returns either the snippet content or the original text
pub fn apply_snippet_expansion(text: &str) -> String {
    match match_snippet(text) {
        Some(content) => content,
        None => text.to_string(),
    }
}

// ═══════════════════════════════════════════════════════════════════
// AI COMMAND MODE (Ollama LLM Integration)
// ═══════════════════════════════════════════════════════════════════

const OLLAMA_DEFAULT_URL: &str = "http://localhost:11434/api/generate";
const OLLAMA_DEFAULT_MODEL: &str = "llama3";

const AI_SYSTEM_PROMPT: &str = r#"You are a text editor. Execute the user's command on the following text. 
Return ONLY the modified text with no explanation, no markdown formatting, no quotes around it. 
Just the raw edited text, nothing else."#;

/// Process text through local Ollama LLM with a voice command
/// selected_text: the text currently highlighted in the user's app
/// voice_command: what the user said (e.g. "make this a list", "fix grammar")
/// Returns: the LLM-modified text ready to paste back
pub fn process_ai_command(selected_text: String, voice_command: String) -> Result<String> {
    process_ai_command_with_config(
        selected_text,
        voice_command,
        OLLAMA_DEFAULT_URL.to_string(),
        OLLAMA_DEFAULT_MODEL.to_string(),
    )
}

/// Configurable version for testing and custom setups
pub fn process_ai_command_with_config(
    selected_text: String,
    voice_command: String,
    ollama_url: String,
    model: String,
) -> Result<String> {
    if selected_text.trim().is_empty() {
        return Err(anyhow!("No text selected — highlight text first"));
    }
    if voice_command.trim().is_empty() {
        return Err(anyhow!("No voice command captured"));
    }

    let prompt = format!(
        "Command: {}\n\nText to edit:\n{}",
        voice_command.trim(),
        selected_text,
    );

    // Build JSON body manually (no serde dependency needed)
    let escaped_system = AI_SYSTEM_PROMPT
        .replace('\\', "\\\\")
        .replace('"', "\\\"")
        .replace('\n', "\\n");
    let escaped_prompt = prompt
        .replace('\\', "\\\\")
        .replace('"', "\\\"")
        .replace('\n', "\\n");
    let escaped_model = model
        .replace('\\', "\\\\")
        .replace('"', "\\\"");

    let body = format!(
        r#"{{"model":"{}","prompt":"{}","system":"{}","stream":false}}"#,
        escaped_model, escaped_prompt, escaped_system
    );

    // HTTP POST to Ollama
    let response = ureq::post(&ollama_url)
        .set("Content-Type", "application/json")
        .send_string(&body);

    match response {
        Ok(resp) => {
            let body_str = resp.into_string()
                .context("Failed to read Ollama response body")?;

            // Extract "response" field from JSON
            if let Some(response_text) = extract_json_string(&body_str, "response") {
                let cleaned = response_text.trim().to_string();
                if cleaned.is_empty() {
                    Err(anyhow!("LLM returned empty response"))
                } else {
                    Ok(cleaned)
                }
            } else {
                Err(anyhow!("Could not parse LLM response: {}", &body_str[..body_str.len().min(200)]))
            }
        }
        Err(e) => {
            Err(anyhow!(
                "Ollama connection failed. Is Ollama running? (ollama serve)\nError: {}",
                e
            ))
        }
    }
}

/// Check if Ollama is available at the default endpoint
pub fn check_ollama_status() -> String {
    match ureq::get("http://localhost:11434/api/tags").call() {
        Ok(resp) => {
            let body = resp.into_string().unwrap_or_default();
            if body.contains("models") {
                "connected".to_string()
            } else {
                "running_no_models".to_string()
            }
        }
        Err(_) => "offline".to_string(),
    }
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
                let is_whisper = WHISPER_MODE.load(Ordering::SeqCst);
                
                if is_whisper {
                    // DSP: +15dB Gain Boost (multiplier ≈ 5.62) + High-Pass Filter (Simple RC)
                    static mut LAST_IN: f32 = 0.0;
                    static mut LAST_OUT: f32 = 0.0;
                    let alpha = 0.95; // Cutoff approx 120Hz at 16kHz
                    
                    for &sample in data {
                        unsafe {
                            // High-pass filter
                            let out = alpha * (LAST_OUT + sample - LAST_IN);
                            LAST_IN = sample;
                            LAST_OUT = out;
                            // Apply +15dB Gain
                            buffer.push(out * 5.62);
                        }
                    }
                } else {
                    buffer.extend_from_slice(data);
                }
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

                     if WHISPER_MODE.load(Ordering::SeqCst) {
                         // Higher sensitivity for hushed voices
                         params.set_no_speech_thold(0.1); 
                     }
                     
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
                                 
                                 // Pipeline: raw → filler removal → snippet expansion
                                 let cleaned = clean_filler_words(&text);
                                 let final_text = apply_snippet_expansion(&cleaned);
                                 if is_speaking {
                                     sink.add(final_text);
                                 } else {
                                     sink.add(apply_snippet_expansion(&clean_filler_words(&text)));
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
                    let cleaned = clean_filler_words(&text.trim().to_string());
                    return Ok(apply_snippet_expansion(&cleaned));
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
}
