import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/theme.dart';
import '../providers/chat_provider.dart';
import '../models/ws_protocol.dart';
import '../services/device_agent_store.dart';
import '../utils/agent_utils.dart';
import '../widgets/agent_logo.dart';

class AgentManagePage extends StatefulWidget {
  const AgentManagePage({super.key});

  @override
  State<AgentManagePage> createState() => _AgentManagePageState();
}

class _AgentManagePageState extends State<AgentManagePage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _storeSearchController = TextEditingController();
  String _storeSearchQuery = '';

  // Custom agent form
  final TextEditingController _customNameController = TextEditingController();
  final TextEditingController _customCommandController = TextEditingController();
  final TextEditingController _customArgsController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final chatProvider = context.read<ChatProvider>();
      chatProvider.listRegistryAgents();
      chatProvider.requestAgents();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _storeSearchController.dispose();
    _customNameController.dispose();
    _customCommandController.dispose();
    _customArgsController.dispose();
    super.dispose();
  }

  void _confirmUninstall(String agentId) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppColors.surface1(context),
        title: Text(
          '确认卸载',
          style: TextStyle(
            color: AppColors.foregroundC(context),
            fontSize: AppFontSize.lg,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          '确定要卸载该 Agent 吗？',
          style: TextStyle(
            color: AppColors.foregroundM(context),
            fontSize: AppFontSize.base,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text(
              '取消',
              style: TextStyle(color: AppColors.foregroundM(context)),
            ),
          ),
          TextButton(
            onPressed: () {
              if (!mounted) return;
              context.read<ChatProvider>().uninstallAgent(agentId);
              if (dialogCtx.mounted) Navigator.pop(dialogCtx);
            },
            child: const Text(
              '卸载',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }

  void _installCustomAgent() {
    if (!mounted) return;
    final name = _customNameController.text.trim();
    final command = _customCommandController.text.trim();
    final argsText = _customArgsController.text.trim();

    if (command.isEmpty) return;

    final args = argsText.isNotEmpty ? argsText.split(' ') : <String>[];

    context.read<ChatProvider>().installCustomAgent(command, args, name);

    _customNameController.clear();
    _customCommandController.clear();
    _customArgsController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();

    final installedAgents = DeviceAgentStore()
        .getAgents(chatProvider.state.currentDeviceId);

    final registryAgents = chatProvider.state.registryAgents;

    // Filter registry agents by search
    var filteredRegistry = registryAgents;
    if (_storeSearchQuery.isNotEmpty) {
      filteredRegistry = registryAgents
          .where((a) =>
              a.name.toLowerCase().contains(_storeSearchQuery.toLowerCase()) ||
              a.description
                  .toLowerCase()
                  .contains(_storeSearchQuery.toLowerCase()))
          .toList();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Agent 商店 & 管理'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '商店'),
            Tab(text: '已安装'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildStoreTab(context, filteredRegistry, installedAgents),
          _buildInstalledTab(context, installedAgents),
        ],
      ),
    );
  }

  // ── Installed Tab ──

  Widget _buildInstalledTab(
    BuildContext context,
    List<AgentInfo> installedAgents,
  ) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        // Installed agents list
        if (installedAgents.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxxl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.extension_off,
                    size: 48,
                    color: AppColors.foregroundM(context).withAlpha(80),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    '暂无已安装的 Agent',
                    style: TextStyle(
                      color: AppColors.foregroundM(context),
                      fontSize: AppFontSize.md,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          ...installedAgents.map((agent) {
            return _buildInstalledAgentCard(context, agent);
          }),

        const SizedBox(height: AppSpacing.xl),

        // Custom agent install form
        _buildCustomInstallForm(context),
      ],
    );
  }

  Widget _buildInstalledAgentCard(BuildContext context, AgentInfo agent) {
    final displayName = AgentUtils.getDisplayName(agent.name);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Material(
        color: AppColors.surface1(context),
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              AgentLogo(
                agentName: agent.name,
                size: 22,
                color: AppColors.accent,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            displayName,
                            style: Theme.of(context).textTheme.titleMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          'v${agent.version}',
                          style: TextStyle(
                            fontSize: AppFontSize.xxs,
                            color: AppColors.foregroundM(context),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      '来源: ${agent.source}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(
                  Icons.delete_outline,
                  size: 20,
                  color: AppColors.error,
                ),
                onPressed: () => _confirmUninstall(agent.name),
                tooltip: '卸载',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCustomInstallForm(BuildContext context) {
    return Material(
      color: AppColors.surface1(context),
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '安装自定义 Agent',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _customNameController,
              decoration: const InputDecoration(
                hintText: 'Agent 名称',
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _customCommandController,
              decoration: const InputDecoration(
                hintText: '命令 (如 npx, npm, python)',
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _customArgsController,
              decoration: const InputDecoration(
                hintText: '参数 (空格分隔)',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _installCustomAgent,
                icon: const Icon(Icons.download, size: 18),
                label: const Text('安装'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Store Tab ──

  Widget _buildStoreTab(
    BuildContext context,
    List<RegistryAgentInfo> registryAgents,
    List<AgentInfo> installedAgents,
  ) {
    return Column(
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 0,
          ),
          child: TextField(
            controller: _storeSearchController,
            onChanged: (v) => setState(() => _storeSearchQuery = v),
            decoration: InputDecoration(
              hintText: '搜索 Agent...',
              prefixIcon: Icon(
                Icons.search,
                size: 18,
                color: AppColors.foregroundMutedCtx(context),
              ),
              suffixIcon: _storeSearchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 16),
                      onPressed: () {
                        _storeSearchController.clear();
                        setState(() => _storeSearchQuery = '');
                      },
                    )
                  : null,
            ),
          ),
        ),

        // Registry agents list
        Expanded(
          child: registryAgents.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.store_outlined,
                        size: 48,
                        color: AppColors.foregroundMutedCtx(context).withAlpha(80),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        _storeSearchQuery.isNotEmpty
                            ? '未找到匹配的 Agent'
                            : '商店暂无 Agent',
                        style: TextStyle(
                          color: AppColors.foregroundMutedCtx(context),
                          fontSize: AppFontSize.md,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  itemCount: registryAgents.length,
                  itemBuilder: (context, index) {
                    return _buildRegistryAgentCard(
                      context,
                      registryAgents[index],
                      installedAgents,
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildRegistryAgentCard(
    BuildContext context,
    RegistryAgentInfo agent,
    List<AgentInfo> installedAgents,
  ) {
    final isInstalled = installedAgents
        .any((a) => a.name == agent.id || a.name == agent.name);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Material(
        color: AppColors.surfaceCtx(context),
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            AgentLogo(
                              agentName: agent.id,
                              size: 16,
                              color: AppColors.accentCtx(context),
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Flexible(
                              child: Text(
                                AgentUtils.getDisplayName(agent.name),
                                style: TextStyle(
                                  fontSize: AppFontSize.md,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.foregroundCtx(context),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Text(
                              'v${agent.version}',
                              style: TextStyle(
                                fontSize: AppFontSize.xxs,
                                color: AppColors.foregroundMutedCtx(context),
                              ),
                            ),
                          ],
                        ),
                        if (agent.description.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            agent.description,
                            style: TextStyle(
                              fontSize: AppFontSize.sm,
                              color: AppColors.foregroundMutedCtx(context),
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  isInstalled
                      ? OutlinedButton(
                          onPressed: null,
                          style: OutlinedButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                            ),
                          ),
                          child: const Text('已安装', style: TextStyle(fontSize: AppFontSize.xs)),
                        )
                      : ElevatedButton(
                          onPressed: () {
                            context.read<ChatProvider>().installAgent(agent.id);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('正在安装 ${agent.name}...'),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.accent,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md,
                              vertical: AppSpacing.sm,
                            ),
                          ),
                          child: const Text(
                            '安装',
                            style: TextStyle(fontSize: AppFontSize.sm),
                          ),
                        ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
