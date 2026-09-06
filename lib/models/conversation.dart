import 'approval.dart';

class ConversationMessage {
  final String id;
  final String sender; // 'user' | 'agent' | 'thought' | 'system'
  String content;
  final ApprovalRequest? approval;
  final CodeDiffArtifact? diffArtifact;
  final List<String>? images; // Base64 or local paths
  final DateTime timestamp;

  ConversationMessage({
    required this.id,
    required this.sender,
    required this.content,
    this.approval,
    this.diffArtifact,
    this.images,
    required this.timestamp,
  });

  factory ConversationMessage.fromJson(Map<String, dynamic> json) {
    return ConversationMessage(
      id: json['id']?.toString() ?? '',
      sender: json['sender']?.toString() ?? 'agent',
      content: json['content']?.toString() ?? '',
      approval: json['approval'] != null
          ? ApprovalRequest.fromJson(Map<String, dynamic>.from(json['approval']))
          : null,
      diffArtifact: json['diff_artifact'] != null
          ? CodeDiffArtifact.fromJson(Map<String, dynamic>.from(json['diff_artifact']))
          : null,
      images: (json['images'] as List<dynamic>?)?.map((e) => e.toString()).toList(),
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sender': sender,
      'content': content,
      if (approval != null) 'approval': approval!.toJson(),
      if (diffArtifact != null) 'diff_artifact': diffArtifact!.toJson(),
      if (images != null && images!.isNotEmpty) 'images': images,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}

enum ConversationSource {
  daemon, // Antigravity 2.0 Headless Daemon
  desktopIde, // Antigravity Desktop IDE
}

class Conversation {
  final String id;
  final String projectId;
  final String? workspacePath;
  String title;
  final List<ConversationMessage> messages;
  final DateTime createdAt;
  final ConversationSource source;
  final String? engine;

  Conversation({
    required this.id,
    required this.projectId,
    this.workspacePath,
    required this.title,
    required this.messages,
    DateTime? createdAt,
    this.source = ConversationSource.daemon,
    this.engine,
  }) : createdAt = createdAt ?? DateTime.now();

  bool get isDaemon => source == ConversationSource.daemon;
  bool get isDesktopIde => source == ConversationSource.desktopIde;

  String get sourceLabel => isDaemon ? 'Antigravity 2.0' : 'Desktop IDE';

  factory Conversation.fromJson(Map<String, dynamic> json) {
    final rawSource = json['source']?.toString().toLowerCase() ?? '';
    final isIde = rawSource == 'desktop_ide' ||
        rawSource == 'ide' ||
        (json['is_pc_synced'] == true && json['engine'] == 'Desktop IDE');

    return Conversation(
      id: json['id']?.toString() ?? '',
      projectId: json['project_id']?.toString() ?? '',
      workspacePath: json['workspace_path']?.toString(),
      title: json['title']?.toString() ?? 'Untitled Conversation',
      messages: (json['messages'] as List<dynamic>?)
              ?.map((m) => ConversationMessage.fromJson(Map<String, dynamic>.from(m)))
              .toList() ??
          [],
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      source: isIde ? ConversationSource.desktopIde : ConversationSource.daemon,
      engine: json['engine']?.toString() ?? (isIde ? 'Desktop IDE' : 'Antigravity 2.0'),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'project_id': projectId,
      if (workspacePath != null) 'workspace_path': workspacePath,
      'title': title,
      'messages': messages.map((m) => m.toJson()).toList(),
      'created_at': createdAt.toIso8601String(),
      'source': source == ConversationSource.desktopIde ? 'desktop_ide' : 'daemon',
      'engine': engine ?? sourceLabel,
    };
  }
}
