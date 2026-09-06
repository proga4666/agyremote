import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../core/theme/app_theme.dart';
import '../models/quick_command.dart';
import '../providers/project_provider.dart';
import '../providers/quick_command_provider.dart';
import '../widgets/adb_device_sheet.dart';

class _BuildConfigResult {
  final QuickCommand command;
  final String? commitMessage;

  _BuildConfigResult({required this.command, this.commitMessage});
}

class TerminalConsoleModal extends StatefulWidget {
  final QuickCommand initialCommand;
  final bool autoRun;

  const TerminalConsoleModal({
    super.key,
    required this.initialCommand,
    this.autoRun = true,
  });

  static Future<void> show(
    BuildContext context, {
    required QuickCommand command,
    bool autoRun = true,
  }) async {
    // Check if command is a Flutter build command
    if (command.category == 'adb' || command.id.contains('build') || command.script.contains('build apk')) {
      final config = await _promptBuildConfig(context, command);
      if (config == null) return; // User cancelled

      if (!context.mounted) return;
      _launchConsole(context, config.command, commitMessage: config.commitMessage);
    } else if (command.requiresCommitMessage && autoRun) {
      final commitMsg = await _promptCommitMessage(context, command);
      if (commitMsg == null) return; // User cancelled

      if (!context.mounted) return;
      _launchConsole(context, command, commitMessage: commitMsg);
    } else {
      _launchConsole(context, command);
    }
  }

  static void _launchConsole(
    BuildContext context,
    QuickCommand command, {
    String? commitMessage,
  }) {
    final proj = context.read<ProjectProvider>().selectedProject;
    final cmdProvider = context.read<QuickCommandProvider>();

    cmdProvider.runCommand(
      command,
      projectId: proj?.id,
      commitMessage: commitMessage,
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AntigravityTheme.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => TerminalConsoleModal(
        initialCommand: command,
        autoRun: false,
      ),
    );
  }

  static Future<_BuildConfigResult?> _promptBuildConfig(BuildContext context, QuickCommand command) async {
    final quickProvider = context.read<QuickCommandProvider>();
    bool isRelease = false;
    bool installToDevice = quickProvider.selectedAdbDevice != null || quickProvider.adbDevices.isNotEmpty;
    bool pushToGit = command.id.contains('push');
    final commitController = TextEditingController(text: 'feat: build apk update');

    return showDialog<_BuildConfigResult>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final modeStr = isRelease ? 'release' : 'debug';
          
          // Construct command preview
          String generatedScript = 'flutter build apk --$modeStr';
          if (installToDevice) {
            generatedScript += ' && adb {DEVICE_TARGET} install -r build/app/outputs/flutter-apk/app-$modeStr.apk';
          }
          if (pushToGit) {
            generatedScript += ' && git add . && git commit -m "{COMMIT_MESSAGE}" && git push';
          }

          return AlertDialog(
            backgroundColor: AntigravityTheme.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            title: const Row(
              children: [
                Icon(Icons.build_circle_rounded, color: AntigravityTheme.googlePurple, size: 22),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Build APK Configuration',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'BUILD MODE',
                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: AntigravityTheme.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () => setDialogState(() => isRelease = false),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: !isRelease ? AntigravityTheme.googlePurple.withValues(alpha: 0.18) : AntigravityTheme.surfaceContainer,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: !isRelease ? AntigravityTheme.googlePurple : AntigravityTheme.borderSubtle,
                                width: !isRelease ? 1.5 : 1,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.bug_report_rounded, size: 16, color: !isRelease ? AntigravityTheme.googlePurple : AntigravityTheme.textMuted),
                                const SizedBox(width: 6),
                                Text(
                                  'Debug',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: !isRelease ? FontWeight.bold : FontWeight.w500,
                                    color: !isRelease ? Colors.white : AntigravityTheme.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: InkWell(
                          onTap: () => setDialogState(() => isRelease = true),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: isRelease ? AntigravityTheme.googlePurple.withValues(alpha: 0.18) : AntigravityTheme.surfaceContainer,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isRelease ? AntigravityTheme.googlePurple : AntigravityTheme.borderSubtle,
                                width: isRelease ? 1.5 : 1,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.rocket_launch_rounded, size: 16, color: isRelease ? AntigravityTheme.googlePurple : AntigravityTheme.textMuted),
                                const SizedBox(width: 6),
                                Text(
                                  'Release',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: isRelease ? FontWeight.bold : FontWeight.w500,
                                    color: isRelease ? Colors.white : AntigravityTheme.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Wireless ADB Install Toggle
                  Container(
                    decoration: BoxDecoration(
                      color: AntigravityTheme.surfaceContainer,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AntigravityTheme.borderSubtle),
                    ),
                    child: Column(
                      children: [
                        SwitchListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                          dense: true,
                          value: installToDevice,
                          activeColor: AntigravityTheme.googlePurple,
                          title: const Text('Install to Device via ADB', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                          subtitle: Text(
                            installToDevice
                                ? (quickProvider.selectedAdbDevice?.displayName ?? 'Auto-detecting on Wi-Fi...')
                                : 'Build APK only (skip installation)',
                            style: const TextStyle(fontSize: 10.5, color: AntigravityTheme.textMuted),
                          ),
                          onChanged: (val) => setDialogState(() => installToDevice = val),
                        ),
                        if (installToDevice) ...[
                          const Divider(height: 1, color: AntigravityTheme.borderSubtle),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            child: Row(
                              children: [
                                const Icon(Icons.install_mobile_rounded, size: 13, color: AntigravityTheme.googlePurple),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    quickProvider.selectedAdbDevice?.serial ?? 'No device chosen',
                                    style: const TextStyle(fontSize: 10.5, color: Colors.white, fontFamily: 'monospace'),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                TextButton(
                                  style: TextButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  onPressed: () {
                                    AdbDeviceSheet.show(context);
                                  },
                                  child: const Text('Manage Devices', style: TextStyle(fontSize: 10.5, color: AntigravityTheme.googlePurple)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Git Push Toggle
                  Container(
                    decoration: BoxDecoration(
                      color: AntigravityTheme.surfaceContainer,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AntigravityTheme.borderSubtle),
                    ),
                    child: Column(
                      children: [
                        SwitchListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                          dense: true,
                          value: pushToGit,
                          activeColor: AntigravityTheme.googleGreen,
                          title: const Text('Push to Git Repository', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                          subtitle: Text(
                            pushToGit
                                ? 'Stage, commit, and push to origin'
                                : 'Only build APK (no git commit or push)',
                            style: TextStyle(
                              fontSize: 10.5,
                              color: pushToGit ? AntigravityTheme.textMuted : AntigravityTheme.googleAmber,
                            ),
                          ),
                          onChanged: (val) => setDialogState(() => pushToGit = val),
                        ),
                        if (pushToGit) ...[
                          const Divider(height: 1, color: AntigravityTheme.borderSubtle),
                          Padding(
                            padding: const EdgeInsets.all(10),
                            child: TextField(
                              controller: commitController,
                              style: const TextStyle(fontSize: 12),
                              decoration: const InputDecoration(
                                labelText: 'Git Commit Message',
                                hintText: 'e.g. feat: new release build',
                                isDense: true,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Script Preview
                  const Text(
                    'COMMAND PREVIEW',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.6, color: AntigravityTheme.textMuted),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0C0D0E),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AntigravityTheme.borderSubtle),
                    ),
                    child: Text(
                      generatedScript,
                      style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: AntigravityTheme.googleBlue),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx, null),
                child: const Text('Cancel', style: TextStyle(color: AntigravityTheme.textSecondary)),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AntigravityTheme.googlePurple,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                ),
                icon: const Icon(Icons.play_arrow_rounded, size: 16),
                label: const Text('Start Build', style: TextStyle(fontWeight: FontWeight.bold)),
                onPressed: () {
                  final customCmd = QuickCommand(
                    id: 'cmd_build_${modeStr}_${DateTime.now().millisecondsSinceEpoch}',
                    title: 'Build APK (${modeStr.toUpperCase()}${pushToGit ? " & Push" : ""})',
                    description: 'Flutter build APK $modeStr mode',
                    script: generatedScript,
                    category: 'adb',
                    requiresCommitMessage: pushToGit,
                    isBuiltIn: false,
                    colorTag: 'purple',
                  );

                  Navigator.pop(
                    dialogCtx,
                    _BuildConfigResult(
                      command: customCmd,
                      commitMessage: pushToGit ? commitController.text.trim() : null,
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  static Future<String?> _promptCommitMessage(BuildContext context, QuickCommand command) async {
    final controller = TextEditingController(text: 'feat: update from agyremote');

    return showDialog<String>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AntigravityTheme.surface,
        title: Row(
          children: [
            const Icon(Icons.commit_rounded, color: AntigravityTheme.googleGreen, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                command.title,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Enter Git commit message:',
                style: TextStyle(fontSize: 12, color: AntigravityTheme.textSecondary),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: controller,
                autofocus: true,
                maxLines: 2,
                decoration: const InputDecoration(
                  hintText: 'e.g. feat: complete tab separation',
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, null),
            child: const Text('Cancel', style: TextStyle(color: AntigravityTheme.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AntigravityTheme.googleGreen,
              foregroundColor: Colors.black,
            ),
            onPressed: () {
              final text = controller.text.trim();
              Navigator.pop(dialogCtx, text.isEmpty ? 'Automated update from agyremote' : text);
            },
            child: const Text('Execute Command', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  State<TerminalConsoleModal> createState() => _TerminalConsoleModalState();
}

class _TerminalConsoleModalState extends State<TerminalConsoleModal> {
  final ScrollController _scrollController = ScrollController();
  Timer? _durationTimer;

  @override
  void initState() {
    super.initState();
    // Live ticking timer for elapsed duration while executing
    _durationTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) {
        final isRunning = context.read<QuickCommandProvider>().isExecuting;
        if (isRunning) {
          setState(() {});
        }
      }
    });

    if (widget.autoRun) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final proj = context.read<ProjectProvider>().selectedProject;
        context.read<QuickCommandProvider>().runCommand(
              widget.initialCommand,
              projectId: proj?.id,
            );
      });
    }
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cmdProvider = context.watch<QuickCommandProvider>();
    final proj = context.watch<ProjectProvider>().selectedProject;
    final exec = cmdProvider.activeExecution;

    _scrollToBottom();

    final statusColor = exec == null
        ? AntigravityTheme.textMuted
        : exec.status == ExecutionStatus.running
            ? AntigravityTheme.googleAmber
            : exec.status == ExecutionStatus.cancelled
                ? AntigravityTheme.googleAmber
                : exec.status == ExecutionStatus.success
                    ? AntigravityTheme.googleGreen
                    : AntigravityTheme.googleRed;

    final statusLabel = exec == null
        ? 'IDLE'
        : exec.status == ExecutionStatus.running
            ? 'RUNNING'
            : exec.status == ExecutionStatus.cancelled
                ? 'CANCELLED BY USER'
                : exec.status == ExecutionStatus.success
                    ? 'SUCCESS (Exit Code 0)'
                    : 'STOPPED AT: ${exec.stoppedAtStep ?? "Error"} (Code ${exec.exitCode ?? 1})';

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag Handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AntigravityTheme.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AntigravityTheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.terminal_rounded, size: 18, color: AntigravityTheme.googleGreen),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.initialCommand.title,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Folder: ${proj?.name ?? "Workstation root"}',
                      style: const TextStyle(fontSize: 10.5, color: AntigravityTheme.textSecondary),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              // NO AI Status Pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: AntigravityTheme.googleBlue.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AntigravityTheme.googleBlue.withValues(alpha: 0.4)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.bolt, size: 12, color: AntigravityTheme.googleBlue),
                    SizedBox(width: 3),
                    Text(
                      'HOST SHELL • NO AI',
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AntigravityTheme.googleBlue),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Execution Status Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AntigravityTheme.surfaceContainer,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AntigravityTheme.borderSubtle),
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    statusLabel,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: statusColor),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (exec != null) ...[
                  const Icon(Icons.timer_outlined, size: 13, color: AntigravityTheme.textMuted),
                  const SizedBox(width: 4),
                  Text(
                    exec.formattedDuration,
                    style: const TextStyle(fontSize: 11, color: AntigravityTheme.textMuted, fontFamily: 'monospace'),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Terminal Output Screen
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0C0D0E),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AntigravityTheme.borderSubtle),
              ),
              child: SelectionArea(
                child: ListView.builder(
                  controller: _scrollController,
                  itemCount: exec?.logs.length ?? 0,
                  itemBuilder: (context, index) {
                    final line = exec!.logs[index];
                    Color textColor = AntigravityTheme.textPrimary;
                    FontWeight fontWeight = FontWeight.normal;

                    if (line.contains('❌') || line.contains('FAILED') || line.contains('error')) {
                      textColor = AntigravityTheme.googleRed;
                      fontWeight = FontWeight.bold;
                    } else if (line.contains('✓') || line.contains('SUCCESS') || line.contains('✅') || line.contains('[git]')) {
                      textColor = AntigravityTheme.googleGreen;
                    } else if (line.contains('▶ [Step')) {
                      textColor = AntigravityTheme.googleBlue;
                      fontWeight = FontWeight.bold;
                    } else if (line.contains('⏹️') || line.contains('🛑') || line.contains('CANCELLED')) {
                      textColor = AntigravityTheme.googleAmber;
                      fontWeight = FontWeight.bold;
                    } else if (line.contains('ℹ️')) {
                      textColor = AntigravityTheme.googlePurple;
                    } else if (line.contains('[Runner]')) {
                      textColor = AntigravityTheme.googleBlue;
                    }

                    return Text(
                      line,
                      style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: textColor,
                        fontWeight: fontWeight,
                        height: 1.3,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Bottom Action Controls
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.copy_rounded, size: 18, color: AntigravityTheme.textSecondary),
                tooltip: 'Copy Terminal Logs',
                onPressed: () {
                  final text = exec?.logs.join('') ?? '';
                  Clipboard.setData(ClipboardData(text: text));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Terminal logs copied to clipboard.'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
              ),
              if (widget.initialCommand.category == 'adb' || widget.initialCommand.id.contains('build'))
                IconButton(
                  icon: const Icon(Icons.install_mobile_rounded, size: 18, color: AntigravityTheme.googlePurple),
                  tooltip: 'ADB Device Settings',
                  onPressed: () => AdbDeviceSheet.show(context),
                ),
              const Spacer(),
              if (cmdProvider.isExecuting) ...[
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AntigravityTheme.googleRed,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  ),
                  icon: const Icon(Icons.stop_circle_outlined, size: 16),
                  label: const Text('Cancel Command', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  onPressed: () => cmdProvider.cancelCommand(),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AntigravityTheme.border),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Background', style: TextStyle(fontSize: 12, color: AntigravityTheme.textSecondary)),
                ),
              ] else ...[
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AntigravityTheme.border),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  icon: const Icon(Icons.replay_rounded, size: 16),
                  label: const Text('Rerun', style: TextStyle(fontSize: 12)),
                  onPressed: () {
                    cmdProvider.runCommand(
                      widget.initialCommand,
                      projectId: proj?.id,
                    );
                  },
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AntigravityTheme.surfaceContainerHigh,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
