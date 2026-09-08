import 'package:flutter/material.dart';
import '../constants/theme.dart';

class ThinkingSection extends StatefulWidget {
  final String content;
  final bool isStreaming;

  const ThinkingSection({super.key, required this.content, this.isStreaming = false});

  @override
  State<ThinkingSection> createState() => _ThinkingSectionState();
}

class _ThinkingSectionState extends State<ThinkingSection> {
  bool _expanded = true;
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  String get _preview {
    final trimmedContent = widget.content.trim();
    if (trimmedContent.isEmpty) return '';
    // Show first meaningful line as preview
    final lines = trimmedContent.split('\n');
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) {
        if (trimmed.length > 40) return '${trimmed.substring(0, 40)}…';
        return trimmed;
      }
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.surface2Ctx(context).withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: AppColors.borderCtx(context).withValues(alpha: 0.4),
            width: 0.6,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Row(
                  children: [
                    Icon(
                      widget.isStreaming ? Icons.psychology : Icons.lightbulb_outline,
                      size: 14,
                      color: AppColors.foregroundLightCtx(context),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '思考过程',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.foregroundMutedCtx(context),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (_preview.isNotEmpty && !_expanded)
                      Expanded(
                        child: Text(
                          _preview,
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.foregroundLightCtx(context),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      )
                    else
                      const Spacer(),
                    Icon(
                      _expanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
                      size: 16,
                      color: AppColors.foregroundM(context),
                    ),
                  ],
                ),
              ),
            ),
            () {
              final trimmed = widget.content.trim();
              if (!_expanded || trimmed.isEmpty) return const SizedBox.shrink();
              return ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: SingleChildScrollView(
                  controller: _scrollController,
                  physics: const ClampingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                  child: Text(
                    trimmed,
                    style: TextStyle(fontSize: 13, color: AppColors.foregroundM(context), height: 1.5),
                  ),
                ),
              );
            }(),
          ],
        ),
      ),
    );
  }
}
