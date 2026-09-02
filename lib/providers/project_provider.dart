import 'package:flutter/material.dart';
import '../core/network/bridge_client.dart';
import '../models/project.dart';

class ProjectProvider extends ChangeNotifier {
  final BridgeClient bridge;

  List<Project> projects = [];
  Project? selectedProject;
  RemoteDirectory? currentBrowsedDir;
  bool isLoading = false;
  bool isCreating = false;
  String? errorMessage;

  ProjectProvider({required this.bridge}) {
    bridge.events.listen(_handleEvents);
    bridge.statusStream.listen((status) {
      if (status == BridgeStatus.connected) {
        fetchProjects();
      }
    });
  }

  void _handleEvents(Map<String, dynamic> event) {
    switch (event['event']) {
      case 'projects_list':
        final rawList = event['projects'] as List<dynamic>? ?? [];
        projects = rawList
            .map((p) => Project.fromJson(Map<String, dynamic>.from(p)))
            .toList();

        if (projects.isNotEmpty) {
          if (selectedProject == null) {
            selectedProject = projects.first;
          } else {
            // Keep selected project or refresh it
            final match = projects.where((p) => p.id == selectedProject!.id);
            if (match.isNotEmpty) {
              selectedProject = match.first;
            } else {
              selectedProject = projects.first;
            }
          }
        }
        isLoading = false;
        notifyListeners();
        break;

      case 'project_created':
        if (event['project'] != null) {
          final newProj = Project.fromJson(Map<String, dynamic>.from(event['project']));
          final exists = projects.any((p) => p.id == newProj.id);
          if (!exists) {
            projects.insert(0, newProj);
          }
          selectedProject = newProj;
        }
        isCreating = false;
        isLoading = false;
        notifyListeners();
        break;

      case 'dir_contents':
        currentBrowsedDir = RemoteDirectory.fromJson(event);
        isLoading = false;
        notifyListeners();
        break;

      case 'error':
        errorMessage = event['message']?.toString();
        isLoading = false;
        isCreating = false;
        notifyListeners();
        break;
    }
  }

  void fetchProjects() {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    bridge.send('list_projects', {});
  }

  void selectProject(Project project) {
    selectedProject = project;
    notifyListeners();
  }

  void selectProjectById(String projectId) {
    final match = projects.where((p) => p.id == projectId);
    if (match.isNotEmpty) {
      selectedProject = match.first;
      notifyListeners();
    }
  }

  void browseDirectory(String path) {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    bridge.send('browse_dir', {'path': path});
  }

  void createNewProject(String name, String rootPath) {
    isCreating = true;
    errorMessage = null;
    notifyListeners();
    bridge.send('create_project', {
      'name': name.trim(),
      'root_path': rootPath.trim(),
    });
  }
}
