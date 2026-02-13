import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:tray_manager/tray_manager.dart';
import 'dart:ui';
import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:math';

// Mock Bridge for UI Dev without compiled Rust
// import 'bridge_generated.dart'; 

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

const String kAppVersion = '1.1.0';
const String kGitHubRepo = 'open-free-launching/Fair9';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  bool modelExists = await _checkModelExists();

  WindowOptions windowOptions = const WindowOptions(
    size: Size(380, 280),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: true, 
    titleBarStyle: TitleBarStyle.hidden,
    alwaysOnTop: true,
  );
  
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
    await windowManager.setAsFrameless();
    await windowManager.setBackgroundColor(Colors.transparent);
  });

  runApp(MyApp(initialRoute: modelExists ? '/' : '/download'));
}

Future<bool> _checkModelExists() async {
  final directory = await getApplicationSupportDirectory();
  final modelDir = Directory('${directory.parent.path}\\OpenFL\\Fair9\\models');
  if (!await modelDir.exists()) return false;
  final modelFile = File('${modelDir.path}\\ggml-tiny.en-q8_0.bin');
  return modelFile.existsSync();
}

final trayManager = TrayManager.instance;

class MyApp extends StatelessWidget {
  final String initialRoute;
  const MyApp({super.key, required this.initialRoute});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fair9',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.transparent,
      ),
      initialRoute: initialRoute,
      routes: {
        '/': (context) => const HUDOverlay(),
        '/download': (context) => const ModelDownloader(),
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// MODEL DOWNLOADER
// ═══════════════════════════════════════════════════════════════════
class ModelDownloader extends StatefulWidget {
  const ModelDownloader({super.key});
  @override
  State<ModelDownloader> createState() => _ModelDownloaderState();
}

class _ModelDownloaderState extends State<ModelDownloader> {
  double _progress = 0;
  String _statusText = "Preparing download...";

  @override
  void initState() {
    super.initState();
    _downloadModel();
  }

  Future<void> _downloadModel() async {
    try {
      final directory = await getApplicationSupportDirectory();
      final modelDir = Directory('${directory.parent.path}\\OpenFL\\Fair9\\models');
      if (!await modelDir.exists()) await modelDir.create(recursive: true);

      final modelPath = '${modelDir.path}\\ggml-tiny.en-q8_0.bin';
      final url = Uri.parse(
        "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.en-q8_0.bin"
      );

      setState(() => _statusText = "Downloading quantized model...");

      final request = http.Request('GET', url);
      final response = await request.send();
      final totalBytes = response.contentLength ?? 0;
      int receivedBytes = 0;
      final file = File(modelPath);
      final sink = file.openWrite();

      await response.stream.listen(
        (chunk) {
          sink.add(chunk);
          receivedBytes += chunk.length;
          if (totalBytes > 0) {
            setState(() {
              _progress = receivedBytes / totalBytes;
              _statusText = "Downloading... ${(_progress * 100).toStringAsFixed(1)}%";
            });
          }
        },
        onDone: () async {
          await sink.close();
          setState(() => _statusText = "Model ready!");
          await Future.delayed(const Duration(seconds: 1));
          if (mounted) Navigator.pushReplacementNamed(context, '/');
        },
        onError: (e) {
          setState(() => _statusText = "Download failed: $e");
        },
      ).asFuture();
    } catch (e) {
      setState(() => _statusText = "Error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              width: 350,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF0A0A14).withOpacity(0.65),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withOpacity(0.12)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_download, color: Color(0xFF7B68EE), size: 40),
                  const SizedBox(height: 12),
                  Text(_statusText,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: _progress > 0 ? _progress : null,
                      backgroundColor: Colors.white.withOpacity(0.08),
                      valueColor: const AlwaysStoppedAnimation(Color(0xFF7B68EE)),
                      minHeight: 6,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// THE FROSTED HUD OVERLAY
// ═══════════════════════════════════════════════════════════════════
class HUDOverlay extends StatefulWidget {
  const HUDOverlay({super.key});
  @override
  State<HUDOverlay> createState() => _HUDOverlayState();
}

class _HUDOverlayState extends State<HUDOverlay>
    with TrayListener, WindowListener, TickerProviderStateMixin {
  String _status = "Ready";
  bool _isRecording = false;
  bool _updateAvailable = false;
  String _latestVersion = '';
  bool _legacyAppMode = false;
  String _activeModel = 'English — Fast';

  // Ghost Text state
  String _ghostText = '';
  String _solidText = '';
  bool _isGhostSolidifying = false;

  // Toast state
  bool _showModelToast = false;

  final StreamController<String> _mockStreamController =
      StreamController<String>.broadcast();
  Stream<String>? _transcriptionStream;

  late AnimationController _waveController;
  late AnimationController _ghostFadeController;
  late Animation<double> _ghostOpacity;

  @override
  void initState() {
    super.initState();
    trayManager.addListener(this);
    windowManager.addListener(this);
    _initTray();
    _checkForUpdates();

    // Waveform animation — loops forever
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    // Ghost → Solid fade animation
    _ghostFadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _ghostOpacity = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _ghostFadeController, curve: Curves.easeInOut),
    );

    _transcriptionStream = _mockStreamController.stream;
  }

  Future<void> _checkForUpdates() async {
    try {
      final response = await http.get(
        Uri.parse('https://api.github.com/repos/$kGitHubRepo/releases/latest'),
        headers: {'Accept': 'application/vnd.github.v3+json'},
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final tagName = data['tag_name'] as String? ?? '';
        final remote = tagName.replaceAll('v', '');
        if (remote.compareTo(kAppVersion) > 0) {
          setState(() {
            _updateAvailable = true;
            _latestVersion = tagName;
          });
        }
      }
    } catch (_) {}
  }

  Duration get _typingDelay => _legacyAppMode
      ? const Duration(milliseconds: 30)
      : const Duration(milliseconds: 10);

  @override
  void dispose() {
    trayManager.removeListener(this);
    windowManager.removeListener(this);
    _waveController.dispose();
    _ghostFadeController.dispose();
    _mockStreamController.close();
    super.dispose();
  }

  Future<void> _initTray() async {
    await trayManager.setIcon(
      Platform.isWindows ? 'images/tray_icon.ico' : 'images/tray_icon.png',
    );
    Menu menu = Menu(
      items: [
        MenuItem(key: 'show_window', label: 'Show HUD'),
        MenuItem.separator(),
        MenuItem(key: 'exit_app', label: 'Exit'),
      ],
    );
    await trayManager.setContextMenu(menu);
  }

  @override
  void onTrayIconMouseDown() {
    windowManager.show();
    windowManager.restore();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (menuItem.key == 'show_window') {
      windowManager.show();
      windowManager.restore();
    } else if (menuItem.key == 'exit_app') {
      windowManager.close();
    }
  }

  void _toggleRecording() {
    setState(() => _isRecording = !_isRecording);

    if (_isRecording) {
      setState(() => _status = "Listening...");
      _showModelBadge();
      _mockStreaming();
    } else {
      setState(() => _status = "Ready");
      // Solidify any remaining ghost text
      if (_ghostText.isNotEmpty) _solidifyGhostText();
    }
  }

  /// Show contextual model toast for 3 seconds
  void _showModelBadge() {
    setState(() => _showModelToast = true);
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showModelToast = false);
    });
  }

  /// Simulate streaming transcription with ghost → solid effect
  void _mockStreaming() async {
    String sentence = "This is a streaming transcription example from Rust engine.";
    List<String> words = sentence.split(' ');
    String current = "";

    for (int i = 0; i < words.length; i++) {
      if (!_isRecording) break;
      await Future.delayed(const Duration(milliseconds: 300));
      current += "${words[i]} ";

      setState(() => _ghostText = current);
      _mockStreamController.add(current);

      // Every 5 words, solidify the ghost text
      if ((i + 1) % 5 == 0 || i == words.length - 1) {
        await Future.delayed(const Duration(milliseconds: 200));
        _solidifyGhostText();
        current = "";
      }
    }
  }

  void _solidifyGhostText() {
    if (_ghostText.isEmpty) return;
    setState(() {
      _solidText += _ghostText;
      _ghostText = '';
      _isGhostSolidifying = true;
    });
    _ghostFadeController.forward(from: 0).then((_) {
      if (mounted) setState(() => _isGhostSolidifying = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // ─── Main Frosted HUD ─────────────────────────────────
          Center(
            child: GestureDetector(
              onPanStart: (_) => windowManager.startDragging(),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18.0, sigmaY: 18.0),
                  child: Container(
                    width: 360,
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          const Color(0xFF0A0A14).withOpacity(0.55),
                          const Color(0xFF0D0D1A).withOpacity(0.70),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.12),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF7B68EE).withOpacity(0.08),
                          blurRadius: 40,
                          spreadRadius: 2,
                        ),
                        BoxShadow(
                          color: Colors.black.withOpacity(0.4),
                          blurRadius: 30,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Handle bar
                        Container(
                          width: 36,
                          height: 3,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // ─── Status Row ──────────────────────────
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(children: [
                              _StatusDot(isActive: _isRecording),
                              const SizedBox(width: 8),
                              Text(
                                _status,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.7),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ]),
                            Row(children: [
                              // Legacy mode indicator
                              if (_legacyAppMode)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  margin: const EdgeInsets.only(right: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: Colors.amber.withOpacity(0.3)),
                                  ),
                                  child: const Text('LEGACY',
                                    style: TextStyle(color: Colors.amber, fontSize: 8, fontWeight: FontWeight.w700, letterSpacing: 1)),
                                ),
                              GestureDetector(
                                onTap: () => setState(() => _legacyAppMode = !_legacyAppMode),
                                child: Icon(Icons.tune_rounded,
                                  color: Colors.white.withOpacity(0.3), size: 18),
                              ),
                              const SizedBox(width: 4),
                              GestureDetector(
                                onTap: () => windowManager.hide(),
                                child: Icon(Icons.remove_rounded,
                                  color: Colors.white.withOpacity(0.3), size: 18),
                              ),
                            ]),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // ─── Ghost Text Transcription Area ───────
                        Container(
                          height: 72,
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.04),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.06),
                            ),
                          ),
                          child: SingleChildScrollView(
                            reverse: true,
                            child: _buildGhostTextArea(),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // ─── Update Banner ────────────────────────
                        if (_updateAvailable)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
                            margin: const EdgeInsets.only(bottom: 10),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(colors: [
                                const Color(0xFF7B68EE).withOpacity(0.15),
                                const Color(0xFF00CED1).withOpacity(0.10),
                              ]),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: const Color(0xFF7B68EE).withOpacity(0.3)),
                            ),
                            child: Row(children: [
                              const Icon(Icons.auto_awesome,
                                color: Color(0xFF7B68EE), size: 14),
                              const SizedBox(width: 6),
                              Text('Update $_latestVersion available',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.6),
                                  fontSize: 11)),
                            ]),
                          ),

                        // ─── Kinetic Waveform (replaces button) ──
                        GestureDetector(
                          onTap: _toggleRecording,
                          child: Container(
                            height: 48,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              gradient: _isRecording
                                  ? const LinearGradient(colors: [
                                      Color(0xFFFF6EC7),
                                      Color(0xFF7B68EE),
                                      Color(0xFF00CED1),
                                    ])
                                  : null,
                              color: _isRecording ? null : Colors.white.withOpacity(0.06),
                              border: Border.all(
                                color: _isRecording
                                    ? Colors.transparent
                                    : Colors.white.withOpacity(0.08),
                              ),
                            ),
                            child: _isRecording
                                ? AnimatedBuilder(
                                    animation: _waveController,
                                    builder: (_, __) => CustomPaint(
                                      painter: _KineticWaveformPainter(
                                        progress: _waveController.value,
                                        isRecording: _isRecording,
                                      ),
                                      size: Size.infinite,
                                    ),
                                  )
                                : Center(
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.mic_none_rounded,
                                          color: Colors.white.withOpacity(0.5), size: 18),
                                        const SizedBox(width: 6),
                                        Text('Tap to Listen',
                                          style: TextStyle(
                                            color: Colors.white.withOpacity(0.5),
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                          )),
                                      ],
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ─── Contextual Model Toast ──────────────────────────
          Positioned(
            top: 12,
            right: 12,
            child: AnimatedSlide(
              offset: _showModelToast ? Offset.zero : const Offset(0, -1.5),
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              child: AnimatedOpacity(
                opacity: _showModelToast ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 250),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D0D1A).withOpacity(0.85),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF7B68EE).withOpacity(0.3)),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF7B68EE).withOpacity(0.1),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF00CED1),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(_activeModel,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      )),
                  ]),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Builds the ghost text area with partial (ghost) and solid (finalized) text
  Widget _buildGhostTextArea() {
    if (_solidText.isEmpty && _ghostText.isEmpty) {
      return Text(
        'Waiting for speech...',
        style: TextStyle(
          color: Colors.white.withOpacity(0.15),
          fontStyle: FontStyle.italic,
          fontSize: 13,
        ),
      );
    }

    return RichText(
      text: TextSpan(children: [
        // Solid (finalized) text
        if (_solidText.isNotEmpty)
          TextSpan(
            text: _solidText,
            style: TextStyle(
              color: Colors.white.withOpacity(
                _isGhostSolidifying ? _ghostOpacity.value : 0.9,
              ),
              fontSize: 14,
              height: 1.5,
            ),
          ),
        // Ghost (partial) text
        if (_ghostText.isNotEmpty)
          TextSpan(
            text: _ghostText,
            style: TextStyle(
              color: Colors.white.withOpacity(0.3),
              fontStyle: FontStyle.italic,
              fontSize: 14,
              height: 1.5,
            ),
          ),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// STATUS DOT — Animated recording indicator
// ═══════════════════════════════════════════════════════════════════
class _StatusDot extends StatelessWidget {
  final bool isActive;
  const _StatusDot({required this.isActive});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isActive ? const Color(0xFFFF6EC7) : Colors.white.withOpacity(0.25),
        boxShadow: isActive
            ? [BoxShadow(color: const Color(0xFFFF6EC7).withOpacity(0.5), blurRadius: 8)]
            : null,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// KINETIC WAVEFORM PAINTER — Siri/Gemini-style neon wave
// ═══════════════════════════════════════════════════════════════════
class _KineticWaveformPainter extends CustomPainter {
  final double progress;
  final bool isRecording;

  _KineticWaveformPainter({required this.progress, required this.isRecording});

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    const barCount = 5;
    final barWidth = size.width / (barCount * 3);
    final spacing = size.width / (barCount + 1);

    final colors = [
      const Color(0xFFFF6EC7),
      const Color(0xFFDA70D6),
      const Color(0xFF7B68EE),
      const Color(0xFF4DBEEE),
      const Color(0xFF00CED1),
    ];

    for (int i = 0; i < barCount; i++) {
      final phase = progress * 2 * pi + (i * pi / 3);
      final amplitude = isRecording
          ? 8.0 + sin(phase) * 10.0
          : 3.0;
      final x = spacing * (i + 1) - barWidth / 2;

      final paint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            colors[i].withOpacity(0.9),
            colors[i].withOpacity(0.4),
          ],
        ).createShader(Rect.fromLTWH(x, centerY - amplitude, barWidth, amplitude * 2))
        ..style = PaintingStyle.fill;

      final rrect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(x + barWidth / 2, centerY), width: barWidth, height: amplitude * 2),
        Radius.circular(barWidth / 2),
      );

      canvas.drawRRect(rrect, paint);

      // Glow effect
      final glowPaint = Paint()
        ..color = colors[i].withOpacity(0.15)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawRRect(rrect, glowPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _KineticWaveformPainter old) => true;
}
