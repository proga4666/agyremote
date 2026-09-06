import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

enum BridgeStatus { disconnected, connecting, connected, error }

class BridgeClient {
  WebSocketChannel? _channel;
  final _eventController = StreamController<Map<String, dynamic>>.broadcast();
  final _statusController = StreamController<BridgeStatus>.broadcast();

  Stream<Map<String, dynamic>> get events => _eventController.stream;
  Stream<BridgeStatus> get statusStream => _statusController.stream;

  BridgeStatus status = BridgeStatus.disconnected;
  String currentHostUrl = 'ws://192.168.0.109:7800/ws';
  bool isMockMode = false;
  Timer? _reconnectTimer;
  bool _intentionalDisconnect = false;
  final List<String> _pendingOutgoingQueue = [];

  BridgeClient({this.isMockMode = false}) {
    _statusController.add(BridgeStatus.disconnected);
  }

  void connect(String hostUrl, {bool forceMock = false}) {
    _intentionalDisconnect = false;
    currentHostUrl = hostUrl;
    _reconnectTimer?.cancel();
    disconnect(intentional: false);

    if (forceMock) {
      _startMockMode();
      return;
    }

    isMockMode = false;
    _setStatus(BridgeStatus.connecting);

    try {
      final uri = Uri.parse(hostUrl);
      _channel = WebSocketChannel.connect(uri);

      _channel!.ready.then((_) {
        debugPrint('[BridgeClient] Connected to $hostUrl');
        _setStatus(BridgeStatus.connected);
        isMockMode = false;
        _flushPendingQueue();
      }).catchError((err) {
        debugPrint('[BridgeClient] Connection error: $err');
        _channel = null;
        if (!_intentionalDisconnect && !isMockMode) {
          _setStatus(BridgeStatus.error);
          _scheduleReconnect();
        }
      });

      _channel!.stream.listen(
        (data) {
          try {
            final decoded = jsonDecode(data as String);
            if (decoded is Map<String, dynamic>) {
              if (status != BridgeStatus.connected) {
                _setStatus(BridgeStatus.connected);
                isMockMode = false;
              }
              _eventController.add(decoded);
            }
          } catch (e) {
            debugPrint('Error parsing incoming WebSocket message: $e');
          }
        },
        onError: (err) {
          debugPrint('[BridgeClient] Stream error: $err');
          _channel = null;
          if (!_intentionalDisconnect && !isMockMode) {
            _setStatus(BridgeStatus.error);
            _scheduleReconnect();
          }
        },
        onDone: () {
          debugPrint('[BridgeClient] WebSocket closed');
          _channel = null;
          if (!_intentionalDisconnect && !isMockMode) {
            _setStatus(BridgeStatus.disconnected);
            _scheduleReconnect();
          } else {
            _setStatus(BridgeStatus.disconnected);
          }
        },
      );
    } catch (e) {
      debugPrint('[BridgeClient] Connect exception: $e');
      _setStatus(BridgeStatus.error);
      _scheduleReconnect();
    }
  }

  void _flushPendingQueue() {
    if (_channel != null && status == BridgeStatus.connected) {
      while (_pendingOutgoingQueue.isNotEmpty) {
        final msg = _pendingOutgoingQueue.removeAt(0);
        try {
          _channel!.sink.add(msg);
        } catch (e) {
          debugPrint('[BridgeClient] Error sending queued message: $e');
        }
      }
    }
  }

  void _startMockMode() {
    isMockMode = true;
    _setStatus(BridgeStatus.connected);
    debugPrint('BridgeClient: Operating in Local Demo / Simulated mode');
    _eventController.add({
      'event': 'status_notice',
      'message': 'Connected to Antigravity Local Simulator',
    });
    send('list_projects', {});
    send('list_conversations', {});
  }

  void _scheduleReconnect() {
    if (_intentionalDisconnect || isMockMode) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      if (status != BridgeStatus.connected && !isMockMode && !_intentionalDisconnect) {
        debugPrint('[BridgeClient] Reconnecting to $currentHostUrl...');
        connect(currentHostUrl, forceMock: false);
      }
    });
  }

  void _setStatus(BridgeStatus newStatus) {
    status = newStatus;
    _statusController.add(newStatus);
  }

  void send(String action, Map<String, dynamic> payload) {
    if (isMockMode) {
      _handleMockAction(action, payload);
      return;
    }

    final msg = jsonEncode({'action': action, ...payload});
    if (_channel != null && status == BridgeStatus.connected) {
      try {
        _channel!.sink.add(msg);
      } catch (e) {
        debugPrint('Error sending message: $e');
      }
    } else {
      // Queue message until connection is established
      _pendingOutgoingQueue.add(msg);
      debugPrint('[BridgeClient] Queued action "$action" (connecting to host...)');
    }
  }

  void disconnect({bool intentional = true}) {
    _intentionalDisconnect = intentional;
    _reconnectTimer?.cancel();
    if (_channel != null) {
      try {
        _channel?.sink.close();
      } catch (_) {}
      _channel = null;
    }
    _setStatus(BridgeStatus.disconnected);
  }

  // --- Offline / Demo Simulation Engine ---
  void _handleMockAction(String action, Map<String, dynamic> payload) {
    switch (action) {
      case 'list_projects':
        Future.microtask(() {
          _eventController.add({
            'event': 'projects_list',
            'projects': [
              {
                'id': 'proj_agy_core',
                'name': 'antigravity-core',
                'path': '/workspace/antigravity-core',
                'conversation_ids': ['conv_auth_demo', 'conv_plan_refactor'],
              },
              {
                'id': 'proj_mobile_flutter',
                'name': 'agyremote-mobile',
                'path': '/workspace/flutter/agyremote',
                'conversation_ids': ['conv_ui_redesign'],
              },
            ],
          });
        });
        break;

      case 'browse_dir':
        final path = (payload['path'] ?? '/workspace').toString();
        Future.microtask(() {
          _eventController.add({
            'event': 'dir_contents',
            'current_path': path == '~' ? '/workspace' : path,
            'parent_path': '/',
            'folders': ['lib', 'android', 'ios', 'test', 'web', 'assets'],
            'files': ['pubspec.yaml', 'README.md'],
          });
        });
        break;

      case 'create_project':
        final name = payload['name'] ?? 'New Project';
        final rootPath = payload['root_path'] ?? '/workspace/$name';
        final newId = 'proj_${DateTime.now().millisecondsSinceEpoch}';

        Future.microtask(() {
          _eventController.add({
            'event': 'project_created',
            'project': {
              'id': newId,
              'name': name,
              'path': rootPath,
              'conversation_ids': [],
            },
          });
          send('list_projects', {});
        });
        break;

      case 'list_conversations':
        Future.microtask(() {
          _eventController.add({
            'event': 'conversations_list',
            'conversations': [
              {
                'id': 'conv_auth_demo',
                'project_id': 'proj_agy_core',
                'title': 'Autonomous Daemon: OAuth Token Watchdog',
                'workspace_path': '/workspace/antigravity-core',
                'source': 'daemon',
                'engine': 'Antigravity 2.0',
                'created_at': DateTime.now().subtract(const Duration(minutes: 15)).toIso8601String(),
                'messages': [
                  {
                    'id': 'msg_1',
                    'sender': 'user',
                    'content': 'Run headless watchdog to verify auth refresh.',
                    'timestamp': DateTime.now().subtract(const Duration(minutes: 15)).toIso8601String(),
                  },
                  {
                    'id': 'msg_2',
                    'sender': 'agent',
                    'content': 'Watchdog active in background on Antigravity 2.0 headless daemon.',
                    'timestamp': DateTime.now().subtract(const Duration(minutes: 14)).toIso8601String(),
                  },
                ],
              },
              {
                'id': 'conv_plan_refactor',
                'project_id': 'proj_agy_core',
                'title': 'Autonomous Task: Daemon Architecture',
                'workspace_path': '/workspace/antigravity-core',
                'source': 'daemon',
                'engine': 'Antigravity 2.0',
                'created_at': DateTime.now().subtract(const Duration(hours: 1)).toIso8601String(),
                'messages': [
                  {
                    'id': 'msg_3',
                    'sender': 'user',
                    'content': 'Create implementation plan for remote daemon.',
                    'timestamp': DateTime.now().subtract(const Duration(hours: 1)).toIso8601String(),
                  },
                ],
              },
              {
                'id': 'conv_ui_redesign',
                'project_id': 'proj_mobile_flutter',
                'title': 'Desktop IDE: Mobile Tab Interface Polish',
                'workspace_path': '/workspace/flutter/agyremote',
                'source': 'desktop_ide',
                'engine': 'Desktop IDE',
                'created_at': DateTime.now().subtract(const Duration(hours: 3)).toIso8601String(),
                'messages': [
                  {
                    'id': 'msg_4',
                    'sender': 'user',
                    'content': 'Separate daemon and IDE chats into distinct tabs.',
                    'timestamp': DateTime.now().subtract(const Duration(hours: 3)).toIso8601String(),
                  },
                  {
                    'id': 'msg_5',
                    'sender': 'agent',
                    'content': 'Created segmented tabs with badge indicators in drawer and dialog.',
                    'timestamp': DateTime.now().subtract(const Duration(hours: 2, minutes: 55)).toIso8601String(),
                  },
                ],
              },
              {
                'id': 'conv_ide_debug',
                'project_id': 'proj_mobile_flutter',
                'title': 'Desktop IDE: Test Harness & Widget Diagnostics',
                'workspace_path': '/workspace/flutter/agyremote',
                'source': 'desktop_ide',
                'engine': 'Desktop IDE',
                'created_at': DateTime.now().subtract(const Duration(days: 1)).toIso8601String(),
                'messages': [
                  {
                    'id': 'msg_6',
                    'sender': 'user',
                    'content': 'Verify widget unit tests.',
                    'timestamp': DateTime.now().subtract(const Duration(days: 1)).toIso8601String(),
                  },
                ],
              },
            ],
          });
        });
        break;

      case 'create_conversation':
        final convId = payload['id'] ?? 'conv_${DateTime.now().millisecondsSinceEpoch}';
        final projId = payload['project_id'] ?? 'proj_agy_core';
        final title = payload['title'] ?? 'Autonomous Task';
        final source = payload['source'] ?? 'daemon';
        final engine = payload['engine'] ?? (source == 'daemon' ? 'Antigravity 2.0' : 'Desktop IDE');

        Future.microtask(() {
          _eventController.add({
            'event': 'conversation_created',
            'conversation': {
              'id': convId,
              'project_id': projId,
              'title': title,
              'source': source,
              'engine': engine,
              'messages': [],
            },
          });
        });
        break;

      case 'send_prompt':
        final convId = payload['conversation_id'];
        final promptText = (payload['text'] ?? '').toString();

        _simulateAgentResponse(convId, promptText);
        break;

      case 'resolve_approval':
        final approvalId = payload['approval_id'];
        final approved = payload['approved'] == true;

        Future.microtask(() {
          _eventController.add({
            'event': 'approval_resolved',
            'approval_id': approvalId,
            'approved': approved,
          });

          if (approved) {
            _eventController.add({
              'event': 'agent_stream',
              'conversation_id': convId,
              'chunk': 'Execution completed successfully:\n```bash\n[daemon] Build verified: tests passed\n```\n',
              'is_thought': false,
            });
          } else {
            _eventController.add({
              'event': 'agent_stream',
              'conversation_id': convId,
              'chunk': 'Command execution rejected by user.\n',
              'is_thought': false,
            });
          }
        });
        break;

      case 'get_daemon_status':
        Future.microtask(() {
          _eventController.add({
            'event': 'daemon_status',
            'status': 'online',
            'uptime_seconds': 3420,
            'pid': 14892,
            'platform': 'Windows',
            'instance_type': 'headless_daemon',
            'cli_remote_control_hostname': 'aws-rising-ember-daemon',
            'remote_control_hostname': 'aws-rising-ember',
            'update_interval': 'daily',
            'has_cli_name_override': false,
            'config_file_path': r'%USERPROFILE%\.gemini\config\config.json',
            'auth_account': 'shahadsirius369@gmail.com',
            'is_authenticated': true,
            'port': 7800,
            'discovery_port': 7801,
            'recent_logs': [
              '[13:00:10] agy-daemon started on port 7800 (background service)',
              '[13:00:11] Loaded configuration from %USERPROFILE%\\.gemini\\config\\config.json',
              '[13:00:11] cliRemoteControlHostname: "aws-rising-ember-daemon"',
              '[13:00:11] remoteControlHostname: "aws-rising-ember"',
              '[13:00:12] Google Pro OAuth session verified for shahadsirius369@gmail.com',
              '[13:00:15] Discovery beacon broadcasting on UDP 7801',
              '[13:05:22] Client connection established from mobile app',
            ],
          });
        });
        break;

      case 'restart_daemon':
        Future.microtask(() {
          _eventController.add({
            'event': 'daemon_restarting',
            'message': 'Service restart initiated. Reconnecting in 3s...',
          });
          Future.delayed(const Duration(seconds: 1), () {
            send('get_daemon_status', {});
          });
        });
        break;

      case 'update_config':
        final cliHost = payload['cli_remote_control_hostname']?.toString();
        final deskHost = payload['remote_control_hostname']?.toString();
        final interval = payload['update_interval']?.toString() ?? 'daily';
        Future.microtask(() {
          _eventController.add({
            'event': 'config_updated',
            'message': 'Configuration updated successfully in config.json',
          });
          _eventController.add({
            'event': 'daemon_status',
            'status': 'online',
            'uptime_seconds': 12,
            'pid': 15200,
            'platform': 'Windows',
            'instance_type': 'headless_daemon',
            'cli_remote_control_hostname': cliHost ?? 'aws-rising-ember-daemon',
            'remote_control_hostname': deskHost ?? 'aws-rising-ember',
            'update_interval': interval,
            'has_cli_name_override': false,
            'config_file_path': r'%USERPROFILE%\.gemini\config\config.json',
            'auth_account': 'shahadsirius369@gmail.com',
            'is_authenticated': true,
            'port': 7800,
            'discovery_port': 7801,
            'recent_logs': [
              '[13:10:00] Applied configuration changes to config.json',
              '[13:10:01] Service restarted to apply new hostname settings',
            ],
          });
        });
        break;

      case 'get_auth_status':
      case 'refresh_auth':
        Future.microtask(() {
          _eventController.add({
            'event': 'auth_status',
            'is_authenticated': true,
            'auth_account': 'shahadsirius369@gmail.com',
            'auth_type': 'headless_daemon_oauth',
            'expires_in': '30 days',
            'message': 'Google Pro Account authenticated and synced.',
          });
        });
        break;

      case 'submit_auth_code':
        Future.microtask(() {
          _eventController.add({
            'event': 'auth_status',
            'is_authenticated': true,
            'auth_account': 'shahadsirius369@gmail.com',
            'auth_type': 'headless_daemon_oauth',
            'message': 'Verification code accepted. Token saved.',
          });
        });
        break;

      case 'get_conversation_artifacts':
        final convId = payload['conversation_id']?.toString() ?? '';
        Future.microtask(() {
          _eventController.add({
            'event': 'conversation_artifacts',
            'conversation_id': convId,
            'artifacts': [
              {
                'id': 'art_plan',
                'conversation_id': convId,
                'name': 'implementation_plan.md',
                'file_path': 'brain/$convId/implementation_plan.md',
                'type': 'plan',
                'last_modified': DateTime.now().toIso8601String(),
                'size_bytes': 3240,
                'request_feedback': true,
                'summary': 'Full refactoring & testing plan for Antigravity Remote.',
                'content': '''# Implementation Plan: Antigravity Remote Service

## User Review Required
> [!IMPORTANT]
> Headless daemon configuration requires Administrator privileges on Windows cmd.exe.

## Proposed Changes
### Core Daemon
- [x] Read & write `config.json`
- [x] Service Lifecycle monitoring

### Verification Plan
- [x] Run `flutter analyze`
- [ ] Connect mobile client and verify live streaming
''',
              },
              {
                'id': 'art_walkthrough',
                'conversation_id': convId,
                'name': 'walkthrough.md',
                'file_path': 'brain/$convId/walkthrough.md',
                'type': 'walkthrough',
                'last_modified': DateTime.now().toIso8601String(),
                'size_bytes': 1520,
                'request_feedback': false,
                'summary': 'Verification steps and feature demonstration.',
                'content': '''# Walkthrough: Verification Results

All tests completed successfully. Daemon status is active on port 7800.
''',
              },
            ],
          });
        });
        break;

      case 'get_artifact_content':
        final artName = payload['name']?.toString() ?? 'implementation_plan.md';
        Future.microtask(() {
          _eventController.add({
            'event': 'artifact_content',
            'name': artName,
            'content': artName.contains('plan')
                ? '''# Implementation Plan: Antigravity Remote Service

## User Review Required
> [!IMPORTANT]
> Headless daemon configuration requires Administrator privileges on Windows cmd.exe.

## Proposed Changes
### Core Daemon
- [x] Read & write `config.json`
- [x] Service Lifecycle monitoring

### Verification Plan
- [x] Run `flutter analyze`
- [ ] Connect mobile client and verify live streaming
'''
                : '# $artName\n\nArtifact generated by remote Antigravity session.',
          });
        });
        break;

      case 'run_diagnostics':
        Future.microtask(() {
          _eventController.add({
            'event': 'diagnostics_result',
            'checks': [
              {
                'id': 'diag_network',
                'category': 'Network & Connectivity',
                'title': 'Outbound Google Services Connectivity',
                'passed': true,
                'detail': 'Successfully connected to Google cloud APIs (latency: 42ms).',
                'recommended_action': null,
              },
              {
                'id': 'diag_auth',
                'category': 'Authentication',
                'title': 'Google Account Token Validity',
                'passed': true,
                'detail': 'Signed in as shahadsirius369@gmail.com with valid OAuth credentials.',
                'recommended_action': null,
              },
              {
                'id': 'diag_config',
                'category': 'Configuration & Naming',
                'title': 'Settings File Integrity & Precedence',
                'passed': true,
                'detail': 'Config valid at %USERPROFILE%\\.gemini\\config\\config.json. No CLI flag precedence conflict.',
                'recommended_action': null,
              },
              {
                'id': 'diag_ports',
                'category': 'Daemon Service',
                'title': 'Port & Process Health (7800 / 7801)',
                'passed': true,
                'detail': 'WebSocket and UDP auto-discovery listening without socket collision.',
                'recommended_action': null,
              },
              {
                'id': 'diag_shell',
                'category': 'Platform Compliance',
                'title': 'Windows Command Prompt (cmd.exe) Environment',
                'passed': true,
                'detail': 'Daemon running in compliant environment with Administrator privileges.',
                'recommended_action': null,
              },
            ],
          });
        });
        break;

      case 'list_quick_commands':
        Future.microtask(() {
          _eventController.add({
            'event': 'quick_commands_list',
            'custom_commands': [
              {
                'id': 'cmd_custom_lint',
                'title': 'Custom Dart Fix',
                'description': 'Run dart fix --apply on entire workspace.',
                'script': 'dart fix --apply',
                'category': 'custom',
                'requires_commit_message': false,
                'is_built_in': false,
                'icon_name': 'build_circle_outlined',
                'color_tag': 'amber',
              }
            ],
          });
        });
        break;

      case 'list_adb_devices':
        Future.microtask(() {
          _eventController.add({
            'event': 'adb_devices_list',
            'adb_available': true,
            'client_ip': '192.168.1.105',
            'devices': [
              {
                'serial': '192.168.1.105:5555',
                'status': 'device',
                'model': 'Pixel_8_Pro',
                'product': 'husky',
                'is_wireless': true,
              },
              {
                'serial': 'emulator-5554',
                'status': 'device',
                'model': 'Android_SDK_built_for_x86_64',
                'product': 'sdk_gphone64_x86_64',
                'is_wireless': false,
              },
            ],
          });
        });
        break;

      case 'connect_adb_device':
        final target = payload['target']?.toString() ?? '192.168.1.105:5555';
        Future.microtask(() {
          _eventController.add({
            'event': 'adb_connect_result',
            'success': true,
            'message': 'connected to $target',
            'devices': [
              {
                'serial': target,
                'status': 'device',
                'model': 'Pixel_8_Pro',
                'product': 'husky',
                'is_wireless': true,
              },
            ],
          });
        });
        break;

      case 'disconnect_adb_device':
        final target = payload['target']?.toString() ?? '192.168.1.105:5555';
        Future.microtask(() {
          _eventController.add({
            'event': 'adb_disconnect_result',
            'success': true,
            'message': 'disconnected $target',
            'devices': [],
          });
        });
        break;

      case 'exec_quick_command':
        final cmdId = payload['command_id']?.toString() ?? 'cmd_test';
        final rawScript = payload['script']?.toString() ?? 'git status';
        final commitMsg = payload['commit_message']?.toString() ?? 'Remote update';
        final devTarget = payload['device_target']?.toString() ?? '192.168.1.105:5555';

        final script = rawScript
            .replaceAll('{COMMIT_MESSAGE}', commitMsg)
            .replaceAll('{DEVICE_TARGET}', devTarget)
            .replaceAll('{DEVICE_IP}', '192.168.1.105');

        Future.microtask(() async {
          _eventController.add({
            'event': 'quick_command_started',
            'command_id': cmdId,
            'script': script,
            'cwd': '/workspace/flutter/agyremote',
            'timestamp': DateTime.now().toIso8601String(),
          });

          await Future.delayed(const Duration(milliseconds: 100));

          if (cmdId.contains('push')) {
            _eventController.add({
              'event': 'quick_command_output',
              'command_id': cmdId,
              'output': '[git] Staging modified files...\n',
            });
            await Future.delayed(const Duration(milliseconds: 150));
            _eventController.add({
              'event': 'quick_command_output',
              'command_id': cmdId,
              'output': '[git] commit -m "$commitMsg"\n[main 7f2a1b9] $commitMsg\n 3 files changed, 45 insertions(+), 12 deletions(-)\n',
            });
            await Future.delayed(const Duration(milliseconds: 150));
            _eventController.add({
              'event': 'quick_command_output',
              'command_id': cmdId,
              'output': '[git] Pushing to origin/main...\nTo github.com:proga4666/agyremote.git\n   3c1e5a2..7f2a1b9  main -> main\n',
            });
          } else if (cmdId.contains('build')) {
            _eventController.add({
              'event': 'quick_command_output',
              'command_id': cmdId,
              'output': 'Compiling Flutter APK (assembleDebug)...\n',
            });
            await Future.delayed(const Duration(milliseconds: 200));
            _eventController.add({
              'event': 'quick_command_output',
              'command_id': cmdId,
              'output': '✓ Built build/app/outputs/flutter-apk/app-debug.apk (32.4MB)\n',
            });
            await Future.delayed(const Duration(milliseconds: 150));
            _eventController.add({
              'event': 'quick_command_output',
              'command_id': cmdId,
              'output': 'Connecting to wireless device $devTarget...\nPerforming Streamed Install\nSuccess: APK installed on $devTarget\n',
            });
            await Future.delayed(const Duration(milliseconds: 150));
            _eventController.add({
              'event': 'quick_command_output',
              'command_id': cmdId,
              'output': '[git] Pushed build release to origin/main\n',
            });
          } else {
            _eventController.add({
              'event': 'quick_command_output',
              'command_id': cmdId,
              'output': 'Running: $script\nResolving dependencies...\nGot dependencies!\n',
            });
          }

          await Future.delayed(const Duration(milliseconds: 100));
          _eventController.add({
            'event': 'quick_command_finished',
            'command_id': cmdId,
            'return_code': 0,
            'success': true,
          });
        });
        break;

      case 'cancel_quick_command':
        final cmdId = payload['command_id']?.toString() ?? '';
        Future.microtask(() {
          _eventController.add({
            'event': 'quick_command_cancelled',
            'command_id': cmdId,
            'message': 'Command execution cancelled by user.',
          });
        });
        break;
    }
  }

  String? get convId => null;

  void _simulateAgentResponse(String? convId, String promptText) {
    Future.microtask(() {
      _eventController.add({
        'event': 'agent_stream',
        'conversation_id': convId,
        'chunk': 'Analyzing workspace structure and files...\n',
        'is_thought': true,
      });

      _eventController.add({
        'event': 'agent_stream',
        'conversation_id': convId,
        'chunk': 'I will execute your task: $promptText.\n\n```dart\nvoid main() {}\n```\n',
        'is_thought': false,
      });

      _eventController.add({
        'event': 'tool_approval_request',
        'conversation_id': convId,
        'approval': {
          'id': 'appr_${DateTime.now().millisecondsSinceEpoch}',
          'tool': 'terminal_exec',
          'command': 'flutter test',
          'description': 'Run local unit test suite',
        },
      });

      _eventController.add({
        'event': 'diff_artifact',
        'conversation_id': convId,
        'file_path': 'lib/core/network/bridge_client.dart',
        'diff': '''@@ -1,3 +1,4 @@
- class OldBridge {}
+ class BridgeClient {}''',
      });

      _eventController.add({
        'event': 'artifact_updated',
        'conversation_id': convId,
        'artifact': {
          'id': 'art_plan',
          'conversation_id': convId,
          'name': 'implementation_plan.md',
          'file_path': 'brain/$convId/implementation_plan.md',
          'type': 'plan',
          'last_modified': DateTime.now().toIso8601String(),
          'size_bytes': 2850,
          'request_feedback': true,
          'summary': 'Multi-step refactoring & test pipeline implementation plan.',
          'content': '''# Implementation Plan: Remote Refactoring Pipeline

## User Review Required
> [!IMPORTANT]
> Verify that the headless daemon service has appropriate file write permissions.

## Proposed Changes
- [x] Configure `cliRemoteControlHostname`
- [x] Service Lifecycle monitoring
- [ ] Connect mobile client and verify live streaming

## Verification Plan
- Run `flutter analyze`
- Run `flutter test`
''',
        },
      });
    });
  }
}
