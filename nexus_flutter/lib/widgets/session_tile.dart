import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../constants/theme.dart';
import '../models/ws_protocol.dart';
import '../providers/chat_provider.dart';

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
    final dark = Theme.of(context).brightness == Brightness.dark;

    final title = session.title?.isNotEmpty == true ? session.title! : '无标题';
    final agent = session.agent ?? '';
    final relativeTime = formatRelativeTime(session.createdAt);

    // Build subtitle string: "opencode · 进行中 · 5 分钟前"
    final subtitleParts = <String>[];
    if (agent.isNotEmpty) subtitleParts.add(agent);
    if (session.status == 'running') {
      subtitleParts.add('进行中');
    } else if (session.status == 'waiting_input') {
      subtitleParts.add('等待输入');
    }
    if (relativeTime.isNotEmpty) subtitleParts.add(relativeTime);
    final subtitle = subtitleParts.join(' · ');

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            // Left icon container with optional green status dot badge
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: dark ? const Color(0x15FFFFFF) : const Color(0x0A000000),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.chat_bubble_outline_rounded,
                    size: 18,
                    color: fg,
                  ),
                ),
                if (session.status == 'running' || session.status == 'waiting_input')
                  Positioned(
                    right: -1,
                    top: -1,
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: session.status == 'waiting_input' ? AppColors.warning : AppColors.success,
                        border: Border.all(
                          color: AppColors.surfaceCtx(context),
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: AppSpacing.md),

            // Middle title & info
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
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: AppFontSize.xs,
                        color: muted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.xs),

            // Trailing popup menu
            PopupMenuButton<String>(
              icon: Icon(Icons.more_horiz_rounded, size: 18, color: muted),
              padding: EdgeInsets.zero,
              onSelected: (value) async {
                final cp = context.read<ChatProvider>();
                switch (value) {
                  case 'rename':
                    final ctrl = TextEditingController(text: session.title ?? '');
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
                    if (newTitle != null && newTitle.trim().isNotEmpty) {
                      cp.renameSession(session.sessionId, newTitle.trim());
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
                            child: const Text('关闭'),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.red,
                            ),
                          ),
                        ],
                      ),
                    );
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
