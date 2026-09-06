import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../core/theme/app_theme.dart';
import '../models/daemon_status.dart';
import '../providers/connection_provider.dart';

class DaemonDashboardScreen extends StatefulWidget {
  const DaemonDashboardScreen({super.key});

  @override
  State<DaemonDashboardScreen> createState() => _DaemonDashboardScreenState();
}

class _DaemonDashboardScreenState extends State<DaemonDashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ConnectionProvider>().fetchDaemonStatus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final conn = context.watch<ConnectionProvider>();
    final status = conn.daemonStatus;

    return Scaffold(
      backgroundColor: AntigravityTheme.background,
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.dns_rounded, color: AntigravityTheme.googleBlue, size: 20),
            SizedBox(width: 8),
            Text('Daemon Service Manager', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            tooltip: 'Refresh Status & Logs',
            onPressed: () => conn.fetchDaemonStatus(),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Notice banner if any
            if (conn.authNotice != null) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AntigravityTheme.googleBlue.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AntigravityTheme.googleBlue),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: AntigravityTheme.googleBlue, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        conn.authNotice!,
                        style: const TextStyle(fontSize: 12, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // 1. Live Daemon Service Status Card
            _buildServiceStatusCard(context, conn, status),
            const SizedBox(height: 16),

            // 2. Machine Naming & Host Switcher Configuration
            _buildMachineNamingSection(context, conn, status),
            const SizedBox(height: 16),

            // 3. Google Sign-In & Authentication Card
            _buildAuthCard(context, conn, status),
            const SizedBox(height: 16),

            // 4. Remote Troubleshooting Diagnostics Suite
            _buildDiagnosticsCard(context, conn),
            const SizedBox(height: 16),

            // 5. Service Lifecycle Matrix
            _buildLifecycleMatrixCard(status?.platform ?? 'Windows'),
            const SizedBox(height: 16),

            // 6. Live Activity Logs Terminal
            _buildActivityLogsCard(status),
            const SizedBox(height: 16),

            // 7. Installation Commands Generator
            _buildInstallationCommandsCard(context, status),
          ],
        ),
      ),
    );
  }

  Widget _buildServiceStatusCard(
    BuildContext context,
    ConnectionProvider conn,
    DaemonStatusInfo? status,
  ) {
    final isOnline = conn.isConnected;
    final isRestarting = conn.isRestarting;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AntigravityTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AntigravityTheme.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isRestarting
                      ? AntigravityTheme.googleAmber.withValues(alpha: 0.15)
                      : (isOnline ? AntigravityTheme.googleGreen.withValues(alpha: 0.15) : AntigravityTheme.googleRed.withValues(alpha: 0.15)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  isRestarting
                      ? Icons.sync
                      : (isOnline ? Icons.check_circle_outline : Icons.error_outline),
                  color: isRestarting
                      ? AntigravityTheme.googleAmber
                      : (isOnline ? AntigravityTheme.googleGreen : AntigravityTheme.googleRed),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          isRestarting
                              ? 'RESTARTING...'
                              : (isOnline ? 'SERVICE ACTIVE' : 'DISCONNECTED'),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                            color: isRestarting
                                ? AntigravityTheme.googleAmber
                                : (isOnline ? AntigravityTheme.googleGreen : AntigravityTheme.googleRed),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AntigravityTheme.googleBlue.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            status?.instanceType == 'headless_daemon' ? 'Headless Daemon' : 'Desktop Editor',
                            style: const TextStyle(fontSize: 10, color: AntigravityTheme.googleBlue, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Host: ${conn.hostAddress}:${conn.port} • Auto-Discovery: 7801',
                      style: const TextStyle(fontSize: 11, color: AntigravityTheme.textSecondary, fontFamily: 'monospace'),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AntigravityTheme.surfaceContainerHigh,
                  foregroundColor: isRestarting ? AntigravityTheme.googleAmber : Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  minimumSize: Size.zero,
                ),
                icon: Icon(Icons.restart_alt_rounded, size: 16, color: isRestarting ? AntigravityTheme.googleAmber : AntigravityTheme.googleBlue),
                label: Text(isRestarting ? 'Restarting...' : 'Restart', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                onPressed: isRestarting ? null : () => conn.restartDaemon(),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(color: AntigravityTheme.borderSubtle, height: 1),
          const SizedBox(height: 12),
          // Metadata grid
          Row(
            children: [
              _buildStatCell('Uptime', status?.formattedUptime ?? 'Unknown', Icons.timer_outlined),
              _buildStatCell('PID', status != null ? '${status.pid}' : '--', Icons.memory_outlined),
              _buildStatCell('Platform', status?.platform ?? 'Windows', Icons.desktop_windows_outlined),
              _buildStatCell('Updates', status?.updateInterval ?? 'daily', Icons.update_outlined),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCell(String label, String value, IconData icon) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: AntigravityTheme.textMuted),
              const SizedBox(width: 4),
              Text(label, style: const TextStyle(fontSize: 10, color: AntigravityTheme.textMuted)),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildMachineNamingSection(
    BuildContext context,
    ConnectionProvider conn,
    DaemonStatusInfo? status,
  ) {
    final hasOverride = status?.hasCliNameOverride == true;
    final cliHost = status?.cliHostname ?? 'Workstation-Daemon';
    final deskHost = status?.desktopHostname ?? 'Workstation-Desktop';
    final configPath = status?.configFilePath ?? r'%USERPROFILE%\.gemini\config\config.json';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AntigravityTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AntigravityTheme.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.badge_outlined, color: AntigravityTheme.googleBlue, size: 18),
              const SizedBox(width: 8),
              const Text(
                'MACHINE NAMING & CONFIGURATION',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.5, color: AntigravityTheme.textSecondary),
              ),
              const Spacer(),
              TextButton.icon(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                ),
                icon: const Icon(Icons.edit, size: 14, color: AntigravityTheme.googleBlue),
                label: const Text('Edit Names', style: TextStyle(fontSize: 11, color: AntigravityTheme.googleBlue, fontWeight: FontWeight.bold)),
                onPressed: () => _showEditNamesDialog(context, conn, cliHost, deskHost, status?.updateInterval ?? 'daily'),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Precedence Alert if --name flag used
          if (hasOverride) ...[
            Container(
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: AntigravityTheme.googleAmber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AntigravityTheme.googleAmber),
              ),
              child: Row(
                children: const [
                  Icon(Icons.warning_amber_rounded, color: AntigravityTheme.googleAmber, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Precedence Warning: Daemon was started with "--name" CLI flag. CLI parameter takes precedence and overwrites manual config file edits on restart.',
                      style: TextStyle(fontSize: 11, color: AntigravityTheme.googleAmber),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Name items
          _buildNameRow(
            label: 'Headless Daemon (cliRemoteControlHostname)',
            badge: 'Headless Service',
            badgeColor: AntigravityTheme.googleGreen,
            value: cliHost,
          ),
          const SizedBox(height: 8),
          _buildNameRow(
            label: 'Desktop IDE (remoteControlHostname)',
            badge: 'Desktop App',
            badgeColor: AntigravityTheme.googleBlue,
            value: deskHost,
          ),
          const SizedBox(height: 10),
          const Divider(color: AntigravityTheme.borderSubtle, height: 1),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.folder_open, size: 13, color: AntigravityTheme.textMuted),
              const SizedBox(width: 6),
              const Text('Settings File: ', style: TextStyle(fontSize: 11, color: AntigravityTheme.textMuted)),
              Expanded(
                child: Text(
                  configPath,
                  style: const TextStyle(fontSize: 11, color: AntigravityTheme.googleBlue, fontFamily: 'monospace'),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNameRow({
    required String label,
    required String badge,
    required Color badgeColor,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AntigravityTheme.surfaceContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AntigravityTheme.borderSubtle),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(label, style: const TextStyle(fontSize: 10, color: AntigravityTheme.textMuted)),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: badgeColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        badge,
                        style: TextStyle(fontSize: 9, color: badgeColor, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuthCard(
    BuildContext context,
    ConnectionProvider conn,
    DaemonStatusInfo? status,
  ) {
    final isAuth = status?.isAuthenticated ?? true;
    final account = status?.authAccount ?? 'shahadsirius369@gmail.com';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AntigravityTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AntigravityTheme.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_circle_outlined, color: AntigravityTheme.googleBlue, size: 18),
              const SizedBox(width: 8),
              const Text(
                'GOOGLE SIGN-IN & AUTHENTICATION',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.5, color: AntigravityTheme.textSecondary),
              ),
              const Spacer(),
              if (conn.isAuthRefreshing)
                const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AntigravityTheme.googleBlue))
              else
                TextButton(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                  ),
                  onPressed: () => conn.refreshAuth(),
                  child: const Text('Refresh Auth', style: TextStyle(fontSize: 11, color: AntigravityTheme.googleBlue, fontWeight: FontWeight.bold)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AntigravityTheme.surfaceContainer,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AntigravityTheme.borderSubtle),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: AntigravityTheme.googleBlue.withValues(alpha: 0.2),
                  child: const Icon(Icons.person, color: AntigravityTheme.googleBlue, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        account,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            isAuth ? Icons.check_circle : Icons.warning_amber_rounded,
                            size: 12,
                            color: isAuth ? AntigravityTheme.googleGreen : AntigravityTheme.googleAmber,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isAuth ? 'Persistent across reboots • Signed in' : 'Session token expired or missing',
                            style: TextStyle(
                              fontSize: 11,
                              color: isAuth ? AntigravityTheme.googleGreen : AntigravityTheme.googleAmber,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AntigravityTheme.border),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    minimumSize: Size.zero,
                  ),
                  onPressed: () => _showAuthCodeDialog(context, conn),
                  child: const Text('Enter Code', style: TextStyle(fontSize: 11, color: AntigravityTheme.googleBlue)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiagnosticsCard(BuildContext context, ConnectionProvider conn) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AntigravityTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AntigravityTheme.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.health_and_safety_outlined, color: AntigravityTheme.googleGreen, size: 18),
              const SizedBox(width: 8),
              const Text(
                'REMOTE TROUBLESHOOTING & DIAGNOSTICS',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.5, color: AntigravityTheme.textSecondary),
              ),
              const Spacer(),
              if (conn.isRunningDiagnostics)
                const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AntigravityTheme.googleGreen))
              else
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AntigravityTheme.googleGreen,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    minimumSize: Size.zero,
                  ),
                  icon: const Icon(Icons.play_arrow_rounded, size: 14),
                  label: const Text('Run Tests', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  onPressed: () => conn.runDiagnostics(),
                ),
            ],
          ),
          const SizedBox(height: 10),

          if (conn.diagnosticResults.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AntigravityTheme.surfaceContainer,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AntigravityTheme.borderSubtle),
              ),
              child: const Text(
                'Tap "Run Tests" to execute the 5-point automated health check (Google connectivity, OAuth validity, config integrity, port status, platform shell compliance).',
                style: TextStyle(fontSize: 11, color: AntigravityTheme.textMuted),
              ),
            )
          else
            Column(
              children: conn.diagnosticResults.map((check) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: check.passed
                        ? AntigravityTheme.surfaceContainer
                        : AntigravityTheme.googleRed.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: check.passed ? AntigravityTheme.borderSubtle : AntigravityTheme.googleRed,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        check.passed ? Icons.check_circle_rounded : Icons.cancel_rounded,
                        color: check.passed ? AntigravityTheme.googleGreen : AntigravityTheme.googleRed,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              check.title,
                              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              check.detail,
                              style: const TextStyle(fontSize: 11, color: AntigravityTheme.textSecondary),
                            ),
                            if (check.recommendedAction != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Action: ${check.recommendedAction!}',
                                style: const TextStyle(fontSize: 11, color: AntigravityTheme.googleAmber, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildLifecycleMatrixCard(String currentPlatform) {
    final matrix = ServiceLifecycleEntry.getMatrix(currentPlatform);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AntigravityTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AntigravityTheme.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.table_chart_outlined, color: AntigravityTheme.googleAmber, size: 18),
              SizedBox(width: 8),
              Text(
                'SERVICE LIFECYCLE MATRIX (OS BEHAVIOR)',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.5, color: AntigravityTheme.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...matrix.map((entry) {
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: entry.isCurrentOs
                    ? AntigravityTheme.googleBlue.withValues(alpha: 0.12)
                    : AntigravityTheme.surfaceContainer,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: entry.isCurrentOs ? AntigravityTheme.googleBlue : AntigravityTheme.borderSubtle,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        entry.osName,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: entry.isCurrentOs ? AntigravityTheme.googleBlue : Colors.white,
                        ),
                      ),
                      if (entry.isCurrentOs) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: AntigravityTheme.googleBlue,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('HOST OS', style: TextStyle(fontSize: 9, color: Colors.black, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  _buildMatrixSubRow('Boot Startup:', entry.bootStartup),
                  _buildMatrixSubRow('Logout Persistence:', entry.logoutPersistence),
                  _buildMatrixSubRow('Crash Recovery:', entry.crashRecovery),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildMatrixSubRow(String title, String val) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(title, style: const TextStyle(fontSize: 11, color: AntigravityTheme.textMuted)),
          ),
          Expanded(
            child: Text(val, style: const TextStyle(fontSize: 11, color: AntigravityTheme.textPrimary)),
          ),
        ],
      ),
    );
  }

  Widget _buildActivityLogsCard(DaemonStatusInfo? status) {
    final logs = status?.recentLogs ?? [];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AntigravityTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AntigravityTheme.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.terminal_rounded, color: AntigravityTheme.googleAmber, size: 18),
              SizedBox(width: 8),
              Text(
                'RECENT ACTIVITY LOGS (agy-daemon status)',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.5, color: AntigravityTheme.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            height: 140,
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF101214),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AntigravityTheme.borderSubtle),
            ),
            child: logs.isEmpty
                ? const Center(
                    child: Text('No activity logs recorded yet.', style: TextStyle(fontSize: 11, color: AntigravityTheme.textMuted)),
                  )
                : ListView.builder(
                    itemCount: logs.length,
                    itemBuilder: (ctx, i) {
                      return Text(
                        logs[i],
                        style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: AntigravityTheme.googleGreen, height: 1.4),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildInstallationCommandsCard(BuildContext context, DaemonStatusInfo? status) {
    const winCmd = 'curl -fsSL https://antigravity.google/cli/agy-daemon.cmd -o agy-daemon.cmd && agy-daemon.cmd install';
    const linuxCmd = 'curl -fsSL https://antigravity.google/cli/agy-daemon.sh | bash';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AntigravityTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AntigravityTheme.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.code_rounded, color: AntigravityTheme.googleBlue, size: 18),
              SizedBox(width: 8),
              Text(
                'INSTALLATION & SERVICE COMMANDS',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.5, color: AntigravityTheme.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildCommandSnippet('Windows (Run as Administrator in cmd.exe):', winCmd),
          const SizedBox(height: 8),
          _buildCommandSnippet('Linux / macOS Terminal:', linuxCmd),
        ],
      ),
    );
  }

  Widget _buildCommandSnippet(String label, String cmd) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AntigravityTheme.surfaceContainer,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AntigravityTheme.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 10.5, color: AntigravityTheme.textMuted)),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  cmd,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: AntigravityTheme.googleAmber),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy_rounded, size: 14, color: AntigravityTheme.googleBlue),
                tooltip: 'Copy Command',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: cmd));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Command copied to clipboard'), duration: Duration(seconds: 2)),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showEditNamesDialog(
    BuildContext context,
    ConnectionProvider conn,
    String initialCli,
    String initialDesk,
    String initialInterval,
  ) {
    final cliCtrl = TextEditingController(text: initialCli);
    final deskCtrl = TextEditingController(text: initialDesk);
    String selectedInterval = initialInterval;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Update Machine Names & Schedule', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Headless Daemon Instance Name:', style: TextStyle(fontSize: 11, color: AntigravityTheme.textMuted)),
                const SizedBox(height: 4),
                TextField(
                  controller: cliCtrl,
                  decoration: const InputDecoration(
                    hintText: 'e.g. aws-rising-ember-daemon',
                    prefixIcon: Icon(Icons.dns_rounded, size: 18),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('Desktop IDE Instance Name:', style: TextStyle(fontSize: 11, color: AntigravityTheme.textMuted)),
                const SizedBox(height: 4),
                TextField(
                  controller: deskCtrl,
                  decoration: const InputDecoration(
                    hintText: 'e.g. aws-rising-ember',
                    prefixIcon: Icon(Icons.laptop_chromebook, size: 18),
                  ),
                ),
                const SizedBox(height: 14),
                const Text('Automatic Update Schedule:', style: TextStyle(fontSize: 11, color: AntigravityTheme.textMuted)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: ['daily', 'weekly', 'disabled'].map((it) {
                    final isSel = selectedInterval == it;
                    return ChoiceChip(
                      label: Text(it.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isSel ? Colors.black : Colors.white)),
                      selected: isSel,
                      selectedColor: AntigravityTheme.googleBlue,
                      backgroundColor: AntigravityTheme.surfaceContainerHigh,
                      onSelected: (val) {
                        if (val) setDialogState(() => selectedInterval = it);
                      },
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel', style: TextStyle(color: AntigravityTheme.textSecondary)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AntigravityTheme.googleBlue,
                foregroundColor: Colors.black,
              ),
              onPressed: () {
                conn.updateHostnames(
                  cliHostname: cliCtrl.text.trim(),
                  desktopHostname: deskCtrl.text.trim(),
                  updateInterval: selectedInterval,
                );
                Navigator.pop(dialogCtx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Configuration saved to config.json. Applying restart...')),
                );
              },
              child: const Text('Save & Restart', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _showAuthCodeDialog(BuildContext context, ConnectionProvider conn) {
    final codeCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Enter Google Verification Code', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'If you ran the one-time sign-in flow in terminal or browser, paste the Google verification code below to store it in daemon credentials.',
              style: TextStyle(fontSize: 12, color: AntigravityTheme.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: codeCtrl,
              decoration: const InputDecoration(
                hintText: '4/0AbCdEfG...',
                prefixIcon: Icon(Icons.vpn_key_outlined, size: 18),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel', style: TextStyle(color: AntigravityTheme.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AntigravityTheme.googleGreen,
              foregroundColor: Colors.black,
            ),
            onPressed: () {
              final code = codeCtrl.text.trim();
              if (code.isNotEmpty) {
                conn.submitAuthCode(code);
                Navigator.pop(dialogCtx);
              }
            },
            child: const Text('Submit Code', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
