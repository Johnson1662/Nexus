import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/theme.dart';
import '../providers/chat_provider.dart';
import '../widgets/session_tile.dart';

class WorkspaceDetailPage extends StatefulWidget {
  const WorkspaceDetailPage({super.key});

  @override
  State<WorkspaceDetailPage> createState() => _WorkspaceDetailPageState();
}

class _WorkspaceDetailPageState extends State<WorkspaceDetailPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<ChatProvider>().requestSessionList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final args = ModalRoute.of(context)?.settings.arguments;
    final workspaceName = args is Map
        ? args['name']?.toString() ?? '工作区'
        : args is String
            ? args
            : '工作区';
    final workspacePath = args is Map ? args['path']?.toString() ?? '' : '';
    final workspaceId = args is Map ? args['workspaceId']?.toString() ?? '' : '';
    final isHerdrWorkspace = workspaceId.isNotEmpty && chatProvider.useHerdrBackend;

    // Filter sessions by workspace (cwd matches by path or dir name)
    final sessions = chatProvider.state.sessions.where((s) {
      if (s.cwd == null || s.cwd!.isEmpty) return false;
      final normCwd = s.cwd!.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '');
      if (workspacePath.isNotEmpty) {
        final normTarget = workspacePath.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '');
        if (normCwd == normTarget || normCwd.startsWith('$normTarget/')) {
          return true;
        }
        // Herdr workspaces carry the real PC cwd: never fall through to
        // loose dir-name matching which mixes unrelated same-named folders.
        if (isHerdrWorkspace) return false;
      }
      if (normCwd == workspaceName) return true;
      final cwdName = normCwd.split('/').lastOrNull ?? '';
      final targetName = (workspacePath.isNotEmpty ? workspacePath : workspaceName)
              .replaceAll('\\', '/')
              .replaceAll(RegExp(r'/+$'), '')
              .split('/')
              .lastOrNull ?? '';
      return cwdName.isNotEmpty && cwdName == targetName;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(workspaceName),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_comment_outlined, size: 22),
            onPressed: () {
              if (isHerdrWorkspace) {
                _showCreateHerdrAgentDialog(context, chatProvider, workspaceId, workspacePath);
                return;
              }
              final path = workspacePath.isNotEmpty
                  ? workspacePath
                  : _findWorkspacePath(context, workspaceName);
              if (path.isNotEmpty) {
                chatProvider.setCurrentWorkspace(path);
              }
              chatProvider.newChat();
              Navigator.pushNamed(context, '/chat');
            },
            tooltip: '新对话',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => chatProvider.requestSessionList(),
        child: sessions.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.6,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 48,
                            color: AppColors.foregroundMutedCtx(context).withAlpha(80),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            '暂无会话',
                            style: TextStyle(
                              color: AppColors.foregroundMutedCtx(context),
                              fontSize: AppFontSize.md,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              )
            : ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xl,
                vertical: AppSpacing.md,
              ),
              itemCount: sessions.length,
              itemBuilder: (context, index) {
                return SessionTile(
                  session: sessions[index],
                  onTap: () {
                    chatProvider.loadSession(
                      sessions[index].sessionId,
                      agent: sessions[index].agent,
                    );
                    Navigator.pushNamed(context, '/chat');
                  },
                );
              },
            ),
      ),
    );
  }

  void _showCreateHerdrAgentDialog(
    BuildContext context,
    ChatProvider chatProvider,
    String workspaceId,
    String workspacePath,
  ) {
    // ponytail: reuse the live agent list from list_agents instead of a hardcoded menu
    final availableKinds = chatProvider.state.agentNames.isNotEmpty
        ? chatProvider.state.agentNames
        : chatProvider.state.registryAgents.map((a) => a.id.isNotEmpty ? a.id : a.name).toList();
    String selectedKind = availableKinds.contains('omp')
        ? 'omp'
        : (availableKinds.isNotEmpty ? availableKinds.first : '');
    final mode = chatProvider.herdrAgentCreationMode;
    final modeLabel = mode == 'new_tab' ? '新建标签页 (tab.create)' : '分屏创建 (pane.split)';

    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '新建 Herdr Agent',
                  style: TextStyle(
                    color: AppColors.foregroundCtx(sheetContext),
                    fontSize: AppFontSize.base,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  '将使用「$modeLabel」模式在 PC 端启动，可在设置中调整',
                  style: TextStyle(
                    fontSize: AppFontSize.xs,
                    color: AppColors.foregroundMutedCtx(sheetContext),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                if (availableKinds.isEmpty)
                  Text(
                    'Agent 列表加载中，请稍后重试',
                    style: TextStyle(
                      fontSize: AppFontSize.xs,
                      color: AppColors.foregroundMutedCtx(sheetContext),
                    ),
                  )
                else
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: availableKinds.map((kind) {
                      final selected = selectedKind == kind;
                      return ChoiceChip(
                        label: Text(kind),
                        selected: selected,
                        onSelected: (_) => setSheetState(() => selectedKind = kind),
                      );
                    }).toList(),
                  ),
                const SizedBox(height: AppSpacing.lg),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: selectedKind.isEmpty
                        ? null
                        : () {
                            Navigator.pop(sheetContext);
                            chatProvider.createHerdrAgent(
                              workspaceId: workspaceId,
                              agentKind: selectedKind,
                              cwd: workspacePath.isNotEmpty ? workspacePath : null,
                            );
                            Navigator.pushNamed(context, '/chat');
                          },
                    child: const Text('在 PC 端启动'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _findWorkspacePath(BuildContext context, String name) {
    for (final workspace in context.read<WorkspaceProvider>().workspaces) {
      if (workspace['workspaceId'] == name && (workspace['path'] ?? '').isNotEmpty) {
        return workspace['path'] ?? '';
      }
    }
    final workspaces = context.read<WorkspaceProvider>().workspaces;
    for (final workspace in workspaces) {
      if (workspace['path'] == name) {
        return workspace['path'] ?? '';
      }
    }
    for (final workspace in workspaces) {
      if (workspace['name'] == name) {
        return workspace['path'] ?? '';
      }
    }
    return '';
  }
}
