// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

enum ProjectType { longVideo, shorts }
enum ProjectState { analyzed, rendered }

class Project {
  final String id;
  String name;
  final ProjectType type;
  double durationSec;
  ProjectState state;
  String videoPath;
  String? outputDir;
  dynamic analysisData;
  bool isDeleted; // Soft-delete (Trash Bin)
  final DateTime createdAt;

  Project({
    required this.id,
    required this.name,
    required this.type,
    required this.durationSec,
    required this.state,
    required this.videoPath,
    this.outputDir,
    this.analysisData,
    this.isDeleted = false,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.toString(),
        'durationSec': durationSec,
        'state': state.toString(),
        'videoPath': videoPath,
        'outputDir': outputDir,
        'analysisData': analysisData,
        'isDeleted': isDeleted,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Project.fromJson(Map<String, dynamic> json) {
    return Project(
      id: json['id'],
      name: json['name'] ?? 'Untitled Project',
      type: json['type'] == ProjectType.shorts.toString() ? ProjectType.shorts : ProjectType.longVideo,
      durationSec: (json['durationSec'] as num?)?.toDouble() ?? 0.0,
      state: json['state'] == ProjectState.rendered.toString() ? ProjectState.rendered : ProjectState.analyzed,
      videoPath: json['videoPath'] ?? '',
      outputDir: json['outputDir'],
      analysisData: json['analysisData'],
      isDeleted: json['isDeleted'] ?? false,
      createdAt: json['createdAt'] != null ? DateTime.parse(json['createdAt']) : DateTime.now(),
    );
  }
}

class ProjectManager {
  static final ProjectManager _instance = ProjectManager._internal();
  factory ProjectManager() => _instance;
  ProjectManager._internal();

  String? _projectsDirPath;
  final String _prefKey = "projects_dir_path";

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _projectsDirPath = prefs.getString(_prefKey);

    if (_projectsDirPath == null) {
      final homeDir = Platform.environment['HOME'] ?? Directory.current.path;
      _projectsDirPath = p.join(homeDir, 'Desktop', 'AI_Video_Studio_Projects');
    }

    _ensureDirectoriesExist();
  }

  void _ensureDirectoriesExist() {
    final rootDir = Directory(_projectsDirPath!);
    if (!rootDir.existsSync()) {
      rootDir.createSync(recursive: true);
    }

    final longDir = Directory(longVideosPath);
    if (!longDir.existsSync()) {
      longDir.createSync(recursive: true);
    }

    final shortsDir = Directory(shortsPath);
    if (!shortsDir.existsSync()) {
      shortsDir.createSync(recursive: true);
    }
  }

  String get projectsDirPath => _projectsDirPath!;
  String get longVideosPath => p.join(_projectsDirPath!, 'Long_Videos');
  String get shortsPath => p.join(_projectsDirPath!, 'Shorts');

  Future<void> setProjectsDirPath(String newPath) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, newPath);
    _projectsDirPath = newPath;

    _ensureDirectoriesExist();
  }

  List<Project> getProjects() {
    final dir = Directory(_projectsDirPath!);
    if (!dir.existsSync()) return [];

    final List<Project> projects = [];
    final files = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.json'));

    for (var file in files) {
      try {
        final content = file.readAsStringSync();
        final json = jsonDecode(content);
        projects.add(Project.fromJson(json));
      } catch (e) {
        print("Project read error: $e");
      }
    }

    // Most recent first
    projects.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return projects;
  }

  void saveProject(Project project) {
    final file = File(p.join(_projectsDirPath!, '${project.id}.json'));
    final json = jsonEncode(project.toJson());
    file.writeAsStringSync(json);
  }

  void moveToTrash(Project project) {
    project.isDeleted = true;
    saveProject(project);
  }

  void restoreProject(Project project) {
    project.isDeleted = false;
    saveProject(project);
  }

  void deletePermanently(Project project) {
    final file = File(p.join(_projectsDirPath!, '${project.id}.json'));
    if (file.existsSync()) {
      file.deleteSync();
    }
  }
}
