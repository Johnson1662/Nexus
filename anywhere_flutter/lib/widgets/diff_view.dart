import 'package:flutter/material.dart';
import '../constants/theme.dart';

/// Diff rendering widget — shows file path + colored line changes
class DiffView extends StatelessWidget {
  final String path;
  final String oldText;
  final String newText;
  final int maxLines;

  const DiffView({
    super.key,
    required this.path,
    this.oldText = '',
    this.newText = '',
    this.maxLines = 200,
  });

  @override
  Widget build(BuildContext context) {
    final lines = _computeDiff();
    if (lines.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surface1(context),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Path header
          if (path.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.xs),
              child: Text(
                path,
                style: TextStyle(
                  fontSize: AppFontSize.xxs,
                  color: AppColors.foregroundM(context),
                  fontFamily: 'monospace',
                ),
              ),
            ),
          // Diff lines
          ...lines.take(maxLines).map((line) {
            Color? bg;
            Color fg;
            if (line.startsWith('+')) {
              bg = AppColors.diffAdd.withOpacity(0.15);
              fg = AppColors.diffAdd;
            } else if (line.startsWith('-')) {
              bg = AppColors.diffDel.withOpacity(0.15);
              fg = AppColors.diffDel;
            } else if (line.startsWith('@@')) {
              fg = Colors.grey;
            } else {
              fg = AppColors.foregroundC(context);
            }
            return Container(
              width: double.infinity,
              color: bg,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 1),
              child: Text(
                line.isEmpty ? ' ' : line,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: AppFontSize.xxs,
                  color: fg,
                  height: 1.5,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            );
          }),
        ],
      ),
    );
  }

  List<String> _computeDiff() {
    if (oldText.isEmpty && newText.isEmpty) return [];
    if (oldText.isEmpty) return newText.split('\n').map((l) => '+$l').toList();
    if (newText.isEmpty) return oldText.split('\n').map((l) => '-$l').toList();

    // Simple line-by-line diff
    final oldLines = oldText.split('\n');
    final newLines = newText.split('\n');
    final result = <String>[];
    result.add('@@ -1,${oldLines.length} +1,${newLines.length} @@');

    final maxLen = oldLines.length > newLines.length ? oldLines.length : newLines.length;
    for (int i = 0; i < maxLen; i++) {
      if (i < oldLines.length && i < newLines.length && oldLines[i] != newLines[i]) {
        result.add('-${oldLines[i]}');
        result.add('+${newLines[i]}');
      } else if (i < oldLines.length && i >= newLines.length) {
        result.add('-${oldLines[i]}');
      } else if (i >= oldLines.length && i < newLines.length) {
        result.add('+${newLines[i]}');
      } else {
        result.add(' ${oldLines[i]}');
      }
    }
    return result;
  }
}
