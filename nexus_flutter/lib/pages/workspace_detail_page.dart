import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/theme.dart';
import '../providers/chat_provider.dart';
import '../widgets/session_tile.dart';

class WorkspaceDetailPage extends StatelessWidget {
  const WorkspaceDetailPage({super.key});

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

    // Filter sessions by workspace (cwd matches by path or dir name)
    final sessions = chatProvider.state.sessions.where((s) {
      if (s.cwd == null || s.cwd!.isEmpty) return false;
      if (s.cwd == workspaceName) return true;
      final cwdName = s.cwd!.split(RegExp(r'[/\\]')).lastOrNull ?? '';
      final targetName = workspaceName.split(RegExp(r'[/\\]')).lastOrNull ?? '';
      return cwdName == targetName;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(workspaceName),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_comment_outlined, size: 22),
            onPressed: () {
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
      body: sessions.isEmpty
          ? Center(
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
            )
          : ListView.builder(
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
    );
  }

  String _findWorkspacePath(BuildContext context, String name) {
    final workspaces = context.read<WorkspaceProvider>().workspaces;
    for (final workspace in workspaces) {
      final path = workspace['path'] ?? '';
      if (workspace['name'] == name ||
          path.split(RegExp(r'[/\\]')).lastOrNull == name) {
        return path;
      }
    }
    return '';
  }
}
