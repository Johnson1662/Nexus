import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/theme.dart';
import '../providers/chat_provider.dart';
import '../services/device_agent_store.dart';

class AgentManagePage extends StatefulWidget {
  const AgentManagePage({super.key});

  @override
  State<AgentManagePage> createState() => _AgentManagePageState();
}

class _AgentManagePageState extends State<AgentManagePage> {
  String? _statusNotice;

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

  void _showNotice(String text) {
    setState(() => _statusNotice = text);
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _statusNotice == text) {
        setState(() => _statusNotice = null);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final installedAgents = DeviceAgentStore()
        .getAgents(chatProvider.state.currentDeviceId);
    final installedNames = installedAgents.map((a) => a.name.toLowerCase()).toSet();
    for (final name in chatProvider.state.agentNames) {
      installedNames.add(name.toLowerCase());
    }

    // Default list of agent integrations aligned with Herdr settings
    final defaultAgentIds = [
      'pi',
      'omp',
      'claude',
      'codex',
      'copilot',
      'devin',
      'droid',
      'kimi',
      'opencode',
      'kilo',
      'hermes',
      'qodercli',
      'qwen',
      'cursor',
      'mastracode',
      'antigravity-cli',
      'grok',
    ];

    final allAgentIds = <String>[...defaultAgentIds];
    for (final r in chatProvider.state.registryAgents) {
      final id = r.id.toLowerCase();
      if (!allAgentIds.contains(id)) {
        allAgentIds.add(id);
      }
    }

    const monoStyle = TextStyle(
      fontFamily: 'monospace',
      fontSize: 14,
      height: 1.5,
      letterSpacing: 0.2,
    );

    return Scaffold(
      backgroundColor: AppColors.backgroundCtx(context),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Settings top tabs navigation
              Text(
                'settings',
                style: monoStyle.copyWith(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.foregroundCtx(context),
                ),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _navItem(context, 'theme'),
                    _navItem(context, 'indicators'),
                    _navItem(context, 'sound'),
                    _navItem(context, 'toasts'),
                    _navItem(context, 'pane labels'),
                    _activeNavItem(context, 'integrations'),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // 2. Section title & subtitle
              Text(
                'agent integrations',
                style: monoStyle.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.foregroundCtx(context),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'let agents report state directly instead of relying only on process detection',
                style: monoStyle.copyWith(
                  fontSize: 12,
                  color: AppColors.foregroundMutedCtx(context),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),

              // 3. Monospace integrations list
              Expanded(
                child: ListView.builder(
                  itemCount: allAgentIds.length,
                  itemBuilder: (context, index) {
                    final agentId = allAgentIds[index];
                    final isInstalled = installedNames.contains(agentId) ||
                        installedNames.contains(agentId.replaceAll('-', ''));

                    return InkWell(
                      onTap: () {
                        if (isInstalled) {
                          chatProvider.uninstallAgent(agentId);
                          _showNotice('uninstalled $agentId');
                        } else {
                          chatProvider.installAgent(agentId);
                          _showNotice('installed $agentId');
                        }
                      },
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 20,
                              child: Text(
                                isInstalled ? '✓' : '-',
                                style: monoStyle.copyWith(
                                  color: isInstalled
                                      ? const Color(0xFF4CAF50)
                                      : AppColors.foregroundMutedCtx(context),
                                  fontWeight: isInstalled ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            SizedBox(
                              width: 140,
                              child: Text(
                                agentId,
                                style: monoStyle.copyWith(
                                  color: isInstalled
                                      ? AppColors.foregroundCtx(context)
                                      : AppColors.foregroundMutedCtx(context),
                                  fontWeight: isInstalled ? FontWeight.w600 : FontWeight.normal,
                                ),
                              ),
                            ),
                            Text(
                              isInstalled ? 'installed' : 'not found',
                              style: monoStyle.copyWith(
                                color: isInstalled
                                    ? const Color(0xFF4CAF50)
                                    : AppColors.foregroundMutedCtx(context),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

              // 4. Status notice
              if (_statusNotice != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    _statusNotice!,
                    style: monoStyle.copyWith(
                      color: AppColors.foregroundCtx(context),
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),

              // 5. Minimal footer with esc close button
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '↑↓ select  tab section',
                    style: monoStyle.copyWith(
                      fontSize: 11,
                      color: AppColors.foregroundMutedCtx(context),
                    ),
                  ),
                  InkWell(
                    onTap: () => Navigator.maybePop(context),
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.surface2Ctx(context),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: AppColors.borderCtx(context)),
                      ),
                      child: Text(
                        'esc close',
                        style: monoStyle.copyWith(
                          fontSize: 12,
                          color: AppColors.foregroundCtx(context),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
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

  Widget _navItem(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(right: 14),
      child: Text(
        title,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
          color: AppColors.foregroundMutedCtx(context),
        ),
      ),
    );
  }

  Widget _activeNavItem(BuildContext context, String title) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF2962FF),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(
        title,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    );
  }
}
