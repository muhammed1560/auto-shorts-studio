// ignore_for_file: avoid_print, deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'video_service.dart';
import 'main.dart';
import 'project_manager.dart';

class LongEditorTab extends StatefulWidget {
  final Project? initialProject;
  const LongEditorTab({super.key, this.initialProject});

  @override
  State<LongEditorTab> createState() => _LongEditorTabState();
}

class _LongEditorTabState extends State<LongEditorTab> {
  String? _videoPath;
  bool _isAnalyzing = false;
  bool _isProcessing = false;

  Map<String, dynamic>? _analysisData;
  String _selectedSfx = 'pop';
  String? _finalOutputPath;
  final VideoService _videoService = VideoService();
  final List<String> _logs = [];
  final ScrollController _logScrollController = ScrollController();

  Project? _currentProject;

  String _currentProgressMessage = "Analyzing video...";
  Stopwatch? _stopwatch;
  Timer? _timer;
  String _timeElapsed = "00:00";

  @override
  void initState() {
    super.initState();

    if (widget.initialProject != null) {
      _currentProject = widget.initialProject;
      _videoPath = _currentProject!.videoPath;
      _analysisData = _currentProject!.analysisData;
      _finalOutputPath = _currentProject!.outputDir;
    }
  }

  void _addLog(String log) {
    setState(() => _logs.add(log));
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_logScrollController.hasClients) {
        _logScrollController.animateTo(
          _logScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showNotification(String title, String message) async {
    if (Platform.isMacOS) {
      const DarwinNotificationDetails darwinDetails = DarwinNotificationDetails();
      const NotificationDetails details = NotificationDetails(macOS: darwinDetails);
      try {
        await flutterLocalNotificationsPlugin.show(
          id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
          title: title,
          body: message,
          notificationDetails: details,
        );
      } catch (e) {
        print("Notification error: $e");
      }
    }
  }

  void _showUSBImportDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2C),
        title: const Row(
          children: [
            Icon(Icons.usb, color: Colors.blueAccent),
            SizedBox(width: 8),
            Text("Lossless USB Cable Import"),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Import high-bitrate 4K/60fps video directly via USB without cloud compression.",
              style: TextStyle(color: Colors.white70),
            ),
            SizedBox(height: 16),
            Text("1. Connect your smartphone to your Mac via USB cable.", style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text("2. Authorize 'Trust this computer' on your mobile device.", style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text("3. Click below to launch macOS Image Capture and transfer files to Desktop.", style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text("4. Once transferred, click 'Select Video' to load the file.", style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel", style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Process.run('open', ['-a', 'Image Capture']);
            },
            icon: const Icon(Icons.camera_alt),
            label: const Text("Open Image Capture"),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
          ),
        ],
      ),
    );
  }

  Future<void> _pickVideo() async {
    FilePickerResult? result = await FilePicker.pickFiles(type: FileType.video);
    if (result != null && result.files.single.path != null) {
      setState(() {
        _videoPath = result.files.single.path;
        _analysisData = null;
        _finalOutputPath = null;
      });
      _addLog("Selected video file: $_videoPath");
    }
  }

  Future<void> _analyzeVideo() async {
    if (_videoPath == null) {
      _addLog("Error: Please select a video file first.");
      return;
    }
    setState(() {
      _isAnalyzing = true;
      _logs.clear();
      _currentProgressMessage = "Analyzing audio-visual stream...";
      _stopwatch = Stopwatch()..start();
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (_stopwatch != null) {
          setState(() {
            final seconds = _stopwatch!.elapsed.inSeconds;
            _timeElapsed = "${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}";
          });
        }
      });
      _addLog("Starting intelligent dual-factor analysis (detecting silence & inactivity)...");
    });

    final jsonStr = await _videoService.analyzeLongVideo(_videoPath!, (progressMsg) {
      setState(() {
        _currentProgressMessage = progressMsg;
      });
      _addLog(progressMsg);
    });

    _stopwatch?.stop();
    _timer?.cancel();
    _addLog("Analysis finished in: $_timeElapsed");

    if (jsonStr != null) {
      try {
        final parsed = jsonDecode(jsonStr);
        setState(() {
          _analysisData = parsed;
        });
        _addLog("Analysis metadata parsed successfully!");
        _showNotification("AI Analysis Completed", "Silent and inactive intervals detected.");

        double calculatedDuration = 0.0;
        if (parsed is Map && parsed.containsKey('segments')) {
          for (var item in parsed['segments']) {
            if (item['action'] == 'keep') {
              double start = (item['start'] as num).toDouble();
              double end = (item['end'] as num).toDouble();
              calculatedDuration += (end - start);
            }
          }
        }

        if (_currentProject == null) {
          String baseName = p.basenameWithoutExtension(_videoPath!);
          _currentProject = Project(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            name: baseName,
            type: ProjectType.longVideo,
            durationSec: calculatedDuration,
            state: ProjectState.analyzed,
            videoPath: _videoPath!,
            analysisData: _analysisData,
          );
        } else {
          _currentProject!.durationSec = calculatedDuration;
          _currentProject!.state = ProjectState.analyzed;
          _currentProject!.analysisData = _analysisData;
        }
        ProjectManager().saveProject(_currentProject!);
      } catch (e) {
        _addLog("JSON Parsing Error: $e");
      }
    } else {
      _addLog("Analysis pipeline failed.");
      _showNotification("Analysis Failed", "An error occurred while analyzing the video.");
    }
    setState(() => _isAnalyzing = false);
  }

  Future<void> _processVideo() async {
    if (_videoPath == null || _analysisData == null) return;

    String outDir = ProjectManager().longVideosPath;

    setState(() {
      _isProcessing = true;
      _logs.clear();
      _finalOutputPath = null;
      _stopwatch = Stopwatch()..start();
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (_stopwatch != null) {
          setState(() {
            final seconds = _stopwatch!.elapsed.inSeconds;
            _timeElapsed = "${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}";
          });
        }
      });
    });

    await _videoService.processLongVideo(
      videoPath: _videoPath!,
      jsonStr: jsonEncode(_analysisData),
      outputDir: outDir,
      sfxName: _selectedSfx,
      onProgress: (log) {
        _addLog(log);
        if (log.startsWith("SUCCESS:") || log.startsWith("STATUS:SUCCESS:")) {
          setState(() {
            _finalOutputPath = log
                .replaceAll("STATUS:SUCCESS:", "")
                .replaceAll("SUCCESS:", "")
                .trim();
          });

          if (_currentProject != null) {
            _currentProject!.state = ProjectState.rendered;
            _currentProject!.outputDir = _finalOutputPath;
            ProjectManager().saveProject(_currentProject!);
          }
        }
      },
    );

    _stopwatch?.stop();
    _timer?.cancel();
    _addLog("Video render completed in: $_timeElapsed");

    if (_finalOutputPath != null) {
      _showNotification("Video Editing Finished!", "Your edited video is ready.");
    } else {
      _showNotification("Rendering Error", "An issue occurred during video rendering.");
    }

    setState(() => _isProcessing = false);
  }

  void _openInSystemPlayer() {
    if (_finalOutputPath != null) {
      Process.run('open', [_finalOutputPath!]);
      _addLog("Opened in system player: $_finalOutputPath");
    }
  }

  String _formatDuration(double sec) {
    int m = sec ~/ 60;
    int s = (sec % 60).toInt();
    return "${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}";
  }

  String _getFileSize(String? path) {
    if (path == null || path.isEmpty) return "Unknown";
    try {
      final file = File(path);
      if (file.existsSync()) {
        final bytes = file.lengthSync();
        if (bytes < 1024 * 1024) {
          return "${(bytes / 1024).toStringAsFixed(1)} KB";
        } else if (bytes < 1024 * 1024 * 1024) {
          return "${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB";
        } else {
          return "${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB";
        }
      }
    } catch (_) {}
    return "Unknown";
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Smart Long Video Editor", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Text(_videoPath ?? 'Select a local long-form video...', style: const TextStyle(color: Colors.white70)),
                      ),
                      ElevatedButton.icon(
                        onPressed: _isAnalyzing || _isProcessing ? null : _showUSBImportDialog,
                        icon: const Icon(Icons.usb),
                        label: const Text("USB Import"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueGrey,
                          foregroundColor: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: _isAnalyzing || _isProcessing ? null : _pickVideo,
                        icon: const Icon(Icons.video_library),
                        label: const Text("Select Video"),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text('Output Directory: ${ProjectManager().longVideosPath}', style: const TextStyle(color: Colors.white70)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _isAnalyzing || _isProcessing ? null : _analyzeVideo,
                      icon: _isAnalyzing
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Icon(Icons.analytics, color: Colors.white),
                      label: Text(
                        _isAnalyzing ? "$_currentProgressMessage ($_timeElapsed)" : "Run AI Timeline Analysis",
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.indigoAccent),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_analysisData != null)
              SizedBox(
                height: 320,
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.indigo.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.indigoAccent.withOpacity(0.5)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 1,
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text("📊 Analysis Report", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                              const Divider(),
                              Text("Original Duration: ${_formatDuration((_analysisData!['original_duration_sec'] as num).toDouble())}"),
                              const SizedBox(height: 8),
                              Text(
                                "New Duration: ${_formatDuration((_analysisData!['new_duration_sec'] as num).toDouble())}",
                                style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                "Removed Dead Air: ${_formatDuration((_analysisData!['total_cut_sec'] as num).toDouble())}",
                                style: const TextStyle(color: Colors.redAccent),
                              ),
                              const SizedBox(height: 8),
                              Text("SFX Transitions: ${_analysisData!['sfx_count']}", style: const TextStyle(color: Colors.orangeAccent)),
                              const SizedBox(height: 16),
                              DropdownButtonFormField<String>(
                                decoration: const InputDecoration(labelText: "Transition Sound Effect (SFX)", border: OutlineInputBorder()),
                                value: _selectedSfx,
                                items: const [
                                  DropdownMenuItem(value: 'none', child: Text("No SFX")),
                                  DropdownMenuItem(value: 'whoosh', child: Text("Whoosh (Cinematic)")),
                                  DropdownMenuItem(value: 'pop', child: Text("Pop (Subtle)")),
                                  DropdownMenuItem(value: 'random', child: Text("Random (Mixed Whoosh & Pop)")),
                                ],
                                onChanged: (val) => setState(() => _selectedSfx = val!),
                              ),
                              const SizedBox(height: 16),
                              SizedBox(
                                width: double.infinity,
                                height: 50,
                                child: ElevatedButton.icon(
                                  onPressed: _isProcessing ? null : _processVideo,
                                  icon: _isProcessing
                                      ? const CircularProgressIndicator(color: Colors.white)
                                      : const Icon(Icons.movie_creation, color: Colors.white),
                                  label: Text(
                                    _isProcessing ? "Rendering Video... ($_timeElapsed)" : "Render Smart Edit (Jump-Cut)",
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                  ),
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 24),
                      Expanded(
                        flex: 1,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("✂️ Timeline Cut Segments", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            Expanded(
                              child: ListView.builder(
                                itemCount: (_analysisData!['segments'] as List).length,
                                itemBuilder: (context, index) {
                                  final segments = _analysisData!['segments'] as List;
                                  final cut = segments[index];
                                  final bool isKeep = cut['action'] == 'keep';

                                  bool hasNextKeep = false;
                                  if (isKeep) {
                                    for (int j = index + 1; j < segments.length; j++) {
                                      if (segments[j]['action'] == 'keep') {
                                        hasNextKeep = true;
                                        break;
                                      }
                                    }
                                  }

                                  return Column(
                                    children: [
                                      Container(
                                        margin: const EdgeInsets.only(bottom: 4),
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        color: isKeep ? Colors.green.withOpacity(0.2) : Colors.red.withOpacity(0.2),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text("${_formatDuration((cut['start'] as num).toDouble())} - ${_formatDuration((cut['end'] as num).toDouble())}"),
                                            Text(
                                              isKeep ? "KEEP" : "CUT",
                                              style: TextStyle(fontWeight: FontWeight.bold, color: isKeep ? Colors.greenAccent : Colors.redAccent),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (isKeep && hasNextKeep && _selectedSfx != 'none')
                                        const Padding(
                                          padding: EdgeInsets.symmetric(vertical: 4),
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(Icons.auto_awesome, color: Colors.orangeAccent, size: 16),
                                              SizedBox(width: 4),
                                              Text("Transition SFX Inserted", style: TextStyle(color: Colors.orangeAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                                            ],
                                          ),
                                        ),
                                    ],
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (_finalOutputPath != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                decoration: BoxDecoration(
                  color: Colors.greenAccent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.greenAccent.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Column(
                      children: [
                        const Text("Original File Size", style: TextStyle(color: Colors.grey, fontSize: 14)),
                        const SizedBox(height: 4),
                        Text(
                          _getFileSize(_videoPath),
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ],
                    ),
                    const Icon(Icons.arrow_forward, color: Colors.greenAccent),
                    Column(
                      children: [
                        const Text("Rendered File Size", style: TextStyle(color: Colors.grey, fontSize: 14)),
                        const SizedBox(height: 4),
                        Text(
                          _getFileSize(_finalOutputPath),
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.greenAccent),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: _openInSystemPlayer,
                    icon: const Icon(Icons.desktop_mac),
                    label: const Text("Open in QuickTime Player"),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.orangeAccent),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              height: 250,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(8)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Terminal Logs',
                          style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                        ),
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.white70, size: 20),
                              tooltip: 'Clear Terminal',
                              onPressed: () {
                                setState(() {
                                  _logs.clear();
                                });
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.copy_all, color: Colors.white70, size: 20),
                              tooltip: 'Copy All Logs',
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: _logs.join('\n')));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Terminal logs copied to clipboard!'), duration: Duration(seconds: 2)),
                                );
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                    const Divider(color: Colors.white24),
                    Expanded(
                      child: ListView.builder(
                        controller: _logScrollController,
                        itemCount: _logs.length,
                        itemBuilder: (ctx, i) => Text(_logs[i], style: const TextStyle(fontFamily: 'Menlo', fontSize: 12, color: Colors.greenAccent)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
