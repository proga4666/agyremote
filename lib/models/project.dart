class Project {
  final String id;
  final String name;
  final String path;
  final List<String> conversationIds;

  Project({
    required this.id,
    required this.name,
    required this.path,
    this.conversationIds = const [],
  });

  factory Project.fromJson(Map<String, dynamic> json) {
    return Project(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Untitled Project',
      path: json['path']?.toString() ?? '',
      conversationIds: (json['conversation_ids'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'path': path,
      'conversation_ids': conversationIds,
    };
  }
}

class RemoteDirectory {
  final String currentPath;
  final String parentPath;
  final List<String> folders;
  final List<String> files;

  RemoteDirectory({
    required this.currentPath,
    required this.parentPath,
    this.folders = const [],
    this.files = const [],
  });

  factory RemoteDirectory.fromJson(Map<String, dynamic> json) {
    return RemoteDirectory(
      currentPath: json['current_path']?.toString() ?? '/',
      parentPath: json['parent_path']?.toString() ?? '/',
      folders: (json['folders'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      files: (json['files'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }
}
