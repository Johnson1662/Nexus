import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../constants/theme.dart';
import '../providers/chat_provider.dart';
import '../services/host_store.dart';
import '../services/ws_client.dart';
import '../models/host_runtime_state.dart';
import '../models/ws_protocol.dart';
import '../models/device_entry.dart';
import '../widgets/host_filter_bar.dart';
import '../widgets/session_tile.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _entered = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _entered = true);
    });
  }

  // ── Helpers ──

  List<String> _getConnectCandidates(DeviceEntry device) {
    final candidates = <String>[...device.urls];
    if (device.relayUrl != null &&
        device.relayUrl!.isNotEmpty &&
        device.hostId.isNotEmpty) {
      final sep = device.relayUrl!.contains('?') ? '&' : '?';
      candidates.add('${device.relayUrl}$sep${device.hostId}');
    }
    if (device.name.isNotEmpty) {
      candidates.add('ws://${device.name}:12138');
    }
    return candidates;
  }

  Future<void> _onRefresh() async {
    if (!mounted) return;
    context.read<ChatProvider>().requestSessionList();
  }

  void _showManualConnectDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppColors.surfaceCtx(context),
        titlePadding: const EdgeInsets.fromLTRB(
          AppSpacing.xl, AppSpacing.xl, AppSpacing.xl, 0,
        ),
        title: Text(
          '手动连接',
          style: TextStyle(
            color: AppColors.foregroundCtx(context),
            fontSize: AppFontSize.lg,
            fontWeight: FontWeight.w600,
          ),
        ),
        contentPadding: const EdgeInsets.fromLTRB(
          AppSpacing.xl, AppSpacing.md, AppSpacing.xl, 0,
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.go,
          decoration: const InputDecoration(
            hintText: 'ws://192.168.1.2:12138',
          ),
          onSubmitted: (url) {
            final trimmed = url.trim();
            if (trimmed.isNotEmpty) {
              context.read<ChatProvider>().connectToUrl(trimmed);
              Navigator.pop(dialogCtx);
            }
          },
        ),
        actionsPadding:
            const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text(
              '取消',
              style: TextStyle(color: AppColors.foregroundMutedCtx(context)),
            ),
          ),
          TextButton(
            onPressed: () {
              final url = controller.text.trim();
              if (url.isNotEmpty) {
                context.read<ChatProvider>().connectToUrl(url);
                // Persist host and automatically merge url if belonging to an existing device
                final uri = Uri.tryParse(url);
                final hostKey = uri?.host ?? url;
                final hostStore = context.read<HostStore>();
                hostStore.addOrUpdateDevice(DeviceEntry(
                  hostId: hostKey,
                  name: hostKey,
                  urls: [url],
                ));
                hostStore.saveToDisk();
              }
              Navigator.pop(dialogCtx);
            },
            child: const Text('连接'),
          ),
        ],
      ),
    );
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

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final hostStore = context.watch<HostStore>();
    final workspaceProvider = context.watch<WorkspaceProvider>();

    final matchedDevice = hostStore.devices
        .where((d) => d.hostId == chatProvider.state.currentDeviceId || d.name == chatProvider.state.currentDeviceId)
        .firstOrNull;
    var activeHostName = (matchedDevice != null && matchedDevice.name.isNotEmpty)
        ? matchedDevice.name
        : (chatProvider.state.currentDeviceId.isNotEmpty
            ? chatProvider.state.currentDeviceId
            : (hostStore.devices.isNotEmpty ? hostStore.devices.first.name : ''));
    if (activeHostName.startsWith('host_')) {
      if (matchedDevice?.urls.isNotEmpty == true) {
        activeHostName = matchedDevice!.urls.first.replaceFirst('ws://', '').replaceFirst('wss://', '');
      } else {
        activeHostName = '远程主机';
      }
    }

    final phase = hostStore.getPhase(matchedDevice?.hostId ?? chatProvider.state.currentDeviceId);
    final isConnected = chatProvider.state.connected;

    final Color statusDotColor;
    if (isConnected || phase == 'online' || phase == 'syncing') {
      statusDotColor = AppColors.success;
    } else if (phase == 'connecting' || phase == 'reconnecting' || phase == 'waiting_host') {
      statusDotColor = AppColors.warning;
    } else {
      statusDotColor = AppColors.foregroundMutedCtx(context).withAlpha(120);
    }

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        automaticallyImplyLeading: false,
        title: const Text(
          'Remote',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: AppFontSize.xl,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_horiz, size: 22),
            onPressed: () => Navigator.pushNamed(context, '/settings'),
            tooltip: '设置',
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Host status row (matching home1.jpg) ──
          if (activeHostName.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xl,
                vertical: AppSpacing.xs,
              ),
              child: Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: statusDotColor,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Icon(
                    Icons.laptop_outlined,
                    size: 14,
                    color: AppColors.foregroundCtx(context),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    activeHostName,
                    style: TextStyle(
                      fontSize: AppFontSize.sm,
                      fontWeight: FontWeight.w600,
                      color: AppColors.foregroundCtx(context),
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: AppSpacing.md),

          // ── Main scrollable content ──
          Expanded(
            child: RefreshIndicator(
              onRefresh: _onRefresh,
              child: AnimatedOpacity(
                opacity: _entered ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: ListView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xl,
                  ),
                  children: [
                    _buildProjectSection(
                      context,
                      chatProvider,
                      hostStore,
                      workspaceProvider,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _buildRecentSessionsSection(context, chatProvider, workspaceProvider),
                    const SizedBox(height: 100),
                  ],
                ),
              ),
            ),
          ),

          // ── Bottom action bar ──
          _buildBottomActionBar(context),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }

  // ── Project / workspace section (matching home1.jpg) ──

  Widget _buildProjectSection(
    BuildContext context,
    ChatProvider chatProvider,
    HostStore hostStore,
    WorkspaceProvider workspaceProvider,
  ) {
    final fg = AppColors.foregroundCtx(context);
    final muted = AppColors.foregroundMutedCtx(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: Row(
            children: [
              Text(
                '项目',
                style: TextStyle(
                  fontSize: AppFontSize.lg,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
              const Spacer(),
              InkWell(
                onTap: () => Navigator.pushNamed(context, '/workspace-list'),
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                    vertical: AppSpacing.xxs,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '查看全部',
                        style: TextStyle(
                          fontSize: AppFontSize.xs,
                          color: muted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 16,
                        color: muted,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        // Item 1: Quick Chat entry (matches home1.jpg)
        _buildProjectRow(
          context,
          icon: Icons.chat_bubble_outline_rounded,
          title: '聊天',
          onTap: () => Navigator.pushNamed(context, '/chat'),
        ),

        // Workspace folders list
        _buildWorkspaceCards(
          context,
          chatProvider,
          hostStore,
          workspaceProvider,
        ),
      ],
    );
  }

  Widget _buildProjectRow(
    BuildContext context, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    final fg = AppColors.foregroundCtx(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.md,
          horizontal: AppSpacing.xs,
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: fg),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: AppFontSize.md,
                  fontWeight: FontWeight.w500,
                  color: fg,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkspaceCards(
    BuildContext context,
    ChatProvider chatProvider,
    HostStore hostStore,
    WorkspaceProvider workspaceProvider,
  ) {
    // No devices configured
    if (hostStore.devices.isEmpty) {
      return _buildEmptyDeviceState(context);
    }

    // Not connected yet — show hint
    if (!chatProvider.state.connected) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Text(
          '未连接主机',
          style: TextStyle(
            color: AppColors.foregroundMutedCtx(context),
            fontSize: AppFontSize.sm,
          ),
        ),
      );
    }

    // Show workspace cards from provider
    if (workspaceProvider.workspaces.isNotEmpty) {
      return Column(
        children: workspaceProvider.workspaces.map((w) {
          final name = w['name'] ??
              (w['path']?.split('/').lastOrNull ?? '');
          return _buildWorkspaceCard(context, name, chatProvider);
        }).toList(),
      );
    }

    // Fallback: show current workspace if set
    if (chatProvider.state.currentWorkspace.isNotEmpty) {
      final name = chatProvider.state.currentWorkspace
          .split(RegExp(r'[/\\]'))
          .last;
      return _buildWorkspaceCard(context, name, chatProvider);
    }

    // Connected but no workspace data
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Text(
        '暂无项目',
        style: TextStyle(
          color: AppColors.foregroundMutedCtx(context),
          fontSize: AppFontSize.sm,
        ),
      ),
    );
  }

  Widget _buildWorkspaceCard(
    BuildContext context,
    String name,
    ChatProvider chatProvider,
  ) {
    return _buildProjectRow(
      context,
      icon: Icons.folder_outlined,
      title: name.isNotEmpty ? name : '未命名',
      onTap: () => Navigator.pushNamed(context, '/workspace-detail', arguments: name),
    );
  }

  Widget _buildEmptyDeviceState(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxxl),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.devices_other,
              size: 40,
              color: AppColors.foregroundMutedCtx(context).withAlpha(100),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'No hosts configured. Tap + to add one.',
              style: TextStyle(
                color: AppColors.foregroundMutedCtx(context),
                fontSize: AppFontSize.md,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ── Helpers ──

  List<ServerSessionData> _getSortedRecentSessions(
    List<ServerSessionData> sessions,
    List<Map<String, String>> addedWorkspaces,
  ) {
    final validPaths = addedWorkspaces
        .map((w) => (w['path'] ?? '').replaceAll('\\', '/').toLowerCase().replaceAll(RegExp(r'/$'), ''))
        .where((p) => p.isNotEmpty)
        .toSet();

    final filtered = sessions.where((s) {
      if (s.cwd == null || s.cwd!.isEmpty) return false;
      final normalizedCwd = s.cwd!.replaceAll('\\', '/').toLowerCase().replaceAll(RegExp(r'/$'), '');
      return validPaths.contains(normalizedCwd);
    }).toList();

    filtered.sort((a, b) {
      final aActive = a.status == 'running' || a.status == 'waiting_input';
      final bActive = b.status == 'running' || b.status == 'waiting_input';
      if (aActive != bActive) return aActive ? -1 : 1;
      return b.createdAt.compareTo(a.createdAt);
    });
    return filtered.take(5).toList();
  }

  // ── Recent sessions section ──

  Widget _buildRecentSessionsSection(
    BuildContext context,
    ChatProvider chatProvider,
    WorkspaceProvider workspaceProvider,
  ) {
    final fg = AppColors.foregroundCtx(context);
    final muted = AppColors.foregroundMutedCtx(context);
    final sessions = _getSortedRecentSessions(
      chatProvider.state.sessions,
      workspaceProvider.workspaces,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: Text(
            '最近会话',
            style: TextStyle(
              fontSize: AppFontSize.lg,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ),
        if (sessions.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Text(
              '暂无最近会话',
              style: TextStyle(
                color: muted,
                fontSize: AppFontSize.sm,
              ),
            ),
          )
        else
          ...sessions.map((s) => SessionTile(
            session: s,
            onTap: () {
              chatProvider.loadSession(s.sessionId, agent: s.agent, cwd: s.cwd);
              Navigator.pushNamed(context, '/chat');
            },
          )),
      ],
    );
  }

  // ── Bottom action bar ──

  Widget _buildBottomActionBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: Row(
        children: [
          // Search button
          Expanded(
            child: Material(
              color: AppColors.surfaceCtx(context),
              borderRadius: BorderRadius.circular(AppRadius.full),
              elevation: 1,
              shadowColor: const Color(0x141A1A2E),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.full),
                onTap: () {
                  // Placeholder — no-op for now
                },
                child: Container(
                  height: 50,
                  padding: const EdgeInsets.only(left: AppSpacing.lg),
                  alignment: Alignment.centerLeft,
                  child: Row(
                    children: [
                      Icon(
                        Icons.search,
                        size: 18,
                        color: AppColors.foregroundMutedCtx(context),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        '搜索聊天',
                        style: TextStyle(
                          color: AppColors.foregroundMutedCtx(context),
                          fontSize: AppFontSize.base,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          // New chat button
          Material(
            color: AppColors.foregroundCtx(context),
            borderRadius: BorderRadius.circular(AppRadius.full),
            elevation: 1,
            shadowColor: const Color(0x1A000000),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.full),
              onTap: () {
                context.read<ChatProvider>().newChat();
                Navigator.pushNamed(context, '/chat');
              },
              child: Container(
                height: 50,
                padding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                alignment: Alignment.center,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.edit_note_rounded,
                      size: 20,
                      color: AppColors.backgroundCtx(context),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      '聊天',
                      style: TextStyle(
                        color: AppColors.backgroundCtx(context),
                        fontWeight: FontWeight.w600,
                        fontSize: AppFontSize.base,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
