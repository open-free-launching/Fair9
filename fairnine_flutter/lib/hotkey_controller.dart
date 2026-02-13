import 'dart:async';

/// Controls global hotkey state with debounce protection.
///
/// Prevents "hotkey ghosting" (rapid double-presses) by enforcing
/// a minimum cooldown between activations.
class HotkeyController {
  final Duration debounceDuration;
  final Duration holdThreshold;
  final void Function() onActivate;
  final void Function() onDeactivate;

  bool _isActive = false;
  DateTime? _lastActivation;
  DateTime? _pressStart;
  Timer? _holdTimer;

  bool get isActive => _isActive;
  DateTime? get lastActivation => _lastActivation;

  HotkeyController({
    this.debounceDuration = const Duration(milliseconds: 200),
    this.holdThreshold = const Duration(milliseconds: 100),
    required this.onActivate,
    required this.onDeactivate,
  });

  /// Called when hotkey is pressed down.
  /// Returns true if the press was accepted, false if debounced.
  bool onKeyDown() {
    final now = DateTime.now();

    // Debounce: reject if pressed too soon after last activation
    if (_lastActivation != null &&
        now.difference(_lastActivation!) < debounceDuration) {
      return false; // Ghosting rejected
    }

    if (_isActive) return false; // Already active

    _pressStart = now;
    return true;
  }

  /// Called when hotkey is released.
  /// Returns the hold duration if valid, null if rejected.
  Duration? onKeyUp() {
    if (_pressStart == null) return null;

    final holdDuration = DateTime.now().difference(_pressStart!);
    _pressStart = null;

    // Only activate if held longer than threshold
    if (holdDuration >= holdThreshold) {
      _isActive = true;
      _lastActivation = DateTime.now();
      onActivate();

      // Schedule deactivation
      Future.delayed(const Duration(milliseconds: 50), () {
        _isActive = false;
        onDeactivate();
      });

      return holdDuration;
    }

    return null; // Too short, ignored
  }

  void dispose() {
    _holdTimer?.cancel();
  }
}

/// Injects text character-by-character with adaptive delay.
///
/// Supports normal mode (10ms) and legacy app mode (30ms).
class TextInjector {
  final Duration normalDelay;
  final Duration legacyDelay;
  bool legacyMode;

  /// Buffer to hold injected characters (for testing)
  final List<String> _buffer = [];
  List<String> get buffer => List.unmodifiable(_buffer);
  String get bufferText => _buffer.join();

  TextInjector({
    this.normalDelay = const Duration(milliseconds: 10),
    this.legacyDelay = const Duration(milliseconds: 30),
    this.legacyMode = false,
  });

  Duration get activeDelay => legacyMode ? legacyDelay : normalDelay;

  /// Inject text into the buffer with per-character delay.
  /// Returns the total time taken.
  Future<Duration> inject(String text) async {
    final stopwatch = Stopwatch()..start();

    for (final char in text.split('')) {
      _buffer.add(char);
      await Future.delayed(activeDelay);
    }

    stopwatch.stop();
    return stopwatch.elapsed;
  }

  void clearBuffer() => _buffer.clear();
}

/// Manages the AI Command Mode pipeline:
/// 1. Copy selected text (Ctrl+C)
/// 2. Record voice command
/// 3. Send (text + command) to LLM
/// 4. Paste result back (Ctrl+V)
enum CommandState { idle, copying, recording, processing, pasting }

class CommandHotkeyController {
  final Duration debounceDuration;
  final void Function(CommandState state, String message) onStateChange;

  CommandState _state = CommandState.idle;
  DateTime? _lastActivation;

  CommandState get state => _state;

  CommandHotkeyController({
    this.debounceDuration = const Duration(milliseconds: 300),
    required this.onStateChange,
  });

  /// Called when Shift+CapsLock is pressed.
  /// Returns true if the command mode activation was accepted.
  bool activate() {
    final now = DateTime.now();

    // Debounce
    if (_lastActivation != null &&
        now.difference(_lastActivation!) < debounceDuration) {
      return false;
    }

    if (_state != CommandState.idle) return false;

    _lastActivation = now;
    _state = CommandState.copying;
    onStateChange(_state, 'Copying selection...');
    return true;
  }

  /// Advance to recording state (after clipboard copy is done)
  void startRecording() {
    if (_state != CommandState.copying) return;
    _state = CommandState.recording;
    onStateChange(_state, 'Listening for command...');
  }

  /// Advance to processing state (after voice is captured)
  void startProcessing(String voiceCommand) {
    if (_state != CommandState.recording) return;
    _state = CommandState.processing;
    onStateChange(_state, 'AI processing: "$voiceCommand"');
  }

  /// Advance to pasting state (after LLM returns result)
  void startPasting() {
    if (_state != CommandState.processing) return;
    _state = CommandState.pasting;
    onStateChange(_state, 'Pasting result...');
  }

  /// Return to idle
  void complete() {
    _state = CommandState.idle;
    onStateChange(_state, 'Command complete ✓');
  }

  /// Cancel and return to idle
  void cancel(String reason) {
    _state = CommandState.idle;
    onStateChange(_state, reason);
  }

  void dispose() {}
}
