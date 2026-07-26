import 'message_data.dart';
import 'ws_protocol.dart';

/// Application-wide chat state — analogous to ArkTS ChatStore.
class ChatState {
  // Messages
  List<MessageData> messages = [];
  String lastMessageId = '';

  // Turn / streaming
  bool turnActive = false;
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
  PendingPermission? pendingPermission;

  void resetForNewChat() {
    sessionId = '';
    sessionTitle = '';
    loadingSession = false;
    turnActive = false;
    messages = [];
    streamingThinking = '';
    streamingText = '';
    accumulatorType = '';
    lastUsage = null;
    pendingPermission = null;
  }
}
