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

      case 'create_conversation':
        final convId = payload['id'] ?? 'conv_${DateTime.now().millisecondsSinceEpoch}';
        final projId = payload['project_id'] ?? 'proj_agy_core';
        final title = payload['title'] ?? 'Autonomous Task';

        Future.microtask(() {
          _eventController.add({
            'event': 'conversation_created',
            'conversation': {
              'id': convId,
              'project_id': projId,
              'title': title,
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
    });
  }
}
