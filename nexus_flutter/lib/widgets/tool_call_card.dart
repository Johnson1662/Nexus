import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:provider/provider.dart';
import '../constants/theme.dart';
import '../models/message_data.dart';
import '../providers/chat_provider.dart';
import '../services/app_preference_service.dart';

class ToolCallCard extends StatefulWidget {
  final MessageData message;

  const ToolCallCard({super.key, required this.message});

  @override
  State<ToolCallCard> createState() => _ToolCallCardState();
}

class _ToolCallCardState extends State<ToolCallCard> {
  late bool _expanded;
  bool _userToggled = false;
  final Map<String, Set<String>> _selectedOptions = {};
  bool _submitted = false;

  final TextEditingController _customAnswerController = TextEditingController();

  @override
  void dispose() {
    _customAnswerController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    final isAsk = widget.message.toolName.toLowerCase() == 'ask';
    _expanded = isAsk || AppPreferenceService().toolCallExpanded;
    _initAskSelections();
  }

  @override
  void didUpdateWidget(covariant ToolCallCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final isAsk = widget.message.toolName.toLowerCase() == 'ask';
    if (!_userToggled) {
      _expanded = isAsk || AppPreferenceService().toolCallExpanded;
    }
    _initAskSelections();
  }

  void _initAskSelections() {
    if (widget.message.toolName.toLowerCase() != 'ask') return;
    final questions = _parseAskQuestions(widget.message.toolInput);
    for (final q in questions) {
      if (!_selectedOptions.containsKey(q.id) || _selectedOptions[q.id]!.isEmpty) {
        if (q.recommended != null && q.recommended! >= 0 && q.recommended! < q.options.length) {
          _selectedOptions[q.id] = {q.options[q.recommended!].label};
        } else if (q.options.isNotEmpty) {
          _selectedOptions[q.id] = {q.options[0].label};
        }
      }
    }
  }

  IconData _toolIcon(String toolName) {
    final name = toolName.toLowerCase();
    if (name == 'ask') return Icons.help_outline_rounded;
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
    final isAsk = msg.toolName.toLowerCase() == 'ask';
    final askQuestions = isAsk ? _parseAskQuestions(msg.toolInput) : const <_AskQuestion>[];
    // Expandable if there is anything worth showing: text output, a diff, or a terminal session.
    final hasContent = msg.toolContent.isNotEmpty ||
        msg.toolOldText.isNotEmpty ||
        msg.toolNewText.isNotEmpty ||
        msg.toolTerminalId.isNotEmpty ||
        msg.toolTruncated ||
        (isAsk && askQuestions.isNotEmpty);

    // Auto-expand while running / streaming
    if ((isAsk || (isRunning && AppPreferenceService().toolCallExpanded)) && !_userToggled) {
      _expanded = true;
    }

    final icon = _toolIcon(msg.toolName);
    Color iconColor;
    if (isRunning) {
      iconColor = AppColors.accent;
    } else if (isCompleted) {
      iconColor = AppColors.success;
    } else if (isError) {
      iconColor = AppColors.error;
    } else {
      iconColor = AppColors.foregroundM(context);
    }

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
              borderRadius: BorderRadius.vertical(
                top: const Radius.circular(8),
                bottom: (_expanded || !hasContent) ? const Radius.circular(8) : Radius.zero,
              ),
              onTap: hasContent
                  ? () => setState(() {
                        _userToggled = true;
                        _expanded = !_expanded;
                      })
                  : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Row(
                  children: [
                    isRunning
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        : Icon(icon, size: 14, color: iconColor),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        msg.toolInput.isNotEmpty
                            ? (isAsk
                                ? 'ask  ${askQuestions.isNotEmpty ? askQuestions.first.question : ''}'
                                : '${msg.toolName.isNotEmpty ? msg.toolName : 'tool'}  ${msg.toolInput}')
                            : (msg.toolName.isNotEmpty ? msg.toolName : 'tool'),
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.foregroundC(context),
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isCompleted) Icon(Icons.check, size: 13, color: AppColors.success),
                    if (isError) Icon(Icons.close, size: 13, color: AppColors.error),
                    if (hasContent) ...[
                      const SizedBox(width: 4),
                      Icon(
                        _expanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
                        size: 14, color: AppColors.foregroundLightCtx(context),
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
    final isAsk = msg.toolName.toLowerCase() == 'ask';
    final askQuestions = isAsk ? _parseAskQuestions(msg.toolInput) : const <_AskQuestion>[];

    if (isAsk && askQuestions.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        child: _buildAskSection(context, askQuestions),
      );
    }

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
                '输出已截断，仅显示前部内容',
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

  Widget _buildAskSection(BuildContext context, List<_AskQuestion> questions) {
    final msg = widget.message;
    // ask 工具在等待回答期间 toolStatus 为 pending（无 tool_call_update），
    // 不能用 isRunning 门控，否则选项永远点不动、提交按钮永远不显示。
    // 只要还没完成/失败、还没提交过，就允许点选与提交。
    final canInteract = msg.toolStatus != 'completed' && msg.toolStatus != 'error' && !_submitted;
    final fg = AppColors.foregroundCtx(context);
    final muted = AppColors.foregroundMutedCtx(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...questions.asMap().entries.map((qEntry) {
          final qIdx = qEntry.key;
          final q = qEntry.value;
          return _buildSingleQuestionBlock(
            context,
            q: q,
            qIdx: qIdx,
            totalCount: questions.length,
            canInteract: canInteract,
            fg: fg,
            muted: muted,
            isDark: isDark,
          );
        }),

        // 自定义答案输入框
        if (canInteract)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: TextField(
              controller: _customAnswerController,
              maxLines: 3,
              minLines: 1,
              textInputAction: TextInputAction.done,
              style: TextStyle(
                fontSize: AppFontSize.sm,
                color: AppColors.foregroundCtx(context),
              ),
              decoration: InputDecoration(
                hintText: '或输入自定义答案…',
                hintStyle: TextStyle(
                  fontSize: AppFontSize.sm,
                  color: AppColors.foregroundMutedCtx(context),
                ),
                filled: true,
                fillColor: AppColors.surface2Ctx(context),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),

        // Submit button when running
        if (canInteract)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: SizedBox(
              width: double.infinity,
              height: 38,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.send_rounded, size: 14),
                label: const Text('提交选择', style: TextStyle(fontSize: AppFontSize.sm, fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                ),
                onPressed: () {
                  final List<String> answers = [];
                  for (final q in questions) {
                    final sel = _selectedOptions[q.id] ?? {};
                    if (sel.isNotEmpty) {
                      if (questions.length == 1) {
                        answers.add(sel.join(', '));
                      } else {
                        answers.add('${q.question}: ${sel.join(', ')}');
                      }
                    }
                  }
                  final customText = _customAnswerController.text.trim();
                  if (customText.isNotEmpty) {
                    answers.add(customText);
                  }
                  final answerText = answers.join('\n').trim();
                  if (answerText.isNotEmpty) {
                    context.read<ChatProvider>().answerAsk(answerText);
                    setState(() => _submitted = true);
                  }
                },
              ),
            ),
          )
        else if (_submitted || msg.toolStatus == 'completed')
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle_rounded, size: 14, color: AppColors.success),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    msg.toolContent.isNotEmpty ? '已选择: ${msg.toolContent.trim()}' : '已提交选择',
                    style: TextStyle(
                      fontSize: AppFontSize.xs,
                      fontWeight: FontWeight.w500,
                      color: AppColors.success,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildSingleQuestionBlock(
    BuildContext context, {
    required _AskQuestion q,
    required int qIdx,
    required int totalCount,
    required bool canInteract,
    required Color fg,
    required Color muted,
    required bool isDark,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (totalCount > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Text(
              '问题 ${qIdx + 1}/$totalCount',
              style: TextStyle(
                fontSize: AppFontSize.xs,
                fontWeight: FontWeight.w600,
                color: AppColors.accent,
              ),
            ),
          ),
        Text(
          q.question.isNotEmpty ? q.question : '请选择：',
          style: TextStyle(
            fontSize: AppFontSize.sm,
            fontWeight: FontWeight.w600,
            color: fg,
            height: 1.4,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        ...q.options.asMap().entries.map((entry) {
          final optIdx = entry.key;
          final opt = entry.value;
          final selectedSet = _selectedOptions[q.id] ?? {};
          final isSelected = selectedSet.contains(opt.label);
          final isRecommended = q.recommended == optIdx;

          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: InkWell(
              onTap: canInteract
                  ? () {
                      setState(() {
                        if (q.multi) {
                          if (isSelected) {
                            selectedSet.remove(opt.label);
                          } else {
                            selectedSet.add(opt.label);
                          }
                          _selectedOptions[q.id] = selectedSet;
                        } else {
                          _selectedOptions[q.id] = {opt.label};
                        }
                      });
                    }
                  : null,
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? (isDark
                          ? AppColors.accent.withValues(alpha: 0.18)
                          : AppColors.accent.withValues(alpha: 0.10))
                      : AppColors.surface2Ctx(context),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(
                    color: isSelected
                        ? AppColors.accent
                        : AppColors.borderCtx(context).withValues(alpha: 0.5),
                    width: isSelected ? 1.2 : 0.6,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2, right: AppSpacing.sm),
                      child: Icon(
                        q.multi
                            ? (isSelected ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded)
                            : (isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded),
                        size: 16,
                        color: isSelected ? AppColors.accent : muted,
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  opt.label,
                                  style: TextStyle(
                                    fontSize: AppFontSize.sm,
                                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                                    color: isSelected ? AppColors.accent : fg,
                                  ),
                                ),
                              ),
                              if (isRecommended) ...[
                                const SizedBox(width: AppSpacing.xs),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: AppColors.accent.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(AppRadius.full),
                                  ),
                                  child: Text(
                                    '推荐',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.accent,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          if (opt.description != null && opt.description!.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              opt.description!,
                              style: TextStyle(
                                fontSize: AppFontSize.xs,
                                color: muted,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
        const SizedBox(height: AppSpacing.xs),
      ],
    );
  }
}

class _AskQuestion {
  final String id;
  final String question;
  final List<_AskOption> options;
  final int? recommended;
  final bool multi;

  _AskQuestion({
    required this.id,
    required this.question,
    required this.options,
    this.recommended,
    this.multi = false,
  });
}

class _AskOption {
  final String label;
  final String? description;
  _AskOption({required this.label, this.description});
}

List<_AskQuestion> _parseAskQuestions(String input) {
  if (input.trim().isEmpty) return [];
  try {
    final decoded = jsonDecode(input);
    if (decoded is Map<String, dynamic>) {
      if (decoded['questions'] is List) {
        return (decoded['questions'] as List)
            .whereType<Map>()
            .map((q) => _parseSingleQuestion(Map<String, dynamic>.from(q)))
            .where((q) => q.question.isNotEmpty || q.options.isNotEmpty)
            .toList();
      } else if (decoded['question'] != null || decoded['options'] != null) {
        return [_parseSingleQuestion(decoded)];
      }
    } else if (decoded is List) {
      return decoded
          .whereType<Map>()
          .map((q) => _parseSingleQuestion(Map<String, dynamic>.from(q)))
          .where((q) => q.question.isNotEmpty || q.options.isNotEmpty)
          .toList();
    }
  } catch (_) {}
  return [];
}

_AskQuestion _parseSingleQuestion(Map<String, dynamic> json) {
  final optsRaw = json['options'];
  final List<_AskOption> opts = [];
  if (optsRaw is List) {
    for (final opt in optsRaw) {
      if (opt is Map) {
        opts.add(_AskOption(
          label: (opt['label'] ?? opt['text'] ?? opt['name'] ?? '').toString(),
          description: opt['description']?.toString(),
        ));
      } else if (opt != null) {
        opts.add(_AskOption(label: opt.toString()));
      }
    }
  }
  return _AskQuestion(
    id: (json['id'] ?? '').toString(),
    question: (json['question'] ?? json['text'] ?? json['prompt'] ?? '').toString(),
    options: opts,
    recommended: json['recommended'] is int ? json['recommended'] as int : null,
    multi: json['multi'] == true,
  );
}

class _DiffLine {
  final String kind; // '+', '-', ' '
  final String line;
  const _DiffLine(this.kind, this.line);
}
