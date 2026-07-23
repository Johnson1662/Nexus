import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
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
  bool _intentionalClose = false;
  int _reconnectAttempt = 0;
  String _lastReceivedMessageId = '';

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
  static const int _reconnectBaseMs = 1000;
  static const int _reconnectMaxMs = 30000;
  DateTime _lastMsgReceived = DateTime.now();

  bool get isConnected => _channel != null;
  String get currentUrl => _currentUrl;
  String get currentHostKey => _currentHostKey;
  int get reconnectAttempt => _reconnectAttempt;

  // ── Public API ──

  void connect(String url, String hostKey) {
    if (_currentUrl == url && isConnected) return;
    _intentionalClose = false;
    _currentUrl = url;
    _currentHostKey = hostKey;
    _reconnectAttempt = 0;
    _notifyPhase(HostPhase.connecting);
    _doConnect(url);
  }

  Future<void> connectBest(List<String> candidates, String hostKey) async {
    _notifyPhase(HostPhase.connecting);
    _currentHostKey = hostKey;
    for (final url in candidates) {
      try {
        if (await probeCandidate(url)) {
          connect(url, hostKey);
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

  Future<bool> probeCandidate(String url) async {
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
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 4);
      final request = await client.getUrl(Uri.parse(probeUrl));
      final response = await request.close().timeout(const Duration(seconds: 4));
      client.close();
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  String _friendlyErrorMessage(dynamic error) {
    final str = error.toString();
    if (str.contains('Connection reset by peer')) {
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
      _channel = WebSocketChannel.connect(uri);

      // Catch channel.ready Future exception to prevent bubbling to runZonedGuarded
      _channel!.ready.catchError((error) {
        _notifyStateChange(false, url);
        _notifyPhase(HostPhase.error);
        _notifyError(_friendlyErrorMessage(error));
        _scheduleReconnect();
      });

      _notifyStateChange(false, url);
      _notifyPhase(HostPhase.connecting);

      _channel!.stream.listen(
        (data) {
          _lastMsgReceived = DateTime.now();
          _handleRaw(data as String);
        },
        onError: (error) {
          _notifyStateChange(false, url);
          _notifyPhase(HostPhase.error);
          _notifyError(_friendlyErrorMessage(error));
          _scheduleReconnect();
        },
        onDone: () {
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

      // Debug: dump raw JSON of all non-heartbeat messages to sandbox file
      if (msg.type != 'heartbeat') {
        try {
          final f = File('/data/storage/el2/base/haps/entry/files/anywhere_acp_debug.jsonl');
          f.writeAsStringSync('${jsonEncode(json)}\n', mode: FileMode.append);
        } catch (_) {}
      }

      // Dedup: skip already-processed messages
      if (msg.messageId != null && msg.messageId!.isNotEmpty) {
        if (msg.messageId == _lastReceivedMessageId) return;
        _lastReceivedMessageId = msg.messageId!;
      }

      _routeMessage(msg);
    } catch (_) {}
  }

  void _routeMessage(ServerMessage msg) {
    for (final cb in _onMessage) { cb(msg); }
    switch (msg.type) {
      case 'server_info': _notifyServerInfo(); break;
      case 'agent_list': if (msg.agents != null) _notifyAgentList(msg.agents!); break;
      case 'registry_agest_list': if (msg.registryAgents != null) _notifyRegistryList(msg.registryAgents!); break;
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

  void _cleanup() {
    _heartbeatTimer?.cancel(); _heartbeatTimer = null;
    _watchdogTimer?.cancel(); _watchdogTimer = null;
    _channel?.sink.close(); _channel = null;
  }

  void dispose() {
    _intentionalClose = true;
    _reconnectTimer?.cancel();
    _cleanup();
  }
}
