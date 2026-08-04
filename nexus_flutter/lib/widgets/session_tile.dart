import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../constants/theme.dart';
import '../models/ws_protocol.dart';
import '../providers/chat_provider.dart';
import '../utils/agent_utils.dart';
import 'agent_logo.dart';

/// Formats an epoch timestamp (ms) into a human-readable relative string.
String formatRelativeTime(int epoch) {
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

/// Unified minimalist session list item widget.
/// Follows ChatGPT/Linear greyscale aesthetic — borderless, clean typography,
/// soft pressed feedback.
class SessionTile extends StatelessWidget {
  final ServerSessionData session;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const SessionTile({
    super.key,
    required this.session,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final fg = AppColors.foregroundCtx(context);
    final muted = AppColors.foregroundMutedCtx(context);

    final title = session.title?.isNotEmpty == true ? session.title! : '无标题';
    final agent = session.agent ?? '';
    final agentDisplayName = AgentUtils.getDisplayName(agent);
    final relativeTime =
        formatRelativeTime(session.lastActivity ?? session.createdAt);

    final isRunning = session.status == 'running';
    final isWaiting = session.status == 'waiting_input';
    final statusText = isRunning
        ? '进行中'
        : isWaiting
            ? '等待输入'
            : '';

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            // Keep the session title primary; agent context stays secondary.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: AppFontSize.md,
                      fontWeight: FontWeight.w500,
                      color: fg,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AgentLogo(
                        agentName: agent,
                        size: 13,
                        color: muted,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        agentDisplayName,
                        style: TextStyle(
                          fontSize: AppFontSize.xs,
                          fontWeight: FontWeight.w500,
                          color: muted,
                        ),
                      ),
                      if (statusText.isNotEmpty) ...[
                        Text(
                          ' · ',
                          style:
                              TextStyle(fontSize: AppFontSize.xs, color: muted),
                        ),
                        Text(
                          statusText,
                          style: TextStyle(
                            fontSize: AppFontSize.xs,
                            color: isRunning
                                ? AppColors.success
                                : AppColors.warning,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (relativeTime.isNotEmpty) ...[
              const SizedBox(width: AppSpacing.sm),
              Text(
                relativeTime,
                style: TextStyle(
                  fontSize: AppFontSize.xs,
                  color: muted,
                ),
              ),
            ],
            const SizedBox(width: AppSpacing.xs),

            // Trailing popup menu
            PopupMenuButton<String>(
              icon: Icon(Icons.more_horiz_rounded, size: 18, color: muted),
              padding: EdgeInsets.zero,
              onSelected: (value) async {
                if (!context.mounted) return;
                final cp = context.read<ChatProvider>();
                switch (value) {
                  case 'rename':
                    final ctrl =
                        TextEditingController(text: session.title ?? '');
                    try {
                      final newTitle = await showDialog<String>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('重命名会话'),
                          content: TextField(
                            controller: ctrl,
                            autofocus: true,
                            decoration: const InputDecoration(
                              hintText: '输入新名称',
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('取消'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, ctrl.text),
                              child: const Text('确认'),
                            ),
                          ],
                        ),
                      );
                      if (!context.mounted) return;
                      if (newTitle != null && newTitle.trim().isNotEmpty) {
                        cp.renameSession(session.sessionId, newTitle.trim());
                      }
                    } finally {
                      ctrl.dispose();
                    }
                    break;
                  case 'pin':
                    cp.togglePinSession(session.sessionId);
                    break;
                  case 'close':
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('关闭会话'),
                        content: const Text('确认关闭此会话？'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('取消'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.red,
                            ),
                            child: const Text('关闭'),
                          ),
                        ],
                      ),
                    );
                    if (!context.mounted) return;
                    if (confirmed == true) {
                      cp.closeSession(session.sessionId);
                    }
                    break;
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'rename',
                  child: Text('重命名'),
                ),
                const PopupMenuItem(
                  value: 'pin',
                  child: Text('置顶'),
                ),
                const PopupMenuItem(
                  value: 'close',
                  child: Text('关闭会话'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
