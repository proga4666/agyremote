class QuickCommand {
  final String id;
  final String title;
  final String description;
  final String script;
  final String category; // 'git' | 'flutter' | 'adb' | 'custom'
  final bool requiresCommitMessage;
  final bool isBuiltIn;
  final String iconName;
  final String colorTag; // 'green' | 'blue' | 'amber' | 'purple' | 'red'

  QuickCommand({
    required this.id,
    required this.title,
    required this.description,
    required this.script,
    this.category = 'custom',
    this.requiresCommitMessage = false,
    this.isBuiltIn = false,
    this.iconName = 'terminal',
    this.colorTag = 'blue',
  });

  factory QuickCommand.fromJson(Map<String, dynamic> json) {
    return QuickCommand(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Quick Command',
      description: json['description']?.toString() ?? '',
      script: json['script']?.toString() ?? '',
      category: json['category']?.toString() ?? 'custom',
      requiresCommitMessage: json['requires_commit_message'] == true,
      isBuiltIn: json['is_built_in'] == true,
      iconName: json['icon_name']?.toString() ?? 'terminal',
      colorTag: json['color_tag']?.toString() ?? 'blue',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'script': script,
      'category': category,
      'requires_commit_message': requiresCommitMessage,
      'is_built_in': isBuiltIn,
      'icon_name': iconName,
      'color_tag': colorTag,
    };
  }

  static List<QuickCommand> get defaultBuiltInCommands => [
        QuickCommand(
          id: 'cmd_git_push',
          title: 'Git Push',
          description: 'Stage all workspace changes, commit, and push to remote origin.',
          script: 'git add . && git commit -m "{COMMIT_MESSAGE}" && git push',
          category: 'git',
          requiresCommitMessage: true,
          isBuiltIn: true,
          iconName: 'upload_rounded',
          colorTag: 'green',
        ),
        QuickCommand(
          id: 'cmd_build_apk_push',
          title: 'Build APK & Wireless Install & Push',
          description:
              'Build Flutter APK, install onto phone via wireless debug (ADB), and Git commit & push.',
          script:
              'flutter build apk --debug && adb -s {DEVICE_TARGET} install -r build/app/outputs/flutter-apk/app-debug.apk && git add . && git commit -m "{COMMIT_MESSAGE}" && git push',
          category: 'adb',
          requiresCommitMessage: true,
          isBuiltIn: true,
          iconName: 'install_mobile_rounded',
          colorTag: 'purple',
        ),
        QuickCommand(
          id: 'cmd_pub_get',
          title: 'Flutter Pub Get',
          description: 'Resolve and download all Dart / Flutter dependencies in pubspec.yaml.',
          script: 'flutter pub get',
          category: 'flutter',
          requiresCommitMessage: false,
          isBuiltIn: true,
          iconName: 'download_for_offline_rounded',
          colorTag: 'blue',
        ),
        QuickCommand(
          id: 'cmd_flutter_test_analyze',
          title: 'Flutter Analyze & Test',
          description: 'Run static Dart analysis and execute the complete automated test suite.',
          script: 'flutter analyze && flutter test',
          category: 'flutter',
          requiresCommitMessage: false,
          isBuiltIn: true,
          iconName: 'checklist_rounded',
          colorTag: 'amber',
        ),
        QuickCommand(
          id: 'cmd_flutter_clean',
          title: 'Flutter Clean & Fetch',
          description: 'Delete ephemeral build caches and reinstall dependencies.',
          script: 'flutter clean && flutter pub get',
          category: 'flutter',
          requiresCommitMessage: false,
          isBuiltIn: true,
          iconName: 'cleaning_services_rounded',
          colorTag: 'blue',
        ),
        QuickCommand(
          id: 'cmd_git_sync',
          title: 'Git Pull & Sync',
          description: 'Stash or pull latest changes from remote branch.',
          script: 'git pull --rebase',
          category: 'git',
          requiresCommitMessage: false,
          isBuiltIn: true,
          iconName: 'sync_rounded',
          colorTag: 'green',
        ),
      ];
}

class AdbDevice {
  final String serial;
  final String status; // 'device' | 'offline' | 'unauthorized'
  final String model;
  final String product;
  final bool isWireless;

  AdbDevice({
    required this.serial,
    required this.status,
    this.model = '',
    this.product = '',
    bool? isWireless,
  }) : isWireless = isWireless ?? serial.contains(':');

  bool get isConnected => status.toLowerCase() == 'device';

  String get displayName {
    if (model.isNotEmpty) return model.replaceAll('_', ' ');
    if (isWireless) return 'Wireless Device ($serial)';
    return serial;
  }

  factory AdbDevice.fromJson(Map<String, dynamic> json) {
    return AdbDevice(
      serial: json['serial']?.toString() ?? '',
      status: json['status']?.toString() ?? 'unknown',
      model: json['model']?.toString() ?? '',
      product: json['product']?.toString() ?? '',
      isWireless: json['is_wireless'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'serial': serial,
      'status': status,
      'model': model,
      'product': product,
      'is_wireless': isWireless,
    };
  }
}

enum ExecutionStatus { idle, running, success, failed }

class QuickCommandExecution {
  final String commandId;
  final String title;
  final String script;
  ExecutionStatus status;
  final List<String> logs;
  int? exitCode;
  DateTime? startedAt;
  DateTime? completedAt;

  QuickCommandExecution({
    required this.commandId,
    required this.title,
    required this.script,
    this.status = ExecutionStatus.idle,
    List<String>? logs,
    this.exitCode,
    this.startedAt,
    this.completedAt,
  }) : logs = logs ?? [];

  Duration? get duration {
    if (startedAt == null) return null;
    final end = completedAt ?? DateTime.now();
    return end.difference(startedAt!);
  }

  String get formattedDuration {
    final d = duration;
    if (d == null) return '0s';
    if (d.inMinutes > 0) {
      return '${d.inMinutes}m ${d.inSeconds % 60}s';
    }
    return '${d.inSeconds}.${(d.inMilliseconds % 1000) ~/ 100}s';
  }
}
