class DaemonStatusInfo {
  final String status;
  final int uptimeSeconds;
  final int pid;
  final String platform;
  final String instanceType; // 'headless_daemon' | 'desktop_editor'
  final String cliHostname;
  final String desktopHostname;
  final String updateInterval; // 'daily', 'weekly', 'disabled'
  final bool hasCliNameOverride;
  final String configFilePath;
  final String authAccount;
  final bool isAuthenticated;
  final List<String> recentLogs;
  final int activePort;
  final int discoveryPort;

  DaemonStatusInfo({
    required this.status,
    required this.uptimeSeconds,
    required this.pid,
    required this.platform,
    required this.instanceType,
    required this.cliHostname,
    required this.desktopHostname,
    required this.updateInterval,
    required this.hasCliNameOverride,
    required this.configFilePath,
    required this.authAccount,
    required this.isAuthenticated,
    required this.recentLogs,
    this.activePort = 7800,
    this.discoveryPort = 7801,
  });

  factory DaemonStatusInfo.fromJson(Map<String, dynamic> json) {
    return DaemonStatusInfo(
      status: json['status']?.toString() ?? 'online',
      uptimeSeconds: (json['uptime_seconds'] as num?)?.toInt() ?? 0,
      pid: (json['pid'] as num?)?.toInt() ?? 0,
      platform: json['platform']?.toString() ?? 'Windows',
      instanceType: json['instance_type']?.toString() ?? 'headless_daemon',
      cliHostname: json['cli_remote_control_hostname']?.toString() ??
          json['cli_hostname']?.toString() ??
          'Workstation-Daemon',
      desktopHostname: json['remote_control_hostname']?.toString() ??
          json['desktop_hostname']?.toString() ??
          'Workstation-Desktop',
      updateInterval: json['update_interval']?.toString() ?? 'daily',
      hasCliNameOverride: json['has_cli_name_override'] == true,
      configFilePath: json['config_file_path']?.toString() ?? '~/.gemini/config/config.json',
      authAccount: json['auth_account']?.toString() ?? 'Unknown Account',
      isAuthenticated: json['is_authenticated'] == true,
      recentLogs: (json['recent_logs'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      activePort: (json['port'] as num?)?.toInt() ?? 7800,
      discoveryPort: (json['discovery_port'] as num?)?.toInt() ?? 7801,
    );
  }

  String get formattedUptime {
    final d = Duration(seconds: uptimeSeconds);
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    if (hours > 0) {
      return '${hours}h ${minutes}m ${seconds}s';
    }
    return '${minutes}m ${seconds}s';
  }
}

class DiagnosticCheck {
  final String id;
  final String category;
  final String title;
  final bool passed;
  final String detail;
  final String? recommendedAction;

  DiagnosticCheck({
    required this.id,
    required this.category,
    required this.title,
    required this.passed,
    required this.detail,
    this.recommendedAction,
  });

  factory DiagnosticCheck.fromJson(Map<String, dynamic> json) {
    return DiagnosticCheck(
      id: json['id']?.toString() ?? '',
      category: json['category']?.toString() ?? 'General',
      title: json['title']?.toString() ?? '',
      passed: json['passed'] == true,
      detail: json['detail']?.toString() ?? '',
      recommendedAction: json['recommended_action']?.toString(),
    );
  }
}

class ServiceLifecycleEntry {
  final String osName;
  final String bootStartup;
  final String logoutPersistence;
  final String crashRecovery;
  final bool isCurrentOs;

  const ServiceLifecycleEntry({
    required this.osName,
    required this.bootStartup,
    required this.logoutPersistence,
    required this.crashRecovery,
    this.isCurrentOs = false,
  });

  static List<ServiceLifecycleEntry> getMatrix(String currentPlatform) {
    final lower = currentPlatform.toLowerCase();
    return [
      ServiceLifecycleEntry(
        osName: 'Linux',
        bootStartup: 'Yes (systemd service at boot)',
        logoutPersistence: 'Yes (runs in background daemon session)',
        crashRecovery: 'Yes (systemd Restart=always auto-recovers)',
        isCurrentOs: lower.contains('linux'),
      ),
      ServiceLifecycleEntry(
        osName: 'macOS',
        bootStartup: 'No (starts upon user login via launchd)',
        logoutPersistence: 'No (resumes at next user login)',
        crashRecovery: 'Yes (launchd KeepAlive auto-recovers)',
        isCurrentOs: lower.contains('mac') || lower.contains('darwin'),
      ),
      ServiceLifecycleEntry(
        osName: 'Windows',
        bootStartup: 'Yes (Windows Service starts at system boot)',
        logoutPersistence: 'Yes (keeps running after user logout)',
        crashRecovery: 'Recovers on next reboot, update, or restart',
        isCurrentOs: lower.contains('win'),
      ),
    ];
  }
}
