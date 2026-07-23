import 'package:flutter/material.dart';
import '../constants/theme.dart';
import '../models/message_data.dart';

class ToolCallCard extends StatefulWidget {
  final MessageData message;

  const ToolCallCard({super.key, required this.message});

  @override
  State<ToolCallCard> createState() => _ToolCallCardState();
}

class _ToolCallCardState extends State<ToolCallCard> {
  bool _expanded = false;

  IconData _toolIcon(String toolName) {
    final name = toolName.toLowerCase();
    if (name.contains('bash') || name.contains('shell') || name.contains('terminal')) return Icons.terminal;
    if (name.contains('edit') || name.contains('write')) return Icons.edit_note;
    if (name.contains('read') || name.contains('open')) return Icons.description_outlined;
    if (name.contains('search') || name.contains('grep') || name.contains('find') || name.contains('web')) return Icons.search;
    if (name.contains('create') || name.contains('new')) return Icons.create_new_folder_outlined;
    if (name.contains('delete') || name.contains('remove')) return Icons.delete_outline;
    return Icons.build_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final msg = widget.message;
    // Server uses 'in_progress' (not 'running') for streaming tools.
    final isRunning = msg.toolStatus == 'running' || msg.toolStatus == 'in_progress';
    final isCompleted = msg.toolStatus == 'completed';
    final isError = msg.toolStatus == 'error';
    // Expandable if there is anything worth showing: text output, a diff, or a terminal session.
    final hasContent = msg.toolContent.isNotEmpty ||
        msg.toolOldText.isNotEmpty ||
        msg.toolNewText.isNotEmpty ||
        msg.toolTerminalId.isNotEmpty;

    // Auto-expand while running / streaming
    if (isRunning && !_expanded) _expanded = true;

    final icon = _toolIcon(msg.toolName);
    Color iconColor;
    if (isRunning) iconColor = AppColors.accent;
    else if (isCompleted) iconColor = AppColors.success;
    else if (isError) iconColor = AppColors.error;
    else iconColor = AppColors.foregroundM(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.surfaceElevatedCtx(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.borderCtx(context).withAlpha(80)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              borderRadius: BorderRadius.vertical(
                top: const Radius.circular(10),
                bottom: (_expanded || !hasContent) ? const Radius.circular(10) : Radius.zero,
              ),
              onTap: hasContent ? () => setState(() => _expanded = !_expanded) : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    isRunning
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        : Icon(icon, size: 16, color: iconColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        msg.toolName.isNotEmpty ? msg.toolName : 'tool',
                        style: TextStyle(fontSize: 13, color: AppColors.foregroundC(context), fontWeight: FontWeight.w500),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isCompleted) Icon(Icons.check, size: 14, color: AppColors.success),
                    if (isError) Icon(Icons.close, size: 14, color: AppColors.error),
                    if (hasContent) ...[
                      const SizedBox(width: 4),
                      Icon(
                        _expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                        size: 18, color: AppColors.foregroundLightCtx(context),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (_expanded && hasContent)
              _buildContent(context),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final ct = widget.message.toolContentType;
    final content = widget.message.toolContent;

    if (ct == 'terminal' || ct == 'shell') {
      return _buildScrollableContent(
        context,
        content,
        bg: const Color(0xFF1E1E1E),
        textColor: const Color(0xFFD4D4D4),
      );
    }
    if (ct == 'diff') {
      return _buildScrollableContent(
        context,
        content,
        bg: AppColors.surface2Ctx(context),
        isDiff: true,
      );
    }
    return _buildScrollableContent(
      context,
      content,
      bg: AppColors.surface2Ctx(context),
    );
  }

  Widget _buildScrollableContent(BuildContext context, String content, {Color? bg, Color? textColor, bool isDiff = false}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: isDiff
          ? _buildDiffLines(context, content)
          : Text(
              content,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: textColor ?? AppColors.foregroundM(context),
                height: 1.4,
              ),
            ),
    );
  }

  Widget _buildDiffLines(BuildContext context, String content) {
    final lines = content.split('\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: lines.map((line) {
        Color? bg;
        Color fg;
        if (line.startsWith('+')) { bg = AppColors.diffAdd.withAlpha(25); fg = AppColors.diffAdd; }
        else if (line.startsWith('-')) { bg = AppColors.diffDel.withAlpha(25); fg = AppColors.diffDel; }
        else if (line.startsWith('@@')) { bg = null; fg = Colors.grey; }
        else { bg = null; fg = AppColors.foregroundM(context); }
        return Container(
          width: double.infinity,
          color: bg,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          child: Text(line.isEmpty ? ' ' : line, style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: fg, height: 1.4)),
        );
      }).toList(),
    );
  }
}
