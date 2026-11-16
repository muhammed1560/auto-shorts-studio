// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:async';
import 'package:path/path.dart' as p;

class VideoService {
  /// Dynamically locates the 'engine' directory across different execution environments (Dev, Release, Bundled)
  String _resolveEngineDirectory() {
    // 1. Current working directory
    final currentDir = Directory.current.path;
    final engineInCurrent = p.join(currentDir, 'engine');
    if (Directory(engineInCurrent).existsSync()) {
      return engineInCurrent;
    }

    // 2. Parent directory (e.g., if launched from a subfolder or build directory)
    final engineInParent = p.join(currentDir, '..', 'engine');
    if (Directory(engineInParent).existsSync()) {
      return engineInParent;
    }

    // 3. Executable parent directory (for packaged desktop applications)
    try {
      final execDir = File(Platform.resolvedExecutable).parent.path;
      final engineInExec = p.join(execDir, 'engine');
      if (Directory(engineInExec).existsSync()) {
        return engineInExec;
      }
      final engineInResources = p.join(execDir, '..', 'Resources', 'engine');
      if (Directory(engineInResources).existsSync()) {
        return engineInResources;
      }
    } catch (_) {}

    // Fallback default
    return engineInCurrent;
  }

  Future<void> generateShorts({
    required String videoPath,
    required String outputDir,
    required void Function(String) onProgress,
    int duration = 60,
    int count = 6,
    String fitMode = 'crop',
  }) async {
    final enginePath = _resolveEngineDirectory();
    final mainScript = p.join(enginePath, 'main.py');

    if (!await File(mainScript).exists()) {
      onProgress("[ERROR] Python engine script not found at: $mainScript");
      return;
    }

    onProgress("Python Engine starting...");
    onProgress("Script: $mainScript");

    try {
      final process = await Process.start(
        'python3',
        [
          '-u',
          mainScript,
          '--video_path',
          videoPath,
          '--output',
          outputDir,
          '--duration',
          duration.toString(),
          '--count',
          count.toString(),
          '--fit_mode',
          fitMode,
        ],
        workingDirectory: enginePath,
      );

      process.stdout.transform(SystemEncoding().decoder).listen((data) {
        for (var line in data.split('\n')) {
          final trimmed = line.trim();
          if (trimmed.isNotEmpty) {
            if (trimmed.startsWith('PROGRESS:')) {
              onProgress(trimmed.substring(9));
            } else if (trimmed.startsWith('STATUS:SUCCESS:')) {
              onProgress("SUCCESS: ${trimmed.substring(15)}");
            } else {
              onProgress(trimmed);
            }
          }
        }
      });

      process.stderr.transform(SystemEncoding().decoder).listen((data) {
        for (var line in data.split('\n')) {
          final trimmed = line.trim();
          if (trimmed.isNotEmpty) {
            onProgress("[ERROR] $trimmed");
          }
        }
      });

      final exitCode = await process.exitCode;

      if (exitCode == 0) {
        onProgress("Process completed successfully!");
      } else {
        onProgress("Process exited with code: $exitCode");
      }
    } catch (e) {
      onProgress("Failed to launch process: $e");
    }
  }

  Future<String?> analyzeLongVideo(
    String videoPath,
    void Function(String) onProgress,
  ) async {
    final enginePath = _resolveEngineDirectory();
    final analyzerScript = p.join(enginePath, 'smart_analyzer.py');

    if (!await File(analyzerScript).exists()) {
      onProgress("[ERROR] Analyzer script not found: $analyzerScript");
      return null;
    }

    try {
      final process = await Process.start(
        'python3',
        ['-u', analyzerScript, videoPath],
        workingDirectory: enginePath,
      );
      String? resultJson;

      process.stdout.transform(SystemEncoding().decoder).listen((data) {
        for (var line in data.split('\n')) {
          final trimmed = line.trim();
          if (trimmed.startsWith('PROGRESS:')) {
            onProgress(trimmed.substring(9));
          } else if (trimmed.startsWith('RESULT_JSON:')) {
            resultJson = trimmed.substring(12);
          } else if (trimmed.isNotEmpty) {
            print("Python Log: $trimmed");
          }
        }
      });

      process.stderr.transform(SystemEncoding().decoder).listen((data) {
        for (var line in data.split('\n')) {
          final trimmed = line.trim();
          if (trimmed.isNotEmpty) {
            print("Analyze Warning/Error: $trimmed");
          }
        }
      });

      await process.exitCode;
      return resultJson;
    } catch (e) {
      print("Analyze Exception: $e");
      return null;
    }
  }

  Future<void> processLongVideo({
    required String videoPath,
    required String jsonStr,
    required String outputDir,
    required String sfxName,
    required void Function(String) onProgress,
  }) async {
    final enginePath = _resolveEngineDirectory();
    final processorScript = p.join(enginePath, 'long_video_processor.py');

    if (!await File(processorScript).exists()) {
      onProgress("[ERROR] Processor script not found: $processorScript");
      return;
    }

    final baseName = p.basenameWithoutExtension(videoPath);
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString().substring(5);
    final outputPath = p.join(outputDir, '${baseName}_edited_$timestamp.mp4');

    onProgress("Editing video and applying transition SFX, please wait...");
    try {
      final process = await Process.start(
        'python3',
        ['-u', processorScript, videoPath, jsonStr, outputPath, sfxName],
        workingDirectory: enginePath,
      );

      process.stdout.transform(SystemEncoding().decoder).listen((data) {
        for (var line in data.split('\n')) {
          final trimmed = line.trim();
          if (trimmed.startsWith('PROGRESS:')) {
            onProgress(trimmed.substring(9));
          } else if (trimmed.startsWith('STATUS:SUCCESS:')) {
            onProgress("SUCCESS: ${trimmed.substring(15)}");
          } else if (trimmed.startsWith('SUCCESS:')) {
            onProgress(trimmed);
          } else if (trimmed.isNotEmpty) {
            print("Python Log: $trimmed");
          }
        }
      });

      process.stderr.transform(SystemEncoding().decoder).listen((data) {
        for (var line in data.split('\n')) {
          final trimmed = line.trim();
          if (trimmed.isNotEmpty) {
            onProgress("[Log] $trimmed");
          }
        }
      });

      final exitCode = await process.exitCode;
      if (exitCode == 0) {
        onProgress("SUCCESS: $outputPath");
      } else {
        onProgress("ERROR Code: $exitCode");
      }
    } catch (e) {
      onProgress("ERROR: $e");
    }
  }
}
