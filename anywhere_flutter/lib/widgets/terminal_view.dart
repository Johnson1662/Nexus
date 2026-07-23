import 'package:flutter/material.dart';
import '../constants/theme.dart';

/// Terminal-style content display with dark background and monospace font
class TerminalView extends StatelessWidget {
  final String content;
  final int maxLines;

  const TerminalView({super.key, required this.content, this.maxLines = 200});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.terminalBg,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SelectableText(
          content.length > 8000 ? content.substring(0, 8000) + '\n... (truncated)' : content,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: AppFontSize.sm,
            color: AppColors.terminalFg,
            height: 1.5,
          ),
          maxLines: maxLines,
        ),
      ),
    );
  }
}
