import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../constants/theme.dart';
import '../providers/chat_provider.dart';
import '../services/host_store.dart';

class WorkspaceListPage extends StatefulWidget {
  const WorkspaceListPage({super.key});

  @override
  State<WorkspaceListPage> createState() => _WorkspaceListPageState();
}

class _WorkspaceListPageState extends State<WorkspaceListPage> {
  final TextEditingController _searchController = TextEditingController();
  String _filter = 'all'; // 'all' | 'active' | 'idle'
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
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

  void _showNewWorkspaceDialog() {
    if (!mounted) return;
    final pathController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppColors.surface1(context),
        titlePadding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.xl,
          AppSpacing.xl,
          0,
        ),
        title: Text(
          '新建工作区',
          style: TextStyle(
            color: AppColors.foregroundC(context),
            fontSize: AppFontSize.lg,
            fontWeight: FontWeight.w600,
          ),
        ),
        contentPadding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.md,
          AppSpacing.xl,
          0,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: pathController,
              autofocus: true,
              decoration: const InputDecoration(hintText: '工作区路径'),
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
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
              final path = pathController.text.trim();
              if (path.isNotEmpty) {
                final name = path.split(RegExp(r'[/\\]')).last;
                context.read<WorkspaceProvider>().addWorkspace(name, path);
                Navigator.pop(dialogCtx);
              }
            },
            child: const Text('创建'),
          ),
        ],
      ),
    ).whenComplete(pathController.dispose);
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final workspaceProvider = context.watch<WorkspaceProvider>();
    final hostStore = context.watch<HostStore>();

    final workspaces = workspaceProvider.workspaces;
    final connected = chatProvider.state.connected;

    // Derive workspace card data
    final workspaceCards = workspaces.map((w) {
      final path = w['path'] ?? '';
      final name =
          w['name'] ?? (path.split(RegExp(r'[/\\]')).lastOrNull ?? '未命名');
      final isActive = path == chatProvider.state.currentWorkspace;
      final sessionsForWs =
          chatProvider.state.sessions.where((s) => s.cwd == path).toList();
      final sessionCount = sessionsForWs.length;
      final lastTime = sessionsForWs.isNotEmpty
          ? sessionsForWs
              .map((s) => s.createdAt)
              .reduce((a, b) => a > b ? a : b)
          : 0;

      final matchedDevice = hostStore.devices
          .where((d) =>
              d.hostId == chatProvider.state.currentDeviceId ||
              d.name == chatProvider.state.currentDeviceId)
          .firstOrNull;
      var deviceName = (matchedDevice != null && matchedDevice.name.isNotEmpty)
          ? matchedDevice.name
          : (chatProvider.state.currentDeviceId.isNotEmpty
              ? chatProvider.state.currentDeviceId
              : '—');
      if (deviceName.startsWith('host_')) {
        if (matchedDevice?.urls.isNotEmpty == true) {
          deviceName = matchedDevice!.urls.first
              .replaceFirst('ws://', '')
              .replaceFirst('wss://', '');
        } else {
          deviceName = '远程主机';
        }
      }

      return _WorkspaceCardData(
        name: name,
        path: path,
        deviceName: deviceName,
        lastSessionTime: lastTime,
        sessionCount: sessionCount,
        isActive: isActive,
      );
    }).toList();

    // Filter by search
    var filtered = workspaceCards;
    if (_searchQuery.isNotEmpty) {
      filtered = filtered
          .where(
              (w) => w.name.toLowerCase().contains(_searchQuery.toLowerCase()))
          .toList();
    }

    // Filter by status
    if (_filter == 'active') {
      filtered = filtered.where((w) => w.isActive).toList();
    } else if (_filter == 'idle') {
      filtered = filtered.where((w) => !w.isActive).toList();
    }

    final dark = Theme.of(context).brightness == Brightness.dark;
    final fg = AppColors.foregroundCtx(context);
    final muted = AppColors.foregroundMutedCtx(context);

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text(
          '工作区',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: AppFontSize.xl,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded, size: 22),
            onPressed: _showNewWorkspaceDialog,
            tooltip: '新建工作区',
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              0,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: dark ? const Color(0x15FFFFFF) : const Color(0x0A000000),
                borderRadius: BorderRadius.circular(AppRadius.full),
                border: Border.all(
                  color: dark
                      ? Colors.white.withOpacity(0.06)
                      : Colors.black.withOpacity(0.05),
                  width: 0.8,
                ),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: (v) => setState(() => _searchQuery = v),
                style: TextStyle(fontSize: AppFontSize.sm, color: fg),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: '搜索工作区...',
                  hintStyle: TextStyle(fontSize: AppFontSize.sm, color: muted),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                      vertical: 10, horizontal: AppSpacing.md),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    size: 18,
                    color: muted,
                  ),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 16),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),

          // Filter tabs
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Row(
              children: [
                _buildFilterChip('全部', 'all'),
                const SizedBox(width: AppSpacing.xs),
                _buildFilterChip('活跃', 'active'),
                const SizedBox(width: AppSpacing.xs),
                _buildFilterChip('空闲', 'idle'),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),

          // Workspace list
          Expanded(
            child: filtered.isEmpty
                ? _buildEmptyState('暂无工作区')
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      0,
                      AppSpacing.lg,
                      80,
                    ),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      return _buildWorkspaceCard(context, filtered[index]);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final selected = _filter == value;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fg = AppColors.foregroundCtx(context);
    final muted = AppColors.foregroundMutedCtx(context);

    return FilterChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      onSelected: (v) {
        if (v) setState(() => _filter = value);
      },
      selectedColor: dark ? Colors.white : Colors.black,
      backgroundColor: dark ? const Color(0x15FFFFFF) : const Color(0x0A000000),
      labelStyle: TextStyle(
        fontSize: AppFontSize.xs,
        color: selected ? (dark ? Colors.black : Colors.white) : muted,
        fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
      ),
      side: BorderSide.none,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
    );
  }

  Widget _buildWorkspaceCard(BuildContext context, _WorkspaceCardData card) {
    final fg = AppColors.foregroundCtx(context);
    final muted = AppColors.foregroundMutedCtx(context);
    final dark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: () {
        Navigator.pushNamed(
          context,
          '/workspace-detail',
          arguments: {'name': card.name, 'path': card.path},
        );
      },
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Icon(
              Icons.folder_outlined,
              size: 20,
              color: fg,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          card.name.isNotEmpty ? card.name : '未命名',
                          style: TextStyle(
                            fontSize: AppFontSize.md,
                            fontWeight: FontWeight.w600,
                            color: fg,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (card.sessionCount > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: dark
                                ? const Color(0x20FFFFFF)
                                : const Color(0x0F000000),
                            borderRadius: BorderRadius.circular(AppRadius.full),
                          ),
                          child: Text(
                            '${card.sessionCount}',
                            style: TextStyle(
                              fontSize: AppFontSize.xxs,
                              color: muted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(
                        Icons.laptop_outlined,
                        size: 12,
                        color: muted,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Flexible(
                        child: Text(
                          card.deviceName.isNotEmpty ? card.deviceName : '—',
                          style: TextStyle(
                            fontSize: AppFontSize.xxs,
                            color: muted,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (card.lastSessionTime > 0) ...[
                        const SizedBox(width: AppSpacing.sm),
                        Icon(
                          Icons.access_time_rounded,
                          size: 12,
                          color: muted,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Flexible(
                          child: Text(
                            _formatRelativeTime(card.lastSessionTime),
                            style: TextStyle(
                              fontSize: AppFontSize.xxs,
                              color: muted,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            _buildStatusChip(card.isActive),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(bool isActive) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: isActive
            ? AppColors.success.withAlpha(30)
            : AppColors.foregroundMuted.withAlpha(30),
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: isActive ? AppColors.success : AppColors.foregroundMuted,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            isActive ? '活跃' : '空闲',
            style: TextStyle(
              fontSize: AppFontSize.xxs,
              fontWeight: FontWeight.w500,
              color:
                  isActive ? AppColors.success : AppColors.foregroundM(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.folder_open,
            size: 48,
            color: AppColors.foregroundM(context).withAlpha(80),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            message,
            style: TextStyle(
              color: AppColors.foregroundM(context),
              fontSize: AppFontSize.md,
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkspaceCardData {
  final String name;
  final String path;
  final String deviceName;
  final int lastSessionTime;
  final int sessionCount;
  final bool isActive;

  _WorkspaceCardData({
    required this.name,
    required this.path,
    required this.deviceName,
    required this.lastSessionTime,
    required this.sessionCount,
    required this.isActive,
  });
}
