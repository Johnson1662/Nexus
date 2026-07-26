import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../constants/theme.dart';
import '../models/message_data.dart';
import '../models/ws_protocol.dart';
import '../providers/chat_provider.dart';

class SessionDetailPage extends StatefulWidget {
  final ServerSessionData session;

  const SessionDetailPage({super.key, required this.session});

  @override
  State<SessionDetailPage> createState() => _SessionDetailPageState();
}

class _SessionDetailPageState extends State<SessionDetailPage> {
  bool _detailsExpanded = false;

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

  Future<void> _showRenameDialog(
    BuildContext context,
    ChatProvider chatProvider,
  ) async {
    final session = widget.session;
    final controller = TextEditingController(text: session.title ?? '');
    final newTitle = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名会话'),
        content: TextField(
          controller: controller,
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
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    if (newTitle != null && newTitle.trim().isNotEmpty) {
      chatProvider.renameSession(session.sessionId, newTitle.trim());
    }
  }

  Future<void> _showDeleteConfirmDialog(
    BuildContext context,
    ChatProvider chatProvider,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除会话'),
        content: const Text('确认删除此会话？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      chatProvider.closeSession(widget.session.sessionId);
      if (context.mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final session = widget.session;
    final title = session.title?.isNotEmpty == true ? session.title! : '无标题';
    final agent = session.agent ?? '';
    final isRunning = chatProvider.state.sessionId == session.sessionId &&
        chatProvider.state.turnActive;

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          // ── Header section ──
          _buildHeader(context, title, agent),
          const SizedBox(height: AppSpacing.lg),

          // ── Running status section ──
          _buildRunningStatus(context, chatProvider, isRunning),
          const SizedBox(height: AppSpacing.lg),

          // ── Activity timeline ──
          _buildActivityTimeline(context, chatProvider),
          const SizedBox(height: AppSpacing.lg),

          // ── Collapsible details ──
          _buildCollapsibleDetails(context, chatProvider, session),
          const SizedBox(height: AppSpacing.lg),

          // ── File changes section ──
          _buildFileChanges(context, chatProvider),
          const SizedBox(height: AppSpacing.xl),

          // ── Session management actions ──
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _showRenameDialog(context, chatProvider),
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('重命名'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.foregroundC(context),
                    side: BorderSide(color: AppColors.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _showDeleteConfirmDialog(context, chatProvider),
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('删除会话'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          // ── Continue chat button ──
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: () {
                chatProvider.loadSession(session.sessionId, agent: session.agent);
                Navigator.pushNamed(context, '/chat');
              },
              icon: const Icon(Icons.chat_outlined, size: 18),
              label: const Text('继续对话'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Header ──

  Widget _buildHeader(BuildContext context, String title, String agent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.headlineMedium,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            if (agent.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xxs,
                ),
                decoration: BoxDecoration(
                  color: AppColors.accentLight,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
                child: Text(
                  agent,
                  style: TextStyle(
                    fontSize: AppFontSize.xs,
                    color: AppColors.accent,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
            ],
            Text(
              _formatRelativeTime(widget.session.createdAt),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ],
    );
  }

  // ── Running Status ──

  Widget _buildRunningStatus(
    BuildContext context,
    ChatProvider chatProvider,
    bool isRunning,
  ) {
    return Material(
      color: AppColors.surface1(context),
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '运行状态',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: isRunning ? AppColors.success : AppColors.foregroundMuted,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  isRunning ? '运行中' : '空闲',
                  style: TextStyle(
                    fontSize: AppFontSize.sm,
                    color: isRunning
                        ? AppColors.success
                        : AppColors.foregroundM(context),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),

            if (isRunning) ...[
              const SizedBox(height: AppSpacing.md),
              // Progress bar
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.full),
                child: LinearProgressIndicator(
                  minHeight: 4,
                  backgroundColor:
                      AppColors.border.withAlpha(100),
                  value: null, // indeterminate
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // Request content
              if (chatProvider.state.messages.isNotEmpty)
                _buildMessagePreview(
                  context,
                  chatProvider.state.messages.lastWhere(
                    (m) => m.role == 'user',
                    orElse: () => chatProvider.state.messages.last,
                  ),
                ),

              // Plan steps
              if (chatProvider.state.planEntries.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                _buildPlanSteps(context, chatProvider),
              ],

              // Token usage
              if (chatProvider.state.lastUsage != null) ...[
                const SizedBox(height: AppSpacing.md),
                _buildTokenUsage(context, chatProvider.state.lastUsage!),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMessagePreview(BuildContext context, MessageData message) {
    final text = message.content.isNotEmpty ? message.content : '请求内容';
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.backgroundCtx(context),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.person_outline,
            size: 16,
            color: AppColors.foregroundM(context),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text.length > 120 ? '${text.substring(0, 120)}…' : text,
              style: TextStyle(
                fontSize: AppFontSize.sm,
                color: AppColors.foregroundM(context),
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanSteps(BuildContext context, ChatProvider chatProvider) {
    final steps = chatProvider.state.planEntries;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '计划步骤',
          style: TextStyle(
            fontSize: AppFontSize.sm,
            fontWeight: FontWeight.w600,
            color: AppColors.foregroundC(context),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        ...steps.map((step) {
          final isCompleted = step.status == 'completed';
          final isInProgress = step.status == 'in_progress';
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Row(
              children: [
                Icon(
                  isCompleted
                      ? Icons.check_circle
                      : isInProgress
                          ? Icons.hourglass_top
                          : Icons.radio_button_unchecked,
                  size: 14,
                  color: isCompleted
                      ? AppColors.success
                      : isInProgress
                          ? AppColors.warning
                          : AppColors.foregroundM(context),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    step.text,
                    style: TextStyle(
                      fontSize: AppFontSize.sm,
                      color: isCompleted
                          ? AppColors.foregroundM(context)
                          : AppColors.foregroundC(context),
                      decoration:
                          isCompleted ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildTokenUsage(BuildContext context, UsageInfo usage) {
    return Row(
      children: [
        _buildTokenChip(context, 'Input', usage.inputTokens),
        const SizedBox(width: AppSpacing.sm),
        _buildTokenChip(context, 'Output', usage.outputTokens),
        const SizedBox(width: AppSpacing.sm),
        _buildTokenChip(context, 'Total', usage.totalTokens),
      ],
    );
  }

  Widget _buildTokenChip(BuildContext context, String label, int value) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: AppColors.backgroundCtx(context),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: AppFontSize.xxs,
              color: AppColors.foregroundM(context),
            ),
          ),
          Text(
            '$value',
            style: TextStyle(
              fontSize: AppFontSize.xxs,
              color: AppColors.foregroundC(context),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ── Activity Timeline ──

  Widget _buildActivityTimeline(BuildContext context, ChatProvider chatProvider) {
    final events = <_TimelineEvent>[];

    // Start event
    events.add(_TimelineEvent(
      icon: Icons.play_arrow,
      label: '会话开始',
      time: _formatRelativeTime(widget.session.createdAt),
      color: AppColors.success,
    ));

    // Tool call events from messages
    for (final msg in chatProvider.state.messages) {
      if (msg.type == 'tool_call') {
        final isRunning = msg.toolStatus == 'running';
        events.add(_TimelineEvent(
          icon: Icons.handyman_outlined,
          label: msg.toolName.isNotEmpty ? msg.toolName : '工具调用',
          time: _formatRelativeTime(msg.timestamp),
          color: isRunning ? AppColors.warning : AppColors.accent,
          status: msg.toolStatus,
        ));
      }
    }

    // Running / completed status
    if (chatProvider.state.turnActive) {
      events.add(_TimelineEvent(
        icon: Icons.hourglass_top,
        label: '运行中',
        time: '',
        color: AppColors.warning,
      ));
    } else if (events.isNotEmpty) {
      events.add(_TimelineEvent(
        icon: Icons.check_circle,
        label: '已完成',
        time: '',
        color: AppColors.success,
      ));
    }

    return Material(
      color: AppColors.surface1(context),
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '活动时间线',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.md),
            ...events.asMap().entries.map((entry) {
              final idx = entry.key;
              final event = entry.value;
              return _buildTimelineItem(context, event, isLast: idx == events.length - 1);
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildTimelineItem(
    BuildContext context,
    _TimelineEvent event, {
    bool isLast = false,
  }) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline line + dot
          SizedBox(
            width: 24,
            child: Column(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: event.color.withAlpha(30),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    event.icon,
                    size: 14,
                    color: event.color,
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 1.5,
                      color: AppColors.border,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          event.label,
                          style: TextStyle(
                            fontSize: AppFontSize.base,
                            color: AppColors.foregroundC(context),
                          ),
                        ),
                      ),
                      if (event.time.isNotEmpty)
                        Text(
                          event.time,
                          style: TextStyle(
                            fontSize: AppFontSize.xxs,
                            color: AppColors.foregroundM(context),
                          ),
                        ),
                    ],
                  ),
                  if (event.status.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      event.status,
                      style: TextStyle(
                        fontSize: AppFontSize.xxs,
                        color: event.color,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Collapsible Details ──

  Widget _buildCollapsibleDetails(
    BuildContext context,
    ChatProvider chatProvider,
    ServerSessionData session,
  ) {
    return Material(
      color: AppColors.surface1(context),
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: () => setState(() => _detailsExpanded = !_detailsExpanded),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '详情',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  Icon(
                    _detailsExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 20,
                    color: AppColors.foregroundM(context),
                  ),
                ],
              ),
              if (_detailsExpanded) ...[
                const SizedBox(height: AppSpacing.md),
                _buildDetailRow(
                  context,
                  'Session ID',
                  session.sessionId.length > 20
                      ? '${session.sessionId.substring(0, 20)}...'
                      : session.sessionId,
                ),
                _buildDetailRow(
                  context,
                  'Session ID',
                  chatProvider.state.sessionId.isNotEmpty
                      ? (chatProvider.state.sessionId.length > 20
                          ? '${chatProvider.state.sessionId.substring(0, 20)}...'
                          : chatProvider.state.sessionId)
                      : '—',
                ),
                _buildDetailRow(
                  context,
                  'Model',
                  chatProvider.lastModelId.isNotEmpty
                      ? chatProvider.lastModelId
                      : '—',
                ),
                _buildDetailRow(
                  context,
                  'Token',
                  chatProvider.state.lastUsage != null
                      ? '${chatProvider.state.lastUsage!.totalTokens}'
                      : '—',
                ),
                _buildDetailRow(
                  context,
                  'Workspace',
                  session.cwd?.isNotEmpty == true ? session.cwd! : '—',
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
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

  // ── File Changes ──

  Widget _buildFileChanges(BuildContext context, ChatProvider chatProvider) {
    // Collect file change info from tool call messages
    final fileChanges = <_FileChange>[];
    for (final msg in chatProvider.state.messages) {
      if (msg.type == 'tool_call' && msg.toolPath.isNotEmpty) {
        fileChanges.add(_FileChange(
          path: msg.toolPath,
          fileName: msg.toolPath.split(RegExp(r'[/\\]')).last,
          additions: msg.toolNewText.isNotEmpty ? msg.toolNewText.split('\n').length : 0,
          deletions: msg.toolOldText.isNotEmpty ? msg.toolOldText.split('\n').length : 0,
        ));
      }
    }

    if (fileChanges.isEmpty) {
      return const SizedBox.shrink();
    }

    return Material(
      color: AppColors.surface1(context),
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '文件变更',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.md),
            ...fileChanges.map((fc) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Row(
                    children: [
                      Icon(
                        Icons.insert_drive_file_outlined,
                        size: 16,
                        color: AppColors.foregroundM(context),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          fc.fileName,
                          style: TextStyle(
                            fontSize: AppFontSize.sm,
                            color: AppColors.foregroundC(context),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (fc.additions > 0)
                        Text(
                          '+${fc.additions}',
                          style: const TextStyle(
                            fontSize: AppFontSize.xxs,
                            color: AppColors.diffAdd,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      if (fc.additions > 0 && fc.deletions > 0)
                        const Text(
                          ' ',
                          style: TextStyle(fontSize: AppFontSize.xxs),
                        ),
                      if (fc.deletions > 0)
                        Text(
                          '-${fc.deletions}',
                          style: const TextStyle(
                            fontSize: AppFontSize.xxs,
                            color: AppColors.diffDel,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }
}

class _TimelineEvent {
  final IconData icon;
  final String label;
  final String time;
  final Color color;
  final String status;

  _TimelineEvent({
    required this.icon,
    required this.label,
    required this.time,
    required this.color,
    this.status = '',
  });
}

class _FileChange {
  final String path;
  final String fileName;
  final int additions;
  final int deletions;

  _FileChange({
    required this.path,
    required this.fileName,
    required this.additions,
    required this.deletions,
  });
}
