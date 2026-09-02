import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:agyremote/core/network/bridge_client.dart';
import 'package:agyremote/core/theme/app_theme.dart';
import 'package:agyremote/models/approval.dart';
import 'package:agyremote/models/conversation.dart';
import 'package:agyremote/models/project.dart';
import 'package:agyremote/providers/chat_provider.dart';
import 'package:agyremote/providers/connection_provider.dart';
import 'package:agyremote/providers/project_provider.dart';
import 'package:agyremote/screens/diff_viewer_screen.dart';
import 'package:agyremote/screens/home_screen.dart';
import 'package:agyremote/screens/project_create_screen.dart';

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

    test('Conversation and Message parsing', () {
      final msg = ConversationMessage.fromJson({
        'id': 'm1',
        'sender': 'user',
        'content': 'Fix bug',
      });
      expect(msg.id, 'm1');
      expect(msg.sender, 'user');
      expect(msg.content, 'Fix bug');

      final conv = Conversation.fromJson({
        'id': 'c1',
        'project_id': 'p1',
        'title': 'Autonomous Fix',
        'messages': [msg.toJson()],
      });
      expect(conv.id, 'c1');
      expect(conv.messages.length, 1);
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

    testWidgets('HomeScreen renders with providers', (tester) async {
      final bridge = BridgeClient();
      bridge.connect('ws://127.0.0.1:7800/ws', forceMock: true);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => ConnectionProvider(bridge: bridge)),
            ChangeNotifierProvider(create: (_) => ProjectProvider(bridge: bridge)..fetchProjects()),
            ChangeNotifierProvider(create: (_) => ChatProvider(bridge: bridge)),
          ],
          child: MaterialApp(
            theme: AntigravityTheme.darkTheme,
            home: const HomeScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byIcon(Icons.create_new_folder_outlined), findsOneWidget);
      expect(find.byIcon(Icons.add_comment_outlined), findsOneWidget);

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
  });
}
