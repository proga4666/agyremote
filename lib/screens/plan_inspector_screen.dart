import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';
import '../core/theme/app_theme.dart';
import '../models/artifact.dart';
import '../providers/chat_provider.dart';

class PlanInspectorScreen extends StatefulWidget {
  final BrainArtifact? initialArtifact;

  const PlanInspectorScreen({super.key, this.initialArtifact});

  @override
  State<PlanInspectorScreen> createState() => _PlanInspectorScreenState();
}

class _PlanInspectorScreenState extends State<PlanInspectorScreen> {
  BrainArtifact? _selectedArtifact;

  @override
  void initState() {
    super.initState();
    final chat = context.read<ChatProvider>();
    _selectedArtifact = widget.initialArtifact ?? chat.activePlanArtifact ?? (chat.currentArtifacts.isNotEmpty ? chat.currentArtifacts.first : null);

    if (_selectedArtifact != null && (_selectedArtifact!.content == null || _selectedArtifact!.content!.isEmpty)) {
      chat.loadArtifactContent(
        _selectedArtifact!.conversationId,
        _selectedArtifact!.name,
        _selectedArtifact!.filePath,
      );
    }
  }

  void _selectArtifact(BrainArtifact art) {
    setState(() => _selectedArtifact = art);
    if (art.content == null || art.content!.isEmpty) {
      context.read<ChatProvider>().loadArtifactContent(
        art.conversationId,
        art.name,
        art.filePath,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final artifacts = chat.currentArtifacts;

    // Refresh selected artifact reference from provider if updated
    if (_selectedArtifact != null) {
      final updated = artifacts.where((a) => a.name == _selectedArtifact!.name);
      if (updated.isNotEmpty) {
        _selectedArtifact = updated.first;
      }
    } else if (artifacts.isNotEmpty) {
      _selectedArtifact = artifacts.first;
    }

    final isPlan = _selectedArtifact?.type == ArtifactType.plan;
    final content = _selectedArtifact?.content ?? 'No content loaded yet.';

    return Scaffold(
      backgroundColor: AntigravityTheme.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _selectedArtifact?.name ?? 'Plan & Artifact Inspector',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            if (_selectedArtifact != null)
              Text(
                'Session: ${chat.activeConversation?.title ?? "Remote Agent"}',
                style: const TextStyle(fontSize: 11, color: AntigravityTheme.textSecondary),
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, size: 18),
            tooltip: 'Refresh Artifacts',
            onPressed: () {
              chat.fetchConversationArtifacts();
              if (_selectedArtifact != null) {
                chat.loadArtifactContent(
                  _selectedArtifact!.conversationId,
                  _selectedArtifact!.name,
                  _selectedArtifact!.filePath,
                );
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.copy_rounded, size: 18),
            tooltip: 'Copy Markdown',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: content));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Artifact markdown copied to clipboard'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Artifact Tabs Selector
          if (artifacts.isNotEmpty) _buildArtifactsTabBar(artifacts),

          // Main Markdown View with alert styling
          Expanded(
            child: Container(
              color: AntigravityTheme.background,
              child: Markdown(
                data: _processMarkdownWithAlerts(content),
                selectable: true,
                padding: const EdgeInsets.all(16),
                styleSheet: MarkdownStyleSheet(
                  h1: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                  h2: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AntigravityTheme.googleBlue),
                  h3: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AntigravityTheme.googleGreen),
                  p: const TextStyle(fontSize: 13, height: 1.5, color: AntigravityTheme.textPrimary),
                  code: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    backgroundColor: Color(0xFF1E2022),
                    color: AntigravityTheme.googleAmber,
                  ),
                  codeblockDecoration: BoxDecoration(
                    color: const Color(0xFF16181A),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AntigravityTheme.borderSubtle),
                  ),
                  blockquoteDecoration: BoxDecoration(
                    color: AntigravityTheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(6),
                    border: const Border(
                      left: BorderSide(color: AntigravityTheme.googleBlue, width: 4),
                    ),
                  ),
                  tableBorder: TableBorder.all(color: AntigravityTheme.borderSubtle, width: 0.5),
                  tableHead: const TextStyle(fontWeight: FontWeight.bold, color: AntigravityTheme.googleBlue),
                ),
              ),
            ),
          ),

          // Action Toolbar for Plans (Approve / Request Changes)
          if (isPlan) _buildPlanActionBar(context, chat),
        ],
      ),
    );
  }

  Widget _buildArtifactsTabBar(List<BrainArtifact> artifacts) {
    return Container(
      width: double.infinity,
      color: AntigravityTheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: artifacts.map((art) {
            final isSelected = _selectedArtifact?.name == art.name;
            return Container(
              margin: const EdgeInsets.only(right: 8),
              child: FilterChip(
                selected: isSelected,
                avatar: Icon(art.icon, size: 14, color: isSelected ? Colors.black : art.color),
                label: Text(
                  art.name,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? Colors.black : Colors.white,
                  ),
                ),
                backgroundColor: AntigravityTheme.surfaceContainerHigh,
                selectedColor: AntigravityTheme.googleBlue,
                checkmarkColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                onSelected: (_) => _selectArtifact(art),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildPlanActionBar(BuildContext context, ChatProvider chat) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: AntigravityTheme.surface,
        border: Border(top: BorderSide(color: AntigravityTheme.border)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AntigravityTheme.googleAmber),
                  foregroundColor: AntigravityTheme.googleAmber,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                icon: const Icon(Icons.edit_note_rounded, size: 18),
                label: const Text('Request Changes', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                onPressed: () => _showFeedbackDialog(context, chat),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AntigravityTheme.googleGreen,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                icon: const Icon(Icons.play_arrow_rounded, size: 20),
                label: const Text('Approve & Execute', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                onPressed: () {
                  chat.sendPrompt('Plan approved. Please proceed with execution.');
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Plan approved! Agent execution resumed.'),
                      backgroundColor: AntigravityTheme.googleGreen,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showFeedbackDialog(BuildContext context, ChatProvider chat) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Request Plan Modifications', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'e.g. Please also include unit tests for the authentication refresh flow...',
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
              final text = controller.text.trim();
              if (text.isNotEmpty) {
                chat.sendPrompt('Please revise the plan based on feedback: $text');
                Navigator.pop(dialogCtx);
                Navigator.pop(context);
              }
            },
            child: const Text('Send Feedback', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  String _processMarkdownWithAlerts(String markdown) {
    // Converts [!IMPORTANT], [!WARNING], [!NOTE] into clear visual callouts
    return markdown
        .replaceAll('> [!IMPORTANT]', '> 🛡️ **IMPORTANT:**')
        .replaceAll('> [!WARNING]', '> ⚠️ **WARNING:**')
        .replaceAll('> [!NOTE]', '> ℹ️ **NOTE:**')
        .replaceAll('> [!TIP]', '> 💡 **TIP:**');
  }
}
