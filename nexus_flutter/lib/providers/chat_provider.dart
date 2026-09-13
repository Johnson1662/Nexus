import 'dart:async';
import 'dart:convert';
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
  String _syncRequestSessionId = '';
  Timer? _turnRequestTimer;
  Timer? _cancelTimer;
  Timer? _cursorPersistTimer;
  String _cursorSessionId = '';
  String _lastConnectionHostKey = '';
  /// Bumped whenever the active host changes; async work tagged with an older
  /// generation is discarded instead of overwriting the new host's state.
  int _hostGeneration = 0;
  int _selectionGeneration = 0;
  final Map<String, int> _probePhaseGenerations = <String, int>{};
  final Set<String> _processedMessageIds = <String>{};
  final List<ListenerDisposer> _listenerDisposers = [];
  late final OnPermissionActionCallback _permissionAction;
  static const int _turnRequestTimeoutMs = 15000;
  static const int _maxProcessedMessageIds = 4096;
  static const int _maxToolCardBytes = 512 * 1024;
  static const String _contextReplacedNotice =
      'Agent 上下文已重新创建。此前消息仍可查看，但新任务不会继承旧 Agent 上下文。';
  Timer? _replayBatchTimer;

  ChatProvider(this._ws, {WorkspaceProvider? workspaceProvider})
      : _workspaceProvider = workspaceProvider {
    _listenerDisposers.add(_ws.onMessage(_handleServerMessage));
    _listenerDisposers.add(_ws.onStateChange((connected, _) {
      _state.connected = connected;
      if (connected) {
        syncRequest();
      } else {
        _syncInFlight = false;
        _syncRequestSessionId = '';
      }
      notifyListeners();
    }));
    _listenerDisposers.add(_ws.onServerInfo(_onServerInfo));
    _listenerDisposers.add(_ws.onError((error) {
      _state.errorMessage = error;
      _markLatestUserStatus('failed');
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
    _preferredBackend = storage.getHostPreferredBackend(_state.currentDeviceId);
    _recomputeEffectiveBackend();
    _herdrAgentCreationMode = storage.getHerdrAgentCreationMode();
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
    _probePhaseGenerations.remove(hk);
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
    final phaseGeneration = selectionGeneration;
    _probePhaseGenerations[hk] = phaseGeneration;
    final protectsCurrentHost = _ws.isConnected && _ws.currentHostKey == hk;
    if (!protectsCurrentHost) {
      HostStore().setPhase(hk, 'connecting', url: normalized.first);
    }
    void clearProbePhase() {
      if (_probePhaseGenerations[hk] != phaseGeneration) return;
      _probePhaseGenerations.remove(hk);
      if (!protectsCurrentHost && HostStore().getPhase(hk) == 'connecting') {
        HostStore().setPhase(hk, 'offline');
      }
    }

    final token = authToken ?? _authTokenForHost(hk, normalized.first);
    final selectedUrl = await _ws.probeBest(
      normalized,
      hk,
      authToken: token,
    );
    if (selectedUrl == null || selectionGeneration != _selectionGeneration) {
      clearProbePhase();
      return;
    }

    final storage = await StorageService.getInstance();
    if (selectionGeneration != _selectionGeneration) {
      clearProbePhase();
      return;
    }

    _beginConnectionBoundary(hk);
    _state.currentDeviceId = hk;
    _probePhaseGenerations.remove(hk);
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
      _clearHostScopedState();
      _hostGeneration++;
    }
    _lastConnectionHostKey = hostKey;
  }

  /// Drop everything that is scoped to the previous host.
  ///
  /// Capabilities, sessions, agent metadata, model/mode state and the active
  /// workspace all describe a specific machine; leaving any of them behind
  /// makes host A's data render for host B.
  void _clearHostScopedState() {
    _state.hostCapabilities = null;
    _state.sessions = [];
    _state.registryAgents = [];
    _state.installedAgents = [];
    _state.agentNames = [];
    _state.selectedAgentName = '';
    _state.models = [];
    _state.modes = [];
    _state.configOptions = [];
    _state.currentWorkspace = '';
    _state.streamingThinking = '';
    _state.streamingText = '';
    _state.messages = [];
    _preferredBackend = 'native';
    _effectiveBackend = 'native';
    _useHerdrBackend = false;
  }

  String? _authTokenForHost(String hostKey, String url) {
    final normalizedUrl = _normalizeUrl(url);
    for (final device in HostStore().devices) {
      if (device.hostId == hostKey ||
          device.name == hostKey ||
          device.urls
              .any((candidate) => _normalizeUrl(candidate) == normalizedUrl) ||
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
    if (url.startsWith('http://')) {
      url = url.replaceFirst('http://', 'ws://');
    }
    if (url.startsWith('https://')) {
      url = url.replaceFirst('https://', 'wss://');
    }
    if (!url.startsWith('ws://') && !url.startsWith('wss://')) {
      url = 'ws://$url';
    }
    if (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
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

  void _cancelPendingProbePhases() {
    final hostStore = HostStore();
    for (final hostKey in _probePhaseGenerations.keys.toList()) {
      if (hostStore.getPhase(hostKey) == 'connecting') {
        hostStore.setPhase(hostKey, 'offline');
      }
    }
    _probePhaseGenerations.clear();
  }

  void disconnect() {
    _selectionGeneration++;
    _cancelPendingProbePhases();
    _ws.disconnect();
    _turnRequestTimer?.cancel();
    _turnRequestTimer = null;
    _startInFlight = false;
    _inputInFlight = false;
    _syncInFlight = false;
    _syncRequestSessionId = '';
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
        _cancelTimer = null;
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
      if (_useHerdrBackend) {
        _state.errorMessage = 'Herdr 模式下请先从工作区新建 Agent';
        notifyListeners();
        return;
      }
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
      MessageData(
          role: 'user', content: text, type: 'text', sendStatus: 'sending'),
    ];
    _setCurrentSessionStatus('running');
  }

  /// 回答 ask 工具的卡住提问：先取消当前回合再把答案作为跟进消息发出。
  /// 直接 sendMessage 会因 turnActive 被拒（或消息发出去但 agent 不消费），
  /// 进程永远停在 ask 工具这里。Herdr 侧 cancel 即终端 Ctrl+C，
  /// ACP 侧 cancel 即 session/cancel，两端随后都走正常 input 通道。
  Future<void> answerAsk(String answerText) async {
    final text = answerText.trim();
    if (text.isEmpty || _state.sessionId.isEmpty || !_ws.isConnected) return;
    if (_state.sessionId.startsWith('herdr:')) {
      // A Herdr pane blocked on a prompt takes the answer as terminal input,
      // never as a cancel-then-prompt round trip.
      interactHerdrBlocked(text, asText: true);
      return;
    }
    final sid = _state.sessionId;
    _state.cancelling = true;
    _clearTurnRequest();
    _ws.send(ClientMessage(type: 'cancel', sessionId: sid));
    notifyListeners();
    final deadline = DateTime.now().add(const Duration(seconds: 8));
    while (_state.turnActive && DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(milliseconds: 200));
    }
    _state.cancelling = false;
    sendMessage(text);
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
        _state.errorMessage =
            kind == 'start' ? '启动会话超时，请检查 Bridge 连接' : '发送消息超时，请重试';
        _markLatestUserStatus('failed');
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
    _markLatestUserStatus('sent');
  }

  void _markLatestUserStatus(String status) {
    for (var i = _state.messages.length - 1; i >= 0; i--) {
      final message = _state.messages[i];
      if (message.role == 'user' && message.sendStatus == 'sending') {
        message.sendStatus = status;
        return;
      }
    }
  }

  void clearError() {
    _state.errorMessage = '';
    notifyListeners();
  }

  void retryMessage(MessageData msg) {
    if (msg.sendStatus == 'failed') {
      _state.messages = _state.messages.where((message) => message.id != msg.id).toList();
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
    _loadingSessionId = '';
    _syncInFlight = false;
    _syncRequestSessionId = '';
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

  void setConfigOption(String configId, Object value) {
    if (_state.sessionId.isEmpty) return;
    _ws.send(ClientMessage(
      type: 'set_config',
      sessionId: _state.sessionId,
      configId: configId,
      value: value,
    ));
  }

  void authenticate(String methodId) {
    if (_state.sessionId.isEmpty) return;
    _ws.send(ClientMessage(
      type: 'authenticate',
      sessionId: _state.sessionId,
      methodId: methodId,
    ));
  }

  // ── Sessions ──
  void loadSession(String sessionId,
      {String? agent, String? cwd, String? title, int? freshAt}) {
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
      freshAt: freshAt,
    ));
    if (targetAgent.isNotEmpty && !sessionId.startsWith('herdr:') && !sessionId.startsWith('ambient:')) {
      _ws.send(ClientMessage(type: 'list_models', agent: targetAgent));
    }
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
    if (sessionId.startsWith('herdr:')) return;
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
    if (sessionId.startsWith('herdr:')) return;
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

  bool _useHerdrBackend = false;
  bool get useHerdrBackend => _useHerdrBackend;
  String _preferredBackend = 'native';
  String _effectiveBackend = 'native';
  String get preferredBackend => _preferredBackend;
  String get effectiveBackend => _effectiveBackend;

  void _recomputeEffectiveBackend() {
    final prevEffective = _effectiveBackend;
    if (_preferredBackend == 'herdr') {
      // Degrade only on a *known* negative; an unknown host keeps the preference
      // so a Herdr pane is never silently replaced by a Native ACP session.
      final caps = _state.hostCapabilities;
      _effectiveBackend = (caps == null || caps.herdr.available) ? 'herdr' : 'native';
    } else {
      _effectiveBackend = 'native';
    }
    _useHerdrBackend = _effectiveBackend == 'herdr';
    if (prevEffective != _effectiveBackend) {
      requestSessionList(useHerdr: _useHerdrBackend);
      if (_useHerdrBackend) {
        requestHerdrWorkspaces();
      }
    }
    notifyListeners();
  }

  Future<void> setUseHerdrBackend(bool value) async {
    _preferredBackend = value ? 'herdr' : 'native';
    final storage = await StorageService.getInstance();
    if (_state.currentDeviceId.isNotEmpty) {
      await storage.setHostPreferredBackend(_state.currentDeviceId, _preferredBackend);
    } else {
    await storage.setUseHerdrBackend(value);
    }
    _recomputeEffectiveBackend();
    _loadingSessionId = '';
    _clearTurnRequest();
    _clearCancelling();
    _resetCursor(clearPersisted: true);
    _processedMessageIds.clear();
    _state.resetForNewChat();
    _state.sessions = [];
    requestSessionList(useHerdr: _useHerdrBackend);
    if (_useHerdrBackend) {
      requestHerdrWorkspaces();
    }
    notifyListeners();
  }

  void requestSessionList({bool? useHerdr}) => _ws.send(
        ClientMessage(
      type: 'list_sessions',
          useHerdr: useHerdr ?? _useHerdrBackend,
        ),
      );

  void requestOlderHistory() {
    if (_state.sessionId.isEmpty || !_state.historyHasMore || _state.loadingOlderHistory) return;
    _state.loadingOlderHistory = true;
    notifyListeners();
    _ws.send(ClientMessage(
      type: 'load_history_page',
      sessionId: _state.sessionId,
      before: _state.historyOffset,
    ));
  }

  String _herdrAgentCreationMode = 'pane_split';
  String get herdrAgentCreationMode => _herdrAgentCreationMode;

  Future<void> setHerdrAgentCreationMode(String mode) async {
    _herdrAgentCreationMode = mode;
    final storage = await StorageService.getInstance();
    await storage.setHerdrAgentCreationMode(mode);
    notifyListeners();
  }

  void requestHerdrWorkspaces() {
    _ws.send(ClientMessage(type: 'list_herdr_workspaces'));
  }

  void requestHerdrIntegrations() {
    _ws.send(ClientMessage(type: 'list_herdr_integrations'));
  }

  void installHerdrIntegration(String target) {
    _ws.send(ClientMessage(type: 'install_herdr_integration', target: target));
  }

  /// Integration install state for a Herdr target, from the last list reply.
  Map<String, dynamic>? integrationFor(String? target) {
    if (target == null || target.isEmpty) return null;
    for (final entry in _state.herdrIntegrations) {
      if (entry['target'] == target) return entry;
    }
    return null;
  }

  void createHerdrWorkspace({required String label, String? cwd}) {
    _ws.send(ClientMessage(
      type: 'create_herdr_workspace',
      label: label,
      cwd: cwd,
    ));
  }

  List<AgentRuntimeCapability> get enabledHerdrAgents {
    final agents = _state.hostCapabilities?.agents ?? [];
    return agents
        .where((a) => a.enabled && a.herdr.supported && a.herdr.ready)
        .toList();
  }

  List<AgentRuntimeCapability> get enabledNativeAgents {
    final agents = _state.hostCapabilities?.agents ?? [];
    return agents
        .where((a) => a.enabled && a.native.supported && a.native.ready)
        .toList();
  }

  /// Runtime capability for a registry agent id, or null before the first
  /// `host_capabilities` reply arrives for the current host.
  AgentRuntimeCapability? capabilityFor(String agentId) {
    final agents = _state.hostCapabilities?.agents;
    if (agents == null) return null;
    for (final agent in agents) {
      if (agent.id == agentId) return agent;
    }
    return null;
  }

  void createHerdrAgent({
    required String workspaceId,
    required String agentId,
    String? creationMode,
    String? cwd,
    String? title,
  }) {
    // A Herdr pane is a new chat even before its ACP session file exists.
    // Clear the previous pane immediately; create_herdr_agent_done will load
    // the new pane after Herdr returns its id.
    newChat();
    _ws.send(ClientMessage(
      type: 'create_herdr_agent',
      workspaceId: workspaceId,
      agentId: agentId,
      creationMode: creationMode ?? _herdrAgentCreationMode,
      cwd: cwd,
      title: title,
    ));
  }

  void focusOnPc({String? paneId, String? workspaceId}) {
    _ws.send(ClientMessage(
      type: 'focus_herdr_target',
      paneId: paneId,
      workspaceId: workspaceId,
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
  void loadRegistryAgents() =>
      _ws.send(ClientMessage(type: 'list_registry_agents'));
  void refreshHostCapabilities() =>
      _ws.send(ClientMessage(type: 'refresh_host_capabilities'));
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

  void interactHerdrBlocked(String key, {bool asText = false}) {
    if (!_state.sessionId.startsWith('herdr:')) return;
    _ws.send(ClientMessage(
      type: 'interact_herdr_blocked',
      paneId: _state.sessionId,
      key: key,
      asText: asText ? true : null,
    ));
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
    _syncRequestSessionId = sessionId;
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
      StorageService.getInstance()
          .then((storage) => storage.setLastMessageId(''));
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
  @visibleForTesting
  void handleMessageForTest(ServerMessage msg) => _handleServerMessage(msg);

  void _handleServerMessage(ServerMessage msg) {
    if (_isCursorScopedMessageType(msg.type) &&
        !_isRequiredSessionEventForCurrentSession(msg.sessionId)) {
      return;
    }
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
        notifyListeners();
        break;
      case 'start_failed':
        _clearTurnRequest();
        _state.turnActive = false;
        _state.errorMessage = msg.text ?? 'Agent 启动失败';
        _markLatestUserStatus('failed');
        notifyListeners();
        break;
      case 'authentication_required':
        _clearTurnRequest();
        _state.turnActive = false;
        _state.sessionId = msg.sessionId ?? '';
        _state.authMethods = msg.authMethods ?? [];
        _state.errorMessage = '请先完成 Agent 认证，再重试消息';
        _markLatestUserStatus('failed');
        notifyListeners();
        break;
      case 'session_context_replaced':
        if (!_isRequiredSessionEventForCurrentSession(msg.sessionId)) {
          break;
        }
        _state.contextReplacedNotice = _contextReplacedNotice;
        notifyListeners();
        break;
      case 'session_started':
        final sessionId = msg.sessionId ?? '';
        if (sessionId.isEmpty) break;
        final acceptsSession = sessionId == _state.sessionId ||
            sessionId == _loadingSessionId ||
            (_state.sessionId.isEmpty && _startInFlight);
        if (!acceptsSession) break;
        if (_state.sessionId != sessionId) {
          _state.contextReplacedNotice = '';
        }
        if (_cursorSessionId.isNotEmpty && _cursorSessionId != sessionId) {
          _resetCursor(clearPersisted: true);
          _processedMessageIds.clear();
        }
        _cursorSessionId = sessionId;
        _clearTurnRequest();
        _markLatestUserStatus('sent');
        _syncInFlight = false;
        _syncRequestSessionId = '';
        if (_loadingSessionId == sessionId) _loadingSessionId = '';
        final previous = _state.sessions
            .where(
              (s) => s.sessionId == sessionId,
            )
            .firstOrNull;
        _state.sessionId = sessionId;
        _state.sessionTitle = msg.title ?? previous?.title ?? sessionId;
        final prevMode = _state.streamMode;
        if (msg.streamMode != null && msg.streamMode!.isNotEmpty) {
          _state.streamMode = msg.streamMode!;
        } else {
          _state.streamMode = sessionId.startsWith('herdr:') ? 'terminal' : 'acp';
        }
        final startedAgent = msg.agent ?? previous?.agent;
        if (startedAgent != null && startedAgent.isNotEmpty) {
          _state.selectedAgentName = startedAgent;
          if (_state.models.isEmpty) {
            _ws.send(ClientMessage(type: 'list_models', agent: startedAgent));
          }
        }
        if (msg.model != null && msg.model!.isNotEmpty) {
          _state.sessionCurrentModelId = msg.model!;
          _state.lastModelId = msg.model!;
          if (_state.models.isNotEmpty) {
            final mIdx = _state.models.indexWhere((m) =>
                m.id == msg.model ||
                m.modelId == msg.model ||
                m.id.endsWith('/${msg.model}') ||
                msg.model!.endsWith('/${m.id}') ||
                m.name.toLowerCase() == msg.model!.toLowerCase());
            if (mIdx >= 0) {
              _state.modelIndex = mIdx;
            }
          }
        }
        if (msg.authMethods != null) {
          _state.authMethods = msg.authMethods!;
        }
        if (msg.configOptions != null) {
          _state.configOptions = msg.configOptions!;
        }
        if (previous?.sessionId == sessionId &&
            prevMode.isNotEmpty &&
            prevMode != _state.streamMode) {
          // terminal → acp upgrade (or vice versa): drop stale rendered
          // content; the replay following session_started rebuilds it.
          _state.messages = [];
          _state.streamingThinking = '';
          _state.streamingText = '';
          _finishRunningTools();
        }
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
            source: previous?.source ?? (sessionId.startsWith('herdr:') ? 'herdr' : null),
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
        if (!_isRequiredSessionEventForCurrentSession(msg.sessionId)) {
          break;
        }
        _handleAgentEvent(msg);
        break;
      case 'session_loaded':
        _state.loadingSession = false;
        _replayBatchTimer?.cancel();
        _flushStreamingThinking();
        _flushStreamingText();
        _finishRunningTools();
        notifyListeners();
        break;
      case 'history_full':
        _handleHistoryFull(msg);
        break;
      case 'history_page':
        _handleHistoryFull(msg);
        break;
      case 'session_cancelled':
        if (msg.sessionId != null &&
            !_isEventForCurrentSession(msg.sessionId)) {
          break;
        }
        _state.cancelling = true;
        notifyListeners();
        break;
      case 'cancel_failed':
        if (msg.sessionId != null &&
            !_isEventForCurrentSession(msg.sessionId)) {
          break;
        }
        _state.cancelling = false;
        _state.turnActive = true;
        _state.errorMessage = msg.error ?? 'Agent 仍在运行，未能终止';
        notifyListeners();
        break;
      case 'turn_ended':
        if (!_isRequiredSessionEventForCurrentSession(msg.sessionId)) {
          break;
        }
        _handleTurnEnded();
        // Remove live view when turn completes
        LiveViewService.stop();
        break;
      case 'session_status':
        if (!_isRequiredSessionEventForCurrentSession(msg.sessionId)) break;
        final status = msg.status ?? 'unknown';
        _state.terminalBlocked =
            status == 'blocked' || status == 'waiting_input';
        if (status == 'working' || status == 'running') {
          _state.turnActive = true;
          _setCurrentSessionStatus('running');
        } else if (status == 'idle' || status == 'done') {
          _handleTurnEnded();
        } else {
          notifyListeners();
        }
        break;
      case 'model_list':
        if (msg.models != null) {
          _state.models = msg.models!;
          if (_state.sessionCurrentModelId.isNotEmpty) {
            final mIdx = _state.models.indexWhere((m) =>
                m.id == _state.sessionCurrentModelId ||
                m.modelId == _state.sessionCurrentModelId ||
                m.id.endsWith('/${_state.sessionCurrentModelId}') ||
                _state.sessionCurrentModelId.endsWith('/${m.id}') ||
                m.name.toLowerCase() == _state.sessionCurrentModelId.toLowerCase());
            if (mIdx >= 0) {
              _state.modelIndex = mIdx;
            }
          }
        }
        if (msg.modes != null) _state.modes = msg.modes!;
        notifyListeners();
        break;
      case 'herdr_integrations_list':
        _state.herdrIntegrations =
            msg.herdrIntegrations ?? const <Map<String, dynamic>>[];
        if (msg.error != null) _state.errorMessage = msg.error!;
        notifyListeners();
        break;
      case 'install_herdr_integration_done':
        if (msg.ok == false) {
          _state.errorMessage = msg.error ?? 'Integration 安装失败';
        }
        requestHerdrIntegrations();
        notifyListeners();
        break;
      case 'host_capabilities':
        if (msg.hostCapabilities != null) {
          // Capabilities describe exactly one machine. A reply that names a
          // different host than the one we are connected to is stale and must
          // not repopulate the capability set.
          final reportedHost = msg.hostId ?? '';
          if (reportedHost.isNotEmpty &&
              reportedHost != _state.currentDeviceId) {
            break;
          }
          _state.hostCapabilities = msg.hostCapabilities;
          // Agent selectors are capability-driven; refresh them the moment the
          // authoritative capability set arrives.
          _applyAgentList(_state.installedAgents);
          _recomputeEffectiveBackend();
          if (msg.hostCapabilities!.herdr.available) {
            requestHerdrIntegrations();
          } else {
            _state.herdrIntegrations = [];
          }
          notifyListeners();
        }
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

          // NOTE: Herdr 模式下工作区以 herdr_workspaces_list 为准，
          // 不再用会话 cwd 经 syncFromServer 写入无 workspaceId 条目，
          // 否则会被首页/列表页的 hasHerdrId 过滤隐藏，造成工作区凭空消失。
        }
        notifyListeners();
        break;
      case 'agent_list':
        if (msg.agents != null) {
          _applyAgentList(msg.agents!);
        }
        // Now we have agents, request sessions with the first one
        requestSessionList();
        notifyListeners();
        break;
      case 'registry_agents_list':
        if (msg.registryAgents != null) {
          _state.registryAgents = msg.registryAgents!;
        }
        notifyListeners();
        break;
      case 'config_option_updated':
        if (msg.configOptions != null) {
          _state.configOptions = msg.configOptions!;
        }
        notifyListeners();
        break;
      case 'auth_result':
        if (msg.sessionId != null) _state.sessionId = msg.sessionId!;
        if (msg.configOptions != null) {
          _state.configOptions = msg.configOptions!;
        }
        _state.authMethods = [];
        _state.errorMessage = '';
        notifyListeners();
        break;
      case 'herdr_workspaces_list':
        if (msg.herdrWorkspaces != null) {
          _workspaceProvider?.syncFromHerdrWorkspaces(msg.herdrWorkspaces!);
        }
        notifyListeners();
        break;
      case 'create_herdr_agent_done':
        if (msg.sessionId != null && msg.sessionId!.isNotEmpty) {
          loadSession(
            msg.sessionId!,
            agent: msg.agent,
            title: msg.title,
            freshAt: msg.freshAt,
          );
        } else if (msg.text != null && msg.text!.isNotEmpty) {
          _state.errorMessage = msg.text!;
        }
        notifyListeners();
        break;
      case 'create_herdr_workspace_done':
        if (msg.ok == true) {
          requestHerdrWorkspaces();
        } else {
          _state.errorMessage = msg.error ?? 'HERDR_WORKSPACE_CREATE_FAILED';
          notifyListeners();
        }
        break;
      case 'install_agent_done':
      case 'uninstall_agent_done':
        if (msg.ok == false) {
          _state.errorMessage = msg.error ?? 'Agent 操作失败';
        }
        _ws.send(ClientMessage(type: 'list_agents'));
        _ws.send(ClientMessage(type: 'list_registry_agents'));
        // Runtime availability changed: without this the newly enabled agent
        // would stay out of the Herdr creation list until the next reconnect.
        if (msg.ok != false) refreshHostCapabilities();
        notifyListeners();
        break;
      case 'error':
        if (msg.sessionId != null &&
            !_isEventForCurrentSession(msg.sessionId)) {
          break;
        }
        _loadingSessionId = '';
        _syncInFlight = false;
        _syncRequestSessionId = '';
        _clearTurnRequest();
        _clearCancelling();
        _state.turnActive = false;
        _state.loadingOlderHistory = false;
        _markLatestUserStatus('failed');
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
      case 'permission_resolved':
        if (msg.requestId != null) {
          _state.pendingPermissions.remove(msg.requestId!);
          NotificationService.cancelForRequest(msg.requestId!);
          notifyListeners();
        }
        break;
      case 'session_closed':
        final closedSessionId = msg.sessionId;
        if (closedSessionId == null) break;
        _state.sessions.removeWhere((session) => session.sessionId == closedSessionId);
        if (!_isEventForCurrentSession(closedSessionId)) {
          notifyListeners();
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
        final responseSessionId = msg.sessionId ?? '';
        if (!_isRequiredSessionEventForCurrentSession(responseSessionId) ||
            (_syncRequestSessionId.isNotEmpty &&
                _syncRequestSessionId != responseSessionId)) {
          break;
        }
        _syncInFlight = false;
        _syncRequestSessionId = '';
        if (msg.turnActive != null) _state.turnActive = msg.turnActive!;
        if (msg.overflow == true) {
          _handleSyncOverflow(responseSessionId);
          break;
        }
        for (final entry in msg.entries ?? const <Map<String, dynamic>>[]) {
          final rawPayload = entry['payload'];
          if (rawPayload is! Map) continue;
          final payload = Map<String, dynamic>.from(rawPayload);
          final rawId = entry['messageId']?.toString() ??
              payload['messageId']?.toString();
          if (rawId != null && rawId.isNotEmpty) payload['messageId'] = rawId;
          payload['sessionId'] ??= responseSessionId;
          final replaySessionId = payload['sessionId']?.toString() ?? '';
          if (replaySessionId != responseSessionId ||
              !_isRequiredSessionEventForCurrentSession(replaySessionId)) {
            continue;
          }
          // Replay entries are complete protocol envelopes. Parsing and
          // routing the original envelope preserves session_context_replaced,
          // turn_ended, and future session-scoped message types.
          _handleServerMessage(ServerMessage.fromJson(payload));
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
        _state.fileGitWarning = _gitWarningFor(msg);
        notifyListeners();
        break;
      case 'file_log':
        if (msg.logEntries != null) _state.fileLogEntries = msg.logEntries!;
        _state.fileGitWarning = _gitWarningFor(msg);
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
            if (updatedSession.sessionId == _state.sessionId) {
              _state.terminalBlocked = updatedSession.status == 'waiting_input';
              if (updatedSession.status == 'running') {
                _state.turnActive = true;
              } else if (updatedSession.status == 'idle' && _state.turnActive) {
                _handleTurnEnded();
              }
            }
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
                  source: _state.sessions[idx].source ??
                      (updatedSession.sessionId.startsWith('herdr:')
                          ? 'herdr'
                          : (updatedSession.sessionId.startsWith('ambient:')
                              ? 'ambient'
                              : null)),
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


  /// Map the server's Git error codes onto a message the user can act on.
  /// File browsing keeps working without Git; only diff/log degrade.
  String _gitWarningFor(ServerMessage msg) {
    switch (msg.error) {
      case 'GIT_UNAVAILABLE':
        return '此电脑未检测到 Git';
      case 'NOT_GIT_REPOSITORY':
        return '该目录不是 Git 仓库';
      case 'GIT_COMMAND_FAILED':
        return 'Git 命令执行失败';
      default:
        return '';
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
        cwd:
            _state.currentWorkspace.isNotEmpty ? _state.currentWorkspace : null,
        agent: _state.selectedAgentName.isNotEmpty
            ? _state.selectedAgentName
            : null,
      ));
    }
    notifyListeners();
  }

  void _handleServerInfo(ServerMessage msg) {
    final actualHostId = msg.hostId ?? _ws.currentHostKey;
    if (actualHostId.isNotEmpty &&
        _state.currentDeviceId.isNotEmpty &&
        _state.currentDeviceId != actualHostId) {
      // The authoritative hostId changed: this is a real host switch even when
      // the caller never went through connectToUrl, so apply the same isolation.
      _resetCursor(clearPersisted: true);
      _processedMessageIds.clear();
      _state.sessionId = '';
      _state.turnActive = false;
      _clearHostScopedState();
      _hostGeneration++;
      _lastConnectionHostKey = actualHostId;
    }
    _state.connected = true;
    _state.errorMessage = '';
    _state.currentDeviceId = actualHostId;

    // server_info itself identifies the canonical host.
    // Workspace partition must be activated even when the server does not
    // include a legacy `workspaces` field.
    if (actualHostId.isNotEmpty) {
      _workspaceProvider?.setActiveHost(actualHostId);

      // Never keep another host's cwd.
      _state.currentWorkspace =
          _workspaceProvider?.currentWorkspace ?? '';

      // Load host-scoped backend preference
      final hostGeneration = ++_hostGeneration;
      StorageService.getInstance().then((storage) {
        // A slow storage read for the previous host must not overwrite the
        // preference of the host we are now connected to.
        if (hostGeneration != _hostGeneration) return;
        _preferredBackend = storage.getHostPreferredBackend(actualHostId);
        _recomputeEffectiveBackend();
      });
    }

    if (msg.workspaces != null) {
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

    // Connection is ready: hydrate all global agent metadata immediately.
    _ws.send(ClientMessage(type: 'get_host_capabilities'));
    _ws.send(ClientMessage(type: 'list_agents'));
    _ws.send(ClientMessage(type: 'list_registry_agents'));

    requestSessionList();
    if (_useHerdrBackend) {
      requestHerdrWorkspaces();
    }
    // server_info is the authenticated connection-ready boundary; replay any
    // events missed while this socket was down before accepting new input.
    syncRequest();
    _onServerInfo();
  }

  String _truncateUtf8(String value, int maxBytes) {
    if (utf8.encode(value).length <= maxBytes) return value;
    final retained = StringBuffer();
    var retainedBytes = 0;
    for (final rune in value.runes) {
      final codePoint = String.fromCharCode(rune);
      final codePointBytes = utf8.encode(codePoint).length;
      if (retainedBytes + codePointBytes > maxBytes) break;
      retained.write(codePoint);
      retainedBytes += codePointBytes;
    }
    return retained.toString();
  }

  void _appendBoundedToolContent(MessageData message, String addition) {
    if (addition.isEmpty) return;
    final originalBytes =
        utf8.encode(message.toolContent).length + utf8.encode(addition).length;
    final bounded = _truncateUtf8(
      '${message.toolContent}$addition',
      _maxToolCardBytes,
    );
    if (utf8.encode(bounded).length < originalBytes) {
      message.toolTruncated = true;
    }
    message.toolContent = bounded;
  }

  String _boundedToolDiffText(MessageData message, String value) {
    final bounded = _truncateUtf8(value, _maxToolCardBytes);
    if (bounded != value) message.toolTruncated = true;
    return bounded;
  }

  void _handleAgentEvent(ServerMessage msg) {
    if (msg.acpUpdate != null) {
      final event = msg.acpUpdate!;
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

          // Defensive check: prevent appending duplicate cards for the same toolCallId
          if (callId.isNotEmpty) {
            final existingIndex = _state.messages.indexWhere((m) => m.toolCallId == callId);
            if (existingIndex >= 0) {
              final m = _state.messages[existingIndex];
              m.toolName = toolName;
              if (event.kind != null && event.kind!.isNotEmpty) m.toolKind = event.kind!;
              break;
            }
          }

          _state.messages = [
            ..._state.messages,
            MessageData(
              role: 'assistant',
              content: toolName,
              type: 'tool_call',
              toolName: toolName,
              toolCallId: callId,
              toolInput: event.toolInput ?? '',
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
                  _appendBoundedToolContent(m, newContent);
                  if (newType.isNotEmpty) {
                    m.toolContentType = newType;
                  }
                  if (event.path != null && event.path!.isNotEmpty) {
                    m.toolPath = event.path!;
                  }
                  if (event.oldText != null && event.oldText!.isNotEmpty) {
                    m.toolOldText = _boundedToolDiffText(m, event.oldText!);
                  }
                  if (event.newText != null && event.newText!.isNotEmpty) {
                    m.toolNewText = _boundedToolDiffText(m, event.newText!);
                  }
                  if (event.terminalId != null && event.terminalId!.isNotEmpty) {
                    m.toolTerminalId = event.terminalId!;
                  }
                  if (event.terminalTruncated) m.toolTruncated = true;
                  m.toolStatus = status;
                  toolName = m.toolName;
                  found = true;
                  debugPrint(
                      '[ToolCall] update OK: toolContent now ${m.toolContent.length} chars, status=${m.toolStatus}');
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
                  _appendBoundedToolContent(m, newContent);
                  if (newType.isNotEmpty) {
                    m.toolContentType = newType;
                  }
                  if (event.path != null && event.path!.isNotEmpty) {
                    m.toolPath = event.path!;
                  }
                  if (event.oldText != null && event.oldText!.isNotEmpty) {
                    m.toolOldText = _boundedToolDiffText(m, event.oldText!);
                  }
                  if (event.newText != null && event.newText!.isNotEmpty) {
                    m.toolNewText = _boundedToolDiffText(m, event.newText!);
                  }
                  if (event.terminalId != null && event.terminalId!.isNotEmpty) {
                    m.toolTerminalId = event.terminalId!;
                  }
                  if (event.terminalTruncated) m.toolTruncated = true;
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
          if (event.config != null) {
            _state.configOptions = event.config!;
          }
          break;
        case 'available_commands_update':
          if (event.commands != null) {
            _state.availableCommands = event.commands!;
          }
          break;
        case 'usage_update':
          if (event.usage != null) {
            _state.lastUsage = event.usage;
          }
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
    if (_state.loadingSession) {
      _replayBatchTimer?.cancel();
      _replayBatchTimer = Timer(const Duration(milliseconds: 30), () {
        _state.loadingSession = false;
        notifyListeners();
      });
    } else {
      notifyListeners();
    }
  }

  void _handleHistoryFull(ServerMessage msg) {
    _state.historyOffset = msg.historyOffset ?? 0;
    _state.historyTotal = msg.historyTotal ?? 0;
    _state.historyHasMore = msg.historyHasMore ?? (msg.historyTruncated ?? false);
    _state.loadingOlderHistory = false;
    if (msg.events == null || msg.events!.isEmpty) {
      notifyListeners();
      return;
    }
    if (!_isRequiredSessionEventForCurrentSession(msg.sessionId)) return;

    final List<MessageData> fullList = [];
    for (final raw in msg.events!) {
      if (raw is! Map) continue;
      final map = raw as Map<String, dynamic>;
      final updateType = map['sessionUpdate'] as String? ?? '';
      final content = map['content'];
      String text = '';
      if (content is Map && content['text'] != null) {
        // 单个异形事件（如 text 为嵌套对象）不能抛异常，
        // 否则整个 history_full 中断，聊天页只剩最近一轮而大面积空白。
        text = content['text'].toString();
      } else if (content is String) {
        text = content;
      }

      switch (updateType) {
        case 'user_message_chunk':
          if (text.isNotEmpty) {
            fullList.add(MessageData(
              role: 'user',
              content: text,
              sendStatus: 'sent',
            ));
          }
          break;
        case 'agent_thought_chunk':
          if (text.isNotEmpty) {
            if (fullList.isNotEmpty &&
                fullList.last.role == 'assistant' &&
                fullList.last.type == 'thinking') {
              fullList.last.content += '\n\n$text';
            } else {
              fullList.add(MessageData(
                role: 'assistant',
                content: text,
                type: 'thinking',
                sendStatus: 'sent',
              ));
            }
          }
          break;
        case 'agent_message_chunk':
          if (text.isNotEmpty) {
            if (fullList.isNotEmpty &&
                fullList.last.role == 'assistant' &&
                fullList.last.type == 'text') {
              fullList.last.content += text;
            } else {
              fullList.add(MessageData(
                role: 'assistant',
                content: text,
                type: 'text',
                sendStatus: 'sent',
              ));
            }
          }
          break;
        case 'tool_call':
          final toolName = (map['title'] ?? map['toolName'] ?? 'tool').toString();
          final toolCallId = (map['toolCallId'] ?? '').toString();
          String toolInput = '';
          final rawInput = map['rawInput'] ?? map['arguments'];
          if (rawInput is Map) {
            if (rawInput['questions'] != null || rawInput['question'] != null) {
              toolInput = jsonEncode(rawInput);
            } else {
              toolInput = (rawInput['command'] ?? rawInput['path'] ?? rawInput['intent'] ?? rawInput['query'] ?? rawInput['title'])?.toString() ?? jsonEncode(rawInput);
            }
          } else if (rawInput != null) {
            toolInput = rawInput.toString();
          }
          fullList.add(MessageData(
            role: 'assistant',
            content: toolName,
            type: 'tool_call',
            toolName: toolName,
            toolCallId: toolCallId,
            toolInput: toolInput,
            toolStatus: 'pending',
          ));
          break;
        case 'tool_call_update':
          final toolCallId = (map['toolCallId'] ?? '').toString();
          final status = (map['status'] ?? 'completed').toString();
          String toolContent = '';
          String toolContentType = map['contentType'] as String? ?? '';
          final rawContent = map['content'];
          if (rawContent is List) {
            for (final item in rawContent) {
              if (item is Map) {
                final type = item['type'] as String? ?? '';
                if (type == 'content' && item['content'] is Map && item['content']['text'] != null) {
                  toolContent += item['content']['text'].toString();
                  if (toolContentType.isEmpty) toolContentType = 'content';
                } else if (type == 'text' && item['text'] != null) {
                  toolContent += item['text'].toString();
                } else if (item['text'] != null) {
                  toolContent += item['text'].toString();
                }
              }
            }
          } else if (rawContent is String) {
            toolContent = rawContent;
          }
          for (int i = fullList.length - 1; i >= 0; i--) {
            if (fullList[i].toolCallId == toolCallId) {
              fullList[i].toolStatus = status;
              if (toolContent.isNotEmpty) fullList[i].toolContent = toolContent;
              if (toolContentType.isNotEmpty) fullList[i].toolContentType = toolContentType;
              break;
            }
          }
          break;
      }
    }

    if (fullList.isEmpty) {
      notifyListeners();
      return;
    }
    _state.messages = msg.type == 'history_page'
        ? [...fullList, ..._state.messages]
        : fullList;
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
      source: current.source ??
          (current.sessionId.startsWith('herdr:')
              ? 'herdr'
              : (current.sessionId.startsWith('ambient:')
                  ? 'ambient'
                  : null)),
      createdAt: current.createdAt,
      lastActivity: DateTime.now().millisecondsSinceEpoch,
      status: status,
    );
    _state.sessions = sessions;
  }

  /// 事件是否属于当前会话：加载历史中允许当前会话或加载会话的事件。
  /// 只有事件 id 为空时才兼容旧协议；当前会话为空时不能放行带 id 的旧事件。
  bool _isEventForCurrentSession(String? eventSessionId) {
    if (eventSessionId == null || eventSessionId.isEmpty) return true;
    if (_state.sessionId.isNotEmpty && eventSessionId == _state.sessionId) {
      return true;
    }
    if (_loadingSessionId.isNotEmpty && eventSessionId == _loadingSessionId) {
      return true;
    }
    return false;
  }

  /// Session-scoped events must carry an explicit session ID. Legacy
  /// session-less compatibility remains reserved for global events/errors.
  bool _isRequiredSessionEventForCurrentSession(String? eventSessionId) {
    if (eventSessionId == null || eventSessionId.isEmpty) return false;
    return _isEventForCurrentSession(eventSessionId);
  }

  bool _isCursorScopedMessageType(String type) {
    switch (type) {
      case 'agent_event':
      case 'session_context_replaced':
      case 'session_cancelled':
      case 'cancel_failed':
      case 'turn_ended':
      case 'permission_request':
      case 'session_ended':
      case 'sync_response':
      case 'session_loaded':
      case 'history_full':
      case 'history_page':
      case 'session_status':
        return true;
      default:
        return false;
    }
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
    _applyAgentList(agents);
    notifyListeners();
  }

  void _applyAgentList(List<AgentInfo> agents) {
    _state.installedAgents = agents;
    // Native selector is driven by HostCapabilities, the single runtime source.
    _state.agentNames = enabledNativeAgents.map((a) => a.id).toList();
    if (!_state.agentNames.contains(_state.selectedAgentName)) {
      _state.selectedAgentName = _state.agentNames.contains('omp')
          ? 'omp'
          : (_state.agentNames.isNotEmpty ? _state.agentNames.first : '');
    }
    if (_state.currentDeviceId.isNotEmpty) {
      DeviceAgentStore().saveAgents(_state.currentDeviceId, agents);
    }
  }

  @override
  void dispose() {
    _selectionGeneration++;
    _cancelPendingProbePhases();
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
    final newPartitionExists = storage.getObject('workspaces_$newId') != null ||
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
        final index =
            oldIndex is int ? oldIndex : storage.loadWorkspaceIndex(oldId);
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

  /// Called by herdr_workspaces_list to sync workspaces directly from Herdr PC
  void syncFromHerdrWorkspaces(List<Map<String, dynamic>> rawList) {
    final state = _activeState;
    for (final raw in rawList) {
      final name = (raw['name'] ?? raw['workspaceId'] ?? '').toString();
      final wsPath = (raw['path'] ?? '').toString();
      final wsId = (raw['workspaceId'] ?? '').toString();
      final effectivePath = wsPath.isNotEmpty ? wsPath : name;
      final existing = state.workspaces.firstWhere(
        (w) => (wsId.isNotEmpty && w['workspaceId'] == wsId) || w['path'] == effectivePath,
        orElse: () => <String, String>{},
      );
      if (existing.isNotEmpty) {
        existing['name'] = name;
        existing['path'] = effectivePath;
        existing['workspaceId'] = wsId;
      } else {
        state.workspaces.add({
          'name': name,
          'path': effectivePath,
          'workspaceId': wsId,
        });
      }
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

    final hasPartition = storage.getObject('workspaces_$hostId') != null ||
        storage.getObject('workspace_index_$hostId') != null;
    var paths = storage.loadWorkspaces(hostId);
    var index = storage.loadWorkspaceIndex(hostId);
    if (!hasPartition) {
      final legacy = storage.getString('workspaces');
      if (legacy != null) {
        paths = legacy.split('\n').where((path) => path.isNotEmpty).toList();
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

