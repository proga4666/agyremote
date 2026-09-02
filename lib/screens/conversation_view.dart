import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../core/theme/app_theme.dart';
import '../models/approval.dart';
import '../models/conversation.dart';
import '../providers/chat_provider.dart';
import 'diff_viewer_screen.dart';

class ConversationView extends StatefulWidget {
  const ConversationView({super.key});

  @override
  State<ConversationView> createState() => _ConversationViewState();
}

class _ConversationViewState extends State<ConversationView> {
  final TextEditingController _promptController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late stt.SpeechToText _speech;
  bool _isListening = false;
  bool _speechAvailable = false;

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _initSpeech();
  }

  void _initSpeech() async {
    try {
      _speechAvailable = await _speech.initialize(
        onError: (e) => debugPrint('STT error: $e'),
        onStatus: (s) {
          if (s == 'done' || s == 'notListening') {
            if (mounted) setState(() => _isListening = false);
          }
        },
      );
    } catch (e) {
      _speechAvailable = false;
    }
  }

  void _toggleListening() async {
    if (!_speechAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Speech recognition not available on this platform/device.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    if (_isListening) {
      _speech.stop();
      setState(() => _isListening = false);
    } else {
      setState(() => _isListening = true);
      _speech.listen(
        onResult: (result) {
          setState(() {
            _promptController.text = result.recognizedWords;
          });
        },
      );
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _promptController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final activeConv = chat.activeConversation;

    if (activeConv == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.terminal_rounded, size: 64, color: AntigravityTheme.googleBlue.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            const Text(
              'No Active Session',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AntigravityTheme.textPrimary),
            ),
            const SizedBox(height: 8),
            const Text(
              'Select a conversation or start a new autonomous task.',
              style: TextStyle(color: AntigravityTheme.textSecondary, fontSize: 13),
            ),
          ],
        ),
      );
    }

    _scrollToBottom();

    return Column(
      children: [
        // Message Stream Feed
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            itemCount: activeConv.messages.length + (chat.isStreaming ? 1 : 0),
            itemBuilder: (context, index) {
              if (index < activeConv.messages.length) {
                final msg = activeConv.messages[index];
                return _buildMessageBubble(context, msg, chat);
              } else {
                return _buildStreamingIndicator();
              }
            },
          ),
        ),

        // Quick Suggestion Chips
        if (activeConv.messages.length <= 2) _buildQuickSuggestionRow(chat),

        // Prompt Input Bar
        _buildPromptBar(context, chat),
      ],
    );
  }

  Widget _buildStreamingIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AntigravityTheme.surfaceContainer,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AntigravityTheme.borderSubtle),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AntigravityTheme.googleBlue),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Antigravity Agent is working...',
                  style: TextStyle(fontSize: 11, color: AntigravityTheme.googleBlue),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickSuggestionRow(ChatProvider chat) {
    final suggestions = [
      '⚡ Run tests & fix failing cases',
      '🔍 Analyze project architecture',
      '🛠️ Refactor controller methods',
    ];

    return Container(
      height: 38,
      margin: const EdgeInsets.only(bottom: 6),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: suggestions.length,
        separatorBuilder: (_, index) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final s = suggestions[i];
          return ActionChip(
            label: Text(s, style: const TextStyle(fontSize: 11, color: AntigravityTheme.textPrimary)),
            backgroundColor: AntigravityTheme.surfaceContainer,
            side: const BorderSide(color: AntigravityTheme.border),
            onPressed: () {
              final cleanText = s.substring(3);
              chat.sendPrompt(cleanText);
            },
          );
        },
      ),
    );
  }

  Widget _buildMessageBubble(
    BuildContext context,
    ConversationMessage msg,
    ChatProvider chat,
  ) {
    if (msg.sender == 'thought') {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        child: Material(
          color: AntigravityTheme.surfaceContainer.withValues(alpha: 0.6),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: AntigravityTheme.googleAmber.withValues(alpha: 0.2)),
          ),
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              dense: true,
              initiallyExpanded: false,
              leading: const Icon(Icons.psychology_outlined, color: AntigravityTheme.googleAmber, size: 18),
              title: const Text(
                'Agent Thought Process',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AntigravityTheme.googleAmber,
                ),
              ),
              subtitle: Text(
                '${DateFormat('HH:mm:ss').format(msg.timestamp)} • Chain of Reasoning',
                style: const TextStyle(fontSize: 10, color: AntigravityTheme.textMuted),
              ),
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(
                    color: Color(0xFF101112),
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(8),
                      bottomRight: Radius.circular(8),
                    ),
                  ),
                  child: Text(
                    msg.content,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AntigravityTheme.textSecondary,
                      fontFamily: 'monospace',
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final isUser = msg.sender == 'user';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isUser ? Icons.person_outline : Icons.auto_awesome,
                size: 13,
                color: isUser ? AntigravityTheme.googleBlue : AntigravityTheme.googleGreen,
              ),
              const SizedBox(width: 4),
              Text(
                isUser ? 'You' : 'Antigravity Agent',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isUser ? AntigravityTheme.googleBlue : AntigravityTheme.googleGreen,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                DateFormat('HH:mm').format(msg.timestamp),
                style: const TextStyle(fontSize: 10, color: AntigravityTheme.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(12),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.88,
            ),
            decoration: BoxDecoration(
              color: isUser ? const Color(0xFF1F2633) : AntigravityTheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isUser
                    ? AntigravityTheme.googleBlue.withValues(alpha: 0.3)
                    : AntigravityTheme.border,
              ),
            ),
            child: MarkdownBody(
              data: msg.content,
              selectable: true,
              styleSheet: MarkdownStyleSheet(
                p: const TextStyle(color: AntigravityTheme.textPrimary, fontSize: 13, height: 1.45),
                code: const TextStyle(
                  backgroundColor: Color(0xFF0F1011),
                  color: AntigravityTheme.googleGreen,
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
                codeblockDecoration: BoxDecoration(
                  color: const Color(0xFF0B0C0E),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AntigravityTheme.borderSubtle),
                ),
                h1: const TextStyle(color: AntigravityTheme.googleBlue, fontSize: 16, fontWeight: FontWeight.bold),
                h2: const TextStyle(color: AntigravityTheme.googleBlue, fontSize: 14, fontWeight: FontWeight.bold),
                h3: const TextStyle(color: AntigravityTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                listBullet: const TextStyle(color: AntigravityTheme.googleBlue),
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
    final isPending = approval.status == ApprovalStatus.pending;
    final isApproved = approval.status == ApprovalStatus.approved;

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF231B0E),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isPending
              ? AntigravityTheme.googleAmber
              : isApproved
                  ? AntigravityTheme.googleGreen
                  : AntigravityTheme.googleRed,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.shield_outlined,
                color: isPending
                    ? AntigravityTheme.googleAmber
                    : isApproved
                        ? AntigravityTheme.googleGreen
                        : AntigravityTheme.googleRed,
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                'Host Permission Request (${approval.tool})',
                style: TextStyle(
                  color: isPending
                      ? AntigravityTheme.googleAmber
                      : isApproved
                          ? AntigravityTheme.googleGreen
                          : AntigravityTheme.googleRed,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          if (approval.description.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              approval.description,
              style: const TextStyle(fontSize: 12, color: AntigravityTheme.textSecondary),
            ),
          ],
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF0F1011),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AntigravityTheme.borderSubtle),
            ),
            child: Text(
              approval.command,
              style: const TextStyle(
                fontFamily: 'monospace',
                color: AntigravityTheme.googleGreen,
                fontSize: 11.5,
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (isPending)
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AntigravityTheme.googleGreen,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    icon: const Icon(Icons.check, size: 16, color: Colors.black),
                    label: const Text('Approve', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    onPressed: () {
                      chat.resolveApproval(approval.id, true);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AntigravityTheme.googleRed),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    icon: const Icon(Icons.close, size: 16, color: AntigravityTheme.googleRed),
                    label: const Text('Reject', style: TextStyle(color: AntigravityTheme.googleRed, fontSize: 13)),
                    onPressed: () {
                      chat.resolveApproval(approval.id, false);
                    },
                  ),
                ),
              ],
            )
          else
            Row(
              children: [
                Icon(
                  isApproved ? Icons.check_circle : Icons.cancel,
                  color: isApproved ? AntigravityTheme.googleGreen : AntigravityTheme.googleRed,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  isApproved ? 'Execution Approved on Workstation' : 'Permission Denied',
                  style: TextStyle(
                    color: isApproved ? AntigravityTheme.googleGreen : AntigravityTheme.googleRed,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildDiffButton(BuildContext context, CodeDiffArtifact diff) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AntigravityTheme.googleBlue),
          backgroundColor: AntigravityTheme.googleBlue.withValues(alpha: 0.08),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
        icon: const Icon(Icons.difference_outlined, size: 16, color: AntigravityTheme.googleBlue),
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Inspect Diff: ${diff.filePath}',
              style: const TextStyle(fontSize: 12, color: AntigravityTheme.googleBlue, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: AntigravityTheme.googleGreen.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '+${diff.additions} -${diff.deletions}',
                style: const TextStyle(fontSize: 10, color: AntigravityTheme.googleGreen, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => DiffViewerScreen(artifact: diff)),
          );
        },
      ),
    );
  }

  Widget _buildPromptBar(BuildContext context, ChatProvider chat) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: AntigravityTheme.surface,
        border: Border(top: BorderSide(color: AntigravityTheme.border)),
      ),
      child: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Voice Input Button
            IconButton(
              icon: Icon(
                _isListening ? Icons.mic : Icons.mic_none_rounded,
                color: _isListening ? AntigravityTheme.googleRed : AntigravityTheme.textSecondary,
              ),
              tooltip: _isListening ? 'Stop Listening' : 'Voice Prompt',
              onPressed: _toggleListening,
            ).animate(target: _isListening ? 1 : 0).scale(duration: 200.ms),
            // Text Input Field
            Expanded(
              child: Container(
                constraints: const BoxConstraints(maxHeight: 120),
                child: TextField(
                  controller: _promptController,
                  maxLines: null,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: const InputDecoration(
                    hintText: 'Prompt Antigravity Agent...',
                    hintStyle: TextStyle(color: AntigravityTheme.textSecondary, fontSize: 13),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 10),
                  ),
                  onSubmitted: (val) {
                    if (val.trim().isNotEmpty) {
                      chat.sendPrompt(val);
                      _promptController.clear();
                    }
                  },
                ),
              ),
            ),
            // Send Button
            IconButton(
              icon: const Icon(Icons.send_rounded, color: AntigravityTheme.googleGreen),
              tooltip: 'Send Prompt',
              onPressed: () {
                final text = _promptController.text.trim();
                if (text.isNotEmpty) {
                  chat.sendPrompt(text);
                  _promptController.clear();
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
