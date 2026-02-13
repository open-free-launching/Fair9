import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:tray_manager/tray_manager.dart';
import 'dart:ui';
import 'dart:async';
import 'dart:io';
import 'dart:convert';

// Mock Bridge for UI Dev without compiled Rust
// import 'bridge_generated.dart'; 

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

const String kAppVersion = '1.0.0';
const String kGitHubRepo = 'open-free-launching/Fair9';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  // Check for Model
  bool modelExists = await _checkModelExists();

  WindowOptions windowOptions = const WindowOptions(
    size: Size(400, 200),
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
  final directory = await getApplicationSupportDirectory(); // AppData/Roaming/.../
  // Adjust path to match Rust expectation: OpenFL/Fair9/models
  // Flutter getApplicationSupportDirectory usually maps to AppData/Roaming/com.example/fairnine_flutter
  // We need to be careful about matching the Rust path.
  // Rust used: dirs::data_dir() + OpenFL/Fair9/models
  // We should try to match that.
  
  final appData = Platform.environment['APPDATA'];
  if (appData != null) {
      final modelPath = '$appData\\OpenFL\\Fair9\\models\\ggml-tiny.en-q8_0.bin';
      return File(modelPath).exists();
  }
  return false;
}

class MyApp extends StatelessWidget {
  final String initialRoute;
  const MyApp({super.key, required this.initialRoute});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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

class ModelDownloader extends StatefulWidget {
  const ModelDownloader({super.key});

  @override
  State<ModelDownloader> createState() => _ModelDownloaderState();
}

class _ModelDownloaderState extends State<ModelDownloader> {
  double _progress = 0.0;
  String _status = "Downloading Model...";

  @override
  void initState() {
    super.initState();
    _downloadModel();
  }

  Future<void> _downloadModel() async {
    // Check/Create Directory
    final appData = Platform.environment['APPDATA'];
    if (appData == null) {
         setState(() => _status = "Error: APPDATA not found");
         return;
    }
    
    final modelDir = Directory('$appData\\OpenFL\\Fair9\\models');
    if (!await modelDir.exists()) {
      await modelDir.create(recursive: true);
    }
    
    final modelPath = '${modelDir.path}\\ggml-tiny.en-q8_0.bin';
    final url = Uri.parse("https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.en-q8_0.bin");

    final request = http.Request('GET', url);
    final response = await http.Client().send(request);
    final contentLength = response.contentLength ?? 75000000; // Approx 75MB

    List<int> bytes = [];
    int received = 0;

    response.stream.listen(
      (List<int> newBytes) {
        bytes.addAll(newBytes);
        received += newBytes.length;
        setState(() {
          _progress = received / contentLength;
          _status = "Downloading... ${(received / 1024 / 1024).toStringAsFixed(1)} MB";
        });
      },
      onDone: () async {
        await File(modelPath).writeAsBytes(bytes);
        setState(() => _status = "Download Complete!");
        await Future.delayed(const Duration(seconds: 1));
        if (mounted) {
           Navigator.pushReplacementNamed(context, '/');
        }
      },
      onError: (e) {
        setState(() => _status = "Error: $e");
      },
      cancelOnError: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: Container(
          width: 300,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.8),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Setup", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 20),
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: 10),
              Text(_status, style: const TextStyle(color: Colors.white70)),
            ],
          ),
        ),
      ),
    );
  }
}

// ... (HUDOverlay class remains mostly the same, ensuring it's the home route target)
class HUDOverlay extends StatefulWidget {
  const HUDOverlay({super.key});

  @override
  State<HUDOverlay> createState() => _HUDOverlayState();
}

class _HUDOverlayState extends State<HUDOverlay> with TrayListener, WindowListener {
  String _status = "Ready";
  bool _isRecording = false;
  bool _updateAvailable = false;
  String _latestVersion = '';
  bool _legacyAppMode = false; // Adaptive typing delay
  final StreamController<String> _mockStreamController = StreamController<String>.broadcast();
  Stream<String>? _transcriptionStream;

  @override
  void initState() {
    super.initState();
    trayManager.addListener(this);
    windowManager.addListener(this);
    _initTray();
    _checkForUpdates();
    
    // For real usage:
    // _transcriptionStream = api.createTranscriptionStream();
    // Mocking for UI dev:
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
    } catch (_) { /* Silent fail — no internet is fine */ }
  }

  /// Adaptive typing delay (10ms default, 30ms for legacy apps)
  Duration get _typingDelay => _legacyAppMode
      ? const Duration(milliseconds: 30)
      : const Duration(milliseconds: 10);
// ... (rest of HUDOverlay)


  @override
  void dispose() {
    trayManager.removeListener(this);
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _initTray() async {
    await trayManager.setIcon(
      Platform.isWindows ? 'images/tray_icon.ico' : 'images/tray_icon.png', 
      // Note: User needs to add assets
    );
    Menu menu = Menu(
      items: [
        MenuItem(
          key: 'show_window',
          label: 'Show HUD',
        ),
        MenuItem.separator(),
        MenuItem(
          key: 'exit_app',
          label: 'Exit',
        ),
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

  // Window dragging
  // window_manager usually requires a DragToMoveArea widget or similar via GestureDetector

  void _toggleRecording() {
    setState(() {
      _isRecording = !_isRecording;
    });

    if (_isRecording) {
      setState(() => _status = "Listening...");
      // Simulate stream updates
      _mockStreaming();
    } else {
      setState(() => _status = "Paused");
    }
  }

  void _mockStreaming() async {
    String sentence = "This is a streaming transcription example from Rust engine.";
    List<String> words = sentence.split(' ');
    String current = "";
    for (var word in words) {
      if (!_isRecording) break;
      await Future.delayed(const Duration(milliseconds: 300));
      current += "$word ";
      _mockStreamController.add(current);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: GestureDetector(
          onPanStart: (details) {
            windowManager.startDragging();
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0), // Glass effect
              child: Container(
                width: 350,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5), // Semi-transparent dark
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withOpacity(0.2)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 20,
                      spreadRadius: 5,
                    )
                  ]
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Handle Bar
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 15),
                    
                    // Status & Icon
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              _isRecording ? Icons.mic : Icons.mic_none,
                              color: _isRecording ? Colors.redAccent : Colors.white70,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              _status,
                              style: const TextStyle(
                                color: Colors.white70, 
                                fontWeight: FontWeight.bold
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                          onPressed: () => windowManager.hide(), // Minimize to tray
                        )
                      ],
                    ),
                    const SizedBox(height: 15),

                    // Transcription Area
                    Container(
                      height: 80,
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: SingleChildScrollView(
                        reverse: true,
                         child: StreamBuilder<String>(
                            stream: _transcriptionStream,
                            builder: (context, snapshot) {
                              if (snapshot.hasData) {
                                return Text(
                                  snapshot.data!,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                  ),
                                );
                              }
                              return const Text(
                                "Waiting for speech...",
                                style: TextStyle(color: Colors.white24, fontStyle: FontStyle.italic),
                              );
                            },
                          ),
                      ),
                    ),
                    
                    const SizedBox(height: 15),
                    
                    // Update Banner
                    if (_updateAvailable)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: Colors.blueAccent.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blueAccent.withOpacity(0.4)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.system_update, color: Colors.blueAccent, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Update $_latestVersion available',
                                style: const TextStyle(color: Colors.white70, fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Controls
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _toggleRecording,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isRecording ? Colors.redAccent.withOpacity(0.8) : Colors.white.withOpacity(0.1),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: Text(_isRecording ? "Stop Listening" : "Start Listening"),
                      ),
                    ),

                    // Legacy App Toggle
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Legacy App Mode', style: TextStyle(color: Colors.white38, fontSize: 11)),
                        Switch(
                          value: _legacyAppMode,
                          onChanged: (v) => setState(() => _legacyAppMode = v),
                          activeColor: Colors.blueAccent,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
