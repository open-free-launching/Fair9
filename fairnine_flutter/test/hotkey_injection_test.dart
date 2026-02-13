import 'package:flutter_test/flutter_test.dart';
import 'package:fairnine_flutter/hotkey_controller.dart';

void main() {
  // ═══════════════════════════════════════════════════════════════════
  // TEST SUITE 1: HOTKEY CONTROLLER — DEBOUNCE & HOLD LOGIC
  // ═══════════════════════════════════════════════════════════════════
  group('HotkeyController', () {
    late HotkeyController controller;
    int activateCount = 0;
    int deactivateCount = 0;

    setUp(() {
      activateCount = 0;
      deactivateCount = 0;
      controller = HotkeyController(
        debounceDuration: const Duration(milliseconds: 200),
        holdThreshold: const Duration(milliseconds: 100),
        onActivate: () => activateCount++,
        onDeactivate: () => deactivateCount++,
      );
    });

    tearDown(() => controller.dispose());

    // ─────────────────────────────────────────────────────────────────
    // TC-1: Normal keypress is accepted
    // ─────────────────────────────────────────────────────────────────
    test('TC-1: Normal keypress is accepted', () {
      final accepted = controller.onKeyDown();
      expect(accepted, isTrue, reason: 'First keypress should always be accepted');
      expect(controller.isActive, isFalse, reason: 'Should not be active until key up');
    });

    // ─────────────────────────────────────────────────────────────────
    // TC-2: Hold for 3 seconds → valid activation
    // ─────────────────────────────────────────────────────────────────
    test('TC-2: Hold for 3s activates and returns hold duration', () async {
      controller.onKeyDown();
      // Simulate 3 second hold
      await Future.delayed(const Duration(seconds: 3));
      final holdDuration = controller.onKeyUp();

      expect(holdDuration, isNotNull, reason: '3s hold should be a valid activation');
      expect(holdDuration!.inSeconds, greaterThanOrEqualTo(2),
          reason: 'Hold duration should be ~3 seconds');
      expect(activateCount, equals(1), reason: 'onActivate should fire once');
    });

    // ─────────────────────────────────────────────────────────────────
    // TC-3: Quick tap (too short) is rejected
    // ─────────────────────────────────────────────────────────────────
    test('TC-3: Quick tap under threshold is rejected', () async {
      controller.onKeyDown();
      // Release almost immediately (under 100ms threshold)
      await Future.delayed(const Duration(milliseconds: 20));
      final holdDuration = controller.onKeyUp();

      expect(holdDuration, isNull, reason: 'Quick tap should be rejected');
      expect(activateCount, equals(0), reason: 'onActivate should NOT fire for quick tap');
    });

    // ─────────────────────────────────────────────────────────────────
    // TC-4: HOTKEY GHOSTING — double press within debounce window
    // ─────────────────────────────────────────────────────────────────
    test('TC-4: Hotkey ghosting — rapid double press is debounced', () async {
      // First press: valid
      controller.onKeyDown();
      await Future.delayed(const Duration(milliseconds: 150));
      final first = controller.onKeyUp();
      expect(first, isNotNull, reason: 'First press (150ms) should be accepted');

      // Second press: within 200ms debounce window → rejected
      await Future.delayed(const Duration(milliseconds: 50)); // Only 50ms gap
      final accepted = controller.onKeyDown();
      expect(accepted, isFalse, reason: 'Second press within debounce should be rejected');
      expect(activateCount, equals(1), reason: 'Only one activation should have occurred');
    });

    // ─────────────────────────────────────────────────────────────────
    // TC-5: Double press outside debounce window is accepted
    // ─────────────────────────────────────────────────────────────────
    test('TC-5: Second press after debounce window is accepted', () async {
      // First activation
      controller.onKeyDown();
      await Future.delayed(const Duration(milliseconds: 150));
      controller.onKeyUp();

      // Wait for debounce to expire + deactivation
      await Future.delayed(const Duration(milliseconds: 300));

      // Second activation should be accepted
      final accepted = controller.onKeyDown();
      expect(accepted, isTrue, reason: 'Press after debounce window should be accepted');
    });

    // ─────────────────────────────────────────────────────────────────
    // TC-6: Multiple rapid presses — only first accepted
    // ─────────────────────────────────────────────────────────────────
    test('TC-6: Triple rapid press — only first accepted', () async {
      // Simulate 3 rapid keypresses
      controller.onKeyDown();
      await Future.delayed(const Duration(milliseconds: 150));
      controller.onKeyUp();

      await Future.delayed(const Duration(milliseconds: 30));
      final second = controller.onKeyDown();
      expect(second, isFalse);

      await Future.delayed(const Duration(milliseconds: 30));
      final third = controller.onKeyDown();
      expect(third, isFalse);

      expect(activateCount, equals(1), reason: 'Only one activation from triple press');
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // TEST SUITE 2: TEXT INJECTOR — ADAPTIVE DELAY & BUFFER INTEGRITY
  // ═══════════════════════════════════════════════════════════════════
  group('TextInjector', () {
    late TextInjector injector;

    setUp(() {
      injector = TextInjector(
        normalDelay: const Duration(milliseconds: 1),  // Speed up for tests
        legacyDelay: const Duration(milliseconds: 3),
        legacyMode: false,
      );
    });

    // ─────────────────────────────────────────────────────────────────
    // TC-7: Text injection produces correct buffer output
    // ─────────────────────────────────────────────────────────────────
    test('TC-7: Inject "Hello Fair9 Test" → buffer matches exactly', () async {
      const testString = 'Hello Fair9 Test';
      await injector.inject(testString);

      expect(injector.bufferText, equals(testString),
          reason: 'Buffer must exactly match injected string');
      expect(injector.buffer.length, equals(testString.length),
          reason: 'Buffer should have one entry per character');
    });

    // ─────────────────────────────────────────────────────────────────
    // TC-8: Empty string injection
    // ─────────────────────────────────────────────────────────────────
    test('TC-8: Empty string injection produces empty buffer', () async {
      await injector.inject('');
      expect(injector.bufferText, isEmpty);
      expect(injector.buffer.length, equals(0));
    });

    // ─────────────────────────────────────────────────────────────────
    // TC-9: Special characters are preserved
    // ─────────────────────────────────────────────────────────────────
    test('TC-9: Special characters preserved', () async {
      const special = 'Fair9 @v1.1! #release\n\ttab';
      await injector.inject(special);
      expect(injector.bufferText, equals(special));
    });

    // ─────────────────────────────────────────────────────────────────
    // TC-10: Normal mode is faster than legacy mode
    // ─────────────────────────────────────────────────────────────────
    test('TC-10: Legacy mode delay is longer than normal mode', () async {
      const testString = 'speed test';

      // Normal mode
      injector.legacyMode = false;
      final normalTime = await injector.inject(testString);
      injector.clearBuffer();

      // Legacy mode
      injector.legacyMode = true;
      final legacyTime = await injector.inject(testString);

      expect(legacyTime.inMilliseconds, greaterThan(normalTime.inMilliseconds),
          reason: 'Legacy mode (30ms/char) should be slower than normal (10ms/char)');
    });

    // ─────────────────────────────────────────────────────────────────
    // TC-11: Buffer clears correctly between injections
    // ─────────────────────────────────────────────────────────────────
    test('TC-11: Buffer clears between injections', () async {
      await injector.inject('First');
      expect(injector.bufferText, equals('First'));

      injector.clearBuffer();
      expect(injector.bufferText, isEmpty);

      await injector.inject('Second');
      expect(injector.bufferText, equals('Second'));
    });

    // ─────────────────────────────────────────────────────────────────
    // TC-12: Unicode / emoji injection
    // ─────────────────────────────────────────────────────────────────
    test('TC-12: Unicode characters injection', () async {
      const unicode = 'Fair9 ✓ héllo 日本';
      await injector.inject(unicode);
      expect(injector.bufferText, equals(unicode));
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // TEST SUITE 3: INTEGRATION — END-TO-END HOTKEY → INJECT FLOW
  // ═══════════════════════════════════════════════════════════════════
  group('Integration: Hotkey → TextInjection', () {
    test('TC-13: Full flow — hold 3s, inject text, verify buffer', () async {
      final injector = TextInjector(
        normalDelay: const Duration(milliseconds: 1),
      );
      String? capturedText;

      final controller = HotkeyController(
        holdThreshold: const Duration(milliseconds: 100),
        onActivate: () {
          capturedText = 'Hello Fair9 Test';
        },
        onDeactivate: () {},
      );

      // Simulate: press down, hold 3 seconds, release
      controller.onKeyDown();
      await Future.delayed(const Duration(seconds: 3));
      final holdDuration = controller.onKeyUp();

      expect(holdDuration, isNotNull);
      expect(holdDuration!.inSeconds, greaterThanOrEqualTo(2));
      expect(capturedText, equals('Hello Fair9 Test'));

      // Now inject the captured text
      await injector.inject(capturedText!);
      expect(injector.bufferText, equals('Hello Fair9 Test'));

      controller.dispose();
    });

    test('TC-14: Ghosting during injection has no effect', () async {
      final injector = TextInjector(
        normalDelay: const Duration(milliseconds: 1),
      );
      int activations = 0;

      final controller = HotkeyController(
        debounceDuration: const Duration(milliseconds: 500),
        holdThreshold: const Duration(milliseconds: 50),
        onActivate: () => activations++,
        onDeactivate: () {},
      );

      // First activation
      controller.onKeyDown();
      await Future.delayed(const Duration(milliseconds: 100));
      controller.onKeyUp();

      // Inject text (takes time)
      await injector.inject('Hello Fair9 Test');

      // Try to ghost-press during/right after injection
      final ghosted = controller.onKeyDown();
      expect(ghosted, isFalse, reason: 'Ghost press during debounce window should be rejected');
      expect(activations, equals(1));
      expect(injector.bufferText, equals('Hello Fair9 Test'));

      controller.dispose();
    });
  });
}
