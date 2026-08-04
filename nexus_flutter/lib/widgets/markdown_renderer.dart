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
    final foreground = AppColors.foregroundCtx(context);
    final muted = AppColors.foregroundMutedCtx(context);
    final surface = AppColors.surfaceElevatedCtx(context);
    final border = AppColors.borderCtx(context);
    final accent = AppColors.accentCtx(context);

    return MarkdownBody(
      data: data,
      shrinkWrap: shrinkWrap,
      selectable: true,
      styleSheet: MarkdownStyleSheet(
        h1: Theme.of(context).textTheme.headlineLarge,
        h2: Theme.of(context).textTheme.headlineMedium,
        h3: Theme.of(context).textTheme.titleLarge,
        p: TextStyle(
          fontSize: AppFontSize.base,
          color: foreground,
          height: 1.5,
        ),
        code: TextStyle(
          fontSize: AppFontSize.sm,
          fontFamily: 'monospace',
          color: foreground,
          backgroundColor: surface,
        ),
        codeblockDecoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        codeblockPadding: const EdgeInsets.all(AppSpacing.md),
        blockquoteDecoration: BoxDecoration(
          border: Border(left: BorderSide(color: accent.withOpacity(0.3), width: 3)),
          color: surface,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        blockquotePadding: const EdgeInsets.all(AppSpacing.md),
        listBullet: TextStyle(
          fontSize: AppFontSize.base,
          color: muted,
        ),
        horizontalRuleDecoration: BoxDecoration(
          border: Border(top: BorderSide(color: border)),
        ),
        tableBorder: TableBorder.all(color: border),
        tableHead: TextStyle(
          fontWeight: FontWeight.bold,
          color: foreground,
        ),
        tableBody: TextStyle(color: foreground),
        del: TextStyle(
          decoration: TextDecoration.lineThrough,
          color: muted,
        ),
      ),
    );
  }
}
