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

  // 17 supported agent integrations
  static const List<Map<String, String>> _defaultAgents = [
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

    // Merge server-reported registry agents
    final agentList = <Map<String, String>>[..._defaultAgents];
    final knownIds = _defaultAgents.map((a) => a['id']!).toSet();
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

    final srf = AppColors.surfaceCtx(context);
    final fg = AppColors.foregroundCtx(context);
    final muted = AppColors.foregroundMutedCtx(context);
    final border = AppColors.borderCtx(context);

    return Scaffold(
      backgroundColor: AppColors.backgroundCtx(context),
      appBar: AppBar(
        backgroundColor: AppColors.backgroundCtx(context),
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: fg),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Text(
          'Agent 集成',
          style: TextStyle(
            fontSize: AppFontSize.lg,
            fontWeight: FontWeight.w600,
            color: fg,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh_rounded, size: 20, color: muted),
            tooltip: '刷新列表',
            onPressed: () {
              chatProvider.listRegistryAgents();
              chatProvider.requestAgents();
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
        children: [
          // 1. Description banner
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: srf,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: border),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.accent.withAlpha(25),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: const Icon(
                    Icons.hub_outlined,
                    size: 20,
                    color: AppColors.accent,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '本地 Agent 状态上报',
                        style: TextStyle(
                          fontSize: AppFontSize.sm,
                          fontWeight: FontWeight.w600,
                          color: fg,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '直接与本地 AI 编程 Agent 通信并获取结构化执行状态。点击即可启用或停用对应集成。',
                        style: TextStyle(
                          fontSize: AppFontSize.xs,
                          color: muted,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // 2. Section Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.xs),
            child: Row(
              children: [
                Text(
                  '可用集成',
                  style: TextStyle(
                    fontSize: AppFontSize.xs,
                    fontWeight: FontWeight.w600,
                    color: muted,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                Text(
                  '${installedNames.length} 个已启用',
                  style: TextStyle(
                    fontSize: AppFontSize.xs,
                    color: AppColors.accent,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),

          // 3. Rounded Settings Group Container
          Container(
            decoration: BoxDecoration(
              color: srf,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: border),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: agentList.length,
                separatorBuilder: (context, index) => Divider(
                  height: 1,
                  indent: 56,
                  color: border.withAlpha(120),
                ),
                itemBuilder: (context, index) {
                  final agent = agentList[index];
                  final id = agent['id']!;
                  final name = agent['name']!;
                  final desc = agent['desc']!;
                  final isInstalled = installedNames.contains(id) ||
                      installedNames.contains(id.replaceAll('-', ''));

                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        if (isInstalled) {
                          chatProvider.uninstallAgent(id);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('已停用 $name 集成'),
                              duration: const Duration(seconds: 2),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        } else {
                          chatProvider.installAgent(id);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('已启用 $name 集成'),
                              duration: const Duration(seconds: 2),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.md,
                        ),
                        child: Row(
                          children: [
                            // Agent Logo Box
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: AppColors.surface2Ctx(context),
                                borderRadius: BorderRadius.circular(AppRadius.md),
                              ),
                              alignment: Alignment.center,
                              child: AgentLogo(
                                agentName: id,
                                size: 20,
                                color: isInstalled ? AppColors.accent : muted,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.md),

                            // Agent Name & Description
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          name,
                                          style: TextStyle(
                                            fontSize: AppFontSize.sm,
                                            fontWeight: FontWeight.w600,
                                            color: fg,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: AppColors.surface2Ctx(context),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          id,
                                          style: TextStyle(
                                            fontFamily: 'monospace',
                                            fontSize: 10,
                                            color: muted,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    desc,
                                    style: TextStyle(
                                      fontSize: AppFontSize.xs,
                                      color: muted,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),

                            // Status Pill Badge
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: isInstalled
                                    ? const Color(0x1830B959)
                                    : AppColors.surface2Ctx(context),
                                borderRadius: BorderRadius.circular(AppRadius.full),
                                border: Border.all(
                                  color: isInstalled
                                      ? const Color(0xFF30B959).withAlpha(80)
                                      : border,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    isInstalled ? Icons.check_circle_rounded : Icons.add_circle_outline_rounded,
                                    size: 13,
                                    color: isInstalled ? const Color(0xFF30B959) : muted,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    isInstalled ? '已启用' : '未启用',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: isInstalled ? FontWeight.w600 : FontWeight.normal,
                                      color: isInstalled ? const Color(0xFF30B959) : muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // 4. Footer explanation
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Text(
              '启用的 Agent 需在宿主 PC 上安装并配置至 PATH 环境变量中，Bridge 将自动通过 ACP 协议与其建立管道。',
              style: TextStyle(
                fontSize: AppFontSize.xxs,
                color: muted,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}
