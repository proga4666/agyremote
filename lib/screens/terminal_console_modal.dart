import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../core/theme/app_theme.dart';
import '../models/quick_command.dart';
import '../providers/project_provider.dart';
import '../providers/quick_command_provider.dart';
import '../widgets/adb_device_sheet.dart';

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
    // If command requires commit message, prompt first
    if (command.requiresCommitMessage && autoRun) {
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

  static Future<String?> _promptCommitMessage(BuildContext context, QuickCommand command) async {
    final controller = TextEditingController(text: 'feat: update from agyremote');
    final quickProvider = context.read<QuickCommandProvider>();

    return showDialog<String>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
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
                if (command.category == 'adb') ...[
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      const Icon(Icons.install_mobile_rounded, size: 14, color: AntigravityTheme.googlePurple),
                      const SizedBox(width: 6),
                      const Text(
                        'Target Wireless Phone:',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AntigravityTheme.textSecondary),
                      ),
                      const Spacer(),
                      TextButton(
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () {
                          Navigator.pop(dialogCtx);
                          AdbDeviceSheet.show(context);
                        },
                        child: const Text('Change', style: TextStyle(fontSize: 11, color: AntigravityTheme.googlePurple)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AntigravityTheme.surfaceContainer,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AntigravityTheme.borderSubtle),
                    ),
                    child: Text(
                      quickProvider.selectedAdbDevice?.displayName ?? 'Auto-detecting on Wi-Fi...',
                      style: const TextStyle(fontSize: 11, color: Colors.white, fontFamily: 'monospace'),
                    ),
                  ),
                ],
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
      ),
    );
  }

  @override
  State<TerminalConsoleModal> createState() => _TerminalConsoleModalState();
}

class _TerminalConsoleModalState extends State<TerminalConsoleModal> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
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
            : exec.status == ExecutionStatus.success
                ? AntigravityTheme.googleGreen
                : AntigravityTheme.googleRed;

    final statusLabel = exec == null
        ? 'IDLE'
        : exec.status == ExecutionStatus.running
            ? 'RUNNING'
            : exec.status == ExecutionStatus.success
                ? 'SUCCESS (Code 0)'
                : 'FAILED (Code ${exec.exitCode ?? 1})';

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
                Text(
                  statusLabel,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: statusColor),
                ),
                const Spacer(),
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
                    if (line.contains('❌') || line.contains('FAILED') || line.contains('error')) {
                      textColor = AntigravityTheme.googleRed;
                    } else if (line.contains('✓') || line.contains('SUCCESS') || line.contains('[git]')) {
                      textColor = AntigravityTheme.googleGreen;
                    } else if (line.contains('[Runner]')) {
                      textColor = AntigravityTheme.googleBlue;
                    }

                    return Text(
                      line,
                      style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: textColor,
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
              if (widget.initialCommand.category == 'adb')
                IconButton(
                  icon: const Icon(Icons.install_mobile_rounded, size: 18, color: AntigravityTheme.googlePurple),
                  tooltip: 'ADB Device Settings',
                  onPressed: () => AdbDeviceSheet.show(context),
                ),
              const Spacer(),
              if (!cmdProvider.isExecuting) ...[
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
              ],
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AntigravityTheme.surfaceContainerHigh,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
                onPressed: () => Navigator.pop(context),
                child: Text(cmdProvider.isExecuting ? 'Background' : 'Close', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
