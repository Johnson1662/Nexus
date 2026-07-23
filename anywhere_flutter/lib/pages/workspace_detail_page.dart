import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../constants/theme.dart';
import '../models/ws_protocol.dart';
import '../providers/chat_provider.dart';

class WorkspaceDetailPage extends StatelessWidget {
  const WorkspaceDetailPage({super.key});

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

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final workspaceName =
        ModalRoute.of(context)?.settings.arguments as String? ?? '工作区';

    // Filter sessions by workspace (cwd matches)
    final sessions = chatProvider.state.sessions
        .where((s) {
          // Match sessions where cwd ends with workspace name
          // or cwd is set and matches the current workspace
          if (s.cwd == null || s.cwd!.isEmpty) return false;
          final cwdName = s.cwd!.split(RegExp(r'[/\\]')).lastOrNull ?? '';
          return cwdName == workspaceName || s.cwd == workspaceName;
        })
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(workspaceName),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_comment_outlined, size: 22),
            onPressed: () {
              // Set workspace cwd before starting new session
              final wp = context.read<WorkspaceProvider>();
              for (final w in wp.workspaces) {
                final name = w['name'] ?? '';
                final path = w['path'] ?? '';
                if (name == workspaceName || path.split(RegExp(r'[/\\]')).last == workspaceName) {
                  chatProvider.setCurrentWorkspace(path);
                  break;
                }
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
            )
          : ListView.builder(
              padding: const EdgeInsets.all(AppSpacing.lg),
              itemCount: sessions.length,
              itemBuilder: (context, index) {
                return _buildSessionCard(context, sessions[index], chatProvider);
              },
            ),
    );
  }

  Widget _buildSessionCard(
    BuildContext context,
    ServerSessionData session,
    ChatProvider chatProvider,
  ) {
    final title = session.title?.isNotEmpty == true ? session.title! : '无标题';
    final agent = session.agent ?? '';
    final model = chatProvider.state.sessionCurrentModelId.isNotEmpty
        ? chatProvider.state.sessionCurrentModelId
        : chatProvider.lastModelId;

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
                  width: 40,
                  height: 40,
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
                      const SizedBox(height: AppSpacing.xxs),
                      Row(
                        children: [
                          if (agent.isNotEmpty) ...[
                            Icon(
                              Icons.smart_toy_outlined,
                              size: 13,
                              color: AppColors.foregroundM(context),
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Flexible(
                              child: Text(
                                agent,
                                style: Theme.of(context).textTheme.bodySmall,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.md),
                          ],
                          if (model.isNotEmpty) ...[
                            Icon(
                              Icons.memory,
                              size: 13,
                              color: AppColors.foregroundM(context),
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Flexible(
                              child: Text(
                                model,
                                style: Theme.of(context).textTheme.bodySmall,
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
  }
}
