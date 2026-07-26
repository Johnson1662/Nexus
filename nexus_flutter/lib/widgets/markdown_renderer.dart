import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../constants/theme.dart';

/// Renders markdown text with app-specific theming.
class AppMarkdownRenderer extends StatelessWidget {
  final String data;
  final bool shrinkWrap;

  const AppMarkdownRenderer({
    super.key,
    required this.data,
    this.shrinkWrap = true,
  });

  @override
  Widget build(BuildContext context) {
    return MarkdownBody(
      data: data,
      shrinkWrap: shrinkWrap,
      selectable: true,
      styleSheet: MarkdownStyleSheet(
        h1: Theme.of(context).textTheme.headlineLarge,
        h2: Theme.of(context).textTheme.headlineMedium,
        h3: Theme.of(context).textTheme.titleLarge,
        p: const TextStyle(
          fontSize: AppFontSize.base,
          color: AppColors.foreground,
          height: 1.5,
        ),
        code: const TextStyle(
          fontSize: AppFontSize.sm,
          fontFamily: 'monospace',
          color: AppColors.foreground,
          backgroundColor: AppColors.surfaceElevated,
        ),
        codeblockDecoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        codeblockPadding: const EdgeInsets.all(AppSpacing.md),
        blockquoteDecoration: BoxDecoration(
          border: Border(left: BorderSide(color: AppColors.accent.withOpacity(0.3), width: 3)),
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        blockquotePadding: const EdgeInsets.all(AppSpacing.md),
        listBullet: const TextStyle(
          fontSize: AppFontSize.base,
          color: AppColors.foregroundMuted,
        ),
        horizontalRuleDecoration: BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        tableBorder: TableBorder.all(color: AppColors.border),
        tableHead: const TextStyle(fontWeight: FontWeight.bold),
        tableBody: const TextStyle(color: AppColors.foreground),
        del: const TextStyle(
          decoration: TextDecoration.lineThrough,
          color: AppColors.foregroundMuted,
        ),
      ),
    );
  }
}
