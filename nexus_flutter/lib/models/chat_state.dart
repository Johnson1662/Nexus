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

  // Agent / Model / Mode
  String selectedAgentName = '';
  String agentType = '';
  List<String> agentNames = [];
  List<ModelItem> models = [];
  int modelIndex = 0;
  String lastModelId = '';
  List<ModeItem> modes = [];
  int modeIndex = 0;
  bool loadingModels = false;
  List<ConfigOption> configOptions = [];

  // Advanced
  List<RegistryAgentInfo> registryAgents = [];
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
    loadingSession = false;
    turnActive = false;
    cancelling = false;
    contextReplacedNotice = '';
    messages = [];
    streamingThinking = '';
    streamingText = '';
    accumulatorType = '';
    lastUsage = null;
    pendingPermissions.clear();
  }
}
