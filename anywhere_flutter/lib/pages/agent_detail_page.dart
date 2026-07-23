import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../constants/theme.dart';
import '../models/ws_protocol.dart';
import '../models/device_entry.dart';
import '../providers/chat_provider.dart';
import '../services/host_store.dart';
import '../services/device_agent_store.dart';

class AgentDetailPage extends StatefulWidget {
  const AgentDetailPage({super.key});

  @override
  State<AgentDetailPage> createState() => _AgentDetailPageState();
}

class _AgentDetailPageState extends State<AgentDetailPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _deviceName = '';
  int _deviceIndex = -1;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map<String, dynamic>) {
      _deviceName = args['name'] as String? ?? '';
      _deviceIndex = args['index'] as int? ?? -1;
    } else if (args is String) {
      _deviceName = args;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _formatRelativeTime(int epoch) {
    if (epoch <= 0) return '';
    final now = DateTime.now();
    final date = DateTime.fromMillisecondsSinceEpoch(epoch);
    final diff = now.difference(date);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    if (diff.inHours < 24) return '${diff.inHours} 小时前';
    if (diff.inDays < 7) return '${diff.inDays} 天前';
    return DateFormat('M/d/yy').format(date);
  }

  DeviceEntry? _getDevice(HostStore hostStore) {
    // Try by index first
    if (_deviceIndex >= 0 && _deviceIndex < hostStore.devices.length) {
      return hostStore.devices[_deviceIndex];
    }
    // Try by name
    if (_deviceName.isNotEmpty) {
      final idx = hostStore.devices.indexWhere(
        (d) => d.hostId == _deviceName || d.name == _deviceName,
      );
      if (idx >= 0) return hostStore.devices[idx];
    }
    // Fallback: use active host
    if (hostStore.activeHostKey.isNotEmpty) {
      final idx = hostStore.devices.indexWhere(
        (d) => d.hostId == hostStore.activeHostKey,
      );
      if (idx >= 0) return hostStore.devices[idx];
    }
    return hostStore.devices.isNotEmpty ? hostStore.devices.first : null;
  }

  bool _isOnline(DeviceEntry device, HostStore hostStore) {
    return hostStore.isOnline(device.hostId) || hostStore.isOnline(device.name);
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final hostStore = context.watch<HostStore>();
    final device = _getDevice(hostStore);
    final online = device != null && _isOnline(device, hostStore);
    final displayName = device?.name.isNotEmpty == true
        ? device!.name
        : (_deviceName.isNotEmpty ? _deviceName : 'Agent');

    final agents = device != null
        ? DeviceAgentStore().getAgents(device.hostId)
        : <AgentInfo>[];

    final sessions = chatProvider.state.sessions;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                displayName,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: online ? AppColors.success : AppColors.foregroundMuted,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              online ? '在线' : '离线',
              style: TextStyle(
                fontSize: AppFontSize.xs,
                color: online ? AppColors.success : AppColors.foregroundM(context),
              ),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '概览'),
            Tab(text: '工具'),
            Tab(text: '会话'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildOverviewTab(context, device, agents),
          _buildToolsTab(context, agents),
          _buildSessionsTab(context, sessions, chatProvider),
        ],
      ),
    );
  }

  // ── Overview Tab ──

  Widget _buildOverviewTab(
    BuildContext context,
    DeviceEntry? device,
    List<AgentInfo> agents,
  ) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        // Host ID
        _buildSectionCard(
          context,
          title: '主机信息',
          children: [
            _buildInfoRow(context, 'Host ID', device?.hostId ?? '—'),
            const Divider(),
            _buildInfoRow(
              context,
              'Endpoint',
              device?.urls.isNotEmpty == true ? device!.urls.first : '—',
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),

        // Agent list
        _buildSectionCard(
          context,
          title: 'Agent 列表',
          children: agents.isEmpty
              ? [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.md,
                    ),
                    child: Text(
                      '暂无 Agent',
                      style: TextStyle(
                        color: AppColors.foregroundM(context),
                        fontSize: AppFontSize.sm,
                      ),
                    ),
                  ),
                ]
              : agents.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final agent = entry.value;
                  return Padding(
                    padding: EdgeInsets.only(
                      bottom: idx < agents.length - 1 ? AppSpacing.sm : 0,
                    ),
                    child: _buildAgentTile(context, agent),
                  );
                }).toList(),
        ),
      ],
    );
  }

  Widget _buildSectionCard(
    BuildContext context, {
    required String title,
    required List<Widget> children,
  }) {
    return Material(
      color: AppColors.surface1(context),
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.md),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 70,
            child: Text(
              label,
              style: TextStyle(
                fontSize: AppFontSize.sm,
                color: AppColors.foregroundM(context),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: AppFontSize.sm,
                color: AppColors.foregroundC(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAgentTile(BuildContext context, AgentInfo agent) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          Icon(
            Icons.smart_toy_outlined,
            size: 18,
            color: AppColors.accent,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      agent.name.isNotEmpty ? agent.name : '未命名',
                      style: Theme.of(context).textTheme.titleMedium,
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
        ],
      ),
    );
  }

  // ── Tools Tab ──

  Widget _buildToolsTab(
    BuildContext context,
    List<AgentInfo> agents,
  ) {
    // Build capability list from agent information
    final capabilities = <String>[];
    if (agents.isNotEmpty) {
      capabilities.add('filesystem');
      capabilities.add('shell');
      for (final agent in agents) {
        if (agent.installed) {
          capabilities.add('agent:${agent.name}');
        }
      }
    } else {
      capabilities.addAll(['filesystem', 'shell']);
    }

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        _buildSectionCard(
          context,
          title: '能力列表',
          children: capabilities.map((cap) {
            final icon = _capabilityIcon(cap);
            final label = _capabilityLabel(cap);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Row(
                children: [
                  Icon(icon, size: 18, color: AppColors.accent),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: AppFontSize.base,
                        color: AppColors.foregroundC(context),
                      ),
                    ),
                  ),
                  Icon(
                    Icons.check_circle,
                    size: 16,
                    color: AppColors.success,
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  IconData _capabilityIcon(String cap) {
    if (cap.startsWith('agent:')) return Icons.smart_toy_outlined;
    switch (cap) {
      case 'filesystem':
        return Icons.folder_outlined;
      case 'shell':
        return Icons.terminal_outlined;
      default:
        return Icons.extension_outlined;
    }
  }

  String _capabilityLabel(String cap) {
    if (cap.startsWith('agent:')) {
      return '已安装 Agent: ${cap.substring(6)}';
    }
    switch (cap) {
      case 'filesystem':
        return '文件系统';
      case 'shell':
        return '命令行';
      default:
        return cap;
    }
  }

  // ── Sessions Tab ──

  Widget _buildSessionsTab(
    BuildContext context,
    List<ServerSessionData> sessions,
    ChatProvider chatProvider,
  ) {
    if (sessions.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 48,
              color: AppColors.foregroundM(context).withAlpha(80),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              '暂无会话',
              style: TextStyle(
                color: AppColors.foregroundM(context),
                fontSize: AppFontSize.md,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.lg),
      itemCount: sessions.length,
      itemBuilder: (context, index) {
        final session = sessions[index];
        final title = session.title?.isNotEmpty == true ? session.title! : '无标题';
        final agent = session.agent ?? '';
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Material(
            color: AppColors.surface1(context),
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.md),
              onTap: () {
                chatProvider.loadSession(session.sessionId);
                Navigator.pushNamed(context, '/chat');
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.lg,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.accentLight,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        title.isNotEmpty ? title.characters.first : '?',
                        style: TextStyle(
                          color: AppColors.accent,
                          fontSize: AppFontSize.md,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: Theme.of(context).textTheme.titleMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (agent.isNotEmpty) ...[
                            const SizedBox(height: AppSpacing.xxs),
                            Text(
                              agent,
                              style: Theme.of(context).textTheme.bodySmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      _formatRelativeTime(session.createdAt),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
