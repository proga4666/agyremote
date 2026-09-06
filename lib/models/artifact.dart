import 'package:flutter/material.dart';

enum ArtifactType {
  plan,
  walkthrough,
  task,
  diff,
  markdown,
  image,
  log,
  other,
}

class BrainArtifact {
  final String id;
  final String conversationId;
  final String name;
  final String filePath;
  final ArtifactType type;
  final DateTime lastModified;
  final int sizeBytes;
  final bool requestFeedback;
  final String? summary;
  final String? content;

  BrainArtifact({
    required this.id,
    required this.conversationId,
    required this.name,
    required this.filePath,
    required this.type,
    required this.lastModified,
    this.sizeBytes = 0,
    this.requestFeedback = false,
    this.summary,
    this.content,
  });

  factory BrainArtifact.fromJson(Map<String, dynamic> json) {
    final name = json['name']?.toString() ?? 'artifact.md';
    return BrainArtifact(
      id: json['id']?.toString() ?? name,
      conversationId: json['conversation_id']?.toString() ?? '',
      name: name,
      filePath: json['file_path']?.toString() ?? name,
      type: _resolveType(name, json['type']?.toString()),
      lastModified: json['last_modified'] != null
          ? DateTime.tryParse(json['last_modified'].toString()) ?? DateTime.now()
          : DateTime.now(),
      sizeBytes: (json['size_bytes'] as num?)?.toInt() ?? 0,
      requestFeedback: json['request_feedback'] == true,
      summary: json['summary']?.toString(),
      content: json['content']?.toString(),
    );
  }

  static ArtifactType _resolveType(String fileName, String? typeHint) {
    if (typeHint != null && typeHint.isNotEmpty) {
      for (final t in ArtifactType.values) {
        if (t.name.toLowerCase() == typeHint.toLowerCase()) return t;
      }
    }
    final lower = fileName.toLowerCase();
    if (lower.contains('implementation_plan') || lower.contains('plan')) {
      return ArtifactType.plan;
    }
    if (lower.contains('walkthrough')) {
      return ArtifactType.walkthrough;
    }
    if (lower.contains('task')) {
      return ArtifactType.task;
    }
    if (lower.endsWith('.diff') || lower.endsWith('.patch')) {
      return ArtifactType.diff;
    }
    if (lower.endsWith('.md')) {
      return ArtifactType.markdown;
    }
    if (lower.endsWith('.png') || lower.endsWith('.jpg') || lower.endsWith('.webp')) {
      return ArtifactType.image;
    }
    if (lower.endsWith('.log') || lower.endsWith('.txt')) {
      return ArtifactType.log;
    }
    return ArtifactType.other;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'conversation_id': conversationId,
      'name': name,
      'file_path': filePath,
      'type': type.name,
      'last_modified': lastModified.toIso8601String(),
      'size_bytes': sizeBytes,
      'request_feedback': requestFeedback,
      if (summary != null) 'summary': summary,
      if (content != null) 'content': content,
    };
  }

  BrainArtifact copyWith({String? content}) {
    return BrainArtifact(
      id: id,
      conversationId: conversationId,
      name: name,
      filePath: filePath,
      type: type,
      lastModified: lastModified,
      sizeBytes: sizeBytes,
      requestFeedback: requestFeedback,
      summary: summary,
      content: content ?? this.content,
    );
  }

  IconData get icon {
    switch (type) {
      case ArtifactType.plan:
        return Icons.architecture_rounded;
      case ArtifactType.walkthrough:
        return Icons.checklist_rounded;
      case ArtifactType.task:
        return Icons.assignment_outlined;
      case ArtifactType.diff:
        return Icons.difference_outlined;
      case ArtifactType.markdown:
        return Icons.description_outlined;
      case ArtifactType.image:
        return Icons.image_outlined;
      case ArtifactType.log:
        return Icons.terminal_outlined;
      case ArtifactType.other:
        return Icons.insert_drive_file_outlined;
    }
  }

  Color get color {
    switch (type) {
      case ArtifactType.plan:
        return const Color(0xFF4285F4); // Google Blue
      case ArtifactType.walkthrough:
        return const Color(0xFF0F9D58); // Google Green
      case ArtifactType.task:
        return const Color(0xFFF4B400); // Google Amber
      case ArtifactType.diff:
        return const Color(0xFFAB47BC); // Purple
      case ArtifactType.markdown:
        return const Color(0xFF26A69A); // Teal
      case ArtifactType.image:
        return const Color(0xFFFF7043); // Orange
      case ArtifactType.log:
        return const Color(0xFF90A4AE); // Grey
      case ArtifactType.other:
        return const Color(0xFF78909C);
    }
  }
}
