import 'package:flutter/material.dart';
import '../core/network/bridge_client.dart';
import '../models/quick_command.dart';

class QuickCommandProvider extends ChangeNotifier {
  final BridgeClient bridge;

  final List<QuickCommand> _builtInCommands = QuickCommand.defaultBuiltInCommands;
  List<QuickCommand> _customCommands = [];

  List<AdbDevice> adbDevices = [];
  AdbDevice? selectedAdbDevice;
  bool isAdbAvailable = true;
  String? detectedClientIp;
  bool isLoadingDevices = false;

  QuickCommandExecution? activeExecution;
  bool get isExecuting => activeExecution?.status == ExecutionStatus.running;

  QuickCommandProvider({required this.bridge}) {
    bridge.events.listen(_handleEvents);
    bridge.statusStream.listen((status) {
      if (status == BridgeStatus.connected) {
        fetchQuickCommands();
        refreshAdbDevices();
      }
    });
    fetchQuickCommands();
    refreshAdbDevices();
  }

  List<QuickCommand> get allCommands => [..._builtInCommands, ..._customCommands];

  List<QuickCommand> get gitCommands =>
      allCommands.where((c) => c.category == 'git').toList();

  List<QuickCommand> get flutterCommands =>
      allCommands.where((c) => c.category == 'flutter' || c.category == 'adb').toList();

  List<QuickCommand> get customCommands => _customCommands;

  void fetchQuickCommands() {
    bridge.send('list_quick_commands', {});
  }

  void refreshAdbDevices() {
    isLoadingDevices = true;
    notifyListeners();
    bridge.send('list_adb_devices', {});
  }

  void selectAdbDevice(AdbDevice? device) {
    selectedAdbDevice = device;
    notifyListeners();
  }

  void connectAdbDevice(String target) {
    isLoadingDevices = true;
    notifyListeners();
    bridge.send('connect_adb_device', {'target': target});
  }

  void disconnectAdbDevice(String target) {
    isLoadingDevices = true;
    notifyListeners();
    bridge.send('disconnect_adb_device', {'target': target});
  }

  void saveCustomCommand(QuickCommand command) {
    _customCommands.removeWhere((c) => c.id == command.id);
    _customCommands.add(command);
    notifyListeners();

    bridge.send('save_quick_command', {
      'command': command.toJson(),
    });
  }

  void deleteCustomCommand(String id) {
    _customCommands.removeWhere((c) => c.id == id);
    notifyListeners();

    bridge.send('delete_quick_command', {
      'id': id,
    });
  }

  void runCommand(
    QuickCommand command, {
    required String? projectId,
    String? commitMessage,
    String? customDeviceTarget,
  }) {
    final devTarget = customDeviceTarget ?? selectedAdbDevice?.serial ?? '';

    activeExecution = QuickCommandExecution(
      commandId: command.id,
      title: command.title,
      script: command.script,
      status: ExecutionStatus.running,
      logs: ['[Runner] Initializing direct host terminal execution (bypassing AI LLM)...\n'],
      startedAt: DateTime.now(),
    );
    notifyListeners();

    bridge.send('exec_quick_command', {
      'command_id': command.id,
      'project_id': projectId ?? '',
      'script': command.script,
      'commit_message': commitMessage ?? 'Automated update from agyremote',
      'device_target': devTarget,
    });
  }

  void cancelCommand() {
    if (activeExecution == null || !isExecuting) return;
    final cmdId = activeExecution!.commandId;
    activeExecution!.status = ExecutionStatus.cancelled;
    activeExecution!.completedAt = DateTime.now();
    activeExecution!.logs.add('\n[Runner] 🛑 Cancelling command execution on host...\n');
    notifyListeners();

    bridge.send('cancel_quick_command', {
      'command_id': cmdId,
    });
  }

  void clearActiveExecution() {
    activeExecution = null;
    notifyListeners();
  }

  void _handleEvents(Map<String, dynamic> event) {
    final evType = event['event'];

    switch (evType) {
      case 'quick_commands_list':
        final rawCustom = event['custom_commands'] as List<dynamic>? ?? [];
        _customCommands = rawCustom
            .map((c) => QuickCommand.fromJson(Map<String, dynamic>.from(c)))
            .toList();
        notifyListeners();
        break;

      case 'adb_devices_list':
        isLoadingDevices = false;
        isAdbAvailable = event['adb_available'] == true;
        detectedClientIp = event['client_ip']?.toString();
        final rawDevs = event['devices'] as List<dynamic>? ?? [];
        adbDevices = rawDevs
            .map((d) => AdbDevice.fromJson(Map<String, dynamic>.from(d)))
            .toList();

        // Auto-select active device if none selected
        if (selectedAdbDevice == null && adbDevices.isNotEmpty) {
          final connected = adbDevices.where((d) => d.isConnected);
          selectedAdbDevice = connected.isNotEmpty ? connected.first : adbDevices.first;
        } else if (selectedAdbDevice != null) {
          final match = adbDevices.where((d) => d.serial == selectedAdbDevice!.serial);
          selectedAdbDevice = match.isNotEmpty ? match.first : null;
        }
        notifyListeners();
        break;

      case 'adb_connect_result':
      case 'adb_disconnect_result':
        isLoadingDevices = false;
        final rawDevs = event['devices'] as List<dynamic>? ?? [];
        adbDevices = rawDevs
            .map((d) => AdbDevice.fromJson(Map<String, dynamic>.from(d)))
            .toList();
        if (adbDevices.isNotEmpty && selectedAdbDevice == null) {
          selectedAdbDevice = adbDevices.first;
        }
        notifyListeners();
        break;

      case 'quick_command_started':
        final cmdId = event['command_id']?.toString();
        if (activeExecution?.commandId == cmdId) {
          final cwd = event['cwd']?.toString() ?? '';
          final script = event['script']?.toString() ?? '';
          activeExecution!.logs.add('[Runner] CWD: $cwd\n[Runner] Executing: $script\n----------------------------------------\n');
          notifyListeners();
        }
        break;

      case 'quick_command_output':
        final cmdId = event['command_id']?.toString();
        final chunk = event['output']?.toString() ?? '';
        if (activeExecution?.commandId == cmdId) {
          activeExecution!.logs.add(chunk);
          notifyListeners();
        }
        break;

      case 'quick_command_cancelled':
        final cmdId = event['command_id']?.toString();
        if (activeExecution?.commandId == cmdId) {
          activeExecution!.status = ExecutionStatus.cancelled;
          activeExecution!.completedAt = DateTime.now();
          activeExecution!.logs.add('[Runner] ⏹️ Process successfully stopped.\n');
          notifyListeners();
        }
        break;

      case 'quick_command_finished':
        final cmdId = event['command_id']?.toString();
        if (activeExecution?.commandId == cmdId) {
          final isCancelled = event['cancelled'] == true || activeExecution!.status == ExecutionStatus.cancelled;
          final success = event['success'] == true && !isCancelled;
          final rc = event['return_code'] as int? ?? (success ? 0 : 1);
          final stoppedStep = event['stopped_at']?.toString();

          activeExecution!.status = isCancelled
              ? ExecutionStatus.cancelled
              : (success ? ExecutionStatus.success : ExecutionStatus.failed);
          activeExecution!.exitCode = rc;
          activeExecution!.completedAt = DateTime.now();
          activeExecution!.stoppedAtStep = stoppedStep;

          if (isCancelled) {
            activeExecution!.logs.add('\n----------------------------------------\n[Runner] Execution CANCELLED by user\n');
          } else if (success) {
            activeExecution!.logs.add('\n----------------------------------------\n[Runner] Process finished successfully (exit code 0)\n');
          } else {
            activeExecution!.logs.add('\n----------------------------------------\n[Runner] 🛑 Command stopped at step "${stoppedStep ?? "command"}" with exit code $rc\n');
          }
          notifyListeners();
        }
        break;
    }
  }
}
