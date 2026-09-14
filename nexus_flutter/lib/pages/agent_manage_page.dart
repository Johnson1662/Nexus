import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/theme.dart';
import '../models/ws_protocol.dart';
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

    // The registry is static metadata; the runtime list also contains custom
    // agents the user installed, which must remain manageable.
    final registryIds = chatProvider.state.registryAgents.map((r) => r.id).toSet();
    final capabilityOnlyAgents = (chatProvider.state.hostCapabilities?.agents ?? [])
        .where((a) => !registryIds.contains(a.id))
        .map((a) => RegistryAgentInfo(id: a.id, name: a.name, description: '', version: '', distribution: const {}));

    final useHerdr = chatProvider.preferredBackend == 'herdr';

    final agentList = [...chatProvider.state.registryAgents, ...capabilityOnlyAgents].map((r) {
      final caps = chatProvider.capabilityFor(r.id);
      final nativeReady = caps?.native.ready ?? false;
      final herdrReady = caps?.herdr.ready ?? false;
      final executable = caps?.native.executable ?? '';
      final nativeHookSupported = caps?.native.hookSupported ?? false;
      final nativeHookInstalled = caps?.native.hookInstalled ?? false;
      final nativeHookState = caps?.native.hookState ?? 'not_installed';
      final nativeHookDesc = caps?.native.hookDescription ?? '';
      final adapterRequired = caps?.native.adapterRequired ?? false;
      final adapterInstalled = caps?.native.adapterInstalled ?? true;
      final adapterSource = caps?.native.adapterSource ?? 'none';
      final adapterPackage = caps?.native.adapterPackage ?? '';
      final adapterBinary = caps?.native.adapterBinary ?? '';

      final integration = chatProvider.integrationFor(caps?.herdr.integrationId);
      final herdrIntegrationLabel = integration == null
          ? (caps?.herdr.supported == true ? 'Herdr 集成未检测' : '')
          : 'Herdr 集成: ${integration['state']}';

      return {
        'id': r.id.toLowerCase(),
        'name': r.name.isNotEmpty ? r.name : AgentUtils.getDisplayName(r.id),
        'desc': r.description,
        'ready': useHerdr
            ? (herdrReady ? 'true' : 'false')
            : (nativeReady ? 'true' : 'false'),
        'nativeReady': nativeReady ? 'true' : 'false',
        'herdrReady': herdrReady ? 'true' : 'false',
        'executable': executable,
        'nativeReason': caps?.native.reason ?? '',
        'herdrReason': caps?.herdr.reason ?? '',
        'herdrIntegration': herdrIntegrationLabel,
        'herdrIntegrationTarget': caps?.herdr.integrationId ?? '',
        'needsHerdrIntegration': (caps != null &&
                caps.herdr.supported &&
                (caps.herdr.integrationState == 'not installed' ||
                    caps.herdr.integrationState == 'missing' ||
                    caps.herdr.integrationState == 'outdated'))
            ? 'true'
            : 'false',
        'nativeHookSupported': nativeHookSupported ? 'true' : 'false',
        'nativeHookInstalled': nativeHookInstalled ? 'true' : 'false',
        'nativeHookState': nativeHookState,
        'nativeHookDesc': nativeHookDesc,
        'adapterRequired': adapterRequired ? 'true' : 'false',
        'adapterInstalled': adapterInstalled ? 'true' : 'false',
        'adapterSource': adapterSource,
        'adapterPackage': adapterPackage,
        'adapterBinary': adapterBinary,
        'nativeSupported': (caps?.native.supported ?? false) ? 'true' : 'false',
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
                      useHerdr: useHerdr,
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
                    useHerdr: useHerdr,
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
    required bool useHerdr,
    required ValueChanged<bool>? onChanged,
  }) {
    final id = agent['id']!;
    final name = agent['name']!;
    final desc = agent['desc']!;
    final herdrReady = agent['herdrReady'] == 'true';
    final executable = agent['executable'] ?? '';
    final nativeHookSupported = agent['nativeHookSupported'] == 'true';
    final nativeHookInstalled = agent['nativeHookInstalled'] == 'true';
    final nativeHookState = agent['nativeHookState'] ?? 'not_installed';
    final nativeHookDesc = agent['nativeHookDesc'] ?? '';
    final nativeSupported = agent['nativeSupported'] == 'true';
    final adapterRequired = agent['adapterRequired'] == 'true';
    final adapterInstalled = agent['adapterInstalled'] == 'true';
    final adapterSource = agent['adapterSource'] ?? 'none';
    final adapterPackage = agent['adapterPackage'] ?? '';

    final herdrIntegrationLabel = agent['herdrIntegration'] ?? '';
    final herdrIntegrationTarget = agent['herdrIntegrationTarget'] ?? '';
    final needsHerdrIntegration = agent['needsHerdrIntegration'] == 'true';
    final cliInstalled = executable.isNotEmpty;
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
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── CLI / Binary detection line ──
          if (useHerdr) ...[
          Text(
              herdrReady
                  ? '$desc · Herdr 就绪${executable.isNotEmpty ? ' ($executable)' : ''}'
                  : '$desc · ${agent['herdrReason']?.isNotEmpty == true ? agent['herdrReason']! : 'PC 未找到命令'}',
              style: TextStyle(fontSize: AppFontSize.xs, color: muted),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
      ),
            if (herdrIntegrationLabel.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  herdrIntegrationLabel,
                  style: TextStyle(fontSize: AppFontSize.xxs, color: muted),
        ),
      ),
            if (needsHerdrIntegration && herdrIntegrationTarget.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => context
                      .read<ChatProvider>()
                      .installHerdrIntegration(herdrIntegrationTarget),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 28),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('安装 Herdr 集成',
                      style: TextStyle(fontSize: AppFontSize.xs)),
                ),
              ),
          ] else ...[
            // ── Native Mode: Explicit Agent CLI status ──
          Text(
              cliInstalled
                  ? '$desc · 已检测到 CLI ($executable)'
                  : '$desc · PC 未安装 CLI (${agent['nativeReason']?.isNotEmpty == true ? agent['nativeReason']! : '未在 PATH 找到命令'})',
              style: TextStyle(fontSize: AppFontSize.xs, color: muted),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            // ── Native Mode: ACP Adapter status & action ──
            if (adapterRequired) ...[
            const SizedBox(height: 2),
              Row(
                children: [
                  Expanded(
                    child: Text(
                    adapterInstalled
                          ? (adapterSource == 'managed'
                              ? 'ACP 适配器: 已就绪 (Nexus 管理)'
                              : 'ACP 适配器: 已就绪 (系统全局)')
                        : 'ACP 适配器: 未安装${adapterPackage.isNotEmpty ? ' ($adapterPackage)' : ''}',
                    style: TextStyle(
                      fontSize: AppFontSize.xxs,
                      color: adapterInstalled
                          ? const Color(0xFF2DA44E)
                          : Colors.orangeAccent,
            ),
                      overflow: TextOverflow.ellipsis,
            ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  if (adapterInstalled && adapterSource == 'managed')
                    TextButton(
                      onPressed: () =>
                          context.read<ChatProvider>().uninstallAcpAdapter(id),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 24),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                      child: const Text('卸载适配器',
                          style: TextStyle(
                              fontSize: AppFontSize.xxs, color: Colors.redAccent)),
                    )
                  else if (!adapterInstalled)
                    TextButton(
                      onPressed: () =>
                          context.read<ChatProvider>().installAcpAdapter(id),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 24),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
                      child: const Text('安装 ACP 适配器',
                          style: TextStyle(
                              fontSize: AppFontSize.xxs, fontWeight: FontWeight.w600)),
            ),
                ],
            ),
            ],
            const SizedBox(height: 2),
            // ── Native Mode: Hook choice or protocol info ──
            if (nativeHookSupported) ...[
              Row(
        children: [
                  Expanded(
                    child: Text(
                    nativeHookInstalled
                          ? (nativeHookState == 'configured'
                              ? 'Hook: 已配置 (需在 Codex 信任后生效)'
                              : 'Hook: 已生效${nativeHookDesc.isNotEmpty ? ' ($nativeHookDesc)' : ''}')
                        : 'Hook: 未安装${nativeHookDesc.isNotEmpty ? ' ($nativeHookDesc)' : ''}',
        style: TextStyle(
                      fontSize: AppFontSize.xxs,
                      color: nativeHookInstalled
                            ? (nativeHookState == 'configured'
                                ? Colors.orangeAccent
                                : const Color(0xFF2DA44E))
                          : muted,
                    ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  if (nativeHookInstalled)
                    TextButton(
                      onPressed: () =>
                          context.read<ChatProvider>().uninstallNativeHook(id),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 24),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('卸载 Hook',
        style: TextStyle(
                              fontSize: AppFontSize.xxs, color: Colors.redAccent)),
                    )
                  else if (cliInstalled)
                    TextButton(
                      onPressed: () =>
                          context.read<ChatProvider>().installNativeHook(id),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 24),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('安装 Hook',
                          style: TextStyle(fontSize: AppFontSize.xxs)),
                    )
                  else
          Text(
                      '(需先在 PC 安装 CLI)',
                      style: TextStyle(fontSize: AppFontSize.xxs, color: muted),
                    ),
                ],
              ),
            ] else if (nativeSupported) ...[
          Text(
                '通信方式: 原生 ACP 协议 (无需 Hook)',
                style: TextStyle(fontSize: AppFontSize.xxs, color: muted),
              ),
            ] else ...[
          Text(
                '仅支持在 Herdr 模式下运行',
                style: TextStyle(fontSize: AppFontSize.xxs, color: muted),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
