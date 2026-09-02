import 'approval.dart';

class ConversationMessage {
  final String id;
  final String sender; // 'user' | 'agent' | 'thought' | 'system'
  String content;
  final ApprovalRequest? approval;
  final CodeDiffArtifact? diffArtifact;
  final DateTime timestamp;

  ConversationMessage({
    required this.id,
    required this.sender,
    required this.content,
    this.approval,
    this.diffArtifact,
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
      'timestamp': timestamp.toIso8601String(),
    };
  }
}

class Conversation {
  final String id;
  final String projectId;
  final String? workspacePath;
  String title;
  final List<ConversationMessage> messages;
  final DateTime createdAt;

  Conversation({
    required this.id,
    required this.projectId,
    this.workspacePath,
    required this.title,
    required this.messages,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory Conversation.fromJson(Map<String, dynamic> json) {
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
    };
  }
}
