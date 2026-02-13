import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'package:tray_manager/tray_manager.dart';
import 'dart:ui';
import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

// ═══════════════════════════════════════════════════════════════════
// CONSTANTS
// ═══════════════════════════════════════════════════════════════════
const String kAppVersion = '1.1.0';
const String kGitHubRepo = 'open-free-launching/Fair9';

// Neon palette
const Color kNeonPink = Color(0xFFFF6EC7);
const Color kNeonPurple = Color(0xFF7B68EE);
const Color kNeonTeal = Color(0xFF00CED1);
const Color kSurfaceDark = Color(0xFF0A0A14);
const Color kSurfaceLight = Color(0xFF0D0D1A);

// Available models for download
const List<Map<String, String>> kAvailableModels = [
  {'name': 'English — Fast',     'file': 'ggml-tiny.en-q8_0.bin',  'size': '42 MB',  'lang': 'en'},
  {'name': 'English — Accurate', 'file': 'ggml-base.en-q8_0.bin',  'size': '82 MB',  'lang': 'en'},
  {'name': 'English — Pro',      'file': 'ggml-small.en-q8_0.bin', 'size': '244 MB', 'lang': 'en'},
  {'name': 'Multilingual Fast',  'file': 'ggml-tiny-q8_0.bin',     'size': '50 MB',  'lang': 'auto'},
  {'name': 'Multilingual Pro',   'file': 'ggml-small-q8_0.bin',    'size': '260 MB', 'lang': 'auto'},
];

// ═══════════════════════════════════════════════════════════════════
// MAIN — STEALTH WINDOW SETUP
// ═══════════════════════════════════════════════════════════════════
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  bool modelExists = await _checkModelExists();

  WindowOptions windowOptions = const WindowOptions(
    size: Size(380, 290),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: true,          // Zero taskbar presence
    titleBarStyle: TitleBarStyle.hidden,
    alwaysOnTop: true,
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
    await windowManager.setAsFrameless();
    await windowManager.setBackgroundColor(Colors.transparent);
    await windowManager.setHasShadow(false);   // No OS shadow
    await windowManager.setSkipTaskbar(true);   // Reinforce stealth
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
    _downloadModel(kAvailableModels[0]['file']!);
  }

  Future<void> _downloadModel(String filename) async {
    try {
      final directory = await getApplicationSupportDirectory();
      final modelDir = Directory('${directory.parent.path}\\OpenFL\\Fair9\\models');
      if (!await modelDir.exists()) await modelDir.create(recursive: true);

      final modelPath = '${modelDir.path}\\$filename';
      final url = Uri.parse(
        "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$filename"
      );

      setState(() => _statusText = "Downloading $filename...");

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
        onError: (e) => setState(() => _statusText = "Download failed: $e"),
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
        child: _FrostedPanel(
          width: 350,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_download_outlined, color: kNeonPurple, size: 36),
              const SizedBox(height: 12),
              Text(_statusText, style: const TextStyle(color: Colors.white60, fontSize: 12), textAlign: TextAlign.center),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: _progress > 0 ? _progress : null,
                  backgroundColor: Colors.white.withOpacity(0.06),
                  valueColor: const AlwaysStoppedAnimation(kNeonPurple),
                  minHeight: 5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// THE STEALTH HUD OVERLAY
// ═══════════════════════════════════════════════════════════════════
enum STTMode { batch, streaming }

class HUDOverlay extends StatefulWidget {
  const HUDOverlay({super.key});
  @override
  State<HUDOverlay> createState() => _HUDOverlayState();
}

class _HUDOverlayState extends State<HUDOverlay>
    with TrayListener, WindowListener, TickerProviderStateMixin {

  // ── State ──────────────────────────────────────────────────────
  String _status = "Ready";
  bool _isRecording = false;
  bool _updateAvailable = false;
  String _latestVersion = '';
  bool _legacyAppMode = false;
  bool _settingsOpen = false;
  bool _isClickThrough = false;
  STTMode _sttMode = STTMode.streaming;
  String _activeModelName = 'English — Fast';
  int _activeModelIndex = 0;

  // Ghost text
  String _ghostText = '';
  String _solidText = '';
  bool _isGhostSolidifying = false;

  // Batch mode result
  String _batchResult = '';

  // Toast
  bool _showModelToast = false;

  // Model downloads
  Map<int, double> _downloadProgress = {};

  // Snippets
  List<Map<String, String>> _snippets = [];
  int _settingsTabIndex = 0; // 0=Settings, 1=Snippets
  final TextEditingController _triggerController = TextEditingController();
  final TextEditingController _contentController = TextEditingController();
  bool _showAddSnippet = false;
  String? _snippetExpandedTo; // shows which snippet was triggered

  // Command Mode
  bool _commandMode = false;
  String _commandStatus = '';
  String _ollamaStatus = 'unknown'; // 'connected', 'offline', 'running_no_models'
  String _commandVoiceInput = '';
  String _selectedText = '';

  final StreamController<String> _mockStreamController = StreamController<String>.broadcast();
  Stream<String>? _transcriptionStream;

  late AnimationController _waveController;
  late AnimationController _ghostFadeController;
  late AnimationController _settingsSlideController;
  late Animation<double> _ghostOpacity;
  late Animation<double> _settingsSlide;

  @override
  void initState() {
    super.initState();
    trayManager.addListener(this);
    windowManager.addListener(this);
    _initTray();
    _checkForUpdates();

    _waveController = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1500),
    )..repeat();

    _ghostFadeController = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 400),
    );
    _ghostOpacity = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _ghostFadeController, curve: Curves.easeInOut),
    );

    _settingsSlideController = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 300),
    );
    _settingsSlide = CurvedAnimation(
      parent: _settingsSlideController, curve: Curves.easeOutCubic,
    );

    _transcriptionStream = _mockStreamController.stream;

    _loadSnippets();
    _checkOllamaStatus();
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
          setState(() { _updateAvailable = true; _latestVersion = tagName; });
        }
      }
    } catch (_) {}
  }

  Duration get _typingDelay => _legacyAppMode
      ? const Duration(milliseconds: 30) : const Duration(milliseconds: 10);

  @override
  void dispose() {
    trayManager.removeListener(this);
    windowManager.removeListener(this);
    _waveController.dispose();
    _ghostFadeController.dispose();
    _settingsSlideController.dispose();
    _mockStreamController.close();
    _triggerController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  // ── Tray ────────────────────────────────────────────────────────
  Future<void> _initTray() async {
    await trayManager.setIcon(
      Platform.isWindows ? 'images/tray_icon.ico' : 'images/tray_icon.png',
    );
    Menu menu = Menu(items: [
      MenuItem(key: 'show_window', label: 'Show HUD'),
      MenuItem.separator(),
      MenuItem(key: 'exit_app', label: 'Exit'),
    ]);
    await trayManager.setContextMenu(menu);
  }

  @override
  void onTrayIconMouseDown() { windowManager.show(); windowManager.restore(); }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (menuItem.key == 'show_window') { windowManager.show(); windowManager.restore(); }
    else if (menuItem.key == 'exit_app') { windowManager.close(); }
  }

  // ── Settings Toggle ─────────────────────────────────────────────
  /// Toggle click-through mode based on current activity
  void _updateClickThrough() {
    final shouldBeInteractive = _isRecording || _settingsOpen;
    if (_isClickThrough == shouldBeInteractive) {
      _isClickThrough = !shouldBeInteractive;
      windowManager.setIgnoreMouseEvents(!shouldBeInteractive, forward: true);
    }
  }

  void _toggleSettings() {
    setState(() => _settingsOpen = !_settingsOpen);
    if (_settingsOpen) {
      _settingsSlideController.forward();
      windowManager.setSize(const Size(380, 580));
      windowManager.setIgnoreMouseEvents(false); // Make interactive
    } else {
      _settingsSlideController.reverse();
      windowManager.setSize(const Size(380, 290));
      // Only go click-through if not recording
      if (!_isRecording) {
        windowManager.setIgnoreMouseEvents(true, forward: true);
      }
    }
  }

  // ── Recording ──────────────────────────────────────────────────
  void _toggleRecording() {
    setState(() => _isRecording = !_isRecording);

    if (_isRecording) {
      windowManager.setIgnoreMouseEvents(false); // Make interactive while recording
      setState(() {
        _status = _sttMode == STTMode.batch ? "Recording..." : "Listening...";
        _batchResult = '';
      });
      _showModelBadge();
      if (_sttMode == STTMode.streaming) _mockStreaming();
    } else {
      if (_sttMode == STTMode.batch) {
        setState(() => _status = "Processing...");
        Future.delayed(const Duration(milliseconds: 800), () {
          if (mounted) {
            setState(() {
              _batchResult = "This is the batch transcription result from the Rust engine.";
              _status = "Done — tap 'Paste' to inject";
            });
          }
        });
      } else {
        setState(() => _status = "Ready");
        if (_ghostText.isNotEmpty) _solidifyGhostText();
      }
      // Restore click-through if settings are also closed
      if (!_settingsOpen) {
        windowManager.setIgnoreMouseEvents(true, forward: true);
      }
    }
  }

  void _showModelBadge() {
    setState(() => _showModelToast = true);
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showModelToast = false);
    });
  }

  // ── Streaming Mock ─────────────────────────────────────────────
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

  /// Sync button — paste streaming text
  void _syncPaste() {
    final text = _solidText + _ghostText;
    if (text.isNotEmpty) {
      // In production: api.inject_text(text, _typingDelay.inMilliseconds)
      setState(() {
        _status = "Pasted ✓";
        _solidText = '';
        _ghostText = '';
      });
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) setState(() => _status = "Ready");
      });
    }
  }

  /// Batch paste
  void _pasteBatch() {
    if (_batchResult.isNotEmpty) {
      setState(() {
        _status = "Pasted ✓";
        _batchResult = '';
      });
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) setState(() => _status = "Ready");
      });
    }
  }

  // ── Model Download ─────────────────────────────────────────────
  Future<void> _downloadModel(int index) async {
    final model = kAvailableModels[index];
    setState(() => _downloadProgress[index] = 0.0);

    // Simulate download progress
    for (int i = 1; i <= 20; i++) {
      await Future.delayed(const Duration(milliseconds: 150));
      if (mounted) setState(() => _downloadProgress[index] = i / 20);
    }

    setState(() {
      _downloadProgress.remove(index);
      _activeModelIndex = index;
      _activeModelName = model['name']!;
    });
  }

  // ── Snippets CRUD ─────────────────────────────────────────────────
  Future<void> _loadSnippets() async {
    try {
      final directory = await getApplicationSupportDirectory();
      final snippetFile = File('${directory.parent.path}\\OpenFL\\Fair9\\snippets.json');
      if (await snippetFile.exists()) {
        final content = await snippetFile.readAsString();
        final data = json.decode(content);
        final list = data['snippets'] as List? ?? [];
        setState(() {
          _snippets = list.map<Map<String, String>>((s) => {
            'trigger': s['trigger']?.toString() ?? '',
            'content': s['content']?.toString() ?? '',
          }).toList();
        });
      } else {
        // Copy built-in defaults on first run
        await _saveSnippets();
      }
    } catch (_) {}
  }

  Future<void> _saveSnippets() async {
    try {
      final directory = await getApplicationSupportDirectory();
      final dir = Directory('${directory.parent.path}\\OpenFL\\Fair9');
      if (!await dir.exists()) await dir.create(recursive: true);
      final file = File('${dir.path}\\snippets.json');
      final data = {'snippets': _snippets};
      await file.writeAsString(json.encode(data));
    } catch (_) {}
  }

  void _addSnippet() {
    final trigger = _triggerController.text.trim();
    final content = _contentController.text.trim();
    if (trigger.isEmpty || content.isEmpty) return;

    // Check for duplicate
    if (_snippets.any((s) => s['trigger']!.toLowerCase() == trigger.toLowerCase())) {
      setState(() => _status = "Duplicate trigger '\'$trigger'\''");
      return;
    }

    setState(() {
      _snippets.add({'trigger': trigger, 'content': content});
      _triggerController.clear();
      _contentController.clear();
      _showAddSnippet = false;
      _status = "Snippet '\'$trigger'\'' added ✓";
    });
    _saveSnippets();
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _status = "Ready");
    });
  }

  void _removeSnippet(int index) {
    final trigger = _snippets[index]['trigger'];
    setState(() {
      _snippets.removeAt(index);
      _status = "Removed '\'$trigger'\'' ✓";
    });
    _saveSnippets();
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _status = "Ready");
    });
  }

  // ── AI Command Mode ───────────────────────────────────────────
  Future<void> _checkOllamaStatus() async {
    try {
      final response = await http.get(Uri.parse('http://localhost:11434/api/tags'));
      if (mounted) {
        setState(() {
          _ollamaStatus = response.statusCode == 200 ? 'connected' : 'offline';
        });
      }
    } catch (_) {
      if (mounted) setState(() => _ollamaStatus = 'offline');
    }
  }

  /// Full AI Command Mode pipeline:
  /// 1. Copy selected text (Ctrl+C)
  /// 2. Record voice command (batch mode)
  /// 3. Send to Ollama LLM
  /// 4. Paste result back (Ctrl+V)
  Future<void> _activateCommandMode() async {
    if (_commandMode) return;

    setState(() {
      _commandMode = true;
      _commandStatus = 'Copying selection...';
      _status = '⌘ CMD';
    });
    windowManager.setIgnoreMouseEvents(false);

    // Step 1: Copy selection (Ctrl+C) — simulate keyboard shortcut
    try {
      // Read clipboard before we copy (to detect if copy actually worked)
      final beforeClip = await Clipboard.getData(Clipboard.kTextPlain);

      // Briefly allow mouse events so the user's app stays focused
      await windowManager.setIgnoreMouseEvents(true, forward: true);
      await Future.delayed(const Duration(milliseconds: 50));

      // Simulate Ctrl+C via platform channel or native code
      // For now, we read whatever is currently in clipboard as the "selection"
      final clipData = await Clipboard.getData(Clipboard.kTextPlain);
      _selectedText = clipData?.text ?? '';

      await windowManager.setIgnoreMouseEvents(false);

      if (_selectedText.isEmpty) {
        _cancelCommandMode('No text selected — highlight text first');
        return;
      }

      setState(() => _commandStatus = 'Text copied. Listening for command...');
    } catch (e) {
      _cancelCommandMode('Failed to copy: $e');
      return;
    }

    // Step 2: Record voice command (batch-style)
    setState(() {
      _isRecording = true;
      _commandStatus = '🎙 Say your command...';
    });
    _showModelBadge();

    // Wait for user to release (simulated with a delay for now)
    // In production this uses the hold-to-record pattern
    await Future.delayed(const Duration(seconds: 3));

    setState(() {
      _isRecording = false;
      _commandStatus = 'Processing command...';
    });

    // Mock voice command for demo (in production, comes from Whisper STT)
    _commandVoiceInput = 'Fix the grammar and make it more professional';

    // Step 3: Send to Ollama
    setState(() => _commandStatus = 'AI processing: "$_commandVoiceInput"');

    try {
      final response = await http.post(
        Uri.parse('http://localhost:11434/api/generate'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'model': 'llama3',
          'prompt': 'Command: $_commandVoiceInput\n\nText to edit:\n$_selectedText',
          'system': 'You are a text editor. Execute the user\'s command on the following text. Return ONLY the modified text with no explanation, no markdown formatting, no quotes around it. Just the raw edited text, nothing else.',
          'stream': false,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final result = data['response']?.toString().trim() ?? '';

        if (result.isEmpty) {
          _cancelCommandMode('LLM returned empty response');
          return;
        }

        // Step 4: Copy result to clipboard and paste (Ctrl+V)
        await Clipboard.setData(ClipboardData(text: result));

        setState(() => _commandStatus = 'Pasting result...');
        await Future.delayed(const Duration(milliseconds: 200));

        // Complete
        setState(() {
          _commandMode = false;
          _commandStatus = '';
          _batchResult = result;
          _status = 'Command complete ✓';
        });

        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) setState(() => _status = 'Ready');
        });
      } else {
        _cancelCommandMode('Ollama error: ${response.statusCode}');
      }
    } catch (e) {
      _cancelCommandMode('Ollama offline. Run: ollama serve');
    }

    // Restore click-through
    if (!_settingsOpen && !_isRecording) {
      windowManager.setIgnoreMouseEvents(true, forward: true);
    }
  }

  void _cancelCommandMode(String reason) {
    setState(() {
      _commandMode = false;
      _commandStatus = '';
      _status = reason;
    });
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _status = 'Ready');
    });
    if (!_settingsOpen) {
      windowManager.setIgnoreMouseEvents(true, forward: true);
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(children: [
        Center(
          child: GestureDetector(
            onPanStart: (_) => windowManager.startDragging(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ─── Main HUD Panel ──────────────────────────
                _buildMainHUD(),

                // ─── Glass Settings Panel (expandable) ───────
                SizeTransition(
                  sizeFactor: _settingsSlide,
                  axisAlignment: -1,
                  child: _buildSettingsPanel(),
                ),
              ],
            ),
          ),
        ),

        // ─── Contextual Model Toast ──────────────────────
        Positioned(
          top: 10, right: 10,
          child: AnimatedSlide(
            offset: _showModelToast ? Offset.zero : const Offset(0, -1.5),
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            child: AnimatedOpacity(
              opacity: _showModelToast ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 250),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: kSurfaceDark.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: kNeonPurple.withOpacity(0.3)),
                  boxShadow: [BoxShadow(color: kNeonPurple.withOpacity(0.1), blurRadius: 12)],
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 5, height: 5, decoration: const BoxDecoration(shape: BoxShape.circle, color: kNeonTeal)),
                  const SizedBox(width: 6),
                  Text(_activeModelName, style: const TextStyle(color: Colors.white60, fontSize: 10, fontWeight: FontWeight.w500)),
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // MAIN HUD PANEL
  // ═══════════════════════════════════════════════════════════════
  Widget _buildMainHUD() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          width: 360,
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [kSurfaceDark.withOpacity(0.55), kSurfaceLight.withOpacity(0.70)],
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withOpacity(0.10)),
            boxShadow: [
              BoxShadow(color: kNeonPurple.withOpacity(0.06), blurRadius: 40, spreadRadius: 2),
              BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 30, spreadRadius: 5),
            ],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Handle
            Container(width: 32, height: 3, decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.12), borderRadius: BorderRadius.circular(2),
            )),
            const SizedBox(height: 10),

            // ── Status Row ──────────────────────────────
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Row(children: [
                _StatusDot(isActive: _isRecording),
                const SizedBox(width: 8),
                Text(_status, style: TextStyle(
                  color: Colors.white.withOpacity(0.65), fontWeight: FontWeight.w600,
                  fontSize: 12, letterSpacing: 0.3,
                )),
              ]),
              Row(children: [
                // Mode badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: (_sttMode == STTMode.batch ? Colors.amber : kNeonTeal).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: (_sttMode == STTMode.batch ? Colors.amber : kNeonTeal).withOpacity(0.25)),
                  ),
                  child: Text(
                    _sttMode == STTMode.batch ? 'BATCH' : 'LIVE',
                    style: TextStyle(
                      color: _sttMode == STTMode.batch ? Colors.amber : kNeonTeal,
                      fontSize: 8, fontWeight: FontWeight.w700, letterSpacing: 0.8,
                    ),
                  ),
                ),
                // Legacy badge
                if (_legacyAppMode)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.amber.withOpacity(0.25)),
                    ),
                    child: const Text('LEGACY', style: TextStyle(color: Colors.amber, fontSize: 8, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
                  ),
                // Command Mode badge
                if (_commandMode)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [kNeonPink.withOpacity(0.15), kNeonPurple.withOpacity(0.15)]),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: kNeonPink.withOpacity(0.4)),
                    ),
                    child: const Text('⌘ CMD', style: TextStyle(color: kNeonPink, fontSize: 8, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
                  ),
                // Gear icon → Settings
                GestureDetector(
                  onTap: _toggleSettings,
                  child: AnimatedRotation(
                    turns: _settingsOpen ? 0.25 : 0,
                    duration: const Duration(milliseconds: 300),
                    child: Icon(CupertinoIcons.gear_alt, color: Colors.white.withOpacity(_settingsOpen ? 0.6 : 0.25), size: 16),
                  ),
                ),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () => windowManager.hide(),
                  child: Icon(Icons.remove_rounded, color: Colors.white.withOpacity(0.25), size: 16),
                ),
              ]),
            ]),
            const SizedBox(height: 12),

            // ── Text Area ──────────────────────────────
            Container(
              height: 68,
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.03),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.05)),
              ),
              child: SingleChildScrollView(
                reverse: true,
                child: _sttMode == STTMode.batch
                    ? _buildBatchTextArea()
                    : _buildGhostTextArea(),
              ),
            ),
            const SizedBox(height: 12),

            // ── Update Banner ──────────────────────────
            if (_updateAvailable)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 10),
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [kNeonPurple.withOpacity(0.12), kNeonTeal.withOpacity(0.08)]),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: kNeonPurple.withOpacity(0.25)),
                ),
                child: Row(children: [
                  const Icon(Icons.auto_awesome, color: kNeonPurple, size: 13),
                  const SizedBox(width: 6),
                  Text('Update $_latestVersion available', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 10)),
                ]),
              ),

            // ── Waveform / Controls Row ────────────────
            Row(children: [
              // Main waveform button
              Expanded(
                child: GestureDetector(
                  onTap: _toggleRecording,
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: _isRecording
                          ? const LinearGradient(colors: [kNeonPink, kNeonPurple, kNeonTeal])
                          : null,
                      color: _isRecording ? null : Colors.white.withOpacity(0.05),
                      border: Border.all(color: _isRecording ? Colors.transparent : Colors.white.withOpacity(0.06)),
                    ),
                    child: _isRecording
                        ? AnimatedBuilder(
                            animation: _waveController,
                            builder: (_, __) => CustomPaint(
                              painter: _KineticWaveformPainter(progress: _waveController.value, isRecording: true),
                              size: Size.infinite,
                            ),
                          )
                        : Center(child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.mic_none_rounded, color: Colors.white.withOpacity(0.4), size: 16),
                            const SizedBox(width: 5),
                            Text(
                              _sttMode == STTMode.batch ? 'Hold to Record' : 'Tap to Listen',
                              style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12, fontWeight: FontWeight.w500),
                            ),
                          ])),
                  ),
                ),
              ),
              // Sync/Paste button
              if ((_sttMode == STTMode.streaming && (_solidText.isNotEmpty || _ghostText.isNotEmpty)) ||
                  (_sttMode == STTMode.batch && _batchResult.isNotEmpty))
                ...[
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _sttMode == STTMode.batch ? _pasteBatch : _syncPaste,
                    child: Container(
                      height: 44,
                      width: 54,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: kNeonPurple.withOpacity(0.2),
                        border: Border.all(color: kNeonPurple.withOpacity(0.3)),
                      ),
                      child: const Center(child: Text('Paste', style: TextStyle(color: kNeonPurple, fontSize: 11, fontWeight: FontWeight.w600))),
                    ),
                  ),
                ],
            ]),
          ]),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // GLASS SETTINGS PANEL (tabbed: Settings | Snippets)
  // ═══════════════════════════════════════════════════════════════
  Widget _buildSettingsPanel() {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            width: 360,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: [kSurfaceDark.withOpacity(0.6), kSurfaceLight.withOpacity(0.75)],
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // ── TAB BAR ─────────────────────────────────
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(children: [
                  _ModeTab(
                    label: 'Settings',
                    icon: CupertinoIcons.gear_alt,
                    isActive: _settingsTabIndex == 0,
                    onTap: () => setState(() => _settingsTabIndex = 0),
                  ),
                  _ModeTab(
                    label: 'Snippets',
                    icon: CupertinoIcons.text_quote,
                    isActive: _settingsTabIndex == 1,
                    onTap: () => setState(() => _settingsTabIndex = 1),
                  ),
                ]),
              ),
              const SizedBox(height: 12),

              // ── TAB CONTENT ─────────────────────────────
              if (_settingsTabIndex == 0) _buildSettingsTab(),
              if (_settingsTabIndex == 1) _buildSnippetsTab(),
            ]),
          ),
        ),
      ),
    );
  }

  // ── Settings Tab ──────────────────────────────────────────────
  Widget _buildSettingsTab() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // MODE TOGGLE
      Text('Transcription Mode', style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
      const SizedBox(height: 8),
      Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(children: [
          _ModeTab(
            label: 'Batch',
            icon: CupertinoIcons.recordingtape,
            isActive: _sttMode == STTMode.batch,
            onTap: () => setState(() => _sttMode = STTMode.batch),
          ),
          _ModeTab(
            label: 'Live Stream',
            icon: CupertinoIcons.waveform,
            isActive: _sttMode == STTMode.streaming,
            onTap: () => setState(() => _sttMode = STTMode.streaming),
          ),
        ]),
      ),
      const SizedBox(height: 14),

      // LEGACY MODE
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('Legacy App Compatibility', style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 10)),
        SizedBox(
          height: 22,
          child: CupertinoSwitch(
            value: _legacyAppMode,
            onChanged: (v) => setState(() => _legacyAppMode = v),
            activeTrackColor: kNeonPurple,
          ),
        ),
      ]),
      const SizedBox(height: 14),

      // MODEL SELECTOR
      Text('Models', style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
      const SizedBox(height: 8),
      ...List.generate(kAvailableModels.length, (i) {
        final model = kAvailableModels[i];
        final isActive = i == _activeModelIndex;
        final isDownloading = _downloadProgress.containsKey(i);
        return _ModelRow(
          name: model['name']!,
          size: model['size']!,
          isActive: isActive,
          isDownloading: isDownloading,
          progress: _downloadProgress[i] ?? 0,
          onTap: isActive ? null : () => _downloadModel(i),
        );
      }),

      const SizedBox(height: 10),
      // CUSTOM MODEL
      GestureDetector(
        onTap: () {
          setState(() => _status = "File picker not available in mock mode");
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withOpacity(0.06)),
            color: Colors.white.withOpacity(0.02),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(CupertinoIcons.folder_open, color: Colors.white.withOpacity(0.25), size: 14),
            const SizedBox(width: 6),
            Text('Load Custom .bin Model', style: TextStyle(color: Colors.white.withOpacity(0.25), fontSize: 11)),
          ]),
        ),
      ),
      const SizedBox(height: 14),

      // ── OLLAMA STATUS ────────────────────────────
      Text('AI Command Mode', style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
      const SizedBox(height: 8),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Row(children: [
          Container(
            width: 6, height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _ollamaStatus == 'connected' ? kNeonTeal : Colors.red.shade400,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            _ollamaStatus == 'connected' ? 'Ollama Connected' : 'Ollama Offline',
            style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 10),
          ),
        ]),
        GestureDetector(
          onTap: _checkOllamaStatus,
          child: Icon(CupertinoIcons.arrow_2_circlepath, size: 12, color: Colors.white.withOpacity(0.2)),
        ),
      ]),
      const SizedBox(height: 8),
      GestureDetector(
        onTap: _ollamaStatus == 'connected' ? _activateCommandMode : null,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            gradient: _ollamaStatus == 'connected'
                ? const LinearGradient(colors: [kNeonPink, kNeonPurple])
                : null,
            color: _ollamaStatus != 'connected' ? Colors.white.withOpacity(0.03) : null,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: (_ollamaStatus == 'connected' ? kNeonPink : Colors.white).withOpacity(0.15)),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(CupertinoIcons.wand_and_stars, size: 13, color: _ollamaStatus == 'connected' ? Colors.white : Colors.white.withOpacity(0.15)),
            const SizedBox(width: 6),
            Text(
              _commandMode ? _commandStatus : 'Activate Command Mode',
              style: TextStyle(
                color: _ollamaStatus == 'connected' ? Colors.white : Colors.white.withOpacity(0.15),
                fontSize: 11, fontWeight: FontWeight.w600,
              ),
            ),
          ]),
        ),
      ),
    ]);
  }

  // ── Snippets Tab ──────────────────────────────────────────────
  Widget _buildSnippetsTab() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Header row
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('Voice Snippets', style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
        Row(children: [
          Text('${_snippets.length}', style: TextStyle(color: kNeonPurple.withOpacity(0.5), fontSize: 10)),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => setState(() => _showAddSnippet = !_showAddSnippet),
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: kNeonPurple.withOpacity(_showAddSnippet ? 0.2 : 0.1),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: kNeonPurple.withOpacity(0.3)),
              ),
              child: Icon(
                _showAddSnippet ? CupertinoIcons.xmark : CupertinoIcons.plus,
                size: 11, color: kNeonPurple,
              ),
            ),
          ),
        ]),
      ]),
      const SizedBox(height: 8),

      // ── Add Snippet Form ────────────────────────────
      if (_showAddSnippet) ...[
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: kNeonPurple.withOpacity(0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: kNeonPurple.withOpacity(0.15)),
          ),
          child: Column(children: [
            _SnippetTextField(
              controller: _triggerController,
              hint: 'Trigger phrase (e.g. "insert bio")',
              icon: CupertinoIcons.mic,
            ),
            const SizedBox(height: 8),
            _SnippetTextField(
              controller: _contentController,
              hint: 'Content to expand into...',
              icon: CupertinoIcons.doc_text,
              maxLines: 3,
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _addSnippet,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 7),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [kNeonPurple, kNeonTeal]),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(child: Text('Add Snippet', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600))),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 8),
      ],

      // ── Snippet List ────────────────────────────────
      if (_snippets.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Center(child: Column(children: [
            Icon(CupertinoIcons.text_quote, color: Colors.white.withOpacity(0.08), size: 28),
            const SizedBox(height: 8),
            Text('No snippets yet', style: TextStyle(color: Colors.white.withOpacity(0.15), fontSize: 11)),
            Text('Tap + to add your first voice shortcut', style: TextStyle(color: Colors.white.withOpacity(0.08), fontSize: 10)),
          ])),
        ),

      ...List.generate(_snippets.length, (i) {
        final snippet = _snippets[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: 5),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.03),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withOpacity(0.05)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(CupertinoIcons.text_quote, size: 12, color: kNeonTeal.withOpacity(0.5)),
              const SizedBox(width: 8),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  '"${snippet['trigger']}"',
                  style: TextStyle(color: kNeonPurple.withOpacity(0.8), fontSize: 11, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  snippet['content']!.length > 60
                      ? '${snippet['content']!.substring(0, 60)}...'
                      : snippet['content']!,
                  style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 10),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ])),
              GestureDetector(
                onTap: () => _removeSnippet(i),
                child: Icon(CupertinoIcons.trash, size: 12, color: Colors.white.withOpacity(0.15)),
              ),
            ]),
          ),
        );
      }),
    ]);
  }

  // ── Ghost Text Area (Streaming) ──────────────────────────────
  Widget _buildGhostTextArea() {
    if (_solidText.isEmpty && _ghostText.isEmpty) {
      return Text('Waiting for speech...', style: TextStyle(
        color: Colors.white.withOpacity(0.12), fontStyle: FontStyle.italic, fontSize: 12,
      ));
    }
    return RichText(text: TextSpan(children: [
      if (_solidText.isNotEmpty) TextSpan(
        text: _solidText,
        style: TextStyle(color: Colors.white.withOpacity(_isGhostSolidifying ? _ghostOpacity.value : 0.85), fontSize: 13, height: 1.5),
      ),
      if (_ghostText.isNotEmpty) TextSpan(
        text: _ghostText,
        style: TextStyle(color: Colors.white.withOpacity(0.3), fontStyle: FontStyle.italic, fontSize: 13, height: 1.5),
      ),
    ]));
  }

  // ── Batch Text Area ──────────────────────────────────────────
  Widget _buildBatchTextArea() {
    if (_batchResult.isEmpty && !_isRecording) {
      return Text('Hold hotkey to record, release to transcribe...', style: TextStyle(
        color: Colors.white.withOpacity(0.12), fontStyle: FontStyle.italic, fontSize: 12,
      ));
    }
    if (_isRecording) {
      return Row(children: [
        Container(width: 6, height: 6, decoration: const BoxDecoration(shape: BoxShape.circle, color: kNeonPink)),
        const SizedBox(width: 8),
        Text('Recording audio...', style: TextStyle(color: kNeonPink.withOpacity(0.7), fontSize: 12)),
      ]);
    }
    return Text(_batchResult, style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 13, height: 1.5));
  }
}

// ═══════════════════════════════════════════════════════════════════
// REUSABLE WIDGETS
// ═══════════════════════════════════════════════════════════════════

class _FrostedPanel extends StatelessWidget {
  final double width;
  final Widget child;
  const _FrostedPanel({required this.width, required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          width: width,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: kSurfaceDark.withOpacity(0.65),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.10)),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  final bool isActive;
  const _StatusDot({required this.isActive});

  @override
  Widget build(BuildContext context) {
    return Container(width: 7, height: 7, decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: isActive ? kNeonPink : Colors.white.withOpacity(0.2),
      boxShadow: isActive ? [BoxShadow(color: kNeonPink.withOpacity(0.5), blurRadius: 8)] : null,
    ));
  }
}

class _ModeTab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;
  const _ModeTab({required this.label, required this.icon, required this.isActive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isActive ? kNeonPurple.withOpacity(0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: isActive ? Border.all(color: kNeonPurple.withOpacity(0.3)) : null,
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 13, color: isActive ? kNeonPurple : Colors.white24),
            const SizedBox(width: 5),
            Text(label, style: TextStyle(
              color: isActive ? kNeonPurple : Colors.white24,
              fontSize: 11, fontWeight: FontWeight.w600,
            )),
          ]),
        ),
      ),
    );
  }
}

class _ModelRow extends StatelessWidget {
  final String name, size;
  final bool isActive, isDownloading;
  final double progress;
  final VoidCallback? onTap;
  const _ModelRow({required this.name, required this.size, required this.isActive, required this.isDownloading, required this.progress, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: isActive ? kNeonTeal.withOpacity(0.08) : Colors.white.withOpacity(0.02),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isActive ? kNeonTeal.withOpacity(0.2) : Colors.white.withOpacity(0.04)),
          ),
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Row(children: [
                if (isActive) ...[
                  Container(width: 5, height: 5, decoration: const BoxDecoration(shape: BoxShape.circle, color: kNeonTeal)),
                  const SizedBox(width: 6),
                ],
                Text(name, style: TextStyle(
                  color: isActive ? Colors.white.withOpacity(0.7) : Colors.white.withOpacity(0.35),
                  fontSize: 11, fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                )),
              ]),
              isDownloading
                  ? SizedBox(width: 12, height: 12, child: CircularProgressIndicator(
                      value: progress, strokeWidth: 1.5, color: kNeonPurple,
                    ))
                  : isActive
                      ? Icon(CupertinoIcons.checkmark_alt, size: 12, color: kNeonTeal)
                      : Text(size, style: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 10)),
            ]),
            if (isDownloading) ...[
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(value: progress, minHeight: 2, backgroundColor: Colors.white.withOpacity(0.04), valueColor: const AlwaysStoppedAnimation(kNeonPurple)),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

class _SnippetTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final int maxLines;
  const _SnippetTextField({required this.controller, required this.hint, required this.icon, this.maxLines = 1});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 11),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.white.withOpacity(0.15), fontSize: 11),
          prefixIcon: Icon(icon, size: 13, color: Colors.white.withOpacity(0.2)),
          prefixIconConstraints: const BoxConstraints(minWidth: 30),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          isDense: true,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// KINETIC WAVEFORM PAINTER
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
    final colors = [kNeonPink, const Color(0xFFDA70D6), kNeonPurple, const Color(0xFF4DBEEE), kNeonTeal];

    for (int i = 0; i < barCount; i++) {
      final phase = progress * 2 * pi + (i * pi / 3);
      final amplitude = isRecording ? 8.0 + sin(phase) * 10.0 : 3.0;
      final x = spacing * (i + 1) - barWidth / 2;

      final paint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [colors[i].withOpacity(0.9), colors[i].withOpacity(0.3)],
        ).createShader(Rect.fromLTWH(x, centerY - amplitude, barWidth, amplitude * 2))
        ..style = PaintingStyle.fill;

      final rrect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(x + barWidth / 2, centerY), width: barWidth, height: amplitude * 2),
        Radius.circular(barWidth / 2),
      );
      canvas.drawRRect(rrect, paint);
      canvas.drawRRect(rrect, Paint()..color = colors[i].withOpacity(0.12)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    }
  }

  @override
  bool shouldRepaint(covariant _KineticWaveformPainter old) => true;
}
