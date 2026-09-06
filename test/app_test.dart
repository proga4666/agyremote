import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:agyremote/core/network/bridge_client.dart';
import 'package:agyremote/core/theme/app_theme.dart';
import 'package:agyremote/models/approval.dart';
import 'package:agyremote/models/artifact.dart';
import 'package:agyremote/models/conversation.dart';
import 'package:agyremote/models/daemon_status.dart';
import 'package:agyremote/models/project.dart';
import 'package:agyremote/models/quick_command.dart';
import 'package:agyremote/providers/chat_provider.dart';
import 'package:agyremote/providers/connection_provider.dart';
import 'package:agyremote/providers/project_provider.dart';
import 'package:agyremote/providers/quick_command_provider.dart';
import 'package:agyremote/screens/daemon_dashboard_screen.dart';
import 'package:agyremote/screens/diff_viewer_screen.dart';
import 'package:agyremote/screens/home_screen.dart';
import 'package:agyremote/screens/plan_inspector_screen.dart';
import 'package:agyremote/screens/project_create_screen.dart';
import 'package:agyremote/widgets/adb_device_sheet.dart';

void main() {
  group('Models Unit Tests', () {
    test('Project and RemoteDirectory parsing', () {
      final proj = Project.fromJson({
        'id': 'p1',
        'name': 'Test Project',
        'path': '/workspace/test',
        'conversation_ids': ['c1', 'c2'],
      });
      expect(proj.id, 'p1');
      expect(proj.name, 'Test Project');
      expect(proj.conversationIds.length, 2);

      final dir = RemoteDirectory.fromJson({
        'current_path': '/workspace',
        'parent_path': '/',
        'folders': ['lib', 'test'],
        'files': ['pubspec.yaml'],
      });
      expect(dir.currentPath, '/workspace');
      expect(dir.folders.contains('lib'), true);
      expect(dir.files.contains('pubspec.yaml'), true);
    });

    test('ApprovalRequest and CodeDiffArtifact parsing', () {
      final appr = ApprovalRequest.fromJson({
        'id': 'appr_1',
        'tool': 'terminal_exec',
        'command': 'npm test',
        'description': 'Run tests',
      });
      expect(appr.id, 'appr_1');
      expect(appr.status, ApprovalStatus.pending);

      final diff = CodeDiffArtifact.fromJson({
        'file_path': 'lib/main.dart',
        'diff': '@@ -1,3 +1,4 @@\n- old\n+ new\n+ added',
      });
      expect(diff.filePath, 'lib/main.dart');
      expect(diff.additions, 2);
      expect(diff.deletions, 1);
    });

    test('Conversation and Message parsing with ConversationSource tabs', () {
      final msg = ConversationMessage.fromJson({
        'id': 'm1',
        'sender': 'user',
        'content': 'Fix bug',
      });
      expect(msg.id, 'm1');
      expect(msg.sender, 'user');
      expect(msg.content, 'Fix bug');

      // Antigravity 2.0 Daemon conversation
      final daemonConv = Conversation.fromJson({
        'id': 'c_daemon',
        'project_id': 'p1',
        'title': 'Autonomous Fix',
        'source': 'daemon',
        'engine': 'Antigravity 2.0',
        'messages': [msg.toJson()],
      });
      expect(daemonConv.id, 'c_daemon');
      expect(daemonConv.isDaemon, true);
      expect(daemonConv.isDesktopIde, false);
      expect(daemonConv.sourceLabel, 'Antigravity 2.0');

      // Antigravity Desktop IDE conversation
      final ideConv = Conversation.fromJson({
        'id': 'c_ide',
        'project_id': 'p1',
        'title': 'IDE Code Polish',
        'source': 'desktop_ide',
        'engine': 'Desktop IDE',
        'messages': [msg.toJson()],
      });
      expect(ideConv.id, 'c_ide');
      expect(ideConv.isDaemon, false);
      expect(ideConv.isDesktopIde, true);
      expect(ideConv.sourceLabel, 'Desktop IDE');
    });

    test('BrainArtifact and DaemonStatusInfo parsing', () {
      final art = BrainArtifact.fromJson({
        'name': 'implementation_plan.md',
        'conversation_id': 'c1',
        'type': 'plan',
        'request_feedback': true,
      });
      expect(art.type, ArtifactType.plan);
      expect(art.requestFeedback, true);

      final status = DaemonStatusInfo.fromJson({
        'status': 'online',
        'uptime_seconds': 7200,
        'pid': 1234,
        'platform': 'Windows',
        'cli_remote_control_hostname': 'box-daemon',
        'remote_control_hostname': 'box-desktop',
        'update_interval': 'daily',
        'has_cli_name_override': false,
        'auth_account': 'test@google.com',
        'is_authenticated': true,
      });
      expect(status.cliHostname, 'box-daemon');
      expect(status.desktopHostname, 'box-desktop');
      expect(status.formattedUptime, '2h 0m 0s');

      final matrix = ServiceLifecycleEntry.getMatrix('Windows');
      expect(matrix.length, 3);
      expect(matrix.any((m) => m.isCurrentOs && m.osName == 'Windows'), true);
    });

    test('QuickCommand and AdbDevice model parsing', () {
      final cmd = QuickCommand.fromJson({
        'id': 'cmd_git_push',
        'title': 'Git Push',
        'description': 'Stage, commit and push',
        'script': 'git add . && git commit -m "{COMMIT_MESSAGE}" && git push',
        'category': 'git',
        'requires_commit_message': true,
        'is_built_in': true,
      });
      expect(cmd.id, 'cmd_git_push');
      expect(cmd.requiresCommitMessage, true);
      expect(cmd.isBuiltIn, true);

      final builtIns = QuickCommand.defaultBuiltInCommands;
      expect(builtIns.any((c) => c.id == 'cmd_git_push'), true);
      expect(builtIns.any((c) => c.id == 'cmd_build_apk_push'), true);

      final dev = AdbDevice.fromJson({
        'serial': '192.168.1.50:5555',
        'status': 'device',
        'model': 'Pixel_7_Pro',
        'is_wireless': true,
      });
      expect(dev.isWireless, true);
      expect(dev.isConnected, true);
      expect(dev.displayName, 'Pixel 7 Pro');
    });
  });

  group('Provider & Simulator Tests', () {
    test('ProjectProvider handles simulated directory and projects', () async {
      final bridge = BridgeClient();
      bridge.connect('ws://127.0.0.1:7800/ws', forceMock: true);

      final projProvider = ProjectProvider(bridge: bridge);
      projProvider.fetchProjects();

      await Future.delayed(const Duration(milliseconds: 50));
      expect(projProvider.projects.isNotEmpty, true);
      expect(projProvider.selectedProject, isNotNull);

      projProvider.browseDirectory('/workspace');
      await Future.delayed(const Duration(milliseconds: 50));
      expect(projProvider.currentBrowsedDir, isNotNull);

      bridge.disconnect();
    });

    test('ChatProvider handles conversation creation, prompts, and streaming', () async {
      final bridge = BridgeClient();
      bridge.connect('ws://127.0.0.1:7800/ws', forceMock: true);

      final chat = ChatProvider(bridge: bridge);
      final conv = chat.createConversation('proj_agy_core', 'Unit Test Task');
      expect(chat.activeConversation?.id, conv.id);

      chat.sendPrompt('Refactor auth controller');
      expect(chat.activeConversation!.messages.any((m) => m.sender == 'user'), true);

      await Future.delayed(const Duration(milliseconds: 50));
      expect(chat.activeConversation!.messages.length, greaterThan(1));

      bridge.disconnect();
    });

    test('ChatProvider filters conversations by ConversationSource tab', () async {
      final bridge = BridgeClient();
      bridge.connect('ws://127.0.0.1:7800/ws', forceMock: true);

      final chat = ChatProvider(bridge: bridge);
      await Future.delayed(const Duration(milliseconds: 50));

      // In mock mode, we populated both daemon and desktop_ide sessions
      expect(chat.daemonConversations.isNotEmpty, true);
      expect(chat.desktopIdeConversations.isNotEmpty, true);

      chat.setSourceFilter(ConversationSource.daemon);
      final daemonOnly = chat.getConversationsForProject(null);
      expect(daemonOnly.every((c) => c.isDaemon), true);

      chat.setSourceFilter(ConversationSource.desktopIde);
      final ideOnly = chat.getConversationsForProject(null);
      expect(ideOnly.every((c) => c.isDesktopIde), true);

      chat.setSourceFilter(null);
      final allConvs = chat.getConversationsForProject(null);
      expect(allConvs.length, greaterThanOrEqualTo(daemonOnly.length + ideOnly.length));

      bridge.disconnect();
    });

    test('QuickCommandProvider handles direct host terminal execution (without AI)', () async {
      final bridge = BridgeClient();
      bridge.connect('ws://127.0.0.1:7800/ws', forceMock: true);

      final quick = QuickCommandProvider(bridge: bridge);
      await Future.delayed(const Duration(milliseconds: 50));

      expect(quick.allCommands.isNotEmpty, true);

      final gitPush = quick.allCommands.firstWhere((c) => c.id == 'cmd_git_push');
      quick.runCommand(gitPush, projectId: 'proj_agyremote', commitMessage: 'test commit');

      expect(quick.isExecuting, true);
      expect(quick.activeExecution?.commandId, 'cmd_git_push');

      // Wait for simulated streaming execution
      await Future.delayed(const Duration(milliseconds: 600));

      expect(quick.isExecuting, false);
      expect(quick.activeExecution?.status, ExecutionStatus.success);
      expect(quick.activeExecution?.logs.any((l) => l.contains('[git]')), true);

      bridge.disconnect();
    });

    test('QuickCommandProvider handles ADB devices listing, connect, and disconnect', () async {
      final bridge = BridgeClient();
      bridge.connect('ws://127.0.0.1:7800/ws', forceMock: true);

      final quick = QuickCommandProvider(bridge: bridge);
      await Future.delayed(const Duration(milliseconds: 50));

      expect(quick.adbDevices.isNotEmpty, true);
      expect(quick.selectedAdbDevice, isNotNull);

      quick.connectAdbDevice('192.168.1.200:5555');
      await Future.delayed(const Duration(milliseconds: 50));
      expect(quick.adbDevices.any((d) => d.serial == '192.168.1.200:5555'), true);

      quick.disconnectAdbDevice('192.168.1.200:5555');
      await Future.delayed(const Duration(milliseconds: 50));

      bridge.disconnect();
    });
  });

  group('Widget Tests', () {
    testWidgets('DiffViewerScreen renders diff lines and stats', (tester) async {
      final diff = CodeDiffArtifact(
        filePath: 'lib/auth/service.dart',
        diffContent: '@@ -1,2 +1,3 @@\n- var x = 1;\n+ var x = 2;\n+ var y = 3;',
        additions: 2,
        deletions: 1,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AntigravityTheme.darkTheme,
          home: DiffViewerScreen(artifact: diff),
        ),
      );

      expect(find.text('service.dart'), findsOneWidget);
      expect(find.text('+2'), findsOneWidget);
      expect(find.text('-1'), findsOneWidget);
      expect(find.textContaining('var x = 2;'), findsOneWidget);
    });

    testWidgets('HomeScreen renders with providers and quick commands bar', (tester) async {
      final bridge = BridgeClient();
      bridge.connect('ws://127.0.0.1:7800/ws', forceMock: true);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => ConnectionProvider(bridge: bridge)),
            ChangeNotifierProvider(create: (_) => ProjectProvider(bridge: bridge)..fetchProjects()),
            ChangeNotifierProvider(create: (_) => ChatProvider(bridge: bridge)),
            ChangeNotifierProvider(create: (_) => QuickCommandProvider(bridge: bridge)),
          ],
          child: MaterialApp(
            theme: AntigravityTheme.darkTheme,
            home: const HomeScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byIcon(Icons.more_vert), findsOneWidget);
      expect(find.byIcon(Icons.add_comment_outlined), findsOneWidget);
      expect(find.text('Push'), findsOneWidget);
      expect(find.text('Build & Push'), findsOneWidget);
      expect(find.text('Pub Get'), findsOneWidget);
      expect(find.text('Test'), findsOneWidget);

      bridge.disconnect();
    });

    testWidgets('ProjectCreateScreen renders inputs', (tester) async {
      final bridge = BridgeClient();
      bridge.connect('ws://127.0.0.1:7800/ws', forceMock: true);

      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => ProjectProvider(bridge: bridge),
          child: MaterialApp(
            theme: AntigravityTheme.darkTheme,
            home: const ProjectCreateScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('Create Remote Project'), findsOneWidget);
      expect(find.text('Project Name'), findsOneWidget);
      expect(find.text('Create & Select Project'), findsOneWidget);

      bridge.disconnect();
    });

    testWidgets('PlanInspectorScreen renders plan and walkthrough', (tester) async {
      final plan = BrainArtifact(
        id: 'art_1',
        conversationId: 'c1',
        name: 'implementation_plan.md',
        filePath: 'brain/c1/implementation_plan.md',
        type: ArtifactType.plan,
        lastModified: DateTime.now(),
        content: '# Implementation Plan\n\n## User Review Required\n> [!IMPORTANT]\n> Test notice\n\n- [ ] Task 1',
      );

      final bridge = BridgeClient();
      bridge.connect('ws://127.0.0.1:7800/ws', forceMock: true);

      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => ChatProvider(bridge: bridge),
          child: MaterialApp(
            theme: AntigravityTheme.darkTheme,
            home: PlanInspectorScreen(initialArtifact: plan),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('implementation_plan.md'), findsOneWidget);
      expect(find.text('Approve & Execute'), findsOneWidget);
      expect(find.text('Request Changes'), findsOneWidget);

      bridge.disconnect();
    });

    testWidgets('DaemonDashboardScreen renders service info and diagnostic controls', (tester) async {
      final bridge = BridgeClient();
      bridge.connect('ws://127.0.0.1:7800/ws', forceMock: true);

      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => ConnectionProvider(bridge: bridge),
          child: MaterialApp(
            theme: AntigravityTheme.darkTheme,
            home: const DaemonDashboardScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('Daemon Service Manager'), findsOneWidget);
      expect(find.text('SERVICE ACTIVE'), findsOneWidget);
      expect(find.text('MACHINE NAMING & CONFIGURATION'), findsOneWidget);
      expect(find.text('GOOGLE SIGN-IN & AUTHENTICATION'), findsOneWidget);
      expect(find.text('REMOTE TROUBLESHOOTING & DIAGNOSTICS'), findsOneWidget);

      bridge.disconnect();
    });

    testWidgets('AdbDeviceSheet renders available devices and controls', (tester) async {
      final bridge = BridgeClient();
      bridge.connect('ws://127.0.0.1:7800/ws', forceMock: true);

      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => QuickCommandProvider(bridge: bridge),
          child: const MaterialApp(
            themeMode: ThemeMode.dark,
            home: Scaffold(body: AdbDeviceSheet()),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('WIRELESS DEBUG & ADB DEVICES'), findsOneWidget);
      expect(find.text('WIRELESS CONNECT & DISCONNECT'), findsOneWidget);
      expect(find.text('Connect'), findsOneWidget);
      expect(find.text('Disconnect'), findsWidgets);

      bridge.disconnect();
    });
  });
}
