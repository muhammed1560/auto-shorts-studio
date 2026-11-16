// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'project_manager.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';

class ProjectsTab extends StatefulWidget {
  final Function(Project) onEditProject;

  const ProjectsTab({super.key, required this.onEditProject});

  @override
  State<ProjectsTab> createState() => _ProjectsTabState();
}

class _ProjectsTabState extends State<ProjectsTab> {
  bool _showTrash = false;

  void _refresh() {
    setState(() {});
  }

  Future<void> _changeProjectsPath() async {
    String? result = await FilePicker.getDirectoryPath();
    if (result != null) {
      await ProjectManager().setProjectsDirPath(result);
      _refresh();
    }
  }

  String _formatDuration(double sec) {
    int m = sec ~/ 60;
    int s = (sec % 60).toInt();
    return "${m}m ${s}s";
  }

  String _getFileSize(String? path) {
    if (path == null || path.isEmpty) return "Unknown";
    try {
      int bytes = 0;
      if (FileSystemEntity.isDirectorySync(path)) {
        final dir = Directory(path);
        if (dir.existsSync()) {
          for (var entity in dir.listSync(recursive: true)) {
            if (entity is File) {
              bytes += entity.lengthSync();
            }
          }
        }
      } else {
        final file = File(path);
        if (file.existsSync()) {
          bytes = file.lengthSync();
        }
      }

      if (bytes == 0) return "Unknown";

      if (bytes < 1024 * 1024) {
        return "${(bytes / 1024).toStringAsFixed(1)} KB";
      } else if (bytes < 1024 * 1024 * 1024) {
        return "${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB";
      } else {
        return "${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB";
      }
    } catch (_) {}
    return "Unknown";
  }

  String _getTimeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inDays > 1) return "${diff.inDays} days ago";
    if (diff.inDays == 1) return "Yesterday";
    if (diff.inHours > 1) return "${diff.inHours} hours ago";
    if (diff.inHours == 1) return "1 hour ago";
    if (diff.inMinutes > 1) return "${diff.inMinutes} minutes ago";
    return "Just now";
  }

  String _getProjectDuration(Project project) {
    if (project.durationSec > 0) {
      return _formatDuration(project.durationSec);
    }

    if (project.type == ProjectType.longVideo && project.analysisData != null) {
      double calculatedDuration = 0.0;
      final parsed = project.analysisData;
      if (parsed is Map && parsed.containsKey('segments')) {
        for (var item in parsed['segments']) {
          if (item is Map && item['action'] == 'keep') {
            double start = (item['start'] as num).toDouble();
            double end = (item['end'] as num).toDouble();
            calculatedDuration += (end - start);
          }
        }
        if (calculatedDuration > 0) {
          return _formatDuration(calculatedDuration);
        }
      }
    } else if (project.type == ProjectType.shorts) {
      return _formatDuration(60.0);
    }

    return 'Unknown';
  }

  @override
  Widget build(BuildContext context) {
    final allProjects = ProjectManager().getProjects();
    final projects = allProjects.where((p) => p.isDeleted == _showTrash).toList();

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _showTrash ? "🗑️ Trash Bin" : "📂 Project Workspace",
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _changeProjectsPath,
                      icon: const Icon(Icons.folder_special),
                      label: const Text("Change Location"),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: () {
                        setState(() {
                          _showTrash = !_showTrash;
                        });
                      },
                      icon: Icon(_showTrash ? Icons.arrow_back : Icons.delete_outline),
                      label: Text(_showTrash ? "Back to Projects" : "Trash"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _showTrash ? Colors.grey[800] : Colors.redAccent.withOpacity(0.2),
                        foregroundColor: _showTrash ? Colors.white : Colors.redAccent,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              "Storage Directory: ${ProjectManager().projectsDirPath}",
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 24),
            if (projects.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(48.0),
                  child: Text(
                    _showTrash
                        ? "Trash bin is empty."
                        : "No projects saved yet. Create your first video in Shorts Generator or Smart Long Editor.",
                    style: const TextStyle(color: Colors.white54, fontSize: 16),
                  ),
                ),
              )
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 400,
                  childAspectRatio: 1.1,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                ),
                itemCount: projects.length,
                itemBuilder: (context, index) {
                  final project = projects[index];
                  final isShort = project.type == ProjectType.shorts;

                  return Card(
                    elevation: 4,
                    color: Theme.of(context).colorScheme.surface,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                isShort ? Icons.flash_on : Icons.movie,
                                color: isShort ? Colors.orangeAccent : Colors.blueAccent,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  project.name,
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const Divider(),
                          Expanded(
                            child: SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "Format: ${isShort ? 'Shorts (9:16)' : 'Long Video'}",
                                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    "Created: ${_getTimeAgo(project.createdAt)}",
                                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    "Runtime: ${_getProjectDuration(project)}",
                                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    "Source Size: ${_getFileSize(project.videoPath)}",
                                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                                  ),
                                  if (project.state == ProjectState.rendered && project.outputDir != null) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      "Exported Size: ${_getFileSize(project.outputDir)}",
                                      style: const TextStyle(color: Colors.greenAccent, fontSize: 13, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              if (_showTrash) ...[
                                IconButton(
                                  icon: const Icon(Icons.restore, color: Colors.greenAccent),
                                  tooltip: "Restore Project",
                                  onPressed: () {
                                    ProjectManager().restoreProject(project);
                                    _refresh();
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_forever, color: Colors.redAccent),
                                  tooltip: "Delete Permanently",
                                  onPressed: () {
                                    ProjectManager().deletePermanently(project);
                                    _refresh();
                                  },
                                ),
                              ] else ...[
                                ElevatedButton.icon(
                                  icon: const Icon(Icons.edit, size: 16),
                                  label: const Text("Edit"),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Theme.of(context).colorScheme.primary,
                                    foregroundColor: Colors.white,
                                  ),
                                  onPressed: () {
                                    widget.onEditProject(project);
                                  },
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.redAccent),
                                  tooltip: "Move to Trash",
                                  onPressed: () {
                                    ProjectManager().moveToTrash(project);
                                    _refresh();
                                  },
                                ),
                              ]
                            ],
                          )
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
