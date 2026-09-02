enum ApprovalStatus { pending, approved, rejected }

class ApprovalRequest {
  final String id;
  final String tool;
  final String command;
  final String description;
  ApprovalStatus status;

  ApprovalRequest({
    required this.id,
    required this.tool,
    required this.command,
    required this.description,
    this.status = ApprovalStatus.pending,
  });

  factory ApprovalRequest.fromJson(Map<String, dynamic> json) {
    return ApprovalRequest(
      id: json['id']?.toString() ?? '',
      tool: json['tool']?.toString() ?? 'Terminal Command',
      command: json['command']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      status: _parseStatus(json['status']),
    );
  }

  static ApprovalStatus _parseStatus(dynamic raw) {
    if (raw == 'approved') return ApprovalStatus.approved;
    if (raw == 'rejected') return ApprovalStatus.rejected;
    return ApprovalStatus.pending;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'tool': tool,
      'command': command,
      'description': description,
      'status': status.name,
    };
  }
}

class CodeDiffArtifact {
  final String filePath;
  final String diffContent;
  final int additions;
  final int deletions;

  CodeDiffArtifact({
    required this.filePath,
    required this.diffContent,
    this.additions = 0,
    this.deletions = 0,
  });

  factory CodeDiffArtifact.fromJson(Map<String, dynamic> json) {
    final diff = json['diff']?.toString() ?? '';
    int adds = 0;
    int dels = 0;
    for (final line in diff.split('\n')) {
      if (line.startsWith('+') && !line.startsWith('+++')) adds++;
      if (line.startsWith('-') && !line.startsWith('---')) dels++;
    }

    return CodeDiffArtifact(
      filePath: json['file_path']?.toString() ?? 'modified_file',
      diffContent: diff,
      additions: json['additions'] is int ? json['additions'] : adds,
      deletions: json['deletions'] is int ? json['deletions'] : dels,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'file_path': filePath,
      'diff': diffContent,
      'additions': additions,
      'deletions': deletions,
    };
  }
}
