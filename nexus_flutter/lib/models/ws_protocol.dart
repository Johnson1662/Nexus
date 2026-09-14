import 'dart:convert';

/// Canonical replay cursor assigned by the bridge (`sessionId:seq`).
class SessionMessageCursor {
  final String sessionId;
  final int sequence;

  const SessionMessageCursor(this.sessionId, this.sequence);

  static SessionMessageCursor? parse(String? value) {
    if (value == null || value.isEmpty) return null;
    final separator = value.lastIndexOf(':');
    if (separator <= 0 || separator == value.length - 1) return null;
    final sequence = int.tryParse(value.substring(separator + 1));
    if (sequence == null || sequence <= 0) return null;
    return SessionMessageCursor(value.substring(0, separator), sequence);
  }

  String get messageId => '$sessionId:$sequence';
}

/// Client → Server message payloads
class ClientMessage {
  final String type;
  final String? agent;
  final String? agentId;
  final String? command;
  final List<String>? args;
  final String? name;
  final String? sessionId;
  final String? text;
  final String? cwd;
  final String? model;
  final String? modeId;
  final String? requestId;
  final String? outcome;
  final String? prompt;
  final String? configId;
  final Object? value;
  final String? optionId;
  final String? methodId;
  final String? lastMessageId;
  final bool? useHerdr;
  final String? workspaceId;
  final String? creationMode;
  final String? paneId;
  final String? title;
  final int? freshAt;
  final int? before;
  final String? key;
  final String? label;
  final String? target;
  final bool? asText;

  ClientMessage({
    required this.type,
    this.agent,
    this.agentId,
    this.command,
    this.args,
    this.name,
    this.sessionId,
    this.text,
    this.cwd,
    this.model,
    this.modeId,
    this.requestId,
    this.outcome,
    this.prompt,
    this.configId,
    this.value,
    this.optionId,
    this.methodId,
    this.lastMessageId,
    this.useHerdr,
    this.workspaceId,
    this.creationMode,
    this.paneId,
    this.title,
    this.freshAt,
    this.before,
    this.key,
    this.label,
    this.target,
    this.asText,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'type': type,
        if (agent != null && agent!.isNotEmpty) 'agent': agent,
        if (command != null) 'command': command,
        if (args != null) 'args': args,
        if (name != null) 'name': name,
        if (sessionId != null && sessionId!.isNotEmpty) 'sessionId': sessionId,
        if (text != null && text!.isNotEmpty) 'text': text,
        if (cwd != null && cwd!.isNotEmpty) 'cwd': cwd,
        if (model != null && model!.isNotEmpty) 'model': model,
        if (modeId != null && modeId!.isNotEmpty) 'modeId': modeId,
        if (requestId != null) 'requestId': requestId,
        if (outcome != null) 'outcome': outcome,
        if (prompt != null) 'prompt': prompt,
        if (configId != null) 'configId': configId,
        if (value != null) 'value': value,
        if (optionId != null) 'optionId': optionId,
        if (methodId != null) 'methodId': methodId,
        if (lastMessageId != null) 'lastMessageId': lastMessageId,
        if (useHerdr != null) 'useHerdr': useHerdr,
        if (workspaceId != null && workspaceId!.isNotEmpty) 'workspaceId': workspaceId,
        if (agentId != null && agentId!.isNotEmpty) 'agentId': agentId,
        if (creationMode != null && creationMode!.isNotEmpty) 'creationMode': creationMode,
        if (paneId != null && paneId!.isNotEmpty) 'paneId': paneId,
        if (title != null && title!.isNotEmpty) 'title': title,
        if (freshAt != null) 'freshAt': freshAt,
        if (before != null) 'before': before,
        if (key != null && key!.isNotEmpty) 'key': key,
        if (label != null && label!.isNotEmpty) 'label': label,
        if (target != null && target!.isNotEmpty) 'target': target,
        if (asText != null) 'asText': asText,
      };
}

/// Server → Client message
class ServerMessage {
  final String type;
  final String? text;
  final String? sessionId;
  final String? agentId;
  final String? agent;
  final String? model;
  final String? title;
  final String? status;
  final AcpUpdate? event;
  final int? exitCode;
  final List<ModelItem>? models;
  final List<ModeItem>? modes;
  final List<ServerSessionData>? sessions;
  final List<AgentInfo>? agents;
  final List<RegistryAgentInfo>? registryAgents;
  final String? stopReason;
  final String? messageId;
  final bool? resumed;
  final String? requestId;
  final Map<String, dynamic>? toolCall;
  final List<Map<String, dynamic>>? options;
  final List<ConfigOption>? configOptions;
  final String? hostname;
  final List<String>? ips;
  final String? hostId;
  final List<String>? workspaces;
  final List<Map<String, dynamic>>? herdrWorkspaces;
  final String? paneId;
  final String? workspaceId;
  final List<Map<String, dynamic>>? entries; // sync_response entries
  final bool? overflow; // sync_response cursor fell out of the replay window
  final bool? turnActive; // optional server turn-state snapshot
  // Workspace file browser
  final List<Map<String, dynamic>>? files; // workspace_files response
  final String? diff; // file_diff response
  final List<Map<String, dynamic>>? logEntries; // file_log response
  final String? fileContent; // file_content response
  final String? path; // file path for responses
  final String? streamMode; // 'acp' | 'terminal'
  final List<dynamic>? events; // history_full response
  final int? freshAt; // creation boundary for a fresh Herdr pane
  final bool? historyTruncated;
  final int? historyTotal;
  final int? historyOffset;
  final bool? historyHasMore;
  final bool? ok;
  final String? error;
  final List<Map<String, String>>? authMethods;
  final HostCapabilities? hostCapabilities;
  final List<Map<String, dynamic>>? herdrIntegrations;
  final Map<String, dynamic>? integration;
  AcpUpdate? get acpUpdate => event;

  ServerMessage({
    required this.type,
    this.text,
    this.sessionId,
    this.agentId,
    this.agent,
    this.model,
    this.title,
    this.status,
    this.event,
    this.exitCode,
    this.models,
    this.modes,
    this.sessions,
    this.agents,
    this.registryAgents,
    this.stopReason,
    this.messageId,
    this.resumed,
    this.requestId,
    this.toolCall,
    this.options,
    this.configOptions,
    this.hostname,
    this.ips,
    this.hostId,
    this.workspaces,
    this.herdrWorkspaces,
    this.paneId,
    this.workspaceId,
    this.entries,
    this.overflow,
    this.turnActive,
    this.files,
    this.diff,
    this.logEntries,
    this.fileContent,
    this.path,
    this.streamMode,
    this.events,
    this.freshAt,
    this.historyTruncated,
    this.historyTotal,
    this.historyOffset,
    this.historyHasMore,
    this.ok,
    this.error,
    this.authMethods,
    this.hostCapabilities,
    this.herdrIntegrations,
    this.integration,
  });

  factory ServerMessage.fromJson(Map<String, dynamic> json) {
    AcpUpdate? parseEvent(Map<String, dynamic>? e) {
      if (e == null) return null;
      // Server sends 'sessionUpdate' as the event type.
      // Content can be:
      //   String  — tool output, simple text
      //   Map     — nested {"text": "..."} for message chunks
      //   List    — content blocks for tool_call_update:
      //       [{"type":"content","content":{"text":"..."}},
      //        {"type":"diff","path":...,"oldText":...,"newText":...},
      //        {"type":"terminal","terminalId":...}]
      String? extractText(dynamic c) {
        if (c is String) return c;
        if (c is Map) return c['text'] as String?;
        if (c is List) {
          // Only blocks with type=="text" carry displayable text here.
          // NOTE: type=="content" blocks are handled separately into toolContentText.
          final text = (c)
              .whereType<Map>()
              .where((b) => b['type'] == 'text')
              .map((b) => (b['text'] as String?) ?? '')
              .join();
          // Return null when empty so callers' ?? fallback actually applies.
          return text.isNotEmpty ? text : null;
        }
        return null;
      }

      // Parse tool_call_update content array into structured fields.
      String? toolContentText;
      String? toolContentType;
      String? toolPath;
      String? toolOldText;
      String? toolNewText;
      String? toolTerminalId;
      bool toolTerminalTruncated = false;
      final rawContent = e['content'] ?? e['toolCallContent'];
      if (rawContent is List) {
        final sb = StringBuffer();
        for (final item in rawContent.whereType<Map>()) {
          final type = item['type'] as String? ?? '';
          if (type == 'content') {
            final nested = item['content'];
            if (nested is Map && nested['text'] != null) {
              sb.write(nested['text'] as String);
              if (toolContentType == null || toolContentType.isEmpty) toolContentType = 'content';
            } else if (item['text'] != null) {
              sb.write(item['text'] as String);
              if (toolContentType == null || toolContentType.isEmpty) toolContentType = 'content';
            }
          } else if (type == 'text') {
            if (item['text'] != null) {
              sb.write(item['text'] as String);
              if (toolContentType == null || toolContentType.isEmpty) toolContentType = 'content';
            }
          } else if (type == 'diff') {
            toolContentType = 'diff';
            toolPath = item['path'] as String?;
            toolOldText = item['oldText'] as String?;
            toolNewText = item['newText'] as String?;
          } else if (type == 'terminal') {
            toolContentType = 'terminal';
            toolTerminalId = item['terminalId'] as String?;
            if (item['truncated'] == true) toolTerminalTruncated = true;
            // terminal 块文本（{type:'text', text}）同样累积进 toolContent
            final nested = item['content'];
            if (nested is Map && nested['text'] != null) {
              sb.write(nested['text'] as String);
            }
          }
        }
        if (sb.length > 0) toolContentText = sb.toString();
      }

      // Prefer the structured parse (toolContentText) — it correctly handles
      // type:"content" blocks. Fall back to raw extraction only if no text was parsed.
      final extractedText = (toolContentText != null && toolContentText.isNotEmpty)
          ? toolContentText
          : (extractText(e['content']) ?? extractText(e['text']));

      String? toolInput;
      final rawInput = e['rawInput'] ?? e['arguments'];
      if (rawInput is Map) {
        if (rawInput['questions'] != null || rawInput['question'] != null) {
          toolInput = jsonEncode(rawInput);
        } else {
          toolInput = (rawInput['command'] ?? rawInput['path'] ?? rawInput['intent'] ?? rawInput['query'] ?? rawInput['title'])?.toString();
          if (toolInput == null || toolInput.isEmpty) {
            toolInput = jsonEncode(rawInput);
          }
        }
      } else if (rawInput != null) {
        toolInput = rawInput.toString();
      }

      return AcpUpdate(
        event: e['sessionUpdate'] as String? ?? '',
        text: extractedText ?? extractText(e['text']),
        toolCallId: e['toolCallId'] as String?,
        toolName: e['toolName'] as String? ?? e['title'] as String?,
        toolInput: toolInput,
        toolStatus: e['status'] as String? ?? e['toolStatus'] as String?,
        content: extractedText ?? extractText(e['text']),
        contentType: e['contentType'] as String? ?? toolContentType,
        path: e['path'] as String? ?? toolPath,
        oldText: e['oldText'] as String? ?? toolOldText,
        newText: e['newText'] as String? ?? toolNewText,
        terminalId: e['terminalId'] as String? ?? toolTerminalId,
        terminalTruncated: toolTerminalTruncated,
        title: e['title'] as String?,
        kind: e['kind'] as String?,
        messageRole: e['role'] as String?,
        messageText: extractedText,
        usage: e['usage'] != null ? UsageInfo.fromJson(e['usage'] as Map<String, dynamic>) : null,
        planContent: e['planContent'] != null ? AcpContent.fromJson(e['planContent'] as Map<String, dynamic>) : null,
        commands: ((e['availableCommands'] ?? e['commands']) as List<dynamic>?)
            ?.whereType<Map>()
            .map((c) => AvailableCommand.fromJson(Map<String, dynamic>.from(c)))
            .toList(),
        config: (e['config'] as List<dynamic>?)?.map((c) => ConfigOption.fromJson(c as Map<String, dynamic>)).toList(),
        planEntries: (e['planEntries'] as List<dynamic>?)?.map((p) => PlanEntry.fromJson(p as Map<String, dynamic>)).toList(),
      );
    }

    return ServerMessage(
      type: json['type'] as String? ?? '',
      text: json['text'] as String?,
      sessionId: json['sessionId'] as String?,
      agentId: json['agentId'] as String?,
      agent: json['agent'] as String?,
      model: json['model'] as String?,
      title: json['title'] as String?,
      status: json['status'] as String?,
      event: parseEvent(json['event'] as Map<String, dynamic>?),
      exitCode: json['exitCode'] as int?,
      models: (json['models'] as List<dynamic>?)
          ?.map((m) => ModelItem.fromJson(m as Map<String, dynamic>))
          .toList(),
      modes: (json['modes'] as List<dynamic>?)
          ?.map((m) => ModeItem.fromJson(m as Map<String, dynamic>))
          .toList(),
      sessions: (json['sessions'] as List<dynamic>?)
          ?.map((s) => ServerSessionData.fromJson(s as Map<String, dynamic>))
          .toList(),
      agents: (json['agents'] as List<dynamic>?)
          ?.map((a) => AgentInfo.fromJson(a as Map<String, dynamic>))
          .toList(),
      registryAgents: ((json['registryAgents'] ??
                  (json['type'] == 'registry_agents_list'
                      ? json['agents']
                      : null)) as List<dynamic>?)
              ?.map((a) =>
                  RegistryAgentInfo.fromJson(Map<String, dynamic>.from(a as Map)))
              .toList(),
      stopReason: json['stopReason'] as String?,
      messageId: json['messageId'] as String?,
      resumed: json['resumed'] as bool?,
      requestId: json['requestId'] as String?,
      toolCall: json['toolCall'] as Map<String, dynamic>?,
      options: (json['options'] as List<dynamic>?)
          ?.map((o) => o as Map<String, dynamic>)
          .toList(),
      configOptions: (json['configOptions'] as List<dynamic>?)
          ?.map((c) => ConfigOption.fromJson(c as Map<String, dynamic>))
          .toList(),
      hostname: json['hostname'] as String?,
      ips: (json['ips'] as List<dynamic>?)?.map((ip) => ip as String).toList(),
      hostId: json['hostId'] as String?,
      workspaces: json['workspaces'] is List &&
              (json['workspaces'] as List).isNotEmpty &&
              (json['workspaces'] as List).first is! Map
          ? (json['workspaces'] as List<dynamic>).map((w) => w.toString()).toList()
          : null,
      herdrWorkspaces: json['workspaces'] is List &&
              (json['workspaces'] as List).isNotEmpty &&
              (json['workspaces'] as List).first is Map
          ? (json['workspaces'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList()
          : null,
      paneId: json['paneId'] as String?,
      workspaceId: json['workspaceId'] as String?,
      entries: (json['entries'] as List<dynamic>?)?.map((e) => e as Map<String, dynamic>).toList(),
      overflow: json['overflow'] as bool?,
      turnActive: json['turnActive'] as bool?,

      files: (json['files'] as List<dynamic>?)?.map((f) => f as Map<String, dynamic>).toList(),
      diff: json['diff'] as String?,
      logEntries: ((json['logEntries'] ??
                  (json['type'] == 'file_log' ? json['entries'] : null))
              as List<dynamic>?)
          ?.map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
      fileContent: (json['fileContent'] ??
              (json['type'] == 'file_content' ? json['content'] : null))
          as String?,
      path: json['path'] as String?,
      streamMode: json['streamMode'] as String?,
      events: json['events'] as List<dynamic>?,
      freshAt: json['freshAt'] as int?,
      historyTruncated: json['historyTruncated'] as bool?,
      historyTotal: json['historyTotal'] as int?,
      historyOffset: json['historyOffset'] as int?,
      historyHasMore: json['historyHasMore'] as bool?,
      ok: json['ok'] as bool?,
      error: json['error'] as String?,
      authMethods: (json['authMethods'] as List<dynamic>?)
          ?.whereType<Map>()
          .map((m) => Map<String, String>.fromEntries(
              m.entries.map((e) => MapEntry(e.key.toString(), e.value.toString()))))
          .toList(),
      hostCapabilities: json['capabilities'] != null && json['type'] == 'host_capabilities'
          ? HostCapabilities.fromJson(json['capabilities'] as Map<String, dynamic>)
          : null,
      herdrIntegrations: (json['integrations'] as List<dynamic>?)
          ?.map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
      integration: json['integration'] is Map
          ? Map<String, dynamic>.from(json['integration'] as Map)
          : null,
    );
  }
}

class AcpUpdate {
  final String event;
  final String? text;
  final String? toolCallId;
  final String? toolName;
  final String? toolInput;
  final String? toolStatus;
  final String? content;
  final String? contentType;
  final String? path;
  final String? oldText;
  final String? newText;
  final String? terminalId;
  final bool terminalTruncated;
  final String? title;
  final String? kind;
  final String? messageRole;
  final String? messageText;
  final AcpContent? planContent;
  final UsageInfo? usage;
  final List<AvailableCommand>? commands;
  final List<ConfigOption>? config;
  final List<PlanEntry>? planEntries;

  AcpUpdate({
    required this.event,
    this.text,
    this.toolCallId,
    this.toolName,
    this.toolInput,
    this.toolStatus,
    this.content,
    this.contentType,
    this.path,
    this.oldText,
    this.newText,
    this.terminalId,
    this.terminalTruncated = false,
    this.title,
    this.kind,
    this.messageRole,
    this.messageText,
    this.planContent,
    this.usage,
    this.commands,
    this.config,
    this.planEntries,
  });
}

class AcpContent {
  final String? type;
  final String? text;
  final List<PlanEntry>? planEntries;

  AcpContent({this.type, this.text, this.planEntries});

  factory AcpContent.fromJson(Map<String, dynamic> json) => AcpContent(
        type: json['type'] as String?,
        text: json['text'] as String?,
        planEntries: (json['planEntries'] as List<dynamic>?)
            ?.map((p) => PlanEntry.fromJson(p as Map<String, dynamic>))
            .toList(),
      );
}

class ServerSessionData {
  final String sessionId;
  final String? title;
  final String? agent;
  final String? cwd;
  final int createdAt;
  final int? lastActivity;
  final String? status;
  final String? source;

  ServerSessionData({
    required this.sessionId,
    this.title,
    this.agent,
    this.cwd,
    this.createdAt = 0,
    this.lastActivity,
    this.status,
    this.source,
  });

  factory ServerSessionData.fromJson(Map<String, dynamic> json) => ServerSessionData(
        sessionId: json['sessionId'] as String? ?? '',
        title: json['title'] as String?,
        agent: json['agent'] as String?,
        cwd: json['cwd'] as String?,
        createdAt: json['createdAt'] as int? ?? DateTime.now().millisecondsSinceEpoch,
        lastActivity: json['lastActivity'] as int?,
        status: json['status'] as String?,
        source: json['source'] as String?,
      );
}

class ModelItem {
  final String modelId;
  final String name;
  String get id => modelId;

  ModelItem({required this.modelId, required this.name});

  factory ModelItem.fromJson(Map<String, dynamic> json) => ModelItem(
        modelId: json['modelId'] as String? ?? '',
        name: json['name'] as String? ?? '',
      );
}

class ModeItem {
  final String value;
  final String name;
  String get id => value;

  ModeItem({required this.value, required this.name});

  factory ModeItem.fromJson(Map<String, dynamic> json) => ModeItem(
        value: json['value'] as String? ?? '',
        name: json['name'] as String? ?? '',
      );
}

class ConfigOption {
  final String id;
  final String name;
  final String? description;
  final String? category;
  final String type;
  final Object currentValue;
  final List<ConfigOptionValue> options;

  ConfigOption({
    required this.id,
    required this.name,
    this.description,
    this.category,
    required this.type,
    required this.currentValue,
    required this.options,
  });

  factory ConfigOption.fromJson(Map<String, dynamic> json) {
    final opts = (json['options'] as List<dynamic>?)
            ?.map((o) => ConfigOptionValue.fromJson(o as Map<String, dynamic>))
            .toList() ??
        [];
    return ConfigOption(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String?,
      category: json['category'] as String?,
      type: json['type'] as String? ?? '',
      currentValue: json['currentValue'] ?? '',
      options: opts,
    );
  }
}

class ConfigOptionValue {
  final String value;
  final String? name;
  String get id => value;

  ConfigOptionValue({required this.value, this.name});

  factory ConfigOptionValue.fromJson(Map<String, dynamic> json) => ConfigOptionValue(
        value: json['value'] as String? ?? '',
        name: json['name'] as String?,
      );
}

class UsageInfo {
  final int inputTokens;
  final int outputTokens;
  final int totalTokens;

  UsageInfo({
    required this.inputTokens,
    required this.outputTokens,
    required this.totalTokens,
  });

  factory UsageInfo.fromJson(Map<String, dynamic> json) => UsageInfo(
        inputTokens: json['inputTokens'] as int? ?? 0,
        outputTokens: json['outputTokens'] as int? ?? 0,
        totalTokens: json['totalTokens'] as int? ?? 0,
      );
}

class AgentInfo {
  final String name;
  final String title;
  final String version;
  final String source;
  final String? binaryPath;
  final bool installed;
  final String? configPath;
  final bool ready;
  final String? error;
  final AgentNativeCapability native;
  final AgentHerdrCapability herdr;

  AgentInfo({
    required this.name,
    required this.title,
    required this.version,
    required this.source,
    this.binaryPath,
    required this.installed,
    this.configPath,
    required this.ready,
    this.error,
    required this.native,
    required this.herdr,
  });

  factory AgentInfo.fromJson(Map<String, dynamic> json) => AgentInfo(
        name: json['name'] as String? ?? '',
        title: json['title'] as String? ?? '',
        version: json['version'] as String? ?? '',
        source: json['source'] as String? ?? '',
        binaryPath: json['binaryPath'] as String?,
        installed: json['installed'] as bool? ?? false,
        configPath: json['configPath'] as String?,
        ready: json['ready'] as bool? ?? false,
        error: json['error'] as String?,
        native: AgentNativeCapability.fromJson(
            json['native'] as Map<String, dynamic>? ?? const {}),
        herdr: AgentHerdrCapability.fromJson(
            json['herdr'] as Map<String, dynamic>? ?? const {}),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'title': title,
        'version': version,
        'source': source,
        if (binaryPath != null) 'binaryPath': binaryPath,
        'installed': installed,
        if (configPath != null) 'configPath': configPath,
        'ready': ready,
        if (error != null) 'error': error,
        'native': native.toJson(),
        'herdr': herdr.toJson(),
      };
}

class RegistryAgentInfo {
  final String id;
  final String name;
  final String description;
  final String version;
  final String? repository;
  final String? icon;
  final Map<String, dynamic> distribution;

  RegistryAgentInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.version,
    this.repository,
    this.icon,
    required this.distribution,
  });

  factory RegistryAgentInfo.fromJson(Map<String, dynamic> json) => RegistryAgentInfo(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        description: json['description'] as String? ?? '',
        version: json['version'] as String? ?? '',
        repository: json['repository'] as String?,
        icon: json['icon'] as String?,
        distribution: json['distribution'] as Map<String, dynamic>? ?? {},
      );
}

class PermissionOption {
  final String optionId;
  final String name;
  final String kind;

  PermissionOption({
    required this.optionId,
    required this.name,
    required this.kind,
  });

  factory PermissionOption.fromJson(Map<String, dynamic> json) => PermissionOption(
        optionId: json['optionId'] as String? ?? '',
        name: json['name'] as String? ?? '',
        kind: json['kind'] as String? ?? '',
      );
}

class GitCapability {
  final bool available;
  final String? executable;
  final String? reason;

  const GitCapability({
    required this.available,
    this.executable,
    this.reason,
  });

  factory GitCapability.fromJson(Map<String, dynamic> json) => GitCapability(
        available: json['available'] as bool? ?? false,
        executable: json['executable'] as String?,
        reason: json['reason'] as String?,
      );
}

class HerdrCapability {
  final bool available;
  final String? version;
  final String? session;
  final String transport; // always 'cli'
  final String? binary;
  final String? reason;

  const HerdrCapability({
    required this.available,
    this.version,
    this.session,
    this.transport = 'cli',
    this.binary,
    this.reason,
  });

  factory HerdrCapability.fromJson(Map<String, dynamic> json) => HerdrCapability(
        available: json['available'] as bool? ?? false,
        version: json['version'] as String?,
        session: json['session'] as String?,
        transport: json['transport'] as String? ?? 'cli',
        binary: json['binary'] as String?,
        reason: json['reason'] as String?,
      );
}

class AgentNativeCapability {
  final bool supported;
  final bool ready;
  final String? executable;
  final String? executableSource;
  final String? reason;
  final bool structuredHistory;
  final bool modelSelection;
  final bool modeSelection;
  final bool authentication;
  final bool hookSupported;
  final bool hookInstalled;
  final String? hookState;
  final String? hookDescription;
  final bool adapterRequired;
  final bool adapterInstalled;
  final String? adapterSource;
  final bool nodeCompatible;
  final String? adapterPackage;
  final String? adapterBinary;

  const AgentNativeCapability({
    required this.supported,
    required this.ready,
    this.executable,
    this.executableSource,
    this.reason,
    this.structuredHistory = false,
    this.modelSelection = false,
    this.modeSelection = false,
    this.authentication = false,
    this.hookSupported = false,
    this.hookInstalled = false,
    this.hookState,
    this.hookDescription,
    this.adapterRequired = false,
    this.adapterInstalled = true,
    this.adapterSource,
    this.nodeCompatible = true,
    this.adapterPackage,
    this.adapterBinary,
  });

  factory AgentNativeCapability.fromJson(Map<String, dynamic> json) =>
      AgentNativeCapability(
        supported: json['supported'] as bool? ?? false,
        ready: json['ready'] as bool? ?? false,
        executable: json['executable'] as String?,
        executableSource: json['executableSource'] as String?,
        reason: json['reason'] as String?,
        structuredHistory: json['structuredHistory'] as bool? ?? false,
        modelSelection: json['modelSelection'] as bool? ?? false,
        modeSelection: json['modeSelection'] as bool? ?? false,
        authentication: json['authentication'] as bool? ?? false,
        hookSupported: json['hookSupported'] as bool? ?? false,
        hookInstalled: json['hookInstalled'] as bool? ?? false,
        hookState: json['hookState'] as String?,
        hookDescription: json['hookDescription'] as String?,
        adapterRequired: json['adapterRequired'] as bool? ?? false,
        adapterInstalled: json['adapterInstalled'] as bool? ?? true,
        adapterSource: json['adapterSource'] as String?,
        nodeCompatible: json['nodeCompatible'] as bool? ?? true,
        adapterPackage: json['adapterPackage'] as String?,
        adapterBinary: json['adapterBinary'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'supported': supported,
        'ready': ready,
        if (executable != null) 'executable': executable,
        if (executableSource != null) 'executableSource': executableSource,
        if (reason != null) 'reason': reason,
        'structuredHistory': structuredHistory,
        'modelSelection': modelSelection,
        'modeSelection': modeSelection,
        'authentication': authentication,
        'hookSupported': hookSupported,
        'hookInstalled': hookInstalled,
        if (hookState != null) 'hookState': hookState,
        if (hookDescription != null) 'hookDescription': hookDescription,
        'adapterRequired': adapterRequired,
        'adapterInstalled': adapterInstalled,
        if (adapterSource != null) 'adapterSource': adapterSource,
        'nodeCompatible': nodeCompatible,
        if (adapterPackage != null) 'adapterPackage': adapterPackage,
        if (adapterBinary != null) 'adapterBinary': adapterBinary,
      };
}

class AgentHerdrCapability {
  final bool supported;
  final bool ready;
  final String? kind;
  final String? integrationId;
  final bool integrationInstalled;
  /// current | not installed | outdated | missing | unknown | unsupported
  final String integrationState;
  final String? executableSource;
  final String? reason;
  final bool structuredHistory;
  final bool modelSelection;
  final bool modeSelection;
  final bool authentication;

  const AgentHerdrCapability({
    required this.supported,
    required this.ready,
    this.kind,
    this.integrationId,
    this.integrationInstalled = false,
    this.integrationState = 'unknown',
    this.executableSource,
    this.reason,
    this.structuredHistory = false,
    this.modelSelection = false,
    this.modeSelection = false,
    this.authentication = false,
  });

  factory AgentHerdrCapability.fromJson(Map<String, dynamic> json) =>
      AgentHerdrCapability(
        supported: json['supported'] as bool? ?? false,
        ready: json['ready'] as bool? ?? false,
        kind: json['kind'] as String?,
        integrationId: json['integrationId'] as String?,
        integrationInstalled: json['integrationInstalled'] as bool? ?? false,
        integrationState: json['integrationState'] as String? ?? 'unknown',
        executableSource: json['executableSource'] as String?,
        reason: json['reason'] as String?,
        structuredHistory: json['structuredHistory'] as bool? ?? false,
        modelSelection: json['modelSelection'] as bool? ?? false,
        modeSelection: json['modeSelection'] as bool? ?? false,
        authentication: json['authentication'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'supported': supported,
        'ready': ready,
        if (kind != null) 'kind': kind,
        if (integrationId != null) 'integrationId': integrationId,
        'integrationInstalled': integrationInstalled,
        'integrationState': integrationState,
        if (executableSource != null) 'executableSource': executableSource,
        if (reason != null) 'reason': reason,
        'structuredHistory': structuredHistory,
        'modelSelection': modelSelection,
        'modeSelection': modeSelection,
        'authentication': authentication,
      };
}

class AgentRuntimeCapability {
  final String id;
  final String name;
  final bool enabled;
  final AgentNativeCapability native;
  final AgentHerdrCapability herdr;

  const AgentRuntimeCapability({
    required this.id,
    required this.name,
    required this.enabled,
    required this.native,
    required this.herdr,
  });

  factory AgentRuntimeCapability.fromJson(Map<String, dynamic> json) =>
      AgentRuntimeCapability(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        enabled: json['enabled'] as bool? ?? true,
        native: AgentNativeCapability.fromJson(
            json['native'] as Map<String, dynamic>? ?? const {}),
        herdr: AgentHerdrCapability.fromJson(
            json['herdr'] as Map<String, dynamic>? ?? const {}),
      );
}

class HostCapabilities {
  final String platform; // 'linux' | 'darwin' | 'win32'
  final String arch;
  final GitCapability git;
  final HerdrCapability herdr;
  final List<AgentRuntimeCapability> agents;

  const HostCapabilities({
    required this.platform,
    required this.arch,
    required this.git,
    required this.herdr,
    required this.agents,
  });

  factory HostCapabilities.fromJson(Map<String, dynamic> json) =>
      HostCapabilities(
        platform: json['platform'] as String? ?? 'linux',
        arch: json['arch'] as String? ?? '',
        git: GitCapability.fromJson(
            json['git'] as Map<String, dynamic>? ?? const {}),
        herdr: HerdrCapability.fromJson(
            json['herdr'] as Map<String, dynamic>? ?? const {}),
        agents: (json['agents'] as List<dynamic>?)
                ?.map((a) =>
                    AgentRuntimeCapability.fromJson(a as Map<String, dynamic>))
                .toList() ??
            const [],
      );
}

class PendingPermission {
  final String requestId;
  final String toolCall;
  final String sessionId;
  final List<PermissionOption> options;

  PendingPermission({
    required this.requestId,
    required this.toolCall,
    this.sessionId = '',
    required this.options,
  });
}

class PendingToolCall {
  final String callId;
  final String name;
  final String status;
  final String title;
  final String kind;

  PendingToolCall({
    required this.callId,
    this.name = '',
    this.status = 'running',
    this.title = '',
    this.kind = '',
  });
}

class AvailableCommand {
  final String name;
  final String description;
  final String? inputHint;

  AvailableCommand({required this.name, required this.description, this.inputHint});

  String get command => name.startsWith('/') ? name : '/$name';

  factory AvailableCommand.fromJson(Map<String, dynamic> json) {
    final rawName = (json['name'] ?? json['command'] ?? '').toString();
    final cleanName = rawName.startsWith('/') ? rawName.substring(1) : rawName;
    final hint = (json['input'] is Map ? json['input']['hint'] : json['args'] ?? json['inputHint'])?.toString();
    return AvailableCommand(
      name: cleanName,
      description: (json['description'] ?? '').toString(),
      inputHint: hint,
    );
  }
}

class PlanEntry {
  final String text;
  final String status;

  PlanEntry({required this.text, required this.status});

  factory PlanEntry.fromJson(Map<String, dynamic> json) => PlanEntry(
        text: json['text'] as String? ?? '',
        status: json['status'] as String? ?? 'pending',
      );
}

class ServerInfoData {
  final String hostname;
  final List<String> ips;
  final String? hostId;

  ServerInfoData({required this.hostname, required this.ips, this.hostId});
}
