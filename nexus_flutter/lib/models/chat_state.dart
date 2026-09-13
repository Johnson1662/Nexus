import 'dart:collection';

import 'message_data.dart';
import 'ws_protocol.dart';

/// Application-wide chat state — analogous to ArkTS ChatStore.
class ChatState {
  // Messages
  List<MessageData> messages = [];
  String lastMessageId = '';

  // Turn / streaming
  bool turnActive = false;
  bool cancelling = false;
  String streamingThinking = '';
  String streamingText = '';
  String accumulatorType = ''; // 'thinking' | 'text' | 'tool'

  // Connection
  bool connected = false;
  String currentDeviceId = '';
  String sessionId = '';
  String reconnectPhase = '';
  int reconnectAttempt = 0;
  String errorMessage = '';
  String contextReplacedNotice = '';

  // Sessions
  List<ServerSessionData> sessions = [];
  Set<String> pinnedSessionIds = {};
  bool loadingSession = false;
  String sessionTitle = '';
  String sessionCurrentModelId = '';
  String streamMode = 'acp'; // 'acp' | 'terminal'

  // Agent / Model / Mode
  String selectedAgentName = '';
  String agentType = '';
  List<String> agentNames = [];
  List<AgentInfo> installedAgents = [];
  List<ModelItem> models = [];
  int modelIndex = 0;
  String lastModelId = '';
  List<ModeItem> modes = [];
  int modeIndex = 0;
  bool loadingModels = false;
  List<ConfigOption> configOptions = [];
  List<Map<String, String>> authMethods = [];
  bool terminalBlocked = false;
  int historyOffset = 0;
  int historyTotal = 0;
  bool historyHasMore = false;
  bool loadingOlderHistory = false;

  // Advanced
  List<RegistryAgentInfo> registryAgents = [];
  HostCapabilities? hostCapabilities;
  List<Map<String, dynamic>> herdrIntegrations = [];
  List<AvailableCommand> availableCommands = [];
  List<PlanEntry> planEntries = [];
  List<PendingToolCall> toolCallStack = [];

  // Workspace
  String currentWorkspace = '';

  // File browser
  List<Map<String, dynamic>> workspaceFiles = [];
  String? selectedFilePath;
  String? fileDiff;
  List<Map<String, dynamic>> fileLogEntries = [];
  String? fileContent;
  bool loadingFiles = false;
  /// Non-empty when Git is missing or the folder is not a repository.
  String fileGitWarning = '';

  // Permissions / Usage
  UsageInfo? lastUsage;
  final LinkedHashMap<String, PendingPermission> pendingPermissions =
      LinkedHashMap();

  /// 队首待处理权限（UI 一次展示一个，响应后展示下一个）。
  PendingPermission? get pendingPermission =>
      pendingPermissions.isEmpty ? null : pendingPermissions.values.first;

  void resetForNewChat() {
    sessionId = '';
    sessionTitle = '';
    streamMode = 'acp';
    loadingSession = false;
    turnActive = false;
    cancelling = false;
    contextReplacedNotice = '';
    errorMessage = '';
    messages = [];
    streamingThinking = '';
    streamingText = '';
    accumulatorType = '';
    sessionCurrentModelId = '';
    modelIndex = -1;
    modes = [];
    modeIndex = -1;
    configOptions = [];
    authMethods = [];
    terminalBlocked = false;
    historyOffset = 0;
    historyTotal = 0;
    historyHasMore = false;
    loadingOlderHistory = false;
    availableCommands = [];
    planEntries = [];
    toolCallStack = [];
    lastUsage = null;
    pendingPermissions.clear();
  }
}
