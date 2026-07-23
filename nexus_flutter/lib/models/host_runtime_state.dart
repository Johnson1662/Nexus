/// Host runtime state — mirrors ArkTS HostState.ets / HostRuntimeStore
enum HostPhase {
  unknown,
  connecting,
  waitingHost,
  online,
  offline,
  reconnecting,
  syncing,
  error,
}

class HostRuntimeState {
  final String hostKey;
  HostPhase phase;
  String activeUrl;
  int lastSeenAt;
  int lastAttemptAt;
  int retryAttempt;
  int latencyMs;
  String lastError;
  bool everOnline;

  HostRuntimeState({
    required this.hostKey,
    this.phase = HostPhase.unknown,
    this.activeUrl = '',
    this.lastSeenAt = 0,
    this.lastAttemptAt = 0,
    this.retryAttempt = 0,
    this.latencyMs = 0,
    this.lastError = '',
    this.everOnline = false,
  });
}

class HostRuntimeStore {
  static final HostRuntimeStore _instance = HostRuntimeStore._();
  factory HostRuntimeStore() => _instance;
  HostRuntimeStore._();

  final Map<String, HostRuntimeState> _statuses = {};
  String activeHostKey = '';

  HostRuntimeState getStatus(String hostKey) {
    return _statuses.putIfAbsent(
      hostKey,
      () => HostRuntimeState(hostKey: hostKey),
    );
  }

  HostRuntimeState? getStatusOrNull(String hostKey) => _statuses[hostKey];

  HostPhase getDevicePhase(String hostKey) =>
      _statuses[hostKey]?.phase ?? HostPhase.unknown;

  bool isOnline(String hostKey) {
    final phase = _statuses[hostKey]?.phase;
    return phase == HostPhase.online || phase == HostPhase.syncing;
  }

  void setPhase(String hostKey, HostPhase phase, {String? url, String? error}) {
    final state = getStatus(hostKey);
    state.phase = phase;
    state.lastAttemptAt = DateTime.now().millisecondsSinceEpoch;
    if (url != null) state.activeUrl = url;
    if (error != null) state.lastError = error;
    if (phase == HostPhase.online) {
      state.everOnline = true;
      state.lastSeenAt = DateTime.now().millisecondsSinceEpoch;
      activeHostKey = hostKey;
    }
  }

  void markOnline(String hostKey, String url) {
    setPhase(hostKey, HostPhase.online, url: url);
  }

  void markOffline(String hostKey) {
    final state = _statuses[hostKey];
    if (state != null) {
      state.phase = HostPhase.offline;
    }
  }

  void markReconnecting(String hostKey) {
    setPhase(hostKey, HostPhase.reconnecting);
    final state = _statuses[hostKey];
    if (state != null) state.retryAttempt++;
  }

  void setLatency(String hostKey, int ms) {
    final state = _statuses[hostKey];
    if (state != null) state.latencyMs = ms;
  }
}
