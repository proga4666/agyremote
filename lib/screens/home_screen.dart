import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../core/theme/app_theme.dart';
import '../models/conversation.dart';
import '../models/project.dart';
import '../providers/chat_provider.dart';
import '../providers/connection_provider.dart';
import '../providers/project_provider.dart';
import 'connection_dialog.dart';
import 'conversation_view.dart';
import 'project_create_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final proj = context.read<ProjectProvider>().selectedProject;
      if (proj != null) {
        context.read<ChatProvider>().syncWithSelectedProject(proj.id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final projProvider = context.watch<ProjectProvider>();
    final chatProvider = context.watch<ChatProvider>();
    final connProvider = context.watch<ConnectionProvider>();

    // Keep chat provider in sync with selected project
    if (projProvider.selectedProject != null &&
        chatProvider.activeConversation?.projectId != projProvider.selectedProject!.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        chatProvider.syncWithSelectedProject(projProvider.selectedProject!.id);
      });
    }

    return Scaffold(
      backgroundColor: AntigravityTheme.background,
      appBar: AppBar(
        titleSpacing: 0,
        title: _buildProjectSelector(context, projProvider, chatProvider),
        actions: [
          // New Project Button
          IconButton(
            icon: const Icon(Icons.create_new_folder_outlined, color: AntigravityTheme.googleBlue),
            tooltip: 'New Project (Select Host Folder)',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProjectCreateScreen()),
              );
            },
          ),
          // New Conversation Button
          IconButton(
            icon: const Icon(Icons.add_comment_outlined, color: AntigravityTheme.googleGreen),
            tooltip: 'New Task / Session',
            onPressed: () => _showNewConversationDialog(context, projProvider, chatProvider),
          ),
          // Connection Dialog Button
          IconButton(
            icon: Icon(
              Icons.sensors,
              color: connProvider.isConnected
                  ? AntigravityTheme.googleGreen
                  : AntigravityTheme.googleAmber,
            ),
            tooltip: 'Daemon Bridge Settings',
            onPressed: () => ConnectionDialog.show(context),
          ),
        ],
      ),
      drawer: _buildDrawer(context, projProvider, chatProvider, connProvider),
      body: Column(
        children: [
          if (!connProvider.isConnected) _buildDisconnectedBanner(context, connProvider),
          const Expanded(child: ConversationView()),
        ],
      ),
    );
  }

  Widget _buildDisconnectedBanner(BuildContext context, ConnectionProvider conn) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AntigravityTheme.googleRed.withValues(alpha: 0.15),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: AntigravityTheme.googleRed, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Disconnected from host daemon (${conn.hostAddress}:${conn.port})',
              style: const TextStyle(fontSize: 12, color: AntigravityTheme.googleRed, fontWeight: FontWeight.w500),
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () => conn.reconnect(),
            child: const Text('Retry', style: TextStyle(color: AntigravityTheme.googleBlue, fontWeight: FontWeight.bold, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildProjectSelector(BuildContext context, ProjectProvider projProvider, ChatProvider chatProvider) {
    if (projProvider.projects.isEmpty) {
      return TextButton.icon(
        onPressed: () => projProvider.fetchProjects(),
        icon: const Icon(Icons.sync, size: 16, color: AntigravityTheme.googleBlue),
        label: const Text('Fetch Projects', style: TextStyle(color: Colors.white, fontSize: 14)),
      );
    }

    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: projProvider.selectedProject?.id,
        isExpanded: true,
        dropdownColor: AntigravityTheme.surfaceContainer,
        icon: const Icon(Icons.arrow_drop_down, color: AntigravityTheme.googleBlue),
        items: projProvider.projects.map((Project p) {
          final activeTask = chatProvider.activeConversation?.title;
          return DropdownMenuItem<String>(
            value: p.id,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        p.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (activeTask != null && p.id == projProvider.selectedProject?.id) ...[
                      const Text(' • ', style: TextStyle(color: AntigravityTheme.textSecondary, fontSize: 11)),
                      Flexible(
                        child: Text(
                          activeTask,
                          style: const TextStyle(color: AntigravityTheme.googleGreen, fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  p.path,
                  style: const TextStyle(
                    color: AntigravityTheme.textSecondary,
                    fontSize: 10,
                    fontFamily: 'monospace',
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          );
        }).toList(),
        onChanged: (selectedId) {
          if (selectedId != null) {
            projProvider.selectProjectById(selectedId);
            chatProvider.syncWithSelectedProject(selectedId);
          }
        },
      ),
    );
  }

  Widget _buildDrawer(
    BuildContext context,
    ProjectProvider projProvider,
    ChatProvider chatProvider,
    ConnectionProvider connProvider,
  ) {
    final activeProj = projProvider.selectedProject;

    return Drawer(
      backgroundColor: AntigravityTheme.surface,
      child: SafeArea(
        child: Column(
          children: [
            // Drawer Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AntigravityTheme.border)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AntigravityTheme.googleBlue.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.rocket_launch, color: AntigravityTheme.googleBlue, size: 20),
                      ),
                      const SizedBox(width: 10),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ANTIGRAVITY',
                            style: TextStyle(
                              letterSpacing: 1.2,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            'Remote Control Companion',
                            style: TextStyle(fontSize: 11, color: AntigravityTheme.textSecondary),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Connection badge
                  InkWell(
                    onTap: () {
                      Navigator.pop(context);
                      ConnectionDialog.show(context);
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
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
                              shape: BoxShape.circle,
                              color: connProvider.isConnected
                                  ? AntigravityTheme.googleGreen
                                  : AntigravityTheme.googleRed,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              connProvider.statusMessage,
                              style: const TextStyle(fontSize: 11, color: AntigravityTheme.textPrimary),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const Icon(Icons.settings_outlined, size: 14, color: AntigravityTheme.textSecondary),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Scrollable Grouped Content
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  _buildSectionHeader(
                    title: 'WORKSPACE PROJECTS & SESSIONS',
                    actionLabel: '+ Add Folder',
                    onAction: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ProjectCreateScreen()),
                      );
                    },
                  ),
                  const SizedBox(height: 4),

                  if (projProvider.projects.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Text(
                        'No workspace folders found. Tap "+ Add Folder" to connect a project.',
                        style: TextStyle(fontSize: 12, color: AntigravityTheme.textMuted),
                      ),
                    )
                  else
                    ...projProvider.projects.map((Project p) {
                      final isSelectedProj = p.id == activeProj?.id;
                      final convs = chatProvider.getConversationsForProject(p.id);

                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        child: Material(
                          color: isSelectedProj
                              ? AntigravityTheme.surfaceContainerHigh
                              : AntigravityTheme.surfaceContainer.withValues(alpha: 0.5),
                          clipBehavior: Clip.antiAlias,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(
                              color: isSelectedProj
                                  ? AntigravityTheme.googleBlue.withValues(alpha: 0.4)
                                  : AntigravityTheme.borderSubtle,
                            ),
                          ),
                          child: Theme(
                            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                            child: ExpansionTile(
                              dense: true,
                              initiallyExpanded: isSelectedProj,
                              leading: Icon(
                                isSelectedProj ? Icons.folder_open_rounded : Icons.folder_rounded,
                                color: isSelectedProj
                                    ? AntigravityTheme.googleBlue
                                    : AntigravityTheme.googleAmber,
                                size: 22,
                              ),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      p.name,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: isSelectedProj ? FontWeight.bold : FontWeight.w600,
                                        color: isSelectedProj ? AntigravityTheme.googleBlue : Colors.white,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AntigravityTheme.surface,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: AntigravityTheme.borderSubtle),
                                    ),
                                    child: Text(
                                      '${convs.length}',
                                      style: const TextStyle(fontSize: 10, color: AntigravityTheme.textSecondary, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Text(
                                p.path,
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: AntigravityTheme.textMuted,
                                  fontFamily: 'monospace',
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              children: [
                                Container(
                                  color: const Color(0xFF101112),
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  child: Column(
                                    children: [
                                      if (convs.isEmpty)
                                        const Padding(
                                          padding: EdgeInsets.all(12),
                                          child: Text(
                                            'No sessions in this folder yet.',
                                            style: TextStyle(fontSize: 11, color: AntigravityTheme.textMuted),
                                          ),
                                        )
                                      else
                                        ...convs.map((Conversation c) {
                                          final isCurrentConv = c.id == chatProvider.activeConversation?.id;
                                          return ListTile(
                                            dense: true,
                                            selected: isCurrentConv,
                                            selectedTileColor: AntigravityTheme.googleGreen.withValues(alpha: 0.12),
                                            leading: Icon(
                                              Icons.chat_bubble_outline_rounded,
                                              color: isCurrentConv ? AntigravityTheme.googleGreen : AntigravityTheme.textSecondary,
                                              size: 16,
                                            ),
                                            title: Text(
                                              c.title,
                                              style: TextStyle(
                                                fontSize: 12.5,
                                                fontWeight: isCurrentConv ? FontWeight.bold : FontWeight.normal,
                                                color: isCurrentConv ? AntigravityTheme.googleGreen : AntigravityTheme.textPrimary,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            subtitle: Text(
                                              '${c.messages.length} msgs • ${DateFormat('MMM d, HH:mm').format(c.createdAt)}',
                                              style: const TextStyle(fontSize: 9.5, color: AntigravityTheme.textMuted),
                                            ),
                                            trailing: convs.length > 1
                                                ? IconButton(
                                                    icon: const Icon(Icons.close, size: 14, color: AntigravityTheme.textMuted),
                                                    tooltip: 'Delete session',
                                                    onPressed: () => chatProvider.deleteConversation(c.id),
                                                  )
                                                : null,
                                            onTap: () {
                                              projProvider.selectProject(p);
                                              chatProvider.selectConversation(c);
                                              Navigator.pop(context);
                                            },
                                          );
                                        }),
                                      // Quick Add Session Button for this folder
                                      Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                        child: InkWell(
                                          onTap: () {
                                            Navigator.pop(context);
                                            projProvider.selectProject(p);
                                            _showNewConversationDialog(context, projProvider, chatProvider);
                                          },
                                          borderRadius: BorderRadius.circular(6),
                                          child: Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.symmetric(vertical: 6),
                                            decoration: BoxDecoration(
                                              color: AntigravityTheme.surfaceContainerHigh,
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(color: AntigravityTheme.borderSubtle),
                                            ),
                                            child: Row(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                const Icon(Icons.add, size: 14, color: AntigravityTheme.googleBlue),
                                                const SizedBox(width: 6),
                                                Text(
                                                  'New Session in ${p.name}',
                                                  style: const TextStyle(fontSize: 11, color: AntigravityTheme.googleBlue, fontWeight: FontWeight.w600),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AntigravityTheme.border)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 16, color: AntigravityTheme.textMuted),
                  const SizedBox(width: 8),
                  const Text('Google Antigravity 2.0 Client', style: TextStyle(fontSize: 11, color: AntigravityTheme.textMuted)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 16, color: AntigravityTheme.textSecondary),
                    tooltip: 'Refresh Projects',
                    onPressed: () => projProvider.fetchProjects(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader({
    required String title,
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 11,
                letterSpacing: 0.5,
                fontWeight: FontWeight.bold,
                color: AntigravityTheme.textSecondary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          InkWell(
            onTap: onAction,
            child: Text(
              actionLabel,
              style: const TextStyle(fontSize: 11, color: AntigravityTheme.googleBlue, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  void _showNewConversationDialog(
    BuildContext context,
    ProjectProvider projProvider,
    ChatProvider chatProvider,
  ) {
    final titleController = TextEditingController();
    final currentProj = projProvider.selectedProject;

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Start New Autonomous Task', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Target Project: ${currentProj?.name ?? "None Selected"}',
              style: const TextStyle(fontSize: 12, color: AntigravityTheme.googleBlue, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: titleController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Task Title / Objective',
                hintText: 'e.g. Fix authentication token refresh bug',
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
              final title = titleController.text.trim();
              if (currentProj != null) {
                chatProvider.createConversation(
                  currentProj.id,
                  title.isEmpty ? 'New Task' : title,
                );
              }
              Navigator.pop(dialogCtx);
            },
            child: const Text('Start Session', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
