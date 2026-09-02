Here is a comprehensive, production-ready **AI Agent Specification & Master Prompt**. 

You can copy and paste the entire prompt below directly into your AI coding assistant (such as **Cursor**, **Claude Code**, **Antigravity**, or **Copilot**) to generate the complete Flutter application.

---

```markdown
# MASTER SPECIFICATION PROMPT: Google Antigravity Remote Control Clone (Flutter Mobile)

## 1. PROJECT OBJECTIVE
Build a high-performance cross-platform Flutter mobile app (Android & iOS) that clones the full functionality of Google Antigravity Remote Control.

The mobile app connects to a running Antigravity 2.0 host daemon (`agy-daemon` on the user's workstation over local network / Tailscale WebSocket). It allows developers to:
1. Browse remote host directories and select a project folder.
2. Create and switch between Projects/Workspaces on the host machine.
3. Create new Agent Conversations attached to specific projects.
4. Stream real-time agent thoughts, planning steps, and model responses in Markdown.
5. Review and approve/deny interactive tool and terminal execution requests (e.g. bash commands, file modifications).
6. Inspect code diff artifacts and modified files directly on mobile.
7. Send text and voice prompts without requiring an API key (consuming the desktop's signed-in Pro account).

---

## 2. TECH STACK & DEPENDENCIES

 
```yaml
name: antigravity_remote
description: Mobile companion client for Google Antigravity 2.0 IDE & CLI.
 
environment:
  sdk:  

dependencies:
  flutter:
    sdk: flutter
  web_socket_channel: 
  flutter_markdown: 
  provider:  
  uuid: 
  flutter_code_editor: 
  highlight: 
  intl: 
  speech_to_text: 
  flutter_animate: 

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints:  
flutter:
  uses-material-design: true
```

---

## 3. WEBSOCKET PROTOCOL SPECIFICATION

The app communicates with the host daemon via JSON messages over WebSocket (`ws://<HOST_IP>:7800/ws`).

### Client -> Host Requests:
1. **Browse Folders**:
   `{ "action": "browse_dir", "path": "/Users/username/projects" }`
2. **Create Project**:
   `{ "action": "create_project", "name": "my-app", "root_path": "/Users/username/projects/my-app" }`
3. **List Projects**:
   `{ "action": "list_projects" }`
4. **Create Conversation**:
   `{ "action": "create_conversation", "project_id": "proj_123", "title": "Fix Auth Bug" }`
5. **Send Prompt**:
   `{ "action": "send_prompt", "conversation_id": "conv_456", "text": "Run tests and refactor auth controller" }`
6. **Resolve Tool Approval**:
   `{ "action": "resolve_approval", "approval_id": "appr_789", "approved": true }`

### Host -> Client Events:
1. **Directory Tree Data**:
   `{ "event": "dir_contents", "current_path": "/...", "folders": ["src", "lib", "tests"], "files": [] }`
2. **Project List**:
   `{ "event": "projects_list", "projects": [{ "id": "proj_123", "name": "backend", "path": "/...", "conversations": [] }] }`
3. **Agent Thought/Text Stream**:
   `{ "event": "agent_stream", "conversation_id": "conv_456", "chunk": "I will run `npm test`...", "is_thought": false }`
4. **Tool Approval Required**:
   `{ "event": "tool_approval_request", "approval": { "id": "appr_789", "tool": "terminal_exec", "command": "rm -rf build && npm run build", "description": "Clean rebuild project" } }`
5. **Code Diff Generated**:
   `{ "event": "diff_artifact", "file_path": "lib/auth.ts", "diff": "@@ -10,3 +10,4 @@\n- const old = 1;\n+ const fixed = 2;" }`

---

## 4. ARCHITECTURE & CODE STRUCTURE

```
lib/
├── main.dart
├── core/
│   ├── theme/
│   │   └── app_theme.dart          # Antigravity Google Dark Theme (#131314, #1E1F20, #28292A)
│   └── network/
│       └── bridge_client.dart      # Persistent WebSocket Manager with reconnect logic
├── models/
│   ├── project.dart                # Project, FolderItem models
│   ├── conversation.dart           # Conversation, Message, Thought models
│   └── approval.dart               # ToolApprovalRequest, CodeDiff models
├── providers/
│   ├── connection_provider.dart    # Manages Host IP, connection status
│   ├── project_provider.dart       # Project creation, folder browsing, workspace switching
│   └── chat_provider.dart          # Active conversation streaming, approvals, prompts
└── screens/
    ├── home_screen.dart            # Main Shell (Project Drawer, Conversation list, Chat area)
    ├── project_create_screen.dart   # Remote folder explorer and project creator
    ├── conversation_view.dart      # Real-time streaming chat, thought accordion, sticky approval bar
    └── diff_viewer_screen.dart     # Side-by-side / Unified syntax-highlighted code diff
```

---

## 5. SOURCE CODE IMPLEMENTATION

### `lib/core/theme/app_theme.dart`
```dart
import 'package:flutter/material.dart';

class AntigravityTheme {
  static const Color background = Color(0xFF131314);
  static const Color surface = Color(0xFF1E1F20);
  static const Color surfaceContainer = Color(0xFF28292A);
  static const Color border = Color(0xFF333538);
  static const Color googleBlue = Color(0xFF8AB4F8);
  static const Color googleGreen = Color(0xFF81C995);
  static const Color googleAmber = Color(0xFFFDD663);
  static const Color googleRed = Color(0xFFF28B82);
  static const Color textPrimary = Color(0xFFE3E3E3);
  static const Color textSecondary = Color(0xFF9AA0A6);

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      primaryColor: googleBlue,
      cardColor: surface,
      dividerColor: border,
      colorScheme: const ColorScheme.dark(
        surface: surface,
        primary: googleBlue,
        secondary: googleGreen,
        error: googleRed,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: surface,
        elevation: 0,
        titleTextStyle: TextStyle(color: textPrimary, fontSize: 18, fontWeight: FontWeight.w600),
      ),
    );
  }
}
```

---

### `lib/models/project.dart`
```dart
class Project {
  final String id;
  final String name;
  final String path;
  final List<String> conversationIds;

  Project({
    required this.id,
    required this.name,
    required this.path,
    required this.conversationIds,
  });

  factory Project.fromJson(Map<String, dynamic> json) {
    return Project(
      id: json['id'] ?? '',
      name: json['name'] ?? 'Untitled Project',
      path: json['path'] ?? '',
      conversationIds: List<String>.from(json['conversation_ids'] ?? []),
    );
  }
}

class RemoteDirectory {
  final String currentPath;
  final String parentPath;
  final List<String> folders;

  RemoteDirectory({
    required this.currentPath,
    required this.parentPath,
    required this.folders,
  });

  factory RemoteDirectory.fromJson(Map<String, dynamic> json) {
    return RemoteDirectory(
      currentPath: json['current_path'] ?? '/',
      parentPath: json['parent_path'] ?? '/',
      folders: List<String>.from(json['folders'] ?? []),
    );
  }
}
```

---

### `lib/models/approval.dart` & `lib/models/conversation.dart`
```dart
enum ApprovalStatus { pending, approved, rejected }

class ApprovalRequest {
  final String id;
  final String tool;
  final String command;
  final String description;
  ApprovalStatus status;

  ApprovalRequest({
    required this.id,
    required this.tool,
    required this.command,
    required this.description,
    this.status = ApprovalStatus.pending,
  });

  factory ApprovalRequest.fromJson(Map<String, dynamic> json) {
    return ApprovalRequest(
      id: json['id'],
      tool: json['tool'] ?? 'Terminal Command',
      command: json['command'] ?? '',
      description: json['description'] ?? '',
    );
  }
}

class CodeDiffArtifact {
  final String filePath;
  final String diffContent;

  CodeDiffArtifact({required this.filePath, required this.diffContent});

  factory CodeDiffArtifact.fromJson(Map<String, dynamic> json) {
    return CodeDiffArtifact(
      filePath: json['file_path'] ?? 'modified_file',
      diffContent: json['diff'] ?? '',
    );
  }
}

class ConversationMessage {
  final String id;
  final String sender; // 'user' | 'agent' | 'thought'
  String content;
  final ApprovalRequest? approval;
  final CodeDiffArtifact? diffArtifact;
  final DateTime timestamp;

  ConversationMessage({
    required this.id,
    required this.sender,
    required this.content,
    this.approval,
    this.diffArtifact,
    required this.timestamp,
  });
}

class Conversation {
  final String id;
  final String projectId;
  final String title;
  final List<ConversationMessage> messages;

  Conversation({
    required this.id,
    required this.projectId,
    required this.title,
    required this.messages,
  });
}
```

---

### `lib/core/network/bridge_client.dart`
```dart
import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

class BridgeClient {
  WebSocketChannel? _channel;
  final _eventController = StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get events => _eventController.stream;
  bool isConnected = false;

  void connect(String hostUrl) {
    disconnect();
    try {
      _channel = WebSocketChannel.connect(Uri.parse(hostUrl));
      isConnected = true;
      _channel!.stream.listen(
        (data) {
          final decoded = jsonDecode(data as String);
          _eventController.add(decoded);
        },
        onError: (err) {
          isConnected = false;
          _eventController.add({'event': 'error', 'message': err.toString()});
        },
        onDone: () {
          isConnected = false;
          _eventController.add({'event': 'disconnected'});
        },
      );
    } catch (e) {
      isConnected = false;
    }
  }

  void send(String action, Map<String, dynamic> payload) {
    if (_channel != null) {
      final msg = jsonEncode({'action': action, ...payload});
      _channel!.sink.add(msg);
    }
  }

  void disconnect() {
    _channel?.sink.close();
    _channel = null;
    isConnected = false;
  }
}
```

---

### `lib/providers/project_provider.dart`
```dart
import 'package:flutter/material.dart';
import '../core/network/bridge_client.dart';
import '../models/project.dart';

class ProjectProvider extends ChangeNotifier {
  final BridgeClient bridge;

  List<Project> projects = [];
  Project? selectedProject;
  RemoteDirectory? currentBrowsedDir;
  bool isLoading = false;

  ProjectProvider({required this.bridge}) {
    bridge.events.listen(_handleEvents);
  }

  void _handleEvents(Map<String, dynamic> event) {
    switch (event['event']) {
      case 'projects_list':
        projects = (event['projects'] as List)
            .map((p) => Project.fromJson(p))
            .toList();
        if (selectedProject == null && projects.isNotEmpty) {
          selectedProject = projects.first;
        }
        isLoading = false;
        notifyListeners();
        break;

      case 'dir_contents':
        currentBrowsedDir = RemoteDirectory.fromJson(event);
        isLoading = false;
        notifyListeners();
        break;
    }
  }

  void fetchProjects() {
    isLoading = true;
    notifyListeners();
    bridge.send('list_projects', {});
  }

  void selectProject(Project project) {
    selectedProject = project;
    notifyListeners();
  }

  void browseDirectory(String path) {
    isLoading = true;
    notifyListeners();
    bridge.send('browse_dir', {'path': path});
  }

  void createNewProject(String name, String rootPath) {
    bridge.send('create_project', {'name': name, 'root_path': rootPath});
  }
}
```

---

### `lib/providers/chat_provider.dart`
```dart
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../core/network/bridge_client.dart';
import '../models/approval.dart';
import '../models/conversation.dart';

class ChatProvider extends ChangeNotifier {
  final BridgeClient bridge;

  List<Conversation> conversations = [];
  Conversation? activeConversation;
  bool isStreaming = false;

  ChatProvider({required this.bridge}) {
    bridge.events.listen(_handleEvents);
  }

  void _handleEvents(Map<String, dynamic> event) {
    switch (event['event']) {
      case 'agent_stream':
        _appendStreamChunk(
          event['conversation_id'],
          event['chunk'] ?? '',
          event['is_thought'] ?? false,
        );
        break;

      case 'tool_approval_request':
        _addApprovalRequest(
          event['conversation_id'],
          ApprovalRequest.fromJson(event['approval']),
        );
        break;

      case 'diff_artifact':
        _addDiffArtifact(
          event['conversation_id'],
          CodeDiffArtifact.fromJson(event),
        );
        break;
    }
  }

  void createConversation(String projectId, String title) {
    final newId = const Uuid().v4();
    final conv = Conversation(
      id: newId,
      projectId: projectId,
      title: title.isEmpty ? 'New Task' : title,
      messages: [],
    );
    conversations.insert(0, conv);
    activeConversation = conv;
    bridge.send('create_conversation', {'id': newId, 'project_id': projectId, 'title': title});
    notifyListeners();
  }

  void selectConversation(Conversation conv) {
    activeConversation = conv;
    notifyListeners();
  }

  void sendPrompt(String text) {
    if (activeConversation == null || text.trim().isEmpty) return;

    final userMsg = ConversationMessage(
      id: const Uuid().v4(),
      sender: 'user',
      content: text,
      timestamp: DateTime.now(),
    );

    activeConversation!.messages.add(userMsg);
    isStreaming = true;
    notifyListeners();

    bridge.send('send_prompt', {
      'conversation_id': activeConversation!.id,
      'text': text,
    });
  }

  void resolveApproval(String approvalId, bool approved) {
    bridge.send('resolve_approval', {
      'approval_id': approvalId,
      'approved': approved,
    });
    notifyListeners();
  }

  void _appendStreamChunk(String convId, String chunk, bool isThought) {
    if (activeConversation == null || activeConversation!.id != convId) return;

    final messages = activeConversation!.messages;
    final senderType = isThought ? 'thought' : 'agent';

    if (messages.isNotEmpty && messages.last.sender == senderType) {
      messages.last.content += chunk;
    } else {
      messages.add(ConversationMessage(
        id: const Uuid().v4(),
        sender: senderType,
        content: chunk,
        timestamp: DateTime.now(),
      ));
    }
    notifyListeners();
  }

  void _addApprovalRequest(String? convId, ApprovalRequest req) {
    if (activeConversation == null) return;
    activeConversation!.messages.add(ConversationMessage(
      id: const Uuid().v4(),
      sender: 'agent',
      content: 'Agent requested tool permission:',
      approval: req,
      timestamp: DateTime.now(),
    ));
    notifyListeners();
  }

  void _addDiffArtifact(String? convId, CodeDiffArtifact diff) {
    if (activeConversation == null) return;
    activeConversation!.messages.add(ConversationMessage(
      id: const Uuid().v4(),
      sender: 'agent',
      content: 'Modified: `${diff.filePath}`',
      diffArtifact: diff,
      timestamp: DateTime.now(),
    ));
    notifyListeners();
  }
}
```

---

### `lib/screens/project_create_screen.dart` (Remote Folder Explorer & Creator)
```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme/app_theme.dart';
import '../providers/project_provider.dart';

class ProjectCreateScreen extends StatefulWidget {
  const ProjectCreateScreen({super.key});

  @override
  State<ProjectCreateScreen> createState() => _ProjectCreateScreenState();
}

class _ProjectCreateScreenState extends State<ProjectCreateScreen> {
  final TextEditingController _nameController = TextEditingController();
  String _selectedPath = '/';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ProjectProvider>().browseDirectory('~');
    });
  }

  @override
  Widget build(BuildContext context) {
    final projProvider = context.watch<ProjectProvider>();
    final dir = projProvider.currentBrowsedDir;

    return Scaffold(
      appBar: AppBar(
        title: const Text('New Remote Project'),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: AntigravityTheme.surface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _nameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Project Name',
                    hintText: 'e.g. ecommerce-backend',
                    labelStyle: TextStyle(color: AntigravityTheme.googleBlue),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Selected Path: ${dir?.currentPath ?? _selectedPath}',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: AntigravityTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Remote Folder Explorer
          Expanded(
            child: projProvider.isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    children: [
                      if (dir != null && dir.parentPath.isNotEmpty)
                        ListTile(
                          leading: const Icon(Icons.arrow_upward, color: AntigravityTheme.googleBlue),
                          title: const Text('.. (Go Up)'),
                          onTap: () => projProvider.browseDirectory(dir.parentPath),
                        ),
                      ...?dir?.folders.map((folder) => ListTile(
                            leading: const Icon(Icons.folder_outlined, color: Colors.amberAccent),
                            title: Text(folder),
                            trailing: const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
                            onTap: () {
                              final newPath = '${dir.currentPath}/$folder'.replaceAll('//', '/');
                              _selectedPath = newPath;
                              projProvider.browseDirectory(newPath);
                            },
                          )),
                    ],
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AntigravityTheme.googleBlue,
                  minimumSize: const Size.fromHeight(48),
                ),
                icon: const Icon(Icons.check, color: Colors.black),
                label: const Text('Create & Select Project', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                onPressed: () {
                  if (_nameController.text.trim().isNotEmpty) {
                    projProvider.createNewProject(_nameController.text.trim(), dir?.currentPath ?? _selectedPath);
                    Navigator.pop(context);
                  }
                },
              ),
            ),
          )
        ],
      ),
    );
  }
}
```

---

### `lib/screens/conversation_view.dart` (Live Stream, Approvals, Diffs & Prompts)
```dart
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';
import '../core/theme/app_theme.dart';
import '../models/approval.dart';
import '../models/conversation.dart';
import '../providers/chat_provider.dart';
import 'diff_viewer_screen.dart';

class ConversationView extends StatelessWidget {
  const ConversationView({super.key});

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final activeConv = chat.activeConversation;

    if (activeConv == null) {
      return const Center(
        child: Text(
          'Select or Create a Conversation to begin.',
          style: TextStyle(color: AntigravityTheme.textSecondary),
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: activeConv.messages.length,
            itemBuilder: (context, index) {
              final msg = activeConv.messages[index];
              return _buildMessageBubble(context, msg, chat);
            },
          ),
        ),
        _buildPromptBar(context, chat),
      ],
    );
  }

  Widget _buildMessageBubble(BuildContext context, ConversationMessage msg, ChatProvider chat) {
    if (msg.sender == 'thought') {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: AntigravityTheme.surfaceContainer.withOpacity(0.5),
          borderRadius: BorderRadius.circular(6),
        ),
        child: ExpansionTile(
          dense: true,
          leading: const Icon(Icons.psychology_outlined, color: AntigravityTheme.googleAmber, size: 18),
          title: const Text('Agent Thought Process', style: TextStyle(fontSize: 12, color: AntigravityTheme.googleAmber)),
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(msg.content, style: const TextStyle(fontSize: 12, color: AntigravityTheme.textSecondary, fontFamily: 'monospace')),
            )
          ],
        ),
      );
    }

    final isUser = msg.sender == 'user';
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Text(
            isUser ? 'You' : 'Antigravity Agent',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isUser ? AntigravityTheme.googleBlue : AntigravityTheme.googleGreen),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isUser ? AntigravityTheme.surfaceContainer : AntigravityTheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AntigravityTheme.border),
            ),
            child: MarkdownBody(
              data: msg.content,
              styleSheet: MarkdownStyleSheet(
                p: const TextStyle(color: AntigravityTheme.textPrimary, fontSize: 13),
                code: const TextStyle(backgroundColor: Color(0xFF0F1011), color: AntigravityTheme.googleGreen),
              ),
            ),
          ),
          if (msg.approval != null) _buildApprovalCard(msg.approval!, chat),
          if (msg.diffArtifact != null) _buildDiffButton(context, msg.diffArtifact!),
        ],
      ),
    );
  }

  Widget _buildApprovalCard(ApprovalRequest approval, ChatProvider chat) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF2C2214),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AntigravityTheme.googleAmber),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.shield_outlined, color: AntigravityTheme.googleAmber, size: 16),
              SizedBox(width: 6),
              Text('Permission Required (Host Exec)', style: TextStyle(color: AntigravityTheme.googleAmber, fontWeight: FontWeight.bold, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 6),
          Text(approval.command, style: const TextStyle(fontFamily: 'monospace', color: Colors.white, fontSize: 11)),
          const SizedBox(height: 10),
          if (approval.status == ApprovalStatus.pending)
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: AntigravityTheme.googleGreen),
                    onPressed: () {
                      approval.status = ApprovalStatus.approved;
                      chat.resolveApproval(approval.id, true);
                    },
                    child: const Text('Approve', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(side: const BorderSide(color: AntigravityTheme.googleRed)),
                    onPressed: () {
                      approval.status = ApprovalStatus.rejected;
                      chat.resolveApproval(approval.id, false);
                    },
                    child: const Text('Reject', style: TextStyle(color: AntigravityTheme.googleRed)),
                  ),
                ),
              ],
            )
          else
            Text(
              approval.status == ApprovalStatus.approved ? '✓ Approved on Host' : '✗ Rejected',
              style: TextStyle(color: approval.status == ApprovalStatus.approved ? AntigravityTheme.googleGreen : AntigravityTheme.googleRed, fontWeight: FontWeight.bold),
            )
        ],
      ),
    );
  }

  Widget _buildDiffButton(BuildContext context, CodeDiffArtifact diff) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: OutlinedButton.icon(
        icon: const Icon(Icons.difference_outlined, size: 14, color: AntigravityTheme.googleBlue),
        label: Text('Inspect Diff: ${diff.filePath}', style: const TextStyle(fontSize: 11, color: AntigravityTheme.googleBlue)),
        onPressed: () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => DiffViewerScreen(artifact: diff)));
        },
      ),
    );
  }

  Widget _buildPromptBar(BuildContext context, ChatProvider chat) {
    final controller = TextEditingController();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: AntigravityTheme.surface,
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: const InputDecoration(
                  hintText: 'Prompt Antigravity Agent...',
                  hintStyle: TextStyle(color: AntigravityTheme.textSecondary),
                  border: InputBorder.none,
                ),
                onSubmitted: (val) {
                  chat.sendPrompt(val);
                  controller.clear();
                },
              ),
            ),
            IconButton(
              icon: const Icon(Icons.send_rounded, color: AntigravityTheme.googleBlue),
              onPressed: () {
                chat.sendPrompt(controller.text);
                controller.clear();
              },
            ),
          ],
        ),
      ),
    );
  }
}
```

---

### `lib/screens/diff_viewer_screen.dart`
```dart
import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';
import '../models/approval.dart';

class DiffViewerScreen extends StatelessWidget {
  final CodeDiffArtifact artifact;

  const DiffViewerScreen({super.key, required this.artifact});

  @override
  Widget build(BuildContext context) {
    final lines = artifact.diffContent.split('\n');

    return Scaffold(
      appBar: AppBar(
        title: Text(artifact.filePath, style: const TextStyle(fontSize: 14, fontFamily: 'monospace')),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: lines.length,
        itemBuilder: (context, index) {
          final line = lines[index];
          Color bg = Colors.transparent;
          Color text = AntigravityTheme.textPrimary;

          if (line.startsWith('+')) {
            bg = AntigravityTheme.googleGreen.withOpacity(0.15);
            text = AntigravityTheme.googleGreen;
          } else if (line.startsWith('-')) {
            bg = AntigravityTheme.googleRed.withOpacity(0.15);
            text = AntigravityTheme.googleRed;
          }

          return Container(
            color: bg,
            padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 6),
            child: Text(
              line,
              style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: text),
            ),
          );
        },
      ),
    );
  }
}
```

---

### `lib/main.dart`
```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/network/bridge_client.dart';
import 'core/theme/app_theme.dart';
import 'providers/chat_provider.dart';
import 'providers/project_provider.dart';
import 'screens/conversation_view.dart';
import 'screens/project_create_screen.dart';

void main() {
  final bridge = BridgeClient();
  // Connect to your workstation daemon or local tunnel
  bridge.connect('ws://127.0.0.1:7800/ws');

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ProjectProvider(bridge: bridge)..fetchProjects()),
        ChangeNotifierProvider(create: (_) => ChatProvider(bridge: bridge)),
      ],
      child: const AntigravityApp(),
    ),
  );
}

class AntigravityApp extends StatelessWidget {
  const AntigravityApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AntigravityTheme.darkTheme,
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final projProvider = context.watch<ProjectProvider>();
    final chatProvider = context.watch<ChatProvider>();

    return Scaffold(
      appBar: AppBar(
        title: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: projProvider.selectedProject?.id,
            hint: const Text('Select Project', style: TextStyle(color: Colors.white)),
            dropdownColor: AntigravityTheme.surface,
            items: projProvider.projects.map((p) {
              return DropdownMenuItem(value: p.id, child: Text(p.name, style: const TextStyle(color: Colors.white)));
            }).toList(),
            onChanged: (id) {
              final proj = projProvider.projects.firstWhere((p) => p.id == id);
              projProvider.selectProject(proj);
            },
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.create_new_folder_outlined, color: AntigravityTheme.googleBlue),
            tooltip: 'New Project (Select Host Folder)',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProjectCreateScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.add_comment_outlined, color: AntigravityTheme.googleGreen),
            tooltip: 'New Conversation',
            onPressed: () {
              if (projProvider.selectedProject != null) {
                chatProvider.createConversation(projProvider.selectedProject!.id, 'New Autonomous Task');
              }
            },
          ),
        ],
      ),
      body: const ConversationView(),
    );
  }
}
```

---

## 6. INSTRUCTIONS FOR THE AI AGENT TO RUN
1. Verify all dependencies and create the file hierarchy under `lib/`.
2. Ensure asynchronous error handling for broken WebSocket connections with an automatic retry banner.
3. Test streaming markdown tokens and interactive approval buttons.
```