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
import '../services/live_view_service.dart';
import '../services/notification_service.dart';

/// Core chat state provider — mirrors ArkTS ChatStore + Index.ets logic
class ChatProvider extends ChangeNotifier with WidgetsBindingObserver {
  final WSClient _ws;
  final WorkspaceProvider? _workspaceProvider;
  final ChatState _state = ChatState();
  ChatState get state => _state;
  bool _isInBackground = false;
  String _loadingSessionId = '';
  bool _startInFlight = false;
  bool _inputInFlight = false;
  bool _syncInFlight = false;
  Timer? _turnRequestTimer;
  Timer? _cancelTimer;
  Timer? _cursorPersistTimer;
  String _cursorSessionId = '';
  String _lastConnectionHostKey = '';
  int _selectionGeneration = 0;
  final Set<String> _processedMessageIds = <String>{};
  final List<ListenerDisposer> _listenerDisposers = [];
  late final OnPermissionActionCallback _permissionAction;
  static const int _turnRequestTimeoutMs = 15000;
  static const int _maxProcessedMessageIds = 4096;
  static const String _contextReplacedNotice =
      'Agent 上下文已重新创建。此前消息仍可查看，但新任务不会继承旧 Agent 上下文。';

  ChatProvider(this._ws, {WorkspaceProvider? workspaceProvider})
      : _workspaceProvider = workspaceProvider {
    _listenerDisposers.add(_ws.onMessage(_handleServerMessage));
    _listenerDisposers.add(_ws.onStateChange((connected, _) {
      _state.connected = connected;
      if (connected) {
        syncRequest();
      } else {
        _syncInFlight = false;
      }
      notifyListeners();
    }));
    _listenerDisposers.add(_ws.onServerInfo(_onServerInfo));
    _listenerDisposers.add(_ws.onError((error) {
      _state.errorMessage = error;
      notifyListeners();
    }));
    _listenerDisposers.add(_ws.onAgentList(_onAgentList));
    // Bridge WS connection phases to HostStore so UI shows online status
    _listenerDisposers.add(_ws.onPhaseChange((hostKey, phase, url) {
      if (hostKey.isEmpty) return;
      HostStore().setPhase(hostKey, phase, url: url);
      notifyListeners();
    }));
    // Observe app lifecycle for background notification decisions
    WidgetsBinding.instance.addObserver(this);
    // Route native permission notification actions into our permission flow
    _permissionAction = (String requestId, bool allow) {
      if (allow) {
        // 最小权限优先：通知栏只能安全地选择 allow_once；
        // 无 allow_once 选项时拒绝并让用户进应用选择
        final perm = _state.pendingPermissions[requestId];
        if (perm == null) return; // 已响应/过期通知，忽略
        final optionId = perm.options
            .where((o) => o.kind.startsWith('allow_once'))
            .firstOrNull
            ?.optionId;
        if (optionId != null && optionId.isNotEmpty) {
          permissionResponse(requestId, 'selected', optionId: optionId);
        } else {
          permissionResponse(requestId, 'cancelled');
        }
      } else {
        permissionResponse(requestId, 'cancelled');
      }
    };
    NotificationService.onPermissionAction = _permissionAction;
  }

  WSClient get ws => _ws;

  /// Test-only: inject a server message as if received from WS.
  @visibleForTesting
  void receiveServerMessage(ServerMessage msg) => _handleServerMessage(msg);

  /// Probe 发现 canonical hostId 变化时迁移旧 hostKey 的 workspace 分区。
  /// Session cursor（last_message_id 全局 key）不迁移：同一设备场景由后续 sync_request 重新对齐。
  void migrateHostKey(String oldKey, String newKey) {
    if (oldKey.isEmpty || newKey.isEmpty || oldKey == newKey) return;
    if (_state.currentDeviceId == oldKey) _state.currentDeviceId = newKey;
    _workspaceProvider?.migrateHostId(oldKey, newKey);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _isInBackground = true;
    } else if (state == AppLifecycleState.resumed) {
      _isInBackground = false;
      NotificationService.cancelAll();
    }
  }

  // ── Connection ──
  Future<void> initFromDisk() async {
    final storage = await StorageService.getInstance();
    final persisted = storage.getLastMessageIdSync();
    final cursor = SessionMessageCursor.parse(persisted);
    if (cursor != null) {
      _state.lastMessageId = cursor.messageId;
      _cursorSessionId = cursor.sessionId;
    } else {
      _state.lastMessageId = '';
      if (persisted.isNotEmpty) await storage.setLastMessageId('');
    }
    await DeviceAgentStore().loadFromDisk();
  }

  Future<void> connectToUrl(String url,
      {String? hostKey, String? authToken}) async {
    _selectionGeneration++;
    final normalizedUrl = _normalizeUrl(url);
    if (normalizedUrl.isEmpty) return;

    final hk = hostKey ?? _getHostKeyForUrl(normalizedUrl);
    _beginConnectionBoundary(hk);
    _state.currentDeviceId = hk;
    final token = authToken ?? _authTokenForHost(hk, normalizedUrl);

    // Save URL to storage immediately (like ArkTS Index.ets:635-636)
    final storage = await StorageService.getInstance();
    storage.putString('server_url', normalizedUrl);

    // Mark connecting in runtime store BEFORE connecting
    HostRuntimeStore().setPhase(hk, HostPhase.connecting, url: normalizedUrl);

    _ws.connect(normalizedUrl, hk, authToken: token);
  }

  Future<void> connectBest(List<String> candidates,
      {String? hostKey, String? authToken}) async {
    final selectionGeneration = ++_selectionGeneration;
    final normalized = candidates
        .map((u) => _normalizeUrl(u))
        .where((u) => u.isNotEmpty)
        .toList();
    if (normalized.isEmpty) return;

    final hk = hostKey ?? _getHostKeyForUrl(normalized.first);
    final token = authToken ?? _authTokenForHost(hk, normalized.first);
    final selectedUrl = await _ws.probeBest(
      normalized,
      hk,
      authToken: token,
    );
    if (selectedUrl == null || selectionGeneration != _selectionGeneration) {
      return;
    }

    final storage = await StorageService.getInstance();
    if (selectionGeneration != _selectionGeneration) return;

    _beginConnectionBoundary(hk);
    _state.currentDeviceId = hk;
    HostRuntimeStore().setPhase(hk, HostPhase.connecting, url: selectedUrl);
    final persistence = storage.putString('server_url', selectedUrl);
    _ws.connect(selectedUrl, hk, authToken: token);
    await persistence;
  }

  void _beginConnectionBoundary(String hostKey) {
    if (_lastConnectionHostKey.isNotEmpty &&
        _lastConnectionHostKey != hostKey) {
      _resetCursor(clearPersisted: true);
      _processedMessageIds.clear();
      _state.sessionId = '';
      _state.contextReplacedNotice = '';
      _state.turnActive = false;
      _startInFlight = false;
      _inputInFlight = false;
      _turnRequestTimer?.cancel();
    }
    _lastConnectionHostKey = hostKey;
  }

  String? _authTokenForHost(String hostKey, String url) {
    final normalizedUrl = _normalizeUrl(url);
    for (final device in HostStore().devices) {
      if (device.hostId == hostKey ||
          device.name == hostKey ||
          device.urls.any((candidate) => _normalizeUrl(candidate) == normalizedUrl) ||
          (device.relayUrl != null &&
              _normalizeUrl(device.relayUrl!) == normalizedUrl)) {
        final token = device.authToken?.trim();
        return token == null || token.isEmpty ? null : token;
      }
    }
    return null;
  }

  String _normalizeUrl(String raw) {
    String url = raw.trim();
    if (url.startsWith('http://')) url = url.replaceFirst('http://', 'ws://');
    if (url.startsWith('https://'))
      url = url.replaceFirst('https://', 'wss://');
    if (!url.startsWith('ws://') && !url.startsWith('wss://'))
      url = 'ws://$url';
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
    _selectionGeneration++;
    _ws.disconnect();
    _turnRequestTimer?.cancel();
    _turnRequestTimer = null;
    _startInFlight = false;
    _inputInFlight = false;
    _syncInFlight = false;
    _state.connected = false;
    _state.currentDeviceId = '';
    _state.sessionTitle = '';
    notifyListeners();
  }

  // ── Messaging ──
  void sendMessage(String text) {
    if (text == '__cancel__') {
      if (_state.turnActive && !_state.cancelling) {
        _state.cancelling = true;
        _clearTurnRequest();
        _ws.send(ClientMessage(type: 'cancel', sessionId: _state.sessionId));
        _cancelTimer?.cancel();
        _cancelTimer = Timer(const Duration(seconds: 10), () {
          _cancelTimer = null;
          _state.cancelling = false;
          _state.turnActive = false;
          _setCurrentSessionStatus('idle');
          notifyListeners();
        });
        notifyListeners();
      }
      return;
    }

    if (text.trim().isEmpty) return;
    if (!_ws.isConnected) {
      _state.errorMessage = '连接未就绪，请稍后重试';
      notifyListeners();
      return;
    }
    if (_state.cancelling) {
      _state.errorMessage = '正在取消当前回合，请稍候';
      notifyListeners();
      return;
    }
    if (_state.turnActive || _startInFlight || _inputInFlight) {
      _state.errorMessage = '当前回合正在运行，请等待完成';
      notifyListeners();
      return;
    }

    final starting = _state.sessionId.isEmpty;
    if (starting) {
      _state.contextReplacedNotice = '';
      _startInFlight = true;
      _state.turnActive = true;
      _resetCursor(clearPersisted: true);
      _appendUserMessage(text);
      notifyListeners();
      _armTurnRequestTimeout('start');
      _ws.send(ClientMessage(
        type: 'start',
        agent: _state.selectedAgentName.isNotEmpty
            ? _state.selectedAgentName
            : null,
        cwd:
            _state.currentWorkspace.isNotEmpty ? _state.currentWorkspace : null,
        model:
            _state.modelIndex >= 0 && _state.modelIndex < _state.models.length
                ? _state.models[_state.modelIndex].id
                : null,
        prompt: text,
      ));
    } else {
      _inputInFlight = true;
      _state.turnActive = true;
      _appendUserMessage(text);
      notifyListeners();
      _armTurnRequestTimeout('input');
      _ws.send(ClientMessage(
        type: 'input',
        sessionId: _state.sessionId,
        text: text,
      ));
    }
  }

  void _appendUserMessage(String text) {
    _state.messages = [
      ..._state.messages,
      MessageData(role: 'user', content: text, type: 'text', sendStatus: 'sent'),
    ];
    _setCurrentSessionStatus('running');
  }

  void _armTurnRequestTimeout(String kind) {
    _turnRequestTimer?.cancel();
    _turnRequestTimer = Timer(
      const Duration(milliseconds: _turnRequestTimeoutMs),
      () {
        final pending = kind == 'start' ? _startInFlight : _inputInFlight;
        if (!pending) return;
        _startInFlight = false;
        _inputInFlight = false;
        _state.turnActive = false;
        _setCurrentSessionStatus('idle');
        _state.errorMessage = kind == 'start'
            ? '启动会话超时，请检查 Bridge 连接'
            : '发送消息超时，请重试';
        _turnRequestTimer = null;
        notifyListeners();
      },
    );
  }

  void _clearTurnRequest() {
    _startInFlight = false;
    _inputInFlight = false;
    _turnRequestTimer?.cancel();
    _turnRequestTimer = null;
  }

  void _clearCancelling() {
    _cancelTimer?.cancel();
    _cancelTimer = null;
    _state.cancelling = false;
  }

  void _markInputStarted() {
    if (!_inputInFlight) return;
    _inputInFlight = false;
    _turnRequestTimer?.cancel();
    _turnRequestTimer = null;
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
      _ws.send(ClientMessage(type: 'cancel', sessionId: _state.sessionId));
      _setCurrentSessionStatus('idle');
    }
    _clearTurnRequest();
    _resetCursor(clearPersisted: true);
    _processedMessageIds.clear();
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
    _ws.send(
        ClientMessage(type: 'list_models', agent: _state.selectedAgentName));
  }

  // ── Sessions ──
  void loadSession(String sessionId,
      {String? agent, String? cwd, String? title}) {
    if (_loadingSessionId == sessionId) return;
    _loadingSessionId = sessionId;
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

    if (targetAgent.isEmpty &&
        matchingSession.agent != null &&
        matchingSession.agent!.isNotEmpty) {
      targetAgent = matchingSession.agent!;
    }
    if (targetAgent.isEmpty) {
      targetAgent = _state.selectedAgentName;
    } else {
      _state.selectedAgentName = targetAgent;
    }

    if (targetCwd.isEmpty &&
        matchingSession.cwd != null &&
        matchingSession.cwd!.isNotEmpty) {
      targetCwd = matchingSession.cwd!;
    }
    if (targetCwd.isNotEmpty) {
      _state.currentWorkspace = targetCwd;
    }

    if (_state.sessionId != sessionId) {
      _resetCursor(clearPersisted: true);
      _processedMessageIds.clear();
      _state.contextReplacedNotice = '';
    }
    _state.sessionId = sessionId;
    _clearTurnRequest();
    // Clear before sending so a fast replay cannot race with stale messages.
    _state.loadingSession = true;
    _state.messages = [];
    _state.planEntries = [];
    _state.streamingThinking = '';
    _state.streamingText = '';
    _state.turnActive = false;
    notifyListeners();
    _ws.send(ClientMessage(
      type: 'load_session',
      sessionId: sessionId,
      cwd: _state.currentWorkspace.isNotEmpty ? _state.currentWorkspace : null,
      agent: targetAgent,
    ));
  }

  bool isPinned(String sessionId) =>
      _state.pinnedSessionIds.contains(sessionId);

  void togglePinSession(String sessionId) {
    if (_state.pinnedSessionIds.contains(sessionId)) {
      _state.pinnedSessionIds.remove(sessionId);
    } else {
      _state.pinnedSessionIds.add(sessionId);
    }
    notifyListeners();
  }

  void closeSession(String sessionId) {
    _ws.send(ClientMessage(type: 'close_session', sessionId: sessionId));
    _state.sessions.removeWhere((s) => s.sessionId == sessionId);
    if (_state.sessionId == sessionId) {
      _clearTurnRequest();
      _resetCursor(clearPersisted: true);
      _processedMessageIds.clear();
      _state.sessionId = '';
      _state.sessionTitle = '';
      _state.contextReplacedNotice = '';
      _state.turnActive = false;
    }
    notifyListeners();
  }

  void renameSession(String sessionId, String newTitle) {
    // Optimistic local update
    final idx = _state.sessions.indexWhere((s) => s.sessionId == sessionId);
    if (idx >= 0) {
      final old = _state.sessions[idx];
      _state.sessions[idx] = ServerSessionData(
        sessionId: old.sessionId,
        title: newTitle,
        agent: old.agent,
        cwd: old.cwd,
        createdAt: old.createdAt,
        lastActivity: old.lastActivity,
        status: old.status,
      );
      if (_state.sessionId == sessionId) {
        _state.sessionTitle = newTitle;
      }
      notifyListeners();
    }
    // Send rename to server for persistence
    _ws.send(ClientMessage(
        type: 'rename_session', sessionId: sessionId, text: newTitle));
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
  void permissionResponse(String requestId, String outcome,
      {String? optionId}) {
    // 按 requestId 精确查找并移除，并发请求互不串线；
    // 已响应/不存在的请求直接忽略（过期通知、重复响应）。
    final perm = _state.pendingPermissions.remove(requestId);
    if (perm == null) return;
    _ws.send(ClientMessage(
      type: 'permission_response',
      sessionId: perm.sessionId.isNotEmpty ? perm.sessionId : _state.sessionId,
      requestId: requestId,
      outcome: outcome,
      optionId: optionId,
    ));
    NotificationService.cancelForRequest(requestId);
    notifyListeners();
  }

  void rejectPermissionOnClose() {
    final pending = _state.pendingPermission;
    if (pending != null) {
      permissionResponse(pending.requestId, 'cancelled');
    }
  }

  // ── Agent Management ──
  void requestAgents() => _ws.send(ClientMessage(type: 'list_agents'));
  void listRegistryAgents() =>
      _ws.send(ClientMessage(type: 'list_registry_agents'));
  void installAgent(String agentId) =>
      _ws.send(ClientMessage(type: 'install_agent', agentId: agentId));
  void uninstallAgent(String agentId) =>
      _ws.send(ClientMessage(type: 'uninstall_agent', agentId: agentId));
  void installCustomAgent(String command, List<String> args, String name) {
    _ws.send(ClientMessage(
        type: 'install_custom_agent',
        command: command,
        args: args,
        name: name));
  }

  // ── Sync after reconnect ──
  void syncRequest() {
    final sessionId = _state.sessionId;
    if (sessionId.isEmpty || !_ws.isConnected || _syncInFlight) return;
    final cursor = SessionMessageCursor.parse(_state.lastMessageId);
    if (cursor != null && cursor.sessionId != sessionId) {
      _resetCursor(clearPersisted: true);
    }
    _syncInFlight = true;
    _ws.send(ClientMessage(
      type: 'sync_request',
      sessionId: sessionId,
      lastMessageId: cursor?.messageId,
    ));
  }

  void _resetCursor({bool clearPersisted = false}) {
    _state.lastMessageId = '';
    _cursorSessionId = '';
    _cursorPersistTimer?.cancel();
    _cursorPersistTimer = null;
    if (clearPersisted) {
      StorageService.getInstance().then((storage) => storage.setLastMessageId(''));
    }
  }

  void _scheduleCursorPersist() {
    _cursorPersistTimer?.cancel();
    final value = _state.lastMessageId;
    _cursorPersistTimer = Timer(const Duration(milliseconds: 250), () {
      StorageService.getInstance().then((storage) {
        storage.setLastMessageId(value);
      });
      _cursorPersistTimer = null;
    });
  }

  bool _acceptMessageId(String? raw, {String? sessionId}) {
    if (raw == null || raw.isEmpty) return true;
    final cursor = SessionMessageCursor.parse(raw);
    if (cursor != null) {
      final expectedSession = sessionId ?? _state.sessionId;
      if (expectedSession.isNotEmpty && cursor.sessionId != expectedSession) {
        return false;
      }
      if (_cursorSessionId.isNotEmpty &&
          _cursorSessionId != cursor.sessionId &&
          _state.sessionId.isNotEmpty) {
        return false;
      }
      final previous = SessionMessageCursor.parse(_state.lastMessageId);
      if (previous != null &&
          previous.sessionId == cursor.sessionId &&
          cursor.sequence <= previous.sequence) {
        return false;
      }
      _cursorSessionId = cursor.sessionId;
      _state.lastMessageId = cursor.messageId;
      _scheduleCursorPersist();
    }
    if (!_processedMessageIds.add(raw)) return false;
    if (_processedMessageIds.length > _maxProcessedMessageIds) {
      _processedMessageIds.remove(_processedMessageIds.first);
    }
    return true;
  }

  // ── Server message routing ──
  void _handleServerMessage(ServerMessage msg) {
    if (!_acceptMessageId(msg.messageId, sessionId: msg.sessionId)) return;
    switch (msg.type) {
      case 'server_info':
        _handleServerInfo(msg);
        break;
      case 'ready':
        _state.connected = true;
        syncRequest();
        notifyListeners();
        break;
      case 'ack':
      case 'start_ack':
        if (_startInFlight) _armTurnRequestTimeout('start');
        break;
      case 'input_ack':
        _markInputStarted();
        break;
      case 'start_failed':
        _clearTurnRequest();
        _state.turnActive = false;
        _state.errorMessage = msg.text ?? 'Agent 启动失败';
        notifyListeners();
        break;
      case 'session_context_replaced':
        if (!_isEventForCurrentSession(msg.sessionId)) {
          break;
        }
        _state.contextReplacedNotice = _contextReplacedNotice;
        notifyListeners();
        break;
      case 'session_started':
        final sessionId = msg.sessionId ?? '';
        if (sessionId.isEmpty) break;
        if (_state.sessionId != sessionId) {
          _state.contextReplacedNotice = '';
        }
        if (_cursorSessionId.isNotEmpty && _cursorSessionId != sessionId) {
          _resetCursor(clearPersisted: true);
          _processedMessageIds.clear();
        }
        _cursorSessionId = sessionId;
        _clearTurnRequest();
        _syncInFlight = false;
        if (_loadingSessionId == sessionId) _loadingSessionId = '';
        final previous = _state.sessions
            .where(
              (s) => s.sessionId == sessionId,
            )
            .firstOrNull;
        _state.sessionId = sessionId;
        _state.sessionTitle = msg.title ?? previous?.title ?? sessionId;
        // Resume: server sends session_started with resumed: true.
        // Keep turnActive false so the next message continues via 'input'.
        if (msg.resumed == true) {
          _state.turnActive = false;
        }
        if (sessionId.isNotEmpty) {
          final now = DateTime.now().millisecondsSinceEpoch;
          final session = ServerSessionData(
            sessionId: sessionId,
            title: _state.sessionTitle,
            agent: msg.agent ?? previous?.agent ?? _state.selectedAgentName,
            cwd: previous?.cwd ??
                (_state.currentWorkspace.isNotEmpty
                    ? _state.currentWorkspace
                    : null),
            createdAt: previous?.createdAt ?? now,
            lastActivity: msg.resumed == true ? previous?.lastActivity : now,
            status: msg.resumed == true
                ? (previous?.status ?? 'idle')
                : (_state.turnActive ? 'running' : 'idle'),
          );
          final index = _state.sessions.indexWhere(
            (s) => s.sessionId == sessionId,
          );
          final sessions = [..._state.sessions];
          if (index >= 0) {
            sessions[index] = session;
          } else {
            sessions.insert(0, session);
          }
          _state.sessions = sessions;
        }
        // Safety net: clear loading state if history replay already completed
        _state.loadingSession = false;
        notifyListeners();
        break;
      case 'session_ended':
        if (msg.sessionId != null &&
            !_isEventForCurrentSession(msg.sessionId)) {
          break;
        }
        _clearTurnRequest();
        _resetCursor(clearPersisted: true);
        _processedMessageIds.clear();
        _state.turnActive = false;
        _state.sessionId = '';
        _state.sessionTitle = '';
        _state.contextReplacedNotice = '';
        notifyListeners();
        break;
      case 'resumed_session':
        final sessionId = msg.sessionId ?? '';
        if (sessionId.isNotEmpty &&
            _cursorSessionId.isNotEmpty &&
            _cursorSessionId != sessionId) {
          _resetCursor(clearPersisted: true);
          _processedMessageIds.clear();
        }
        _cursorSessionId = sessionId;
        _clearTurnRequest();
        _state.sessionId = sessionId;
        _state.turnActive = false;
        _state.loadingSession = false;
        notifyListeners();
        break;
      case 'agent_event':
        if (!_isEventForCurrentSession(msg.sessionId)) {
          break;
        }
        _handleAgentEvent(msg);
        break;
      case 'session_cancelled':
        // Cancel ACK only: 服务端已受理取消请求，不代表回合结束。
        // 不清 cancelling、不取消 10s 兜底 timer；由 turn_ended /
        // 当前会话 error / session_closed / 10s 兜底结束取消状态
        // （防止 ACP 永不发 turn_ended 时输入框永久锁死）。
        if (msg.sessionId != null &&
            !_isEventForCurrentSession(msg.sessionId)) {
          break;
        }
        break;
      case 'turn_ended':
        if (!_isEventForCurrentSession(msg.sessionId)) {
          break;
        }
        _handleTurnEnded();
        // Remove live view when turn completes
        LiveViewService.stop();
        break;
      case 'model_list':
        if (msg.models != null) _state.models = msg.models!;
        if (msg.modes != null) _state.modes = msg.modes!;
        notifyListeners();
        break;
      case 'session_list':
        if (msg.sessions != null) {
          final sessions = [...msg.sessions!];
          final active = _state.sessions
              .where((s) => s.sessionId == _state.sessionId)
              .firstOrNull;
          if (active != null) {
            final index = sessions.indexWhere(
              (s) => s.sessionId == active.sessionId,
            );
            if (index >= 0) {
              sessions[index] = active;
            } else {
              sessions.insert(0, active);
            }
          }
          _state.sessions = sessions;
        }
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
        if (msg.sessionId != null &&
            !_isEventForCurrentSession(msg.sessionId)) {
          break;
        }
        _loadingSessionId = '';
        _syncInFlight = false;
        _clearTurnRequest();
        _clearCancelling();
        _state.turnActive = false;
        _state.pendingPermissions.clear();
        NotificationService.cancelAll();
        if (msg.text != null) {
          _state.errorMessage = msg.text!;
          _setCurrentSessionStatus('idle');
        }
        notifyListeners();
        break;
      case 'permission_request':
        if (msg.requestId != null) {
          _state.pendingPermissions[msg.requestId!] = PendingPermission(
            requestId: msg.requestId!,
            toolCall: msg.toolCall?.toString() ?? '',
            sessionId: msg.sessionId ?? '',
            options: (msg.options ?? [])
                .map((o) => PermissionOption(
                      optionId: o['optionId']?.toString() ?? '',
                      name: o['name']?.toString() ?? '',
                      kind: o['kind']?.toString() ?? '',
                    ))
                .toList(),
          );
          // Show OS notification only when app is in background；
          // 每个请求独立通知（ID 由 requestId 派生，互不覆盖）
          if (_isInBackground) {
            final toolCallStr = msg.toolCall?.toString() ?? '';
            NotificationService.showPermissionNotification(
              requestId: msg.requestId!,
              toolName: msg.acpUpdate?.toolName ?? 'Tool',
              command: toolCallStr,
              path: msg.path ?? '',
            );
          }
        }
        notifyListeners();
        break;
      case 'session_closed':
        if (msg.sessionId != null &&
            !_isEventForCurrentSession(msg.sessionId)) {
          break;
        }
        _clearTurnRequest();
        _clearCancelling();
        _resetCursor(clearPersisted: true);
        _processedMessageIds.clear();
        _state.turnActive = false;
        _state.pendingPermissions.clear();
        NotificationService.cancelAll();
        _state.sessionId = '';
        notifyListeners();
        break;
      case 'sync_response':
        _syncInFlight = false;
        final sessionId = msg.sessionId ?? _state.sessionId;
        if (msg.turnActive != null) _state.turnActive = msg.turnActive!;
        if (msg.overflow == true) {
          _handleSyncOverflow(sessionId);
          break;
        }
        for (final entry in msg.entries ?? const <Map<String, dynamic>>[]) {
          final rawPayload = entry['payload'];
          if (rawPayload is! Map) continue;
          final payload = Map<String, dynamic>.from(rawPayload);
          final rawId = entry['messageId']?.toString() ??
              payload['messageId']?.toString();
          if (!_acceptMessageId(rawId, sessionId: sessionId)) continue;
          if (rawId != null && rawId.isNotEmpty) payload['messageId'] = rawId;
          final syntheticJson = <String, dynamic>{
            'type': 'agent_event',
            'sessionId': sessionId,
            'messageId': rawId,
            'event': payload,
          };
          final eventMsg = ServerMessage.fromJson(syntheticJson);
          _handleAgentEvent(eventMsg);
        }
        notifyListeners();
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
              if (_state.sessions[idx].status != updatedSession.status ||
                  _state.sessions[idx].lastActivity !=
                      updatedSession.lastActivity) {
                _state.sessions[idx] = ServerSessionData(
                  sessionId: _state.sessions[idx].sessionId,
                  title: _state.sessions[idx].title,
                  agent: _state.sessions[idx].agent,
                  cwd: _state.sessions[idx].cwd,
                  createdAt: _state.sessions[idx].createdAt,
                  lastActivity: updatedSession.lastActivity ??
                      _state.sessions[idx].lastActivity,
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

  void _handleSyncOverflow(String sessionId) {
    _clearTurnRequest();
    _resetCursor(clearPersisted: true);
    _processedMessageIds.clear();
    _state.messages = [];
    _state.planEntries = [];
    _state.toolCallStack.clear();
    _state.accumulatorType = '';
    _state.streamingThinking = '';
    _state.streamingText = '';
    _state.turnActive = false;
    _state.loadingSession = sessionId.isNotEmpty;
    _loadingSessionId = sessionId;
    _state.errorMessage = '消息同步窗口已过期，正在重新加载';
    if (sessionId.isNotEmpty) {
      _ws.send(ClientMessage(
        type: 'load_session',
        sessionId: sessionId,
        cwd: _state.currentWorkspace.isNotEmpty ? _state.currentWorkspace : null,
        agent: _state.selectedAgentName.isNotEmpty ? _state.selectedAgentName : null,
      ));
    }
    notifyListeners();
  }

  void _handleServerInfo(ServerMessage msg) {
    final actualHostId = msg.hostId ?? _ws.currentHostKey;
    if (actualHostId.isNotEmpty &&
        _state.currentDeviceId.isNotEmpty &&
        _state.currentDeviceId != actualHostId) {
      _resetCursor(clearPersisted: true);
      _processedMessageIds.clear();
      _state.sessionId = '';
      _state.turnActive = false;
    }
    _state.connected = true;
    _state.errorMessage = '';
    _state.currentDeviceId = actualHostId;

    if (msg.workspaces != null) {
      _workspaceProvider?.setActiveHost(actualHostId);
      _workspaceProvider?.syncFromServer(msg.workspaces!);
      final providerWorkspace = _workspaceProvider?.currentWorkspace ?? '';
      if (providerWorkspace.isNotEmpty) {
        _state.currentWorkspace = providerWorkspace;
      } else if (msg.workspaces!.isNotEmpty) {
        _state.currentWorkspace = msg.workspaces!.first;
      }
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
    // server_info is the authenticated connection-ready boundary; replay any
    // events missed while this socket was down before accepting new input.
    syncRequest();
    _onServerInfo();
  }

  void _handleAgentEvent(ServerMessage msg) {
    if (msg.acpUpdate != null) {
      final event = msg.acpUpdate!;
      if (_state.loadingSession) {
        _state.loadingSession = false;
      }
      _markInputStarted();

      switch (event.event) {
        case 'turn_started':
          _state.turnActive = true;
          break;
        case 'turn_ended':
          _handleTurnEnded();
          break;
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
                MessageData(
                    role: 'assistant',
                    content: cleaned,
                    type: 'text',
                    sendStatus: 'sent'),
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
          debugPrint(
              '[ToolCall] start: name=$toolName callId=$callId kind=${event.kind}');
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
          // Show live view for the new tool
          LiveViewService.updateProgress(
            progress: 0.0,
            statusText: 'Starting $toolName...',
            title: toolName,
          );
          break;

        case 'tool_call_update':
          {
            final newContent = event.content ?? '';
            final newType = event.contentType ?? '';
            final status = event.toolStatus ??
                (newContent.isNotEmpty ? 'completed' : 'in_progress');
            debugPrint(
                '[ToolCall] update: callId=${event.toolCallId} len=${newContent.length} type=$newType status=$status');
            bool found = false;
            String toolName = '';
            if (event.toolCallId != null && event.toolCallId!.isNotEmpty) {
              for (int i = _state.messages.length - 1; i >= 0; i--) {
                if (_state.messages[i].toolCallId == event.toolCallId) {
                  final m = _state.messages[i];
                  if (newContent.isNotEmpty)
                    m.toolContent = (m.toolContent) + newContent;
                  if (newType.isNotEmpty) m.toolContentType = newType;
                  if (event.path != null && event.path!.isNotEmpty)
                    m.toolPath = event.path!;
                  if (event.oldText != null && event.oldText!.isNotEmpty)
                    m.toolOldText = event.oldText!;
                  if (event.newText != null && event.newText!.isNotEmpty)
                    m.toolNewText = event.newText!;
                  if (event.terminalId != null && event.terminalId!.isNotEmpty)
                    m.toolTerminalId = event.terminalId!;
                  m.toolStatus = status;
                  toolName = m.toolName;
                  found = true;
                  debugPrint(
                      '[ToolCall] update OK: toolContent now ${m.toolContent.length} chars, status=${m.toolStatus}');
                  break;
                }
              }
            }
            if (!found) {
              // Fallback: update the last pending/in_progress tool card
              for (int i = _state.messages.length - 1; i >= 0; i--) {
                if (_state.messages[i].type == 'tool_call' &&
                    (_state.messages[i].toolStatus == 'pending' ||
                        _state.messages[i].toolStatus == 'in_progress' ||
                        _state.messages[i].toolStatus == 'running')) {
                  final m = _state.messages[i];
                  if (newContent.isNotEmpty)
                    m.toolContent = (m.toolContent) + newContent;
                  if (newType.isNotEmpty) m.toolContentType = newType;
                  if (event.path != null && event.path!.isNotEmpty)
                    m.toolPath = event.path!;
                  if (event.oldText != null && event.oldText!.isNotEmpty)
                    m.toolOldText = event.oldText!;
                  if (event.newText != null && event.newText!.isNotEmpty)
                    m.toolNewText = event.newText!;
                  if (event.terminalId != null && event.terminalId!.isNotEmpty)
                    m.toolTerminalId = event.terminalId!;
                  m.toolStatus = status;
                  toolName = m.toolName;
                  found = true;
                  debugPrint('[ToolCall] update (fallback last-running): OK');
                  break;
                }
              }
            }
            if (!found) {
              debugPrint(
                  '[ToolCall] update: NO card found for callId=${event.toolCallId}');
            }
            // Update live view with progress
            if (toolName.isNotEmpty) {
              final int totalLen = newContent.length;
              // Scale progress based on content accumulation; cap at 90% until completed
              final double progress = status == 'completed' ||
                      status == 'cancelled' ||
                      status == 'failed'
                  ? 1.0
                  : (totalLen > 0 ? (totalLen / 1000).clamp(0.05, 0.9) : 0.05);
              LiveViewService.updateProgress(
                progress: progress,
                statusText: status == 'completed'
                    ? 'Completed'
                    : status == 'cancelled'
                        ? 'Cancelled'
                        : 'Running... (${totalLen}B)',
                title: toolName,
              );
            }
          }
          break;

        case 'tool_call_end':
          debugPrint(
              '[ToolCall] end: callId=${event.toolCallId} status=${event.toolStatus}');
          if (event.toolCallId != null) {
            for (int i = _state.messages.length - 1; i >= 0; i--) {
              if (_state.messages[i].toolCallId == event.toolCallId) {
                _state.messages[i].toolStatus = event.toolStatus ?? 'completed';
                final toolName = _state.messages[i].toolName;
                // Show completed status on live view immediately
                if (toolName.isNotEmpty) {
                  LiveViewService.updateProgress(
                    progress: 1.0,
                    statusText: 'Completed',
                    title: toolName,
                  );
                }
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
                MessageData(
                    role: 'user',
                    content: text,
                    type: 'text',
                    sendStatus: 'sent'),
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
          if (event.commands != null)
            _state.availableCommands = event.commands!;
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
              MessageData(
                  role: mRole,
                  content: mText,
                  type: 'text',
                  sendStatus: 'sent'),
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
        MessageData(
            role: 'assistant',
            content: _state.streamingThinking,
            type: 'thinking',
            sendStatus: 'sent'),
      ];
      _state.streamingThinking = '';
    }
  }

  void _flushStreamingText() {
    if (_state.streamingText.isNotEmpty) {
      _state.messages = [
        ..._state.messages,
        MessageData(
            role: 'assistant',
            content: _state.streamingText,
            type: 'text',
            sendStatus: 'sent'),
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

  void _setCurrentSessionStatus(String status) {
    final sessionId = _state.sessionId;
    if (sessionId.isEmpty) return;
    final index = _state.sessions.indexWhere(
      (s) => s.sessionId == sessionId,
    );
    if (index < 0) return;

    final current = _state.sessions[index];
    final sessions = [..._state.sessions];
    sessions[index] = ServerSessionData(
      sessionId: current.sessionId,
      title: current.title,
      agent: current.agent,
      cwd: current.cwd,
      createdAt: current.createdAt,
      lastActivity: DateTime.now().millisecondsSinceEpoch,
      status: status,
    );
    _state.sessions = sessions;
  }

  /// 事件是否属于当前会话：加载历史中允许当前会话或加载会话的事件；
  /// 事件/当前会话 id 为空（旧协议或启动早期）时放行。
  bool _isEventForCurrentSession(String? eventSessionId) {
    final current = _state.sessionId;
    return eventSessionId == null ||
        eventSessionId.isEmpty ||
        current.isEmpty ||
        eventSessionId == current ||
        eventSessionId == _loadingSessionId;
  }

  void _handleTurnEnded() {
    _clearTurnRequest();
    _clearCancelling();
    _state.turnActive = false;
    _setCurrentSessionStatus('idle');
    _finishRunningTools();
    _flushStreamingThinking();
    _flushStreamingText();
    _state.accumulatorType = '';
    _state.toolCallStack.clear();
    // lastMessageId is the bridge's sessionId:seq cursor, never a local
    // MessageData id. It is persisted when each canonical event is accepted.
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

  @override
  void dispose() {
    _selectionGeneration++;
    for (final dispose in _listenerDisposers) {
      dispose();
    }
    _listenerDisposers.clear();
    _turnRequestTimer?.cancel();
    _cancelTimer?.cancel();
    _cursorPersistTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    if (identical(NotificationService.onPermissionAction, _permissionAction)) {
      NotificationService.onPermissionAction = null;
    }
    super.dispose();
  }

  // Convenience
  String get lastModelId => _state.models.isNotEmpty && _state.modelIndex >= 0
      ? _state.models[_state.modelIndex].id
      : '';
}

class HostWorkspaceState {
  List<Map<String, String>> workspaces;
  int selectedIndex;

  HostWorkspaceState({
    List<Map<String, String>>? workspaces,
    this.selectedIndex = 0,
  }) : workspaces = workspaces ?? <Map<String, String>>[];
}

class WorkspaceProvider extends ChangeNotifier {
  final Map<String, HostWorkspaceState> _byHost = {};
  String _activeHostId = '';

  HostWorkspaceState _stateFor(String hostId) =>
      _byHost.putIfAbsent(hostId, HostWorkspaceState.new);

  HostWorkspaceState get _activeState => _stateFor(_activeHostId);

  int get selectedIndex => _activeState.selectedIndex;
  List<Map<String, String>> get workspaces => _activeState.workspaces;
  String get currentWorkspace {
    final state = _activeState;
    return state.selectedIndex >= 0 &&
            state.selectedIndex < state.workspaces.length
        ? state.workspaces[state.selectedIndex]['path'] ?? ''
        : '';
  }

  void setActiveHost(String hostId) {
    if (hostId == _activeHostId) return;
    _persistWorkspaces();
    _activeHostId = hostId;
    _stateFor(hostId);
    notifyListeners();
    _loadHostState(hostId);
  }

  Future<void> migrateHostId(String oldId, String newId) async {
    if (oldId.isEmpty || newId.isEmpty || oldId == newId) return;

    final state = _byHost.remove(oldId);
    if (state != null && !_byHost.containsKey(newId)) {
      _byHost[newId] = state;
    }
    if (_activeHostId == oldId) _activeHostId = newId;

    final storage = await StorageService.getInstance();
    final oldWorkspacesKey = 'workspaces_$oldId';
    final oldIndexKey = 'workspace_index_$oldId';
    final newPartitionExists =
        storage.getObject('workspaces_$newId') != null ||
            storage.getObject('workspace_index_$newId') != null;
    if (newPartitionExists) {
      await storage.remove(oldWorkspacesKey);
      await storage.remove(oldIndexKey);
    } else {
      final oldWorkspaces = storage.getObject(oldWorkspacesKey);
      final oldIndex = storage.getObject(oldIndexKey);
      if (oldWorkspaces != null) {
        final paths = oldWorkspaces is List
            ? oldWorkspaces.whereType<String>().toList()
            : storage.loadWorkspaces(oldId);
        await storage.saveWorkspaces(newId, paths);
      }
      if (oldIndex != null) {
        final index = oldIndex is int ? oldIndex : storage.loadWorkspaceIndex(oldId);
        await storage.saveWorkspaceIndex(newId, index);
      }
      await storage.remove(oldWorkspacesKey);
      await storage.remove(oldIndexKey);
    }

    if (_activeHostId == newId) notifyListeners();
  }

  void setWorkspaces(List<String> paths) {
    final state = _activeState;
    state.workspaces = _entriesFor(paths);
    if (state.selectedIndex >= state.workspaces.length) {
      state.selectedIndex = 0;
    }
    notifyListeners();
    _persistWorkspaces();
  }

  void addWorkspace(String name, String path) {
    final state = _activeState;
    if (state.workspaces.any((w) => w['path'] == path)) return;
    state.workspaces.add({'name': name, 'path': path});
    notifyListeners();
    _persistWorkspaces();
  }

  /// Called by server_info to sync workspaces from server
  void syncFromServer(List<String> paths) {
    final state = _activeState;
    for (final path in paths) {
      if (state.workspaces.any((w) => w['path'] == path)) continue;
      state.workspaces
          .add({'name': path.split(RegExp(r'[/\\]')).last, 'path': path});
    }
    if (state.selectedIndex >= state.workspaces.length) {
      state.selectedIndex = 0;
    }
    notifyListeners();
    _persistWorkspaces();
  }

  Future<void> _persistWorkspaces() async {
    final hostId = _activeHostId;
    final state = _byHost[hostId];
    if (state == null) return;
    final paths = state.workspaces
        .map((w) => w['path'] ?? '')
        .where((p) => p.isNotEmpty)
        .toList();
    final index = state.selectedIndex;
    final storage = await StorageService.getInstance();
    await storage.saveWorkspaces(hostId, paths);
    await storage.saveWorkspaceIndex(hostId, index);
  }

  Future<void> _loadHostState(String hostId) async {
    final storage = await StorageService.getInstance();
    if (hostId != _activeHostId) return;

    final hasPartition =
        storage.getObject('workspaces_$hostId') != null ||
            storage.getObject('workspace_index_$hostId') != null;
    var paths = storage.loadWorkspaces(hostId);
    var index = storage.loadWorkspaceIndex(hostId);
    if (!hasPartition) {
      final legacy = storage.getString('workspaces');
      if (legacy != null) {
        paths = legacy
            .split('\n')
            .where((path) => path.isNotEmpty)
            .toList();
        index = 0;
        await storage.saveWorkspaces(hostId, paths);
        await storage.saveWorkspaceIndex(hostId, index);
        await storage.remove('workspaces');
      }
    }
    if (hostId != _activeHostId) return;

    final state = _stateFor(hostId);
    final existingPaths = state.workspaces
        .map((workspace) => workspace['path'] ?? '')
        .where((path) => path.isNotEmpty)
        .toSet();
    for (final path in paths) {
      if (existingPaths.add(path)) {
        state.workspaces.add({
          'name': path.split(RegExp(r'[/\\]')).last,
          'path': path,
        });
      }
    }
    if (state.workspaces.isEmpty) {
      state.selectedIndex = 0;
    } else if (state.selectedIndex == 0 && index > 0) {
      state.selectedIndex = index < state.workspaces.length ? index : 0;
    } else if (state.selectedIndex >= state.workspaces.length) {
      state.selectedIndex = 0;
    }
    notifyListeners();
  }

  Future<void> loadWorkspaces() async {
    final storage = await StorageService.getInstance();
    final state = _stateFor('');
    final raw = storage.getString('workspaces');
    if (raw != null && raw.isNotEmpty) {
      state.workspaces = _entriesFor(
        raw.split('\n').where((path) => path.isNotEmpty).toList(),
      );
      final index = storage.loadWorkspaceIndex('');
      state.selectedIndex = index < state.workspaces.length ? index : 0;
    }
    if (_activeHostId == '') notifyListeners();
  }

  void selectWorkspace(int index) {
    final state = _activeState;
    if (index < 0 || index >= state.workspaces.length) return;
    state.selectedIndex = index;
    notifyListeners();
    _persistWorkspaces();
  }

  List<Map<String, String>> _entriesFor(List<String> paths) => paths
      .map((path) => {
            'path': path,
            'name': path.split(RegExp(r'[/\\]')).last,
          })
      .toList();
}
