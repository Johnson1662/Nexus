import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  /// Content to copy: toolContent if non-empty, else the diff (old→new) as text.
  String _copyableContent() {
    final msg = widget.message;
    if (msg.toolContent.isNotEmpty) return msg.toolContent;
    if (msg.toolOldText.isNotEmpty || msg.toolNewText.isNotEmpty) {
      final buf = StringBuffer();
      if (msg.toolOldText.isNotEmpty) {
        buf.writeln('--- old');
        buf.writeln(msg.toolOldText);
      }
      if (msg.toolNewText.isNotEmpty) {
        buf.writeln('+++ new');
        buf.writeln(msg.toolNewText);
      }
      return buf.toString().trim();
    }
    return msg.toolName;
  }

  /// Simple line-diff: walk matching prefix, then mark remainder old as `-` and new as `+`.
  List<_DiffLine> _computeDiff(String oldText, String newText) {
    final oldLines = oldText.split('\n');
    final newLines = newText.split('\n');
    final result = <_DiffLine>[];
    int i = 0, j = 0;
    while (i < oldLines.length && j < newLines.length) {
      if (oldLines[i] == newLines[j]) {
        result.add(_DiffLine(' ', newLines[j]));
        i++;
        j++;
      } else {
        break;
      }
    }
    // Remaining old lines are deletions
    while (i < oldLines.length) {
      result.add(_DiffLine('-', oldLines[i]));
      i++;
    }
    // Remaining new lines are insertions
    while (j < newLines.length) {
      result.add(_DiffLine('+', newLines[j]));
      j++;
    }
    return result;
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
        msg.toolTerminalId.isNotEmpty ||
        msg.toolTruncated;

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
                        _expanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
                        size: 16, color: AppColors.foregroundLightCtx(context),
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
    final msg = widget.message;
    final ct = msg.toolContentType;
    final hasDiff = msg.toolOldText.isNotEmpty || msg.toolNewText.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Header row: label + Copy button ──
          Row(
            children: [
              Text(
                ct == 'terminal' || ct == 'shell' ? '输出' :
                ct == 'diff' ? '变更' :
                hasDiff ? '变更' : '详情',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.foregroundM(context),
                ),
              ),
              const Spacer(),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: _copyableContent()));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已复制'), duration: Duration(seconds: 1)),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Icons.copy, size: 14, color: AppColors.foregroundM(context)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (msg.toolTruncated)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '输出已截断，仅显示前 256KB',
                style: TextStyle(fontSize: 11, color: AppColors.warning),
              ),
            ),

          // ── Old/New diff block ──
          if (hasDiff)
            _buildOldNewDiff(context, msg.toolOldText, msg.toolNewText),

          // ── Content block ──
          if (msg.toolContent.isNotEmpty)
            _buildContentBlock(context, msg.toolContent, ct),
        ],
      ),
    );
  }

  Widget _buildOldNewDiff(BuildContext context, String oldText, String newText) {
    if (oldText.isEmpty && newText.isEmpty) return const SizedBox.shrink();

    final diffLines = _computeDiff(oldText, newText);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.surface2Ctx(context),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: diffLines.map((dl) {
          Color? bg;
          Color fg;
          String prefix;
          if (dl.kind == '+') {
            bg = AppColors.diffAdd.withAlpha(25);
            fg = AppColors.diffAdd;
            prefix = '+ ';
          } else if (dl.kind == '-') {
            bg = AppColors.diffDel.withAlpha(25);
            fg = AppColors.diffDel;
            prefix = '- ';
          } else {
            bg = null;
            fg = AppColors.foregroundM(context);
            prefix = '  ';
          }
          final text = dl.line.isEmpty ? ' ' : '$prefix${dl.line}';
          return Container(
            width: double.infinity,
            color: bg,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            child: Text(
              text,
              style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: fg, height: 1.4),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildContentBlock(BuildContext context, String content, String contentType) {
    final isTerminal = contentType == 'terminal' || contentType == 'shell';
    final isDiff = contentType == 'diff';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isTerminal ? const Color(0xFF1E1E1E) : AppColors.surface2Ctx(context),
        borderRadius: BorderRadius.circular(6),
      ),
      child: isDiff
          ? _buildDiffLines(context, content)
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Text(
                content,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: isTerminal ? const Color(0xFFD4D4D4) : AppColors.foregroundM(context),
                  height: 1.4,
                ),
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

class _DiffLine {
  final String kind; // '+', '-', ' '
  final String line;
  const _DiffLine(this.kind, this.line);
}
