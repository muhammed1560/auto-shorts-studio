// ignore_for_file: avoid_print, deprecated_member_use
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'video_service.dart';
import 'package:path/path.dart' as p;
import 'main.dart';
import 'project_manager.dart';

class ShortsTab extends StatefulWidget {
  final Project? initialProject;
  const ShortsTab({super.key, this.initialProject});

  @override
  State<ShortsTab> createState() => _ShortsTabState();
}

class _ShortsTabState extends State<ShortsTab> {
  bool _useYoutubeLink = false;
  String? _selectedVideoPath;
  int _targetDuration = 60;
  int _shortsCount = 6;
  String _videoFitMode = 'blur';
  final List<String> _logs = [];
  bool _isProcessing = false;
  bool _isDone = false;
  final VideoService _videoService = VideoService();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _urlController = TextEditingController();

  Project? _currentProject;

  @override
  void initState() {
    super.initState();
    if (widget.initialProject != null) {
      _currentProject = widget.initialProject;
      _selectedVideoPath = _currentProject!.videoPath;
      if (_selectedVideoPath != null && _selectedVideoPath!.startsWith('http')) {
        _useYoutubeLink = true;
        _urlController.text = _selectedVideoPath!;
      }
      if (_currentProject!.state == ProjectState.rendered) {
        _isDone = true;
        _logs.add("Previous rendering complete. Your generated shorts are ready!");
        _logs.add("Click 'Open Output Folder' below to view exported video files.");
      }
    }
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

  void _addLog(String message) {
    setState(() {
      _logs.add(message);
    });
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        final position = _scrollController.position;
        if (position.maxScrollExtent - position.pixels <= 150) {
          _scrollController.animateTo(
            position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      }
    });
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
            Text("4. Once transferred, click 'Select Video' to choose the file.", style: TextStyle(fontWeight: FontWeight.bold)),
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
    FilePickerResult? result = await FilePicker.pickFiles(
      type: FileType.video,
      allowMultiple: false,
    );

    if (result != null && result.files.single.path != null) {
      setState(() {
        _selectedVideoPath = result.files.single.path;
      });
      _addLog("Selected video: $_selectedVideoPath");
    }
  }

  Future<void> _startProcessing() async {
    String inputTarget = "";
    if (_useYoutubeLink) {
      if (_urlController.text.trim().isEmpty) {
        _addLog("Error: Please provide a valid YouTube link.");
        return;
      }
      inputTarget = _urlController.text.trim();
    } else {
      if (_selectedVideoPath == null) {
        _addLog("Error: Please select a local video file first.");
        return;
      }
      inputTarget = _selectedVideoPath!;
    }

    String outputDir = ProjectManager().shortsPath;

    setState(() {
      _isProcessing = true;
      _isDone = false;
      _logs.clear();
      _addLog("Starting Auto-Shorts pipeline...");

      if (_currentProject == null) {
        String baseName = _useYoutubeLink
            ? "YouTube_${DateTime.now().millisecondsSinceEpoch}"
            : p.basenameWithoutExtension(inputTarget);
        _currentProject = Project(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          name: baseName,
          type: ProjectType.shorts,
          durationSec: 0.0,
          state: ProjectState.analyzed,
          videoPath: inputTarget,
          outputDir: outputDir,
        );
      } else {
        _currentProject!.durationSec = 0.0;
        _currentProject!.outputDir = outputDir;
      }
      ProjectManager().saveProject(_currentProject!);
    });

    await _videoService.generateShorts(
      videoPath: inputTarget,
      outputDir: outputDir,
      onProgress: (msg) {
        _addLog(msg);
        if (msg.startsWith("FINAL_DURATION:")) {
          double actualDuration = double.tryParse(msg.substring(15)) ?? 0.0;
          _currentProject!.durationSec += actualDuration;
        }
        if (msg.startsWith("STATUS:SUCCESS:") || msg.startsWith("SUCCESS:")) {
          ProjectManager().saveProject(_currentProject!);
        }
      },
      duration: _targetDuration,
      count: _shortsCount,
      fitMode: _videoFitMode,
    );

    setState(() {
      _isProcessing = false;
      _isDone = true;
      _addLog("--------------------------------------------------");
      _addLog("All shorts generated successfully! Check output folder.");
      _showNotification("Auto-Shorts Studio", "All vertical shorts generated successfully!");

      _currentProject!.state = ProjectState.rendered;
      ProjectManager().saveProject(_currentProject!);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(24.0),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white10),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text("Source Type:", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 16),
                    ChoiceChip(
                      label: const Text("Local Video"),
                      selected: !_useYoutubeLink,
                      onSelected: (val) {
                        setState(() {
                          _useYoutubeLink = !val;
                        });
                      },
                    ),
                    const SizedBox(width: 12),
                    ChoiceChip(
                      label: const Text("YouTube URL"),
                      selected: _useYoutubeLink,
                      onSelected: (val) {
                        setState(() {
                          _useYoutubeLink = val;
                        });
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (!_useYoutubeLink)
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _selectedVideoPath ?? 'No video selected yet',
                          style: TextStyle(
                            color: _selectedVideoPath == null ? Colors.white54 : Colors.white,
                            fontSize: 16,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: _isProcessing ? null : _showUSBImportDialog,
                        icon: const Icon(Icons.usb),
                        label: const Text("USB Import"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueGrey,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: _isProcessing ? null : _pickVideo,
                        icon: const Icon(Icons.video_file),
                        label: const Text('Select Video'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        ),
                      ),
                    ],
                  )
                else
                  TextField(
                    controller: _urlController,
                    decoration: const InputDecoration(
                      labelText: "Paste YouTube Video Link Here",
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.link),
                    ),
                    enabled: !_isProcessing,
                  ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Output Directory: ${ProjectManager().shortsPath}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 16,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        decoration: const InputDecoration(
                          labelText: "Target Duration",
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        value: _targetDuration,
                        items: [15, 30, 45, 60]
                            .map((val) => DropdownMenuItem(
                                  value: val,
                                  child: Text("$val seconds"),
                                ))
                            .toList(),
                        onChanged: _isProcessing ? null : (val) => setState(() => _targetDuration = val!),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        decoration: const InputDecoration(
                          labelText: "Clips Count",
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        value: _shortsCount,
                        items: List.generate(10, (i) => i + 1)
                            .map((val) => DropdownMenuItem(
                                  value: val,
                                  child: Text("$val Short${val > 1 ? 's' : ''}"),
                                ))
                            .toList(),
                        onChanged: _isProcessing ? null : (val) => setState(() => _shortsCount = val!),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        decoration: const InputDecoration(
                          labelText: "9:16 Aspect Ratio Fit",
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        value: _videoFitMode,
                        items: const [
                          DropdownMenuItem(value: "blur", child: Text("Blur Background (1080x1920)")),
                          DropdownMenuItem(value: "crop", child: Text("Center Crop (1080x1920)")),
                        ],
                        onChanged: _isProcessing ? null : (val) => setState(() => _videoFitMode = val!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: _isProcessing ? null : _startProcessing,
                    icon: _isProcessing
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_awesome),
                    label: Text(
                      _isProcessing ? 'AI Engine Processing...' : 'Generate Vertical Shorts (Jump Cut)',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_isDone) ...[
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: () {
                    Process.run('open', [ProjectManager().shortsPath]);
                  },
                  icon: const Icon(Icons.folder_open),
                  label: const Text("Open in Finder"),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orangeAccent),
                ),
              ],
            ),
          ],
          const SizedBox(height: 24),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Terminal Logs',
                        style: TextStyle(
                          color: Colors.grey,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy, color: Colors.grey, size: 20),
                        tooltip: 'Copy Logs',
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: _logs.join('\n')));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Terminal logs copied to clipboard!'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white24),
                  Expanded(
                    child: ListView.builder(
                      controller: _scrollController,
                      itemCount: _logs.length,
                      itemBuilder: (context, index) {
                        final log = _logs[index];
                        final isError = log.startsWith('[ERROR]');
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4.0),
                          child: SelectableText(
                            log,
                            style: TextStyle(
                              color: isError ? Colors.redAccent : Colors.greenAccent,
                              fontFamily: 'Menlo',
                              fontSize: 13,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
