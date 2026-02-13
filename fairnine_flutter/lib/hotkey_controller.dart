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
