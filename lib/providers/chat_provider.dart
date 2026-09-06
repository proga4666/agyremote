import 'dart:async';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../core/network/bridge_client.dart';
import '../models/approval.dart';
import '../models/artifact.dart';
import '../models/conversation.dart';

class ChatProvider extends ChangeNotifier {
  final BridgeClient bridge;
  final _uuid = const Uuid();
  Timer? _ticker;

  List<Conversation> conversations = [];
  Conversation? activeConversation;
  bool isStreaming = false;
  String? currentStreamingConvId;
  String? _currentProjectId;
  ConversationSource? sourceFilter;

  List<BrainArtifact> currentArtifacts = [];
  BrainArtifact? activePlanArtifact;
  BrainArtifact? activeWalkthroughArtifact;

  ChatProvider({required this.bridge}) {
    bridge.events.listen(_handleEvents);
    bridge.statusStream.listen((status) {
      if (status == BridgeStatus.connected) {
        bridge.send('list_conversations', {});
      }
    });
    // Ticks every 30s so relative times ("2 mins ago", etc.) stay fresh
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void refresh() {
    bridge.send('list_conversations', {});
    if (activeConversation != null) {
      fetchConversationArtifacts(activeConversation!.id);
    }
  }

  void _sortConversations() {
    conversations.sort((a, b) => b.lastMessageTime.compareTo(a.lastMessageTime));
  }

  void setSourceFilter(ConversationSource? filter) {
    sourceFilter = filter;
    notifyListeners();
  }

  List<Conversation> get daemonConversations =>
      conversations.where((c) => c.isDaemon).toList();

  List<Conversation> get desktopIdeConversations =>
      conversations.where((c) => c.isDesktopIde).toList();

  List<Conversation> getConversationsForProject(String? projectId, {ConversationSource? filter}) {
    final effectiveFilter = filter ?? sourceFilter;
    var list = (projectId == null || projectId.isEmpty)
        ? conversations
        : conversations.where((c) => c.projectId == projectId).toList();
    if (effectiveFilter != null) {
      list = list.where((c) => c.source == effectiveFilter).toList();
    }
    return list;
  }

  int countForProjectAndSource(String? projectId, ConversationSource? source) {
    var list = (projectId == null || projectId.isEmpty)
        ? conversations
        : conversations.where((c) => c.projectId == projectId).toList();
    if (source != null) {
      list = list.where((c) => c.source == source).toList();
    }
    return list.length;
  }

  void syncWithSelectedProject(String? projectId) {
    if (projectId == null || projectId.isEmpty) return;
    _currentProjectId = projectId;

    final projectConvs = getConversationsForProject(projectId);
    if (projectConvs.isNotEmpty) {
      if (activeConversation == null || activeConversation!.projectId != projectId) {
        activeConversation = projectConvs.first;
        fetchConversationArtifacts(activeConversation!.id);
        notifyListeners();
      }
    } else {
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

        loadedConvs.sort((a, b) => b.lastMessageTime.compareTo(a.lastMessageTime));
        conversations = loadedConvs;

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

        if (activeConversation != null) {
          fetchConversationArtifacts(activeConversation!.id);
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
          _sortConversations();
          fetchConversationArtifacts(conv.id);
          notifyListeners();
        }
        break;

      case 'conversation_updated':
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
          if (activeConversation?.id == conv.id) {
            activeConversation = conv;
            fetchConversationArtifacts(conv.id);
          }
          _sortConversations();
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
        if (activeConversation != null) {
          fetchConversationArtifacts(activeConversation!.id);
        }
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

      case 'artifact_updated':
        if (event['artifact'] != null) {
          final art = BrainArtifact.fromJson(Map<String, dynamic>.from(event['artifact']));
          _updateOrAddArtifact(art);
        }
        break;

      case 'conversation_artifacts':
        final rawArts = event['artifacts'] as List<dynamic>? ?? [];
        currentArtifacts = rawArts
            .map((a) => BrainArtifact.fromJson(Map<String, dynamic>.from(a)))
            .toList();
        _updateActivePlanAndWalkthrough();
        notifyListeners();
        break;

      case 'artifact_content':
        final artName = event['name']?.toString() ?? '';
        final content = event['content']?.toString() ?? '';
        final index = currentArtifacts.indexWhere((a) => a.name == artName);
        if (index != -1) {
          currentArtifacts[index] = currentArtifacts[index].copyWith(content: content);
          _updateActivePlanAndWalkthrough();
          notifyListeners();
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

  void _updateOrAddArtifact(BrainArtifact art) {
    final idx = currentArtifacts.indexWhere((a) => a.name == art.name);
    if (idx != -1) {
      currentArtifacts[idx] = art;
    } else {
      currentArtifacts.insert(0, art);
    }
    _updateActivePlanAndWalkthrough();
    notifyListeners();
  }

  void _updateActivePlanAndWalkthrough() {
    final plans = currentArtifacts.where((a) => a.type == ArtifactType.plan).toList();
    activePlanArtifact = plans.isNotEmpty ? plans.first : null;

    final walks = currentArtifacts.where((a) => a.type == ArtifactType.walkthrough).toList();
    activeWalkthroughArtifact = walks.isNotEmpty ? walks.first : null;
  }

  void fetchConversationArtifacts([String? convId]) {
    final targetId = convId ?? activeConversation?.id;
    if (targetId == null) return;
    bridge.send('get_conversation_artifacts', {'conversation_id': targetId});
  }

  void loadArtifactContent(String convId, String artifactName, [String? filePath]) {
    final payload = <String, dynamic>{
      'conversation_id': convId,
      'name': artifactName,
    };
    if (filePath != null) {
      payload['file_path'] = filePath;
    }
    bridge.send('get_artifact_content', payload);
  }

  Conversation createConversation(
    String projectId,
    String title, {
    ConversationSource source = ConversationSource.daemon,
  }) {
    final newId = 'conv_${_uuid.v4().substring(0, 8)}';
    final conv = Conversation(
      id: newId,
      projectId: projectId,
      title: title.trim().isEmpty ? 'Autonomous Task' : title.trim(),
      source: source,
      engine: source == ConversationSource.desktopIde ? 'Desktop IDE' : 'Antigravity 2.0',
      messages: [],
    );

    conversations.insert(0, conv);
    activeConversation = conv;
    _currentProjectId = projectId;
    currentArtifacts.clear();
    activePlanArtifact = null;
    activeWalkthroughArtifact = null;
    notifyListeners();

    bridge.send('create_conversation', {
      'id': newId,
      'project_id': projectId,
      'title': conv.title,
      'source': source == ConversationSource.desktopIde ? 'desktop_ide' : 'daemon',
      'engine': conv.engine,
    });

    return conv;
  }

  void deleteConversation(String convId) {
    conversations.removeWhere((c) => c.id == convId);
    if (activeConversation?.id == convId) {
      final projectConvs = getConversationsForProject(_currentProjectId);
      activeConversation = projectConvs.isNotEmpty ? projectConvs.first : (conversations.isNotEmpty ? conversations.first : null);
      if (activeConversation != null) {
        fetchConversationArtifacts(activeConversation!.id);
      }
    }
    notifyListeners();

    bridge.send('delete_conversation', {
      'id': convId,
    });
  }

  void selectConversation(Conversation conv) {
    activeConversation = conv;
    _currentProjectId = conv.projectId;
    currentArtifacts.clear();
    activePlanArtifact = null;
    activeWalkthroughArtifact = null;
    fetchConversationArtifacts(conv.id);
    notifyListeners();
  }

  void selectConversationById(String convId) {
    final match = conversations.where((c) => c.id == convId);
    if (match.isNotEmpty) {
      activeConversation = match.first;
      _currentProjectId = match.first.projectId;
      currentArtifacts.clear();
      activePlanArtifact = null;
      activeWalkthroughArtifact = null;
      fetchConversationArtifacts(convId);
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
    _sortConversations();
    notifyListeners();

    bridge.send('send_prompt', {
      'conversation_id': activeConversation!.id,
      'text': text.trim(),
      if (images != null && images.isNotEmpty) 'images': images,
    });
  }

  void sendMultiStepWorkflow(String workflowType) {
    String prompt = '';
    switch (workflowType) {
      case 'refactor':
        prompt =
            'Please initiate a multi-step codebase refactor: analyze code quality, clean unused imports/dependencies, optimize component architecture, and verify lint compliance.';
        break;
      case 'build_test':
        prompt =
            'Please run the project build pipeline and test suite: compile the workspace, execute automated tests, inspect error outputs, and report verification status.';
        break;
      case 'security_audit':
        prompt =
            'Please perform a full security and dependency audit: verify packages, check file permissions, ensure secrets/tokens are safely configured, and report risks.';
        break;
      case 'implementation_plan':
        prompt =
            'Please create an implementation_plan.md artifact for the current project: outline user review items, open questions, proposed architecture changes, and a verification plan.';
        break;
      default:
        prompt = 'Please inspect the workspace and perform necessary maintenance tasks.';
    }
    sendPrompt(prompt);
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
      _sortConversations();
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
