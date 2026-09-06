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
          ? (DateTime.tryParse(json['timestamp'].toString())?.toLocal() ?? DateTime.now())
          : (json['created_at'] != null
              ? (DateTime.tryParse(json['created_at'].toString())?.toLocal() ?? DateTime.now())
              : DateTime.now()),
    );
  }

  String get formattedTime {
    final local = timestamp.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '$hour:$min';
  }

  String get timeAgo => Conversation.formatTimeAgo(timestamp);

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
  final DateTime? updatedAt;
  final ConversationSource source;
  final String? engine;

  Conversation({
    required this.id,
    required this.projectId,
    this.workspacePath,
    required this.title,
    required this.messages,
    DateTime? createdAt,
    this.updatedAt,
    this.source = ConversationSource.daemon,
    this.engine,
  }) : createdAt = createdAt ?? DateTime.now();

  bool get isDaemon => source == ConversationSource.daemon;
  bool get isDesktopIde => source == ConversationSource.desktopIde;

  String get sourceLabel => isDaemon ? 'Antigravity 2.0' : 'Desktop IDE';

  DateTime get lastMessageTime {
    if (messages.isNotEmpty) {
      return messages.last.timestamp;
    }
    return updatedAt ?? createdAt;
  }

  String get timeAgo => formatTimeAgo(lastMessageTime);

  String get lastMessageSnippet {
    if (messages.isEmpty) return 'No messages yet';
    final content = messages.last.content.replaceAll('\n', ' ').trim();
    if (content.isEmpty) return 'No messages yet';
    return content;
  }

  static DateTime? _parseDateTime(dynamic val) {
    if (val == null) return null;
    final dt = DateTime.tryParse(val.toString());
    return dt?.toLocal();
  }

  static String formatTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime.toLocal());

    if (difference.isNegative || difference.inSeconds < 60) {
      return 'just now';
    } else if (difference.inMinutes < 60) {
      final mins = difference.inMinutes;
      return mins == 1 ? '1 min ago' : '$mins mins ago';
    } else if (difference.inHours < 24) {
      final hours = difference.inHours;
      return hours == 1 ? '1 hour ago' : '$hours hours ago';
    } else if (difference.inDays == 1) {
      return 'yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else if (difference.inDays < 30) {
      final weeks = (difference.inDays / 7).floor();
      return weeks <= 1 ? '1 week ago' : '$weeks weeks ago';
    } else if (difference.inDays < 365) {
      final months = (difference.inDays / 30).floor();
      return months <= 1 ? '1 month ago' : '$months months ago';
    } else {
      final years = (difference.inDays / 365).floor();
      return years <= 1 ? '1 year ago' : '$years years ago';
    }
  }

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
      createdAt: _parseDateTime(json['created_at']) ?? DateTime.now(),
      updatedAt: _parseDateTime(json['updated_at']) ??
          _parseDateTime(json['last_message_at']),
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
      if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
      'source': source == ConversationSource.desktopIde ? 'desktop_ide' : 'daemon',
      'engine': engine ?? sourceLabel,
    };
  }
}
