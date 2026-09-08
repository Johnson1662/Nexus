import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/theme.dart';
import '../providers/chat_provider.dart';
import '../services/device_agent_store.dart';
import '../widgets/agent_logo.dart';
import '../utils/agent_utils.dart';

class AgentManagePage extends StatefulWidget {
  const AgentManagePage({super.key});

  @override
  State<AgentManagePage> createState() => _AgentManagePageState();
}

class _AgentManagePageState extends State<AgentManagePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final chatProvider = context.read<ChatProvider>();
      chatProvider.listRegistryAgents();
      chatProvider.requestAgents();
    });
  }

  static const List<Map<String, String>> _allSupportedAgents = [
    {'id': 'omp', 'name': 'Oh My Pi (OMP)', 'desc': '高性能 AI 编程 Agent 核心'},
    {'id': 'codex', 'name': 'Codex CLI', 'desc': 'OpenAI 终端编程 Agent'},
    {'id': 'claude', 'name': 'Claude Code', 'desc': 'Anthropic 交互式编码助手'},
    {'id': 'opencode', 'name': 'OpenCode', 'desc': '开源多模型终端编程 Agent'},
    {'id': 'pi', 'name': 'Pi CLI', 'desc': '极简原生终端 Agent'},
    {'id': 'kimi', 'name': 'Kimi CLI', 'desc': 'Moonshot 长上下文编程 Agent'},
    {'id': 'qwen', 'name': 'Qwen Code', 'desc': '通义千问代码大模型 Agent'},
    {'id': 'cursor', 'name': 'Cursor Agent', 'desc': 'Cursor 协议兼容 Agent'},
    {'id': 'copilot', 'name': 'GitHub Copilot', 'desc': 'GitHub Copilot CLI'},
    {'id': 'devin', 'name': 'Devin CLI', 'desc': 'Cognition 自动化软件工程师'},
    {'id': 'droid', 'name': 'Droid', 'desc': '自动化脚本与开发执行器'},
    {'id': 'kilo', 'name': 'Kilo Code', 'desc': '轻量级端侧推理 Agent'},
    {'id': 'hermes', 'name': 'Hermes Agent', 'desc': '自主循环决策 Agent'},
    {'id': 'qodercli', 'name': 'Qoder CLI', 'desc': '企业级代码重构工具'},
    {'id': 'mastracode', 'name': 'Mastra Code', 'desc': '工作流自动化 Agent'},
    {'id': 'antigravity-cli', 'name': 'Antigravity CLI', 'desc': 'Google Antigravity Agent'},
    {'id': 'grok', 'name': 'Grok Code', 'desc': 'xAI 代码推理 Agent'},
  ];

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final installedAgents = DeviceAgentStore()
        .getAgents(chatProvider.state.currentDeviceId);
    final installedNames = installedAgents.map((a) => a.name.toLowerCase()).toSet();
    for (final name in chatProvider.state.agentNames) {
      installedNames.add(name.toLowerCase());
    }

    final agentList = <Map<String, String>>[..._allSupportedAgents];
    final knownIds = _allSupportedAgents.map((a) => a['id']!).toSet();
    for (final r in chatProvider.state.registryAgents) {
      final id = r.id.toLowerCase();
      if (!knownIds.contains(id)) {
        knownIds.add(id);
        agentList.add({
          'id': id,
          'name': r.name.isNotEmpty ? r.name : AgentUtils.getDisplayName(id),
          'desc': r.description.isNotEmpty ? r.description : 'ACP 编程助手',
        });
      }
    }

    final enabledAgents = agentList.where((a) {
      final id = a['id']!;
      return installedNames.contains(id) || installedNames.contains(id.replaceAll('-', ''));
    }).toList();

    final availableAgents = agentList.where((a) {
      final id = a['id']!;
      return !installedNames.contains(id) && !installedNames.contains(id.replaceAll('-', ''));
    }).toList();

    final dark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: AppColors.backgroundCtx(context),
      appBar: AppBar(
        title: const Text('Agent 集成'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 20),
            tooltip: '刷新列表',
            onPressed: () {
              chatProvider.listRegistryAgents();
              chatProvider.requestAgents();
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          // Section 1: Enabled Integrations
          if (enabledAgents.isNotEmpty) ...[
            _sectionHeader(context, '已启用集成 (${enabledAgents.length})'),
            _buildGroupContainer(
              context,
              dark,
              enabledAgents.asMap().entries.map((entry) {
                final index = entry.key;
                final agent = entry.value;
                final id = agent['id']!;
                return Column(
                  children: [
                    _buildAgentTile(
                      context,
                      agent: agent,
                      isInstalled: true,
                      onChanged: (val) => chatProvider.uninstallAgent(id),
                    ),
                    if (index < enabledAgents.length - 1) const Divider(height: 1),
                  ],
                );
              }).toList(),
            ),
            const SizedBox(height: AppSpacing.xxl),
          ],

          // Section 2: Available Integrations
          _sectionHeader(context, '可选集成 (${availableAgents.length})'),
          _buildGroupContainer(
            context,
            dark,
            availableAgents.asMap().entries.map((entry) {
              final index = entry.key;
              final agent = entry.value;
              final id = agent['id']!;
              return Column(
                children: [
                  _buildAgentTile(
                    context,
                    agent: agent,
                    isInstalled: false,
                    onChanged: (val) => chatProvider.installAgent(id),
                  ),
                  if (index < availableAgents.length - 1) const Divider(height: 1),
                ],
              );
            }).toList(),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Section 3: Footer Note
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Text(
              '已启用的 Agent 将在会话创建与选择器中可用。请确保目标 Agent 已在 PC 上安装并在 PATH 环境变量中。',
              style: TextStyle(
                fontSize: AppFontSize.xxs,
                color: AppColors.foregroundMutedCtx(context),
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.sm, bottom: AppSpacing.sm),
      child: Text(
        title,
        style: TextStyle(
          color: AppColors.foregroundMutedCtx(context),
          fontSize: AppFontSize.xs,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildGroupContainer(BuildContext context, bool dark, List<Widget> children) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surfaceCtx(context),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: dark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.black.withValues(alpha: 0.05),
          width: 0.8,
        ),
      ),
      child: Column(
        children: children,
      ),
    );
  }

  Widget _buildAgentTile(
    BuildContext context, {
    required Map<String, String> agent,
    required bool isInstalled,
    required ValueChanged<bool> onChanged,
  }) {
    final id = agent['id']!;
    final name = agent['name']!;
    final desc = agent['desc']!;
    final fg = AppColors.foregroundCtx(context);
    final muted = AppColors.foregroundMutedCtx(context);

    return SwitchListTile.adaptive(
      value: isInstalled,
      onChanged: onChanged,
      activeTrackColor: fg,
      secondary: AgentLogo(
        agentName: id,
        size: 22,
        color: isInstalled ? fg : muted,
      ),
      title: Text(
        name,
        style: TextStyle(
          color: fg,
          fontSize: AppFontSize.base,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        desc,
        style: TextStyle(
          fontSize: AppFontSize.xs,
          color: muted,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
