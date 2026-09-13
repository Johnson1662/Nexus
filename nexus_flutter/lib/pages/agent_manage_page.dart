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

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final installedAgents = DeviceAgentStore()
        .getAgents(chatProvider.state.currentDeviceId);
    final installedNames = installedAgents.map((a) => a.name.toLowerCase()).toSet();
    for (final agent in chatProvider.state.installedAgents) {
      installedNames.add(agent.name.toLowerCase());
    }

    final agentList = chatProvider.state.registryAgents.map((r) {
      final caps = chatProvider.capabilityFor(r.id);
      final nativeReady = caps?.native.ready ?? false;
      final herdrReady = caps?.herdr.ready ?? false;
      final executable = caps?.native.executable ?? '';
      return {
        'id': r.id.toLowerCase(),
        'name': r.name.isNotEmpty ? r.name : AgentUtils.getDisplayName(r.id),
        'desc': r.description,
        'ready': (nativeReady || herdrReady) ? 'true' : 'false',
        'native': nativeReady ? 'Native ✓' : 'Native ✗',
        'herdr': herdrReady ? 'Herdr ✓' : 'Herdr ✗',
        'executable': executable,
        'reason': caps?.native.reason ?? caps?.herdr.reason ?? '',
      };
    }).toList();

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
                    onChanged: agent['ready'] == 'true'
                        ? (val) => chatProvider.installAgent(id)
                        : null,
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
              '仅可启用 PC 上已安装的 Agent。原生会话只显示支持 ACP 的 Agent；其他 Agent 通过 Herdr 运行。',
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
    required ValueChanged<bool>? onChanged,
  }) {
    final id = agent['id']!;
    final name = agent['name']!;
    final desc = agent['desc']!;
    final nativeLabel = agent['native']!;
    final herdrLabel = agent['herdr']!;
    final reason = agent['reason'] ?? '';
    final installable = agent['ready'] == 'true';
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
        installable
            ? '$desc · $nativeLabel · $herdrLabel'
            : '$desc · ${reason.isNotEmpty ? reason : 'PC 未找到命令'}',
        style: TextStyle(
          fontSize: AppFontSize.xs,
          color: muted,
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
