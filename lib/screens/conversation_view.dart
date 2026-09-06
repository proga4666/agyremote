import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../core/theme/app_theme.dart';
import '../models/approval.dart';
import '../models/conversation.dart';
import '../providers/chat_provider.dart';
import 'diff_viewer_screen.dart';
import 'plan_inspector_screen.dart';

class ConversationView extends StatefulWidget {
  const ConversationView({super.key});

  @override
  State<ConversationView> createState() => _ConversationViewState();
}

class _ConversationViewState extends State<ConversationView> {
  final TextEditingController _promptController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _picker = ImagePicker();
  final List<XFile> _selectedImages = [];
  final List<String> _selectedImagesBase64 = [];

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

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? file = await _picker.pickImage(
        source: source,
        imageQuality: 85,
      );
      if (file != null) {
        final bytes = await file.readAsBytes();
        final b64 = base64Encode(bytes);
        setState(() {
          _selectedImages.add(file);
          _selectedImagesBase64.add(b64);
        });
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
    }
  }

  void _showImageSourceDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AntigravityTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Attach Image to Prompt',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined, color: AntigravityTheme.googleBlue),
                title: const Text('Choose from Photo Gallery'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined, color: AntigravityTheme.googleGreen),
                title: const Text('Take a Photo with Camera'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage(ImageSource.camera);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _removeSelectedImage(int index) {
    setState(() {
      _selectedImages.removeAt(index);
      _selectedImagesBase64.removeAt(index);
    });
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
        // Engine Origin Pill Header (Antigravity 2.0 vs Desktop IDE)
        _buildSessionOriginHeader(context, activeConv, chat),

        // Active Plan / Walkthrough Top Banner
        if (chat.activePlanArtifact != null || chat.activeWalkthroughArtifact != null)
          _buildActivePlanBanner(context, chat),

        // Message Stream Feed with Pull-To-Refresh
        Expanded(
          child: RefreshIndicator(
            color: AntigravityTheme.googleBlue,
            backgroundColor: AntigravityTheme.surfaceContainer,
            onRefresh: () async {
              chat.refresh();
              await Future.delayed(const Duration(milliseconds: 400));
            },
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
        ),

        // Multi-Step Workflow Task Chips
        _buildMultiStepWorkflowRow(chat),

        // Prompt Input Bar with Image Attachments
        _buildPromptBar(context, chat),
      ],
    );
  }

  Widget _buildSessionOriginHeader(BuildContext context, Conversation conv, ChatProvider chat) {
    final isDaemon = conv.isDaemon;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: AntigravityTheme.surfaceContainer.withValues(alpha: 0.6),
        border: const Border(
          bottom: BorderSide(color: AntigravityTheme.borderSubtle),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: isDaemon
                  ? AntigravityTheme.googleGreen.withValues(alpha: 0.15)
                  : AntigravityTheme.googleBlue.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isDaemon
                    ? AntigravityTheme.googleGreen.withValues(alpha: 0.3)
                    : AntigravityTheme.googleBlue.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isDaemon ? Icons.smart_toy_outlined : Icons.laptop_chromebook_rounded,
                  size: 12,
                  color: isDaemon ? AntigravityTheme.googleGreen : AntigravityTheme.googleBlue,
                ),
                const SizedBox(width: 4),
                Text(
                  isDaemon ? 'Antigravity 2.0 Headless' : 'Desktop IDE Session',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: isDaemon ? AntigravityTheme.googleGreen : AntigravityTheme.googleBlue,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              conv.title,
              style: const TextStyle(fontSize: 11, color: AntigravityTheme.textSecondary, fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Tooltip(
            message: 'Last active: ${conv.timeAgo} (${DateFormat('MMM d, HH:mm').format(conv.lastMessageTime)})',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.access_time_rounded, size: 11, color: AntigravityTheme.textMuted),
                const SizedBox(width: 3),
                Text(
                  conv.timeAgo,
                  style: const TextStyle(fontSize: 10, color: AntigravityTheme.textMuted, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Refresh / Sync Button
          InkWell(
            onTap: () {
              chat.refresh();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Syncing chat messages with host PC...'),
                  duration: Duration(milliseconds: 900),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            borderRadius: BorderRadius.circular(4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: AntigravityTheme.surfaceContainerHigh.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AntigravityTheme.borderSubtle),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.sync_rounded, size: 12, color: AntigravityTheme.googleBlue),
                  SizedBox(width: 3),
                  Text(
                    'Sync',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AntigravityTheme.googleBlue),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivePlanBanner(BuildContext context, ChatProvider chat) {
    final plan = chat.activePlanArtifact;
    final walkthrough = chat.activeWalkthroughArtifact;
    final totalArtifacts = chat.currentArtifacts.length;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AntigravityTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AntigravityTheme.googleBlue.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AntigravityTheme.googleBlue.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(Icons.architecture_rounded, color: AntigravityTheme.googleBlue, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      plan != null ? 'Implementation Plan Ready' : 'Walkthrough Artifact Ready',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: AntigravityTheme.googleGreen.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '$totalArtifacts artifact(s)',
                        style: const TextStyle(fontSize: 9, color: AntigravityTheme.googleGreen, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                Text(
                  plan != null ? plan.name : (walkthrough?.name ?? 'Artifacts available'),
                  style: const TextStyle(fontSize: 10, color: AntigravityTheme.textSecondary, fontFamily: 'monospace'),
                  overflow: TextOverflow.ellipsis,
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
            icon: const Icon(Icons.visibility_outlined, size: 14),
            label: const Text('Inspect Plan', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PlanInspectorScreen(initialArtifact: plan ?? walkthrough),
                ),
              );
            },
          ),
        ],
      ),
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
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AntigravityTheme.googleBlue),
                ),
                SizedBox(width: 8),
                Text(
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

  Widget _buildMultiStepWorkflowRow(ChatProvider chat) {
    final workflows = [
      {'key': 'refactor', 'icon': Icons.cleaning_services_rounded, 'label': 'Multi-Step Refactor', 'color': AntigravityTheme.googleBlue},
      {'key': 'build_test', 'icon': Icons.play_circle_outline_rounded, 'label': 'Build & Test Suite', 'color': AntigravityTheme.googleGreen},
      {'key': 'security_audit', 'icon': Icons.security_rounded, 'label': 'Security & Config Audit', 'color': AntigravityTheme.googleAmber},
      {'key': 'implementation_plan', 'icon': Icons.architecture_rounded, 'label': 'Generate Plan', 'color': Colors.purpleAccent},
    ];

    return Container(
      height: 36,
      margin: const EdgeInsets.only(bottom: 6),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: workflows.length,
        separatorBuilder: (_, index) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final wf = workflows[i];
          final color = wf['color'] as Color;
          return ActionChip(
            avatar: Icon(wf['icon'] as IconData, size: 14, color: color),
            label: Text(
              wf['label'] as String,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AntigravityTheme.textPrimary),
            ),
            backgroundColor: AntigravityTheme.surfaceContainer,
            side: BorderSide(color: color.withValues(alpha: 0.3)),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            onPressed: chat.isStreaming
                ? null
                : () => chat.sendMultiStepWorkflow(wf['key'] as String),
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
                '${msg.formattedTime} (${msg.timeAgo}) • Chain of Reasoning',
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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: AntigravityTheme.surfaceContainerHigh.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AntigravityTheme.borderSubtle),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.access_time, size: 9, color: AntigravityTheme.textMuted),
                    const SizedBox(width: 3),
                    Text(
                      msg.formattedTime,
                      style: const TextStyle(fontSize: 10, color: AntigravityTheme.textSecondary, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '• ${msg.timeAgo}',
                      style: const TextStyle(fontSize: 9.5, color: AntigravityTheme.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),

          // Attached Images Preview in Message Bubble
          if (msg.images != null && msg.images!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: msg.images!.map((imgData) {
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: 140,
                      height: 100,
                      decoration: BoxDecoration(
                        border: Border.all(color: AntigravityTheme.border),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: _renderImage(imgData),
                    ),
                  );
                }).toList(),
              ),
            ),

          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MarkdownBody(
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
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.bottomRight,
                  child: Text(
                    msg.formattedTime,
                    style: TextStyle(
                      fontSize: 9.5,
                      color: AntigravityTheme.textMuted.withValues(alpha: 0.7),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Interactive Approval Card
          if (msg.approval != null) _buildApprovalCard(context, msg.approval!, chat),

          // Code Diff Artifact Button
          if (msg.diffArtifact != null) _buildDiffButton(context, msg.diffArtifact!),
        ],
      ),
    );
  }

  Widget _renderImage(String imgData) {
    try {
      if (imgData.startsWith('data:image') || imgData.length > 100) {
        final cleanB64 = imgData.contains(',') ? imgData.split(',').last : imgData;
        final Uint8List bytes = base64Decode(cleanB64);
        return Image.memory(bytes, fit: BoxFit.cover);
      }
    } catch (_) {}
    return Container(
      color: AntigravityTheme.surfaceContainer,
      child: const Center(
        child: Icon(Icons.image, color: AntigravityTheme.textSecondary),
      ),
    );
  }

  Widget _buildApprovalCard(BuildContext context, ApprovalRequest approval, ChatProvider chat) {
    final isPending = approval.status == ApprovalStatus.pending;
    final isApproved = approval.status == ApprovalStatus.approved;

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AntigravityTheme.surfaceContainer,
        borderRadius: BorderRadius.circular(8),
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
                size: 16,
                color: isPending
                    ? AntigravityTheme.googleAmber
                    : isApproved
                        ? AntigravityTheme.googleGreen
                        : AntigravityTheme.googleRed,
              ),
              const SizedBox(width: 6),
              const Text(
                'HOST PERMISSION REQUEST',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                  color: AntigravityTheme.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            approval.description,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AntigravityTheme.textPrimary),
          ),
          const SizedBox(height: 6),
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
                fontSize: 11.5,
                color: AntigravityTheme.googleAmber,
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
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Allow Action', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    onPressed: () {
                      chat.resolveApproval(approval.id, true);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AntigravityTheme.googleRed,
                      side: const BorderSide(color: AntigravityTheme.googleRed),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    icon: const Icon(Icons.close, size: 16),
                    label: const Text('Deny', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
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
      decoration: const BoxDecoration(
        color: AntigravityTheme.surface,
        border: Border(top: BorderSide(color: AntigravityTheme.border)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Attached Images Thumbnail Preview Bar
            if (_selectedImages.isNotEmpty)
              Container(
                height: 75,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _selectedImages.length,
                  separatorBuilder: (_, index) => const SizedBox(width: 8),
                  itemBuilder: (ctx, i) {
                    final b64 = _selectedImagesBase64[i];
                    return Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            width: 65,
                            height: 65,
                            decoration: BoxDecoration(
                              border: Border.all(color: AntigravityTheme.googleBlue),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: _renderImage(b64),
                          ),
                        ),
                        Positioned(
                          top: 2,
                          right: 2,
                          child: InkWell(
                            onTap: () => _removeSelectedImage(i),
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.black87,
                              ),
                              child: const Icon(Icons.close, size: 12, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),

            // Input Actions Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Attach Photo Button
                  IconButton(
                    icon: const Icon(Icons.add_a_photo_outlined, color: AntigravityTheme.googleBlue, size: 20),
                    tooltip: 'Attach Image / Camera',
                    onPressed: _showImageSourceDialog,
                  ),
                  // Voice Input Button
                  IconButton(
                    icon: Icon(
                      _isListening ? Icons.mic : Icons.mic_none_rounded,
                      color: _isListening ? AntigravityTheme.googleRed : AntigravityTheme.textSecondary,
                      size: 20,
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
                          _sendCurrentPrompt(chat);
                        },
                      ),
                    ),
                  ),
                  // Send Button
                  IconButton(
                    icon: const Icon(Icons.send_rounded, color: AntigravityTheme.googleGreen, size: 22),
                    tooltip: 'Send Prompt',
                    onPressed: () => _sendCurrentPrompt(chat),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _sendCurrentPrompt(ChatProvider chat) {
    final text = _promptController.text.trim();
    if (text.isNotEmpty || _selectedImagesBase64.isNotEmpty) {
      chat.sendPrompt(text, images: List.from(_selectedImagesBase64));
      _promptController.clear();
      setState(() {
        _selectedImages.clear();
        _selectedImagesBase64.clear();
      });
    }
  }
}
