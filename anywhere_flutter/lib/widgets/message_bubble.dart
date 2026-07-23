import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/theme.dart';
import '../models/message_data.dart';
import '../models/ws_protocol.dart';
import '../widgets/markdown_renderer.dart';
import '../widgets/thinking_section.dart';
import '../widgets/tool_call_card.dart';
import '../widgets/plan_view.dart';

// ── File prefix parsing helpers ──

class _FileAttachment {
  final String name;
  final String type; // 'image' | 'file'
  final String data; // base64 bytes for image, text content for file

  _FileAttachment({required this.name, required this.type, required this.data});
}

class _ParsedContent {
  final String text;
  final List<_FileAttachment> files;

  _ParsedContent({required this.text, required this.files});
}

/// Parses [Image: name]\ndata:... and [File: name]\ncontent from user content.
_ParsedContent _parseContent(String content) {
  final files = <_FileAttachment>[];
  String remaining = content;

  final prefixPattern = RegExp(r'^\[(Image|File):\s*(.+?)\]\n', multiLine: true);

  String textPart = '';

  while (remaining.isNotEmpty) {
    final match = prefixPattern.firstMatch(remaining);
    if (match != null) {
      // Text before this match
      textPart += remaining.substring(0, match.start);
      final type = match.group(1)!.toLowerCase();
      final name = match.group(2)!;
      remaining = remaining.substring(match.end);

      // Data is everything until the next [Image:/[File: prefix or end of string
      final nextMatch = prefixPattern.firstMatch(remaining);
      final data = nextMatch != null
          ? remaining.substring(0, nextMatch.start).trimRight()
          : remaining.trimRight();
      remaining = nextMatch != null ? remaining.substring(nextMatch.start) : '';

      files.add(_FileAttachment(name: name, type: type, data: data));
    } else {
      textPart += remaining;
      remaining = '';
    }
  }

  return _ParsedContent(text: textPart.trim(), files: files);
}



// ── MessageBubble ──

class MessageBubble extends StatefulWidget {
  final MessageData? message;
  final String? streamingText;
  final bool showCursor;
  final VoidCallback? onRetry;
  final List<PlanEntry>? planEntries;

  const MessageBubble({
    super.key,
    this.message,
    this.streamingText,
    this.showCursor = false,
    this.onRetry,
    this.planEntries,
  });

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble>
    with SingleTickerProviderStateMixin {
  late AnimationController _spinController;

  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
  }

  @override
  void didUpdateWidget(covariant MessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    final msg = widget.message;
    if (msg != null && msg.role == 'user' && msg.sendStatus == 'sending') {
      if (!_spinController.isAnimating) _spinController.repeat();
    } else {
      if (_spinController.isAnimating) _spinController.stop();
    }
  }

  @override
  void dispose() {
    _spinController.dispose();
    super.dispose();
  }

  // ── Copy menu on long press ──

  void _showCopyMenu(BuildContext context, Offset globalPosition, String text) {
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        globalPosition.dx + 1,
        globalPosition.dy + 1,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
      items: [
        PopupMenuItem<String>(
          value: 'copy',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.copy, size: 16, color: AppColors.foregroundMuted),
              const SizedBox(width: AppSpacing.sm),
              Text('复制', style: const TextStyle(fontSize: AppFontSize.sm)),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'copy') {
        Clipboard.setData(ClipboardData(text: text));
      }
    });
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    if (widget.message == null) {
      if (widget.streamingText != null && widget.streamingText!.isNotEmpty) {
        return _buildAgentText(context, widget.streamingText!, isStreaming: true);
      }
      return const SizedBox.shrink();
    }

    final msg = widget.message!;

    if (msg.role == 'user') {
      return _buildUserMessage(context, msg);
    }

    switch (msg.type) {
      case 'thinking':
        return _buildThinking(msg);
      case 'tool_call':
        return _buildToolCall(msg);
      case 'plan':
        return _buildPlan();
      default:
        return _buildAgentText(context, msg.content);
    }
  }

  // ── User message ──

  Widget _buildUserMessage(BuildContext context, MessageData msg) {
    final parsed = _parseContent(msg.content);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Align(
        alignment: Alignment.centerRight,
        child: GestureDetector(
          onLongPressStart: (details) {
            _showCopyMenu(context, details.globalPosition, msg.content);
          },
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.72,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.userBubbleCtx(context),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(18),
                bottomLeft: Radius.circular(18),
                bottomRight: Radius.circular(18),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                ...parsed.files.map((f) => _buildFileAttachment(context, f)),
                if (parsed.text.isNotEmpty)
                  Text(
                    parsed.text,
                    style: TextStyle(fontSize: 14, color: AppColors.foregroundC(context), height: 1.4),
                  ),
                if (msg.sendStatus == 'sending' || msg.sendStatus == 'failed')
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: _buildSendStatus(msg),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSendStatus(MessageData msg) {
    IconData icon;
    Color color;

    switch (msg.sendStatus) {
      case 'sending':
        icon = Icons.sync;
        color = AppColors.foregroundMuted;
        return AnimatedBuilder(
          animation: _spinController,
          builder: (_, child) => Transform.rotate(
            angle: _spinController.value * 6.28318,
            child: child,
          ),
          child: Icon(icon, size: 14, color: color),
        );
      case 'sent':
        icon = Icons.check;
        color = AppColors.success;
        break;
      case 'failed':
        icon = Icons.error_outline;
        color = AppColors.error;
        return GestureDetector(
          onTap: widget.onRetry,
          child: Icon(icon, size: 14, color: color),
        );
      default:
        icon = Icons.check;
        color = AppColors.success;
    }

    return Icon(icon, size: 14, color: color);
  }

  Widget _buildFileAttachment(BuildContext context, _FileAttachment file) {
    if (file.type == 'image') {
      try {
        final bytes = base64Decode(file.data);
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: Image.memory(
              bytes,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) =>
                  _buildFileCard(context, file.name, '[Image decode error]'),
            ),
          ),
        );
      } catch (_) {
        return _buildFileCard(context, file.name, '[Image decode error]');
      }
    }
    return _buildFileCard(context, file.name, file.data);
  }

  Widget _buildFileCard(BuildContext context, String name, String preview) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.surface1(context),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Row(
          children: [
            const Icon(Icons.insert_drive_file_outlined, size: 18, color: AppColors.foregroundMuted),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: AppFontSize.sm,
                      fontWeight: FontWeight.w500,
                      color: AppColors.foreground,
                    ),
                  ),
                  if (preview.isNotEmpty && preview.length <= 200)
                    Text(
                      preview,
                      style: const TextStyle(
                        fontSize: AppFontSize.xs,
                        color: AppColors.foregroundMuted,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Agent text (with markdown) ──

  Widget _buildAgentText(BuildContext context, String content, {bool isStreaming = false}) {
    final displayContent = (isStreaming || widget.showCursor) ? '$content\u258C' : content;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: GestureDetector(
        onLongPressStart: (details) {
          _showCopyMenu(context, details.globalPosition, content);
        },
        child: SizedBox(
          width: double.infinity,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: AppMarkdownRenderer(data: displayContent),
          ),
        ),
      ),
    );
  }

  // ── Thinking ──

  Widget _buildThinking(MessageData msg) {
    return ThinkingSection(content: msg.content);
  }

  // ── Tool call ──

  Widget _buildToolCall(MessageData msg) {
    return ToolCallCard(message: msg);
  }

  // ── Plan ──

  Widget _buildPlan() {
    final entries = widget.planEntries;
    if (entries == null || entries.isEmpty) return const SizedBox.shrink();
    return PlanView(entries: entries);
  }
}
