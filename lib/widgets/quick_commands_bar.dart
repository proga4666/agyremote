import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme/app_theme.dart';
import '../models/quick_command.dart';
import '../providers/quick_command_provider.dart';
import '../screens/terminal_console_modal.dart';
import 'adb_device_sheet.dart';

class QuickCommandsBar extends StatelessWidget {
  const QuickCommandsBar({super.key});

  @override
  Widget build(BuildContext context) {
    final cmdProvider = context.watch<QuickCommandProvider>();
    final allCmds = cmdProvider.allCommands;

    final gitPush = allCmds.firstWhere(
      (c) => c.id == 'cmd_git_push',
      orElse: () => QuickCommand.defaultBuiltInCommands[0],
    );
    final buildPush = allCmds.firstWhere(
      (c) => c.id == 'cmd_build_apk_push',
      orElse: () => QuickCommand.defaultBuiltInCommands[1],
    );
    final pubGet = allCmds.firstWhere(
      (c) => c.id == 'cmd_pub_get',
      orElse: () => QuickCommand.defaultBuiltInCommands[2],
    );
    final testCmd = allCmds.firstWhere(
      (c) => c.id == 'cmd_flutter_test_analyze',
      orElse: () => QuickCommand.defaultBuiltInCommands[3],
    );

    final selectedDevice = cmdProvider.selectedAdbDevice;

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: AntigravityTheme.surfaceContainer.withValues(alpha: 0.85),
        border: const Border(
          bottom: BorderSide(color: AntigravityTheme.borderSubtle),
        ),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          // Push button
          _buildQuickButton(
            context,
            icon: Icons.upload_rounded,
            label: 'Push',
            color: AntigravityTheme.googleGreen,
            onTap: () => TerminalConsoleModal.show(context, command: gitPush),
          ),
          const SizedBox(width: 6),

          // Build & Push button
          _buildQuickButton(
            context,
            icon: Icons.install_mobile_rounded,
            label: 'Build & Push',
            color: AntigravityTheme.googlePurple,
            onTap: () => TerminalConsoleModal.show(context, command: buildPush),
          ),
          const SizedBox(width: 6),

          // Pub Get button
          _buildQuickButton(
            context,
            icon: Icons.download_for_offline_outlined,
            label: 'Pub Get',
            color: AntigravityTheme.googleBlue,
            onTap: () => TerminalConsoleModal.show(context, command: pubGet),
          ),
          const SizedBox(width: 6),

          // Test button
          _buildQuickButton(
            context,
            icon: Icons.fact_check_outlined,
            label: 'Test',
            color: AntigravityTheme.googleAmber,
            onTap: () => TerminalConsoleModal.show(context, command: testCmd),
          ),
          const SizedBox(width: 6),

          // Wireless ADB Pill
          InkWell(
            onTap: () => AdbDeviceSheet.show(context),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: selectedDevice != null && selectedDevice.isConnected
                    ? AntigravityTheme.googlePurple.withValues(alpha: 0.15)
                    : AntigravityTheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: selectedDevice != null && selectedDevice.isConnected
                      ? AntigravityTheme.googlePurple.withValues(alpha: 0.4)
                      : AntigravityTheme.borderSubtle,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.wifi_tethering_rounded,
                    size: 13,
                    color: selectedDevice != null && selectedDevice.isConnected
                        ? AntigravityTheme.googlePurple
                        : AntigravityTheme.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    selectedDevice?.displayName ?? 'No Device',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: selectedDevice != null && selectedDevice.isConnected
                          ? AntigravityTheme.googlePurple
                          : AntigravityTheme.textSecondary,
                    ),
                  ),
                  const Icon(Icons.arrow_drop_down, size: 14, color: AntigravityTheme.textSecondary),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),

          // All / Custom Commands Launcher
          ActionChip(
            avatar: const Icon(Icons.more_horiz_rounded, size: 14, color: Colors.white),
            label: const Text('Commands', style: TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold)),
            backgroundColor: AntigravityTheme.surfaceContainerHigh,
            side: const BorderSide(color: AntigravityTheme.borderSubtle),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            visualDensity: VisualDensity.compact,
            onPressed: () => _showAllCommandsSheet(context),
          ),
        ],
      ),
    );
  }

  static Widget _buildQuickButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
            ),
          ],
        ),
      ),
    );
  }

  static void _showAllCommandsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AntigravityTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (modalCtx) => const _AllCommandsSheetContent(),
    );
  }
}

class _AllCommandsSheetContent extends StatelessWidget {
  const _AllCommandsSheetContent();

  @override
  Widget build(BuildContext context) {
    final cmdProvider = context.watch<QuickCommandProvider>();

    return SafeArea(
      child: Container(
        height: MediaQuery.of(context).size.height * 0.75,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                const Icon(Icons.terminal_rounded, color: AntigravityTheme.googleBlue, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'PRE-SAVED TERMINAL COMMANDS',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: AntigravityTheme.textSecondary),
                      ),
                      Text(
                        'Direct host shell execution (bypassing AI)',
                        style: TextStyle(fontSize: 11, color: AntigravityTheme.textMuted),
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AntigravityTheme.googleBlue,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    minimumSize: Size.zero,
                  ),
                  icon: const Icon(Icons.add, size: 14),
                  label: const Text('Add Custom', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  onPressed: () => _showAddCustomCommandDialog(context),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Command List
            Expanded(
              child: ListView(
                children: [
                  ...cmdProvider.allCommands.map((QuickCommand cmd) {
                    final color = _getColor(cmd.colorTag);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Material(
                        color: AntigravityTheme.surfaceContainer,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AntigravityTheme.borderSubtle),
                          ),
                          child: ListTile(
                        dense: true,
                        leading: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Icon(Icons.terminal_rounded, size: 18, color: color),
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                cmd.title,
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                            ),
                            if (cmd.isBuiltIn)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: AntigravityTheme.surfaceContainerHigh,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text('BUILT-IN', style: TextStyle(fontSize: 8.5, color: AntigravityTheme.textMuted, fontWeight: FontWeight.bold)),
                              )
                            else
                              IconButton(
                                icon: const Icon(Icons.delete_outline_rounded, size: 16, color: AntigravityTheme.googleRed),
                                tooltip: 'Delete custom command',
                                onPressed: () => cmdProvider.deleteCustomCommand(cmd.id),
                              ),
                          ],
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (cmd.description.isNotEmpty) ...[
                              Text(cmd.description, style: const TextStyle(fontSize: 11, color: AntigravityTheme.textSecondary)),
                              const SizedBox(height: 2),
                            ],
                            Text(
                              cmd.script,
                              style: const TextStyle(fontSize: 10, color: AntigravityTheme.textMuted, fontFamily: 'monospace'),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                        trailing: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: color.withValues(alpha: 0.2),
                            foregroundColor: color,
                            side: BorderSide(color: color.withValues(alpha: 0.4)),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            minimumSize: Size.zero,
                          ),
                          onPressed: () {
                            Navigator.pop(context);
                            TerminalConsoleModal.show(context, command: cmd);
                          },
                          child: const Text('Run', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ),
                  ),
                );
              }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Color _getColor(String tag) {
    switch (tag) {
      case 'green':
        return AntigravityTheme.googleGreen;
      case 'purple':
        return AntigravityTheme.googlePurple;
      case 'amber':
        return AntigravityTheme.googleAmber;
      case 'red':
        return AntigravityTheme.googleRed;
      default:
        return AntigravityTheme.googleBlue;
    }
  }

  static void _showAddCustomCommandDialog(BuildContext context) {
    final titleController = TextEditingController();
    final scriptController = TextEditingController();
    final descController = TextEditingController();
    bool requiresCommit = false;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AntigravityTheme.surface,
          title: const Text('New Custom Terminal Command', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: 'Command Title',
                    hintText: 'e.g. Docker Restart',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: scriptController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Shell Script / Command',
                    hintText: 'e.g. docker-compose restart',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: descController,
                  decoration: const InputDecoration(
                    labelText: 'Description (optional)',
                    hintText: 'e.g. Restarts local services container',
                  ),
                ),
                const SizedBox(height: 10),
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Prompt for Git commit message', style: TextStyle(fontSize: 12)),
                  value: requiresCommit,
                  onChanged: (val) => setDialogState(() => requiresCommit = val ?? false),
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
                final title = titleController.text.trim();
                final script = scriptController.text.trim();
                if (title.isNotEmpty && script.isNotEmpty) {
                  final newCmd = QuickCommand(
                    id: 'cmd_custom_${DateTime.now().millisecondsSinceEpoch}',
                    title: title,
                    description: descController.text.trim(),
                    script: script,
                    category: 'custom',
                    requiresCommitMessage: requiresCommit,
                    isBuiltIn: false,
                    colorTag: 'amber',
                  );
                  context.read<QuickCommandProvider>().saveCustomCommand(newCmd);
                  Navigator.pop(dialogCtx);
                }
              },
              child: const Text('Save Command', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}
