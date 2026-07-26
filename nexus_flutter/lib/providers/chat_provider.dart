import 'dart:async';
import 'package:flutter/material.dart';
import '../models/message_data.dart';
import '../models/chat_state.dart';
import '../models/device_entry.dart';
import '../models/host_runtime_state.dart';
import '../models/ws_protocol.dart';
import '../services/ws_client.dart';
import '../services/storage_service.dart';
import '../services/host_store.dart';
import '../services/device_agent_store.dart';

/// Core chat state provider — mirrors ArkTS ChatStore + Index.ets logic
class ChatProvider extends ChangeNotifier {
  final WSClient _ws;
  final ChatState _state = ChatState();
  ChatState get state => _state;

  ChatProvider(this._ws) {
    _ws.onMessage(_handleServerMessage);
    _ws.onServerInfo(_onServerInfo);
    _ws.onAgentList(_onAgentList);
    // Bridge WS connection phases to HostStore so UI shows online status
    _ws.onPhaseChange((phase) {
      final hk = _ws.currentHostKey;
      if (hk.isEmpty) return;
      final hs = HostStore();
      hs.setPhase(hk, phase, url: _ws.currentUrl);
      notifyListeners();
    });
  }

  WSClient get ws => _ws;

  // ── Connection ──
  Future<void> initFromDisk() async {
    final storage = await StorageService.getInstance();
    _state.lastMessageId = storage.getLastMessageIdSync();
    await DeviceAgentStore().loadFromDisk();
  }

  Future<void> connectToUrl(String url, {String? hostKey}) async {
    final normalizedUrl = _normalizeUrl(url);
    if (normalizedUrl.isEmpty) return;

    final hk = hostKey ?? _getHostKeyForUrl(normalizedUrl);
    _state.currentDeviceId = hk;

    // Save URL to storage immediately (like ArkTS Index.ets:635-636)
    final storage = await StorageService.getInstance();
    storage.putString('server_url', normalizedUrl);

    // Mark connecting in runtime store BEFORE connecting
    HostRuntimeStore().setPhase(hk, HostPhase.connecting, url: normalizedUrl);

    _ws.connect(normalizedUrl, hk);
  }

  Future<void> connectBest(List<String> candidates, {String? hostKey}) async {
    // Normalize all candidates
    final normalized = candidates.map((u) => _normalizeUrl(u)).where((u) => u.isNotEmpty).toList();
    if (normalized.isEmpty) return;

    final hk = hostKey ?? _getHostKeyForUrl(normalized.first);
    _state.currentDeviceId = hk;

    // Save first URL to storage
    if (normalized.first.isNotEmpty) {
      final storage = await StorageService.getInstance();
      storage.putString('server_url', normalized.first);
    }

    // Mark connecting
    HostRuntimeStore().setPhase(hk, HostPhase.connecting, url: normalized.first);

    await _ws.connectBest(normalized, hk);
  }

  String _normalizeUrl(String raw) {
    String url = raw.trim();
    if (url.startsWith('http://')) url = url.replaceFirst('http://', 'ws://');
    if (url.startsWith('https://')) url = url.replaceFirst('https://', 'wss://');
    if (!url.startsWith('ws://') && !url.startsWith('wss://')) url = 'ws://$url';
    if (url.endsWith('/')) url = url.substring(0, url.length - 1);
    return url;
  }

  String _getHostKeyForUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.host.isNotEmpty ? uri.host : url;
    } catch (_) {
      return url;
    }
  }

  void disconnect() {
    _ws.disconnect();
    _state.connected = false;
    _state.currentDeviceId = '';
    _state.sessionTitle = '';
    notifyListeners();
  }

  // ── Messaging ──
  void sendMessage(String text) {
    if (text == '__cancel__') {
      _ws.send(ClientMessage(type: 'cancel'));
      _state.turnActive = false;
      notifyListeners();
      return;
    }

    if (_state.sessionId.isEmpty) {
      // New session: use 'start' with full config
      _state.turnActive = true;
      _state.messages = [
        ..._state.messages,
        MessageData(role: 'user', content: text, type: 'text', sendStatus: 'sent'),
      ];
      notifyListeners();

      _ws.send(ClientMessage(
        type: 'start',
        agent: _state.selectedAgentName.isNotEmpty ? _state.selectedAgentName : null,
        cwd: _state.currentWorkspace.isNotEmpty ? _state.currentWorkspace : null,
        model: _state.modelIndex >= 0 && _state.modelIndex < _state.models.length
            ? _state.models[_state.modelIndex].id : null,
        prompt: text,
      ));
    } else {
      // Continue existing / resumed session
      _state.turnActive = true;
      _state.messages = [
        ..._state.messages,
        MessageData(role: 'user', content: text, type: 'text', sendStatus: 'sent'),
      ];
      notifyListeners();

      _ws.send(ClientMessage(
        type: 'input',
        sessionId: _state.sessionId,
        text: text,
      ));
    }
  }

  void retryMessage(MessageData msg) {
    if (msg.sendStatus == 'failed') {
      msg.sendStatus = 'sending';
      notifyListeners();
      sendMessage(msg.content);
    }
  }

  void newChat() {
    // Abort any running turn on the old session, then reset local state to a
    // fresh, empty chat. The next sent message opens a brand-new server
    // session ('start' instead of 'input').
    if (_state.turnActive) {
      _ws.send(ClientMessage(type: 'cancel'));
    }
    _state.resetForNewChat();
    notifyListeners();
  }

  void setCurrentWorkspace(String path) {
    _state.currentWorkspace = path;
    notifyListeners();
  }

  // ── Agent / Model / Mode ──
  void selectAgent(String name) {
    _state.selectedAgentName = name;
    _state.models = [];
    _state.modelIndex = -1;
    notifyListeners();
    // Request model list from server for this agent
    _ws.send(ClientMessage(type: 'list_models', agent: name));
  }

  void selectModel(int index) {
    if (index >= 0 && index < _state.models.length) {
      _state.modelIndex = index;
      notifyListeners();
      if (_state.sessionId.isNotEmpty) {
        _ws.send(ClientMessage(
          type: 'switch_model',
          sessionId: _state.sessionId,
          model: _state.models[index].id,
        ));
      }
    }
  }

  void selectMode(int index) {
    if (index >= 0 && index < _state.modes.length) {
      _state.modeIndex = index;
      notifyListeners();
      if (_state.sessionId.isNotEmpty) {
        _ws.send(ClientMessage(
          type: 'set_mode',
          sessionId: _state.sessionId,
          modeId: _state.modes[index].id,
        ));
      }
    }
  }

  void refreshModels() {
    _ws.send(ClientMessage(type: 'list_models', agent: _state.selectedAgentName));
  }

  // ── Sessions ──
  void loadSession(String sessionId, {String? agent, String? cwd, String? title}) {
    String targetAgent = agent ?? '';
    String targetCwd = cwd ?? '';

    final matchingSession = _state.sessions.firstWhere(
      (s) => s.sessionId == sessionId,
      orElse: () => ServerSessionData(sessionId: sessionId),
    );

    if (matchingSession.title != null && matchingSession.title!.isNotEmpty) {
      _state.sessionTitle = matchingSession.title!;
    } else if (title != null && title.isNotEmpty) {
      _state.sessionTitle = title;
    } else {
      _state.sessionTitle = '';
    }

    if (targetAgent.isEmpty && matchingSession.agent != null && matchingSession.agent!.isNotEmpty) {
      targetAgent = matchingSession.agent!;
    }
    if (targetAgent.isEmpty) {
      targetAgent = _state.selectedAgentName;
    } else {
      _state.selectedAgentName = targetAgent;
    }

    if (targetCwd.isEmpty && matchingSession.cwd != null && matchingSession.cwd!.isNotEmpty) {
      targetCwd = matchingSession.cwd!;
    }
    if (targetCwd.isNotEmpty) {
      _state.currentWorkspace = targetCwd;
    }

    _ws.send(ClientMessage(
      type: 'load_session',
      sessionId: sessionId,
      cwd: _state.currentWorkspace.isNotEmpty ? _state.currentWorkspace : null,
      agent: targetAgent,
      lastMessageId: _state.lastMessageId.isNotEmpty ? _state.lastMessageId : null,
    ));
    // Clear messages and enter loading state; mirror ArkTS loadSessionIntoStore
    _state.loadingSession = true;
    _state.messages = [];
    _state.planEntries = [];
    _state.streamingThinking = '';
    _state.turnActive = false;
    notifyListeners();
  }

  void requestSessionList() => _ws.send(ClientMessage(type: 'list_sessions'));

  void _requestServerSessions() {
    _ws.send(ClientMessage(
      type: 'list_sessions',
      cwd: _state.currentWorkspace.isNotEmpty ? _state.currentWorkspace : null,
    ));
  }

  // ── Workspace File Browser ──
  void requestWorkspaceFiles() {
    _state.loadingFiles = true;
    _state.fileDiff = null;
    _state.selectedFilePath = null;
    _state.fileLogEntries = [];
    notifyListeners();
    _ws.send(ClientMessage(
      type: 'list_workspace_files',
      cwd: _state.currentWorkspace,
    ));
  }

  void requestFileDiff(String filePath) {
    _state.fileDiff = null;
    _state.selectedFilePath = filePath;
    notifyListeners();
    _ws.send(ClientMessage(
      type: 'get_file_diff',
      cwd: _state.currentWorkspace,
      text: filePath,
    ));
  }

  void requestFileLog(String filePath) {
    _state.fileLogEntries = [];
    notifyListeners();
    _ws.send(ClientMessage(
      type: 'get_file_log',
      cwd: _state.currentWorkspace,
      text: filePath,
    ));
  }

  void requestFileContent(String filePath) {
    _state.fileContent = null;
    notifyListeners();
    _ws.send(ClientMessage(
      type: 'get_file_content',
      cwd: _state.currentWorkspace,
      text: filePath,
    ));
  }

  // ── Permissions ──
  void permissionResponse(String requestId, String outcome, {String? optionId}) {
    _ws.send(ClientMessage(
      type: 'permission_response',
      sessionId: _state.sessionId,
      requestId: requestId,
      outcome: outcome,
      optionId: optionId,
    ));
    _state.pendingPermission = null;
    notifyListeners();
  }

  void rejectPermissionOnClose() {
    if (_state.pendingPermission != null) {
      permissionResponse(_state.pendingPermission!.requestId, 'reject_once');
    }
  }

  // ── Agent Management ──
  void requestAgents() => _ws.send(ClientMessage(type: 'list_agents'));
  void listRegistryAgents() => _ws.send(ClientMessage(type: 'list_registry_agents'));
  void installAgent(String agentId) => _ws.send(ClientMessage(type: 'install_agent', agentId: agentId));
  void uninstallAgent(String agentId) => _ws.send(ClientMessage(type: 'uninstall_agent', agentId: agentId));
  void installCustomAgent(String command, List<String> args, String name) {
    _ws.send(ClientMessage(type: 'install_custom_agent', command: command, args: args, name: name));
  }

  // ── Sync after reconnect ──
  void syncRequest() {
    if (_state.sessionId.isNotEmpty) {
      _ws.send(ClientMessage(
        type: 'sync_request',
        sessionId: _state.sessionId,
        lastMessageId: _state.lastMessageId,
      ));
    }
  }

  // ── Server message routing ──
  void _handleServerMessage(ServerMessage msg) {
    switch (msg.type) {
      case 'server_info':
        _handleServerInfo(msg);
        break;
      case 'session_started':
        _state.sessionId = msg.sessionId ?? '';
        _state.sessionTitle = msg.title ?? msg.sessionId ?? '';
        // Resume: server sends session_started with resumed: true.
        // Keep turnActive false so the next message continues via 'input'.
        if (msg.resumed == true) {
          _state.turnActive = false;
        }
        // Safety net: clear loading state if history replay already completed
        _state.loadingSession = false;
        notifyListeners();
        break;
      case 'session_ended':
        _state.turnActive = false;
        _state.sessionId = '';
        _state.sessionTitle = '';
        notifyListeners();
        break;
      case 'resumed_session':
        _state.sessionId = msg.sessionId ?? '';
        _state.turnActive = false;
        _state.loadingSession = false;
        notifyListeners();
        break;
      case 'agent_event':
        _handleAgentEvent(msg);
        break;
      case 'turn_ended':
        _handleTurnEnded();
        break;
      case 'model_list':
        if (msg.models != null) _state.models = msg.models!;
        if (msg.modes != null) _state.modes = msg.modes!;
        notifyListeners();
        break;
      case 'session_list':
        if (msg.sessions != null) _state.sessions = msg.sessions!;
        notifyListeners();
        break;
      case 'agent_list':
        if (msg.agents != null) {
          _state.agentNames = msg.agents!.map((a) => a.name).toList();
          if (_state.currentDeviceId.isNotEmpty) {
            DeviceAgentStore().saveAgents(_state.currentDeviceId, msg.agents!);
          }
        }
        // Now we have agents, request sessions with the first one
        _requestServerSessions();
        notifyListeners();
        break;
      case 'registry_agents_list':
        if (msg.registryAgents != null) {
          _state.registryAgents = msg.registryAgents!;
        }
        notifyListeners();
        break;
      case 'install_agent_done':
      case 'uninstall_agent_done':
        _ws.send(ClientMessage(type: 'list_agents'));
        _ws.send(ClientMessage(type: 'list_registry_agents'));
        notifyListeners();
        break;
      case 'error':
        if (msg.text != null) {
          _state.errorMessage = msg.text!;
          notifyListeners();
        }
        break;
      case 'permission_request':
        if (msg.requestId != null) {
          _state.pendingPermission = PendingPermission(
            requestId: msg.requestId!,
            toolCall: msg.toolCall?.toString() ?? '',
            options: (msg.options ?? []).map((o) => PermissionOption(
              optionId: o['optionId']?.toString() ?? '',
              name: o['name']?.toString() ?? '',
              kind: o['kind']?.toString() ?? '',
            )).toList(),
          );
        }
        notifyListeners();
        break;
      case 'session_closed':
        _state.turnActive = false;
        _state.sessionId = '';
        notifyListeners();
        break;
      case 'sync_response':
        if (msg.entries != null) {
          for (final entry in msg.entries!) {
            // Each entry is { messageId, payload: { sessionUpdate, text, ... }, timestamp }
            final payload = entry['payload'];
            if (payload is Map<String, dynamic>) {
              // Construct a synthetic agent_event JSON so ServerMessage.fromJson
              // applies the full event parsing (content blocks, nesting, etc.)
              final syntheticJson = <String, dynamic>{
                'type': 'agent_event',
                'sessionId': msg.sessionId,
                'event': payload,
              };
              final eventMsg = ServerMessage.fromJson(syntheticJson);
              _handleAgentEvent(eventMsg);
            }
          }
        }
        break;
      case 'target_offline':
        _state.connected = false;
        notifyListeners();
        break;
      case 'workspace_files':
        if (msg.files != null) {
          _state.workspaceFiles = msg.files!;
          _state.loadingFiles = false;
        }
        notifyListeners();
        break;
      case 'file_diff':
        _state.fileDiff = msg.diff;
        _state.selectedFilePath = msg.path;
        notifyListeners();
        break;
      case 'file_log':
        if (msg.logEntries != null) _state.fileLogEntries = msg.logEntries!;
        notifyListeners();
        break;
      case 'file_content':
        _state.fileContent = msg.fileContent;
        notifyListeners();
        break;
      case 'session_status_update':
        // Real-time update of session status & activity from server watcher
        if (msg.sessions != null && msg.sessions!.isNotEmpty) {
          bool updated = false;
          for (final updatedSession in msg.sessions!) {
            final idx = _state.sessions.indexWhere(
              (s) => s.sessionId == updatedSession.sessionId,
            );
            if (idx >= 0) {
              if (_state.sessions[idx].status != updatedSession.status) {
                _state.sessions[idx] = ServerSessionData(
                  sessionId: _state.sessions[idx].sessionId,
                  title: _state.sessions[idx].title,
                  agent: _state.sessions[idx].agent,
                  cwd: _state.sessions[idx].cwd,
                  createdAt: _state.sessions[idx].createdAt,
                  status: updatedSession.status,
                );
                updated = true;
              }
            }
          }
          if (updated) {
            notifyListeners();
          }
        }
        break;
    }
  }

  void _handleServerInfo(ServerMessage msg) {
    final actualHostId = msg.hostId ?? _ws.currentHostKey;
    _state.connected = true;
    _state.currentDeviceId = actualHostId;

    if (msg.workspaces != null && msg.workspaces!.isNotEmpty) {
      _state.currentWorkspace = msg.workspaces!.first;
    }

    // Persist/update device in HostStore — matching ArkTS WSClient.handleServerInfo
    final hostStore = HostStore();
    final hostname = msg.hostname ?? actualHostId;
    final currentUrl = _ws.currentUrl;

    hostStore.addOrUpdateDevice(DeviceEntry(
      hostId: actualHostId,
      name: hostname,
      urls: currentUrl.isNotEmpty ? [currentUrl] : [],
    ));
    hostStore.saveToDisk();

    // Mark online in runtime store (matching ArkTS HostRuntimeStore.markOnline)
    HostRuntimeStore().markOnline(actualHostId, currentUrl);
    hostStore.markOnline(actualHostId, currentUrl);

    // Request agents, models, and all sessions
    _ws.send(ClientMessage(type: 'list_agents'));
    requestSessionList();
    _onServerInfo();
  }

  void _handleAgentEvent(ServerMessage msg) {
    if (msg.acpUpdate != null) {
      final event = msg.acpUpdate!;

      if (_state.loadingSession) {
        _state.loadingSession = false;
      }

      switch (event.event) {
        case 'agent_thought_chunk':
          _flushStreamingText();
          _finishRunningTools(); // tool → thought: tool is done
          _state.accumulatorType = 'thinking';
          _state.streamingThinking += event.text ?? '';
          break;

        case 'agent_message_chunk':
          _flushStreamingThinking();
          _finishRunningTools(); // tool → text: tool is done
          {
            final text = event.text ?? '';
            if (text.isNotEmpty) {
              // Mirror ArkTS appendText: append to last assistant text bubble, else create new
              if (_state.messages.isNotEmpty) {
                final last = _state.messages.last;
                if (last.role == 'assistant' && last.type == 'text') {
                  final updated = MessageData(
                    role: last.role,
                    content: last.content + text,
                    type: 'text',
                    id: last.id,
                    sendStatus: 'sent',
                  );
                  _state.messages = [
                    ..._state.messages.sublist(0, _state.messages.length - 1),
                    updated,
                  ];
                  break;
                }
              }
              final cleaned = text.replaceFirst(RegExp(r'^\n+'), '');
              _state.messages = [
                ..._state.messages,
                MessageData(role: 'assistant', content: cleaned, type: 'text', sendStatus: 'sent'),
              ];
            }
          }
          break;

        case 'tool_call':
          _flushStreamingThinking();
          _state.accumulatorType = 'tool';
          final callId = event.toolCallId ?? '';
          final toolName = event.toolName?.isNotEmpty == true
              ? event.toolName!
              : (event.title?.isNotEmpty == true ? event.title! : callId);
          debugPrint('[ToolCall] start: name=$toolName callId=$callId kind=${event.kind}');
          _state.messages = [
            ..._state.messages,
            MessageData(
              role: 'assistant',
              content: toolName,
              type: 'tool_call',
              toolName: toolName,
              toolCallId: callId,
              toolStatus: 'pending',
              toolKind: event.kind ?? '',
            ),
          ];
          break;

        case 'tool_call_update':
          {
            final newContent = event.content ?? '';
            final newType = event.contentType ?? '';
            final status = event.toolStatus ?? (newContent.isNotEmpty ? 'completed' : 'in_progress');
            debugPrint('[ToolCall] update: callId=${event.toolCallId} len=${newContent.length} type=$newType status=$status');
            bool found = false;
            if (event.toolCallId != null && event.toolCallId!.isNotEmpty) {
              for (int i = _state.messages.length - 1; i >= 0; i--) {
                if (_state.messages[i].toolCallId == event.toolCallId) {
                  final m = _state.messages[i];
                  if (newContent.isNotEmpty) m.toolContent = (m.toolContent) + newContent;
                  if (newType.isNotEmpty) m.toolContentType = newType;
                  if (event.path != null && event.path!.isNotEmpty) m.toolPath = event.path!;
                  if (event.oldText != null && event.oldText!.isNotEmpty) m.toolOldText = event.oldText!;
                  if (event.newText != null && event.newText!.isNotEmpty) m.toolNewText = event.newText!;
                  if (event.terminalId != null && event.terminalId!.isNotEmpty) m.toolTerminalId = event.terminalId!;
                  m.toolStatus = status;
                  found = true;
                  debugPrint('[ToolCall] update OK: toolContent now ${m.toolContent.length} chars, status=${m.toolStatus}');
                  break;
                }
              }
            }
            if (!found) {
              // Fallback: update the last pending/in_progress tool card
              for (int i = _state.messages.length - 1; i >= 0; i--) {
                if (_state.messages[i].type == 'tool_call' &&
                    (_state.messages[i].toolStatus == 'pending' || _state.messages[i].toolStatus == 'in_progress' || _state.messages[i].toolStatus == 'running')) {
                  final m = _state.messages[i];
                  if (newContent.isNotEmpty) m.toolContent = (m.toolContent) + newContent;
                  if (newType.isNotEmpty) m.toolContentType = newType;
                  if (event.path != null && event.path!.isNotEmpty) m.toolPath = event.path!;
                  if (event.oldText != null && event.oldText!.isNotEmpty) m.toolOldText = event.oldText!;
                  if (event.newText != null && event.newText!.isNotEmpty) m.toolNewText = event.newText!;
                  if (event.terminalId != null && event.terminalId!.isNotEmpty) m.toolTerminalId = event.terminalId!;
                  m.toolStatus = status;
                  found = true;
                  debugPrint('[ToolCall] update (fallback last-running): OK');
                  break;
                }
              }
            }
            if (!found) {
              debugPrint('[ToolCall] update: NO card found for callId=${event.toolCallId}');
            }
          }
          break;

        case 'tool_call_end':
          debugPrint('[ToolCall] end: callId=${event.toolCallId} status=${event.toolStatus}');
          if (event.toolCallId != null) {
            for (int i = _state.messages.length - 1; i >= 0; i--) {
              if (_state.messages[i].toolCallId == event.toolCallId) {
                _state.messages[i].toolStatus = event.toolStatus ?? 'completed';
                break;
              }
            }
          }
          break;

        case 'plan':
          _handleAcpContent(event.planContent);
          break;
        case 'user_message_chunk':
          {
            final text = event.text ?? '';
            if (text.isNotEmpty) {
              if (_state.messages.isNotEmpty) {
                final last = _state.messages.last;
                if (last.role == 'user' && last.type == 'text') {
                  final updated = MessageData(
                    role: 'user',
                    content: last.content + text,
                    type: 'text',
                    id: last.id,
                    sendStatus: 'sent',
                  );
                  _state.messages = [
                    ..._state.messages.sublist(0, _state.messages.length - 1),
                    updated,
                  ];
                  break;
                }
              }
              _state.messages = [
                ..._state.messages,
                MessageData(role: 'user', content: text, type: 'text', sendStatus: 'sent'),
              ];
            }
          }
          break;
        case 'session_info_update':
          if (event.text != null && event.text!.isNotEmpty) {
            _state.sessionTitle = event.text!;
          }
          break;
        case 'config_option_update':
          if (event.config != null) _state.configOptions = event.config!;
          break;
        case 'available_commands_update':
          if (event.commands != null) _state.availableCommands = event.commands!;
          break;
        case 'usage_update':
          if (event.usage != null) _state.lastUsage = event.usage;
          break;
        case 'message':
          // ACP replay: consolidated message (user or assistant)
          _flushStreamingThinking();
          _flushStreamingText();
          _finishRunningTools();
          final mRole = event.messageRole ?? 'assistant';
          final mText = event.messageText ?? event.text ?? '';
          if (mText.isNotEmpty) {
            _state.messages = [
              ..._state.messages,
              MessageData(role: mRole, content: mText, type: 'text', sendStatus: 'sent'),
            ];
          }
          break;
        default:
          debugPrint('[ACP] unhandled event: ${event.event}');
          break;
      }
    }
    notifyListeners();
  }

  void _flushStreamingThinking() {
    if (_state.streamingThinking.isNotEmpty) {
      _state.messages = [
        ..._state.messages,
        MessageData(role: 'assistant', content: _state.streamingThinking, type: 'thinking', sendStatus: 'sent'),
      ];
      _state.streamingThinking = '';
    }
  }

  void _flushStreamingText() {
    if (_state.streamingText.isNotEmpty) {
      _state.messages = [
        ..._state.messages,
        MessageData(role: 'assistant', content: _state.streamingText, type: 'text', sendStatus: 'sent'),
      ];
      _state.streamingText = '';
    }
  }

  void _finishRunningTools() {
    for (final m in _state.messages) {
      // Server uses 'in_progress' (and sometimes 'running') for active tools.
      if (m.type == 'tool_call' &&
          (m.toolStatus == 'running' || m.toolStatus == 'in_progress')) {
        m.toolStatus = 'completed';
        debugPrint('[ToolCall] auto-completed: ${m.toolName}');
      }
    }
  }

  void _handleTurnEnded() {
    _state.turnActive = false;
    _finishRunningTools();
    _flushStreamingThinking();
    _flushStreamingText();
    _state.accumulatorType = '';
    _state.toolCallStack.clear();
    _state.lastMessageId = _state.messages.isNotEmpty
        ? _state.messages.last.id : '';
    // Persist last message id
    StorageService.getInstance().then((s) => s.setLastMessageId(_state.lastMessageId));
    notifyListeners();
  }

  void _handleAcpContent(AcpContent? content) {
    if (content == null) return;
    if (content.planEntries != null) {
      _state.planEntries = content.planEntries!;
    }
  }

  void _onServerInfo() {
    _state.connected = true;
    notifyListeners();
  }

  void _onAgentList(List<AgentInfo> agents) {
    _state.agentNames = agents.map((a) => a.name).toList();
    notifyListeners();
  }

  // Convenience
  String get lastModelId => _state.models.isNotEmpty && _state.modelIndex >= 0
      ? _state.models[_state.modelIndex].id : '';
}

/// Simple workspace provider — mirrors ArkTS WorkspaceStore
class WorkspaceProvider extends ChangeNotifier {
  int _currentIndex = 0;
  List<Map<String, String>> _workspaces = [];

  int get selectedIndex => _currentIndex;
  List<Map<String, String>> get workspaces => _workspaces;
  String get currentWorkspace => _workspaces.isNotEmpty && _currentIndex < _workspaces.length
      ? _workspaces[_currentIndex]['path'] ?? '' : '';

  void setWorkspaces(List<String> paths) {
    _workspaces = paths.map((p) => {'path': p, 'name': p.split(RegExp(r'[/\\]')).last}).toList();
    if (_currentIndex >= _workspaces.length) _currentIndex = 0;
    notifyListeners();
    _persistWorkspaces();
  }

  void addWorkspace(String name, String path) {
    if (_workspaces.any((w) => w['path'] == path)) return;
    _workspaces.add({'name': name, 'path': path});
    notifyListeners();
    _persistWorkspaces();
  }

  /// Called by server_info to sync workspaces from server
  void syncFromServer(List<String> paths) {
    for (final path in paths) {
      if (_workspaces.any((w) => w['path'] == path)) continue;
      _workspaces.add({'name': path.split(RegExp(r'[/\\]')).last, 'path': path});
    }
    notifyListeners();
    _persistWorkspaces();
  }

  Future<void> _persistWorkspaces() async {
    final storage = await StorageService.getInstance();
    final paths = _workspaces.map((w) => w['path'] ?? '').where((p) => p.isNotEmpty).toList();
    storage.putString('workspaces', paths.join('\n'));
  }

  Future<void> loadWorkspaces() async {
    final storage = await StorageService.getInstance();
    final raw = storage.getString('workspaces') ?? '';
    if (raw.isNotEmpty) {
      final paths = raw.split('\n').where((p) => p.isNotEmpty).toList();
      setWorkspaces(paths);
    }
  }

  void selectWorkspace(int index) {
    _currentIndex = index;
    notifyListeners();
  }
}
