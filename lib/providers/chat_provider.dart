import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../core/network/bridge_client.dart';
import '../models/approval.dart';
import '../models/conversation.dart';

class ChatProvider extends ChangeNotifier {
  final BridgeClient bridge;
  final _uuid = const Uuid();

  List<Conversation> conversations = [];
  Conversation? activeConversation;
  bool isStreaming = false;
  String? currentStreamingConvId;
  String? _currentProjectId;

  ChatProvider({required this.bridge}) {
    bridge.events.listen(_handleEvents);
    bridge.statusStream.listen((status) {
      if (status == BridgeStatus.connected) {
        bridge.send('list_conversations', {});
      }
    });
  }

  List<Conversation> getConversationsForProject(String? projectId) {
    if (projectId == null || projectId.isEmpty) return conversations;
    return conversations.where((c) => c.projectId == projectId).toList();
  }

  void syncWithSelectedProject(String? projectId) {
    if (projectId == null || projectId.isEmpty) return;
    _currentProjectId = projectId;

    final projectConvs = getConversationsForProject(projectId);
    if (projectConvs.isNotEmpty) {
      if (activeConversation == null || activeConversation!.projectId != projectId) {
        activeConversation = projectConvs.first;
        notifyListeners();
      }
    } else {
      // Create initial conversation for this project
      createConversation(projectId, 'Initial Task');
    }
  }

  void _handleEvents(Map<String, dynamic> event) {
    switch (event['event']) {
      case 'conversations_list':
        final rawList = event['conversations'] as List<dynamic>? ?? [];
        final loadedConvs = rawList
            .map((c) => Conversation.fromJson(Map<String, dynamic>.from(c)))
            .toList();

        // Sort most recent first
        loadedConvs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        conversations = loadedConvs;

        // Keep active conversation or select first matching project
        if (activeConversation != null) {
          final match = conversations.where((c) => c.id == activeConversation!.id);
          if (match.isNotEmpty) {
            activeConversation = match.first;
          } else {
            final projMatch = getConversationsForProject(_currentProjectId);
            activeConversation = projMatch.isNotEmpty ? projMatch.first : (conversations.isNotEmpty ? conversations.first : null);
          }
        } else if (_currentProjectId != null) {
          final projMatch = getConversationsForProject(_currentProjectId);
          activeConversation = projMatch.isNotEmpty ? projMatch.first : (conversations.isNotEmpty ? conversations.first : null);
        } else if (conversations.isNotEmpty) {
          activeConversation = conversations.first;
        }

        notifyListeners();
        break;

      case 'conversation_created':
        if (event['conversation'] != null) {
          final conv = Conversation.fromJson(
            Map<String, dynamic>.from(event['conversation']),
          );
          final index = conversations.indexWhere((c) => c.id == conv.id);
          if (index == -1) {
            conversations.insert(0, conv);
          } else {
            conversations[index] = conv;
          }
          activeConversation = conv;
          notifyListeners();
        }
        break;

      case 'agent_stream':
        final convId = event['conversation_id']?.toString() ?? activeConversation?.id;
        final chunk = event['chunk']?.toString() ?? '';
        final isThought = event['is_thought'] == true;

        if (convId != null) {
          _appendStreamChunk(convId, chunk, isThought);
        }
        break;

      case 'agent_stream_end':
        isStreaming = false;
        notifyListeners();
        break;

      case 'tool_approval_request':
        final convId = event['conversation_id']?.toString() ?? activeConversation?.id;
        if (event['approval'] != null && convId != null) {
          final req = ApprovalRequest.fromJson(
            Map<String, dynamic>.from(event['approval']),
          );
          _addApprovalRequest(convId, req);
        }
        break;

      case 'diff_artifact':
        final convId = event['conversation_id']?.toString() ?? activeConversation?.id;
        if (convId != null) {
          final diff = CodeDiffArtifact.fromJson(
            Map<String, dynamic>.from(event),
          );
          _addDiffArtifact(convId, diff);
        }
        break;

      case 'approval_resolved':
        final approvalId = event['approval_id']?.toString();
        final approved = event['approved'] == true;
        if (approvalId != null) {
          _updateApprovalStatus(approvalId, approved);
        }
        break;
    }
  }

  Conversation createConversation(String projectId, String title) {
    final newId = 'conv_${_uuid.v4().substring(0, 8)}';
    final conv = Conversation(
      id: newId,
      projectId: projectId,
      title: title.trim().isEmpty ? 'Autonomous Task' : title.trim(),
      messages: [],
    );

    conversations.insert(0, conv);
    activeConversation = conv;
    _currentProjectId = projectId;
    notifyListeners();

    bridge.send('create_conversation', {
      'id': newId,
      'project_id': projectId,
      'title': conv.title,
    });

    return conv;
  }

  void deleteConversation(String convId) {
    conversations.removeWhere((c) => c.id == convId);
    if (activeConversation?.id == convId) {
      final projectConvs = getConversationsForProject(_currentProjectId);
      activeConversation = projectConvs.isNotEmpty ? projectConvs.first : (conversations.isNotEmpty ? conversations.first : null);
    }
    notifyListeners();

    bridge.send('delete_conversation', {
      'id': convId,
    });
  }

  void selectConversation(Conversation conv) {
    activeConversation = conv;
    _currentProjectId = conv.projectId;
    notifyListeners();
  }

  void selectConversationById(String convId) {
    final match = conversations.where((c) => c.id == convId);
    if (match.isNotEmpty) {
      activeConversation = match.first;
      _currentProjectId = match.first.projectId;
      notifyListeners();
    }
  }

  void sendPrompt(String text, {List<String>? images}) {
    if (activeConversation == null) return;
    if (text.trim().isEmpty && (images == null || images.isEmpty)) return;

    final userMsg = ConversationMessage(
      id: _uuid.v4(),
      sender: 'user',
      content: text.trim().isEmpty ? 'Attached ${images?.length ?? 1} photo(s)' : text.trim(),
      images: images,
      timestamp: DateTime.now(),
    );

    activeConversation!.messages.add(userMsg);
    isStreaming = true;
    currentStreamingConvId = activeConversation!.id;
    notifyListeners();

    bridge.send('send_prompt', {
      'conversation_id': activeConversation!.id,
      'text': text.trim(),
      if (images != null && images.isNotEmpty) 'images': images,
    });
  }

  void resolveApproval(String approvalId, bool approved) {
    _updateApprovalStatus(approvalId, approved);
    bridge.send('resolve_approval', {
      'approval_id': approvalId,
      'approved': approved,
    });
    notifyListeners();
  }

  void _updateApprovalStatus(String approvalId, bool approved) {
    for (final conv in conversations) {
      for (final msg in conv.messages) {
        if (msg.approval?.id == approvalId) {
          msg.approval!.status =
              approved ? ApprovalStatus.approved : ApprovalStatus.rejected;
        }
      }
    }
    notifyListeners();
  }

  void _appendStreamChunk(String convId, String chunk, bool isThought) {
    final conv = conversations.firstWhere(
      (c) => c.id == convId,
      orElse: () => activeConversation!,
    );

    final senderType = isThought ? 'thought' : 'agent';
    final messages = conv.messages;

    if (messages.isNotEmpty && messages.last.sender == senderType) {
      messages.last.content += chunk;
    } else {
      messages.add(ConversationMessage(
        id: _uuid.v4(),
        sender: senderType,
        content: chunk,
        timestamp: DateTime.now(),
      ));
    }

    notifyListeners();
  }

  void _addApprovalRequest(String convId, ApprovalRequest req) {
    final conv = conversations.firstWhere(
      (c) => c.id == convId,
      orElse: () => activeConversation!,
    );

    conv.messages.add(ConversationMessage(
      id: _uuid.v4(),
      sender: 'agent',
      content: 'Agent requests tool permission on host:',
      approval: req,
      timestamp: DateTime.now(),
    ));
    isStreaming = false;
    notifyListeners();
  }

  void _addDiffArtifact(String convId, CodeDiffArtifact diff) {
    final conv = conversations.firstWhere(
      (c) => c.id == convId,
      orElse: () => activeConversation!,
    );

    conv.messages.add(ConversationMessage(
      id: _uuid.v4(),
      sender: 'agent',
      content: 'Modified: `${diff.filePath}`',
      diffArtifact: diff,
      timestamp: DateTime.now(),
    ));
    isStreaming = false;
    notifyListeners();
  }

  void clearActiveConversation() {
    if (activeConversation != null) {
      activeConversation!.messages.clear();
      notifyListeners();
    }
  }
}
