import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import '../models/ws_protocol.dart';
import '../models/host_runtime_state.dart';

typedef MessageCallback = void Function(ServerMessage msg);

class WSClient {
  WebSocketChannel? _channel;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  Timer? _watchdogTimer;

  String _currentUrl = '';
  String _currentHostKey = '';
  String? _authToken;
  bool _intentionalClose = false;
  bool _ready = false;
  int _reconnectAttempt = 0;
  final Set<String> _seenMessageIds = <String>{};

  // Callback sets
  final List<MessageCallback> _onMessage = [];
  final List<void Function(bool, String)> _onStateChange = [];
  final List<void Function()> _onServerInfo = [];
  final List<void Function(List<AgentInfo>)> _onAgentList = [];
  final List<void Function(String)> _onError = [];
  final List<void Function(List<RegistryAgentInfo>)> _onRegistryList = [];
  final List<void Function(String phase)> _onPhaseChange = [];

  static const int _heartbeatMs = 20000;
  static const int _watchdogMs = 5000;
  static const int _watchdogTimeoutMs = 45000;
  static const int _readyTimeoutMs = 10000;
  static const int _maxSeenMessageIds = 4096;
  static const int _reconnectBaseMs = 1000;
  static const int _reconnectMaxMs = 30000;
  DateTime _lastMsgReceived = DateTime.now();
  Timer? _readyTimer;

  bool get isConnected => _channel != null && _ready;
  String get currentUrl => _currentUrl;
  String get currentHostKey => _currentHostKey;
  int get reconnectAttempt => _reconnectAttempt;

  // ── Public API ──

  void connect(String url, String hostKey, {String? authToken}) {
    final normalizedToken = _normalizeToken(authToken);
    if (_currentUrl == url &&
        _currentHostKey == hostKey &&
        _authToken == normalizedToken &&
        isConnected) {
      return;
    }
    final changedEndpoint = _currentUrl != url ||
        _currentHostKey != hostKey ||
        _authToken != normalizedToken;
    _intentionalClose = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _currentUrl = url;
    _currentHostKey = hostKey;
    _authToken = normalizedToken;
    _reconnectAttempt = 0;
    if (changedEndpoint) _clearSeenMessageIds();
    _notifyPhase(HostPhase.connecting);
    _doConnect(url);
  }

  Future<void> connectBest(List<String> candidates, String hostKey,
      {String? authToken}) async {
    final normalizedToken = _normalizeToken(authToken);
    final changedEndpoint = _currentHostKey != hostKey ||
        (_authToken != normalizedToken && _currentUrl.isNotEmpty);
    if (changedEndpoint) _clearSeenMessageIds();
    _notifyPhase(HostPhase.connecting);
    _currentHostKey = hostKey;
    _authToken = normalizedToken;
    for (final url in candidates) {
      try {
        if (await probeCandidate(url, authToken: _authToken)) {
          connect(url, hostKey, authToken: _authToken);
          return;
        }
      } catch (_) {}
    }
    // All candidates probe failed — mark offline gracefully, do NOT force WebSocket connect
    _notifyStateChange(false, candidates.isNotEmpty ? candidates.first : '');
    _notifyPhase(HostPhase.offline);
  }

  void disconnect() {
    _intentionalClose = true;
    _notifyPhase(HostPhase.offline);
    _clearSeenMessageIds();
    _cleanup();
  }

  void send(ClientMessage msg) {
    if (_channel == null) return;
    try {
      _channel!.sink.add(jsonEncode(msg.toJson()));
    } catch (e) {
      _notifyError('send failed: $e');
    }
  }

  Future<bool> probeCandidate(String url, {String? authToken}) async {
    final client = HttpClient();
    try {
      var probeUrl = url
          .replaceFirst('ws://', 'http://')
          .replaceFirst('wss://', 'https://');
      if (!probeUrl.endsWith('/probe')) {
        if (probeUrl.endsWith('/')) {
          probeUrl = '${probeUrl}probe';
        } else {
          probeUrl = '$probeUrl/probe';
        }
      }
      client.connectionTimeout = const Duration(seconds: 4);
      final request = await client.getUrl(Uri.parse(probeUrl));
      final token = _normalizeToken(authToken);
      if (token != null) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      final response = await request.close().timeout(const Duration(seconds: 4));
      final status = response.statusCode;
      await response.drain<void>();
      if (status == HttpStatus.unauthorized || status == HttpStatus.forbidden) {
        _notifyError('需要认证 Token');
      }
      return status == HttpStatus.ok;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  String? _normalizeToken(String? token) {
    final value = token?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  String _friendlyErrorMessage(dynamic error) {
    final str = error.toString();
    if (str.contains('401') ||
        str.contains('403') ||
        str.contains('Unauthorized') ||
        str.contains('Forbidden')) {
      return '需要认证 Token';
    } else if (str.contains('Connection reset by peer')) {
      return '连接被重置，请检查 Tailscale 或局域网网络';
    } else if (str.contains('Connection refused')) {
      return '连接被拒绝，目标主机 Bridge 服务未启动';
    } else if (str.contains('Network is unreachable')) {
      return '网络不可达，请检查网络配置';
    } else if (str.contains('Connection timed out') || str.contains('TimeoutException')) {
      return '网络连接超时';
    } else if (str.contains('WebSocketChannelException')) {
      return 'WebSocket 连接失败，网络中断或连接受阻';
    }
    return '网络异常: $str';
  }

  // ── Connection ──
  void _doConnect(String url) {
    _cleanup();
    try {
      final uri = Uri.parse(url);
      final headers = <String, dynamic>{};
      final token = _authToken;
      if (token != null) {
        headers[HttpHeaders.authorizationHeader] = 'Bearer $token';
      }
      _channel = IOWebSocketChannel.connect(
        uri,
        headers: headers,
        connectTimeout: const Duration(seconds: 10),
      );
      final channel = _channel!;

      // Catch channel.ready Future exception to prevent bubbling to runZonedGuarded
      _readyTimer = Timer(const Duration(milliseconds: _readyTimeoutMs), () {
        if (_channel != channel || _intentionalClose) return;
        _notifyError('连接就绪超时');
        _cleanup();
        _scheduleReconnect();
      });
      channel.ready.then((_) {
        if (_channel != channel || _intentionalClose) return;
        _readyTimer?.cancel();
        _readyTimer = null;
        _ready = true;
        // 连接成功即重置指数退避，避免长稳连接后偶发断开直接进入长退避
        _reconnectAttempt = 0;
        if (_channel != null) _notifyStateChange(true, url);
      }).catchError((error) {
        if (_channel != channel) return;
        _ready = false;
        _readyTimer?.cancel();
        _readyTimer = null;
        _notifyStateChange(false, url);
        _notifyPhase(HostPhase.error);
        _notifyError(_friendlyErrorMessage(error));
        _scheduleReconnect();
      });

      _notifyStateChange(false, url);
      _notifyPhase(HostPhase.connecting);

      channel.stream.listen(
        (data) {
          if (_channel != channel) return;
          _lastMsgReceived = DateTime.now();
          _handleRaw(data as String);
        },
        onError: (error) {
          if (_channel != channel) return;
          _ready = false;
          _notifyStateChange(false, url);
          _notifyPhase(HostPhase.error);
          _notifyError(_friendlyErrorMessage(error));
          _scheduleReconnect();
        },
        onDone: () {
          if (_channel != channel) return;
          _ready = false;
          _notifyStateChange(false, url);
          _scheduleReconnect();
        },
      );
      _startHeartbeat();
      _startWatchdog();
    } catch (e) {
      _notifyStateChange(false, url);
      _notifyPhase(HostPhase.error);
      _notifyError(_friendlyErrorMessage(e));
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_intentionalClose) return;
    _notifyPhase(HostPhase.reconnecting);
    final delay = (_reconnectBaseMs * (1 << _reconnectAttempt.clamp(0, 5)))
        .clamp(_reconnectBaseMs, _reconnectMaxMs);
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(milliseconds: delay), () {
      if (_currentUrl.isNotEmpty && !_intentionalClose) {
        _reconnectAttempt++;
        if (_reconnectAttempt > 12) {
          _notifyPhase(HostPhase.offline);
          return;
        }
        _doConnect(_currentUrl);
      }
    });
  }

  // ── Heartbeat & Watchdog ──
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      const Duration(milliseconds: _heartbeatMs),
      (_) => send(ClientMessage(type: 'heartbeat')),
    );
  }

  void _startWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer.periodic(const Duration(milliseconds: _watchdogMs), (_) {
      final elapsed = DateTime.now().difference(_lastMsgReceived).inMilliseconds;
      if (elapsed > _watchdogTimeoutMs && !_intentionalClose) {
        _notifyError('heartbeat timeout');
        _cleanup();
        _scheduleReconnect();
      }
    });
  }

  // ── Message handling with dedup ──
  void _handleRaw(String raw) {
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final msg = ServerMessage.fromJson(json);

      // Message IDs are bridge cursors (`sessionId:seq`). Keep a bounded set so
      // replay after reconnect cannot duplicate assistant/tool output.
      final messageId = msg.messageId;
      if (messageId != null && messageId.isNotEmpty) {
        if (!_seenMessageIds.add(messageId)) return;
        if (_seenMessageIds.length > _maxSeenMessageIds) {
          _seenMessageIds.remove(_seenMessageIds.first);
        }
      }

      _routeMessage(msg);
    } catch (_) {}
  }

  void _routeMessage(ServerMessage msg) {
    for (final cb in _onMessage) { cb(msg); }
    switch (msg.type) {
      case 'server_info':
        _reconnectAttempt = 0;
        _notifyServerInfo();
        break;
      case 'agent_list': if (msg.agents != null) _notifyAgentList(msg.agents!); break;
      case 'registry_agents_list': if (msg.registryAgents != null) _notifyRegistryList(msg.registryAgents!); break;
      case 'error': if (msg.text != null) _notifyError(msg.text!); break;
      case 'target_offline': _notifyPhase(HostPhase.waitingHost); break;
      default: break;
    }
  }

  // ── Callbacks ──
  void onMessage(MessageCallback cb) => _onMessage.add(cb);
  void removeMessageListener(MessageCallback cb) => _onMessage.remove(cb);
  void onStateChange(void Function(bool, String) cb) => _onStateChange.add(cb);
  void onServerInfo(void Function() cb) => _onServerInfo.add(cb);
  void onAgentList(void Function(List<AgentInfo>) cb) => _onAgentList.add(cb);
  void onError(void Function(String) cb) => _onError.add(cb);
  void onRegistryList(void Function(List<RegistryAgentInfo>) cb) => _onRegistryList.add(cb);
  void onPhaseChange(void Function(String phase) cb) => _onPhaseChange.add(cb);

  void clearListeners() {
    _onMessage.clear(); _onStateChange.clear(); _onServerInfo.clear();
    _onAgentList.clear(); _onError.clear(); _onRegistryList.clear(); _onPhaseChange.clear();
  }

  void _notifyStateChange(bool connected, String detail) {
    for (final cb in _onStateChange) { cb(connected, detail); }
  }
  void _notifyServerInfo() { for (final cb in _onServerInfo) { cb(); } }
  void _notifyAgentList(List<AgentInfo> agents) {
    for (final cb in _onAgentList) { cb(agents); }
  }
  void _notifyError(String text) { for (final cb in _onError) { cb(text); } }
  void _notifyRegistryList(List<RegistryAgentInfo> list) {
    for (final cb in _onRegistryList) { cb(list); }
  }
  void _notifyPhase(HostPhase phase) {
    final s = phase.name;
    if (_currentHostKey.isNotEmpty) {
      HostRuntimeStore().setPhase(_currentHostKey, phase);
    }
    for (final cb in _onPhaseChange) { cb(s); }
  }

  void _clearSeenMessageIds() {
    _seenMessageIds.clear();
  }

  void _cleanup() {
    _heartbeatTimer?.cancel(); _heartbeatTimer = null;
    _watchdogTimer?.cancel(); _watchdogTimer = null;
    _readyTimer?.cancel(); _readyTimer = null;
    _ready = false;
    _channel?.sink.close(); _channel = null;
  }

  void dispose() {
    _intentionalClose = true;
    _reconnectTimer?.cancel();
    _clearSeenMessageIds();
    _cleanup();
  }
}
