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
    if (widget.content.isEmpty) return '';
    // Show first meaningful line as preview
    final lines = widget.content.split('\n');
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
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.surfaceElevatedCtx(context),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      _expanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
                      size: 16, color: AppColors.foregroundM(context),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      widget.isStreaming ? Icons.psychology : Icons.lightbulb_outline,
                      size: 14, color: AppColors.accent,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '思考过程',
                      style: TextStyle(fontSize: 13, color: AppColors.foregroundM(context), fontWeight: FontWeight.w500),
                    ),
                    const Spacer(),
                    if (_preview.isNotEmpty && !_expanded)
                      Flexible(
                        child: Text(
                          _preview,
                          style: TextStyle(fontSize: 11, color: AppColors.foregroundLightCtx(context)),
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (_expanded && widget.content.isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: SingleChildScrollView(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                  child: Text(
                    widget.content,
                    style: TextStyle(fontSize: 13, color: AppColors.foregroundM(context), height: 1.5),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
