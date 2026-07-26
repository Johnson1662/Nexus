import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/theme.dart';
import '../models/ws_protocol.dart';
import '../models/message_data.dart';
import '../providers/chat_provider.dart';

// ── Filter kind ──
enum _Filter { all, sessions, messages, toolCalls }

enum _MatchField { title, content, toolName, toolContent }

// ── Unified search result ──
class _SearchResult {
  final String sessionId;
  final String? sessionTitle;
  final String? agent;
  final String? cwd;
  final int timestamp;
  final String matchText;   // the text where the match was found
  final _MatchField matchField; // what kind of match
  final String preview;     // snippet around the match

  _SearchResult({
    required this.sessionId,
    this.sessionTitle,
    this.agent,
    this.cwd,
    required this.timestamp,
    required this.matchText,
    required this.matchField,
    required this.preview,
  });
}

// ── SearchPage ──
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  _Filter _filter = _Filter.all;
  List<_SearchResult> _results = [];

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onQueryChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onQueryChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    final chatProvider = context.read<ChatProvider>();
    final query = _controller.text.trim().toLowerCase();
    if (query.isEmpty) {
      setState(() => _results = []);
      return;
    }

    final results = <_SearchResult>[];
    final sessions = chatProvider.state.sessions;
    final messages = chatProvider.state.messages;

    // ── Search session titles ──
    if (_filter == _Filter.all || _filter == _Filter.sessions) {
      for (final s in sessions) {
        if (s.title != null && s.title!.isNotEmpty && s.title!.toLowerCase().contains(query)) {
          results.add(_SearchResult(
            sessionId: s.sessionId,
            sessionTitle: s.title,
            agent: s.agent,
            cwd: s.cwd,
            timestamp: s.createdAt,
            matchText: s.title!,
            matchField: _MatchField.title,
            preview: s.title!,
          ));
        }
      }
    }

    // ── Search message content ──
    if (_filter == _Filter.all || _filter == _Filter.messages) {
      for (final m in messages) {
        if (m.content.isNotEmpty && m.content.toLowerCase().contains(query)) {
          results.add(_SearchResult(
            sessionId: chatProvider.state.sessionId,
            sessionTitle: chatProvider.state.sessionTitle.isNotEmpty
                ? chatProvider.state.sessionTitle
                : null,
            agent: null,
            cwd: null,
            timestamp: m.timestamp,
            matchText: m.content,
            matchField: _MatchField.content,
            preview: _snippet(m.content, query),
          ));
        }
      }
    }

    // ── Search tool calls ──
    if (_filter == _Filter.all || _filter == _Filter.toolCalls) {
      for (final m in messages) {
        if (m.type != 'tool_call' && m.type != 'tool') continue;
        // Match tool name
        if (m.toolName.isNotEmpty && m.toolName.toLowerCase().contains(query)) {
          results.add(_SearchResult(
            sessionId: chatProvider.state.sessionId,
            sessionTitle: chatProvider.state.sessionTitle.isNotEmpty
                ? chatProvider.state.sessionTitle
                : null,
            agent: null,
            cwd: null,
            timestamp: m.timestamp,
            matchText: m.toolName,
            matchField: _MatchField.toolName,
            preview: '${m.toolName}: ${_snippet(m.toolContent.isNotEmpty ? m.toolContent : m.content, query)}',
          ));
        }
        // Match tool content
        final content = m.toolContent.isNotEmpty ? m.toolContent : m.content;
        if (content.isNotEmpty && content.toLowerCase().contains(query)) {
          results.add(_SearchResult(
            sessionId: chatProvider.state.sessionId,
            sessionTitle: chatProvider.state.sessionTitle.isNotEmpty
                ? chatProvider.state.sessionTitle
                : null,
            agent: null,
            cwd: null,
            timestamp: m.timestamp,
            matchText: content,
            matchField: _MatchField.toolContent,
            preview: '${m.toolName.isNotEmpty ? '${m.toolName}: ' : ''}${_snippet(content, query)}',
          ));
        }
      }
    }

    // Sort by timestamp descending
    results.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    setState(() => _results = results);
  }

  /// Returns a short snippet around the first occurrence of [query].
  String _snippet(String text, String query) {
    final idx = text.toLowerCase().indexOf(query);
    if (idx < 0) return text.length > 120 ? '${text.substring(0, 120)}…' : text;

    final start = (idx - 40).clamp(0, text.length);
    final end = (idx + query.length + 80).clamp(0, text.length);
    final prefix = start > 0 ? '…' : '';
    final suffix = end < text.length ? '…' : '';
    return '$prefix${text.substring(start, end)}$suffix';
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Container(
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.surface2Ctx(context),
            borderRadius: BorderRadius.circular(AppRadius.full),
          ),
          child: TextField(
            controller: _controller,
            autofocus: true,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: '搜索聊天',
              hintStyle: TextStyle(
                color: AppColors.foregroundMutedCtx(context),
                fontSize: AppFontSize.base,
              ),
              prefixIcon: Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Icon(
                  Icons.search,
                  size: 18,
                  color: AppColors.foregroundMutedCtx(context),
                ),
              ),
              suffixIcon: _controller.text.isNotEmpty
                  ? IconButton(
                      icon: Icon(
                        Icons.close,
                        size: 18,
                        color: AppColors.foregroundMutedCtx(context),
                      ),
                      onPressed: () {
                        _controller.clear();
                        setState(() => _results = []);
                      },
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
            ),
            style: TextStyle(
              color: AppColors.foregroundCtx(context),
              fontSize: AppFontSize.base,
            ),
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                '取消',
                style: TextStyle(
                  color: AppColors.foregroundMutedCtx(context),
                  fontSize: AppFontSize.base,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Filter chips ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.sm),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterChip('全部', _Filter.all),
                  const SizedBox(width: AppSpacing.sm),
                  _buildFilterChip('会话', _Filter.sessions),
                  const SizedBox(width: AppSpacing.sm),
                  _buildFilterChip('消息', _Filter.messages),
                  const SizedBox(width: AppSpacing.sm),
                  _buildFilterChip('工具调用', _Filter.toolCalls),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: AppColors.borderCtx(context)),

          // ── Results ──
          Expanded(
            child: _buildResults(context),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, _Filter value) {
    final selected = _filter == value;
    return GestureDetector(
      onTap: () {
        setState(() => _filter = value);
        _onQueryChanged();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.accentCtx(context)
              : AppColors.surface2Ctx(context),
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppColors.foregroundCtx(context),
            fontSize: AppFontSize.sm,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }

  Widget _buildResults(BuildContext context) {
    if (_controller.text.trim().isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_rounded,
              size: 48,
              color: AppColors.foregroundMutedCtx(context).withAlpha(80),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              '输入关键词搜索会话、消息和工具调用',
              style: TextStyle(
                color: AppColors.foregroundMutedCtx(context),
                fontSize: AppFontSize.sm,
              ),
            ),
          ],
        ),
      );
    }

    if (_results.isEmpty) {
      return Center(
        child: Text(
          '无结果',
          style: TextStyle(
            color: AppColors.foregroundMutedCtx(context),
            fontSize: AppFontSize.md,
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.xl),
      itemCount: _results.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, index) {
        final r = _results[index];
        return _buildResultTile(context, r);
      },
    );
  }

  Widget _buildResultTile(BuildContext context, _SearchResult r) {
    final query = _controller.text.trim();

    return Material(
      color: AppColors.surfaceCtx(context),
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: () {
          // Load the session and navigate
          final chatProvider = context.read<ChatProvider>();
          chatProvider.loadSession(r.sessionId, agent: r.agent, cwd: r.cwd,
              title: r.sessionTitle);
          Navigator.pushNamed(context, '/chat');
        },
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Top row: session title + timestamp ──
              Row(
                children: [
                  Icon(
                    _iconForField(r.matchField),
                    size: 14,
                    color: AppColors.foregroundMutedCtx(context),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      r.sessionTitle ?? r.sessionId,
                      style: TextStyle(
                        fontSize: AppFontSize.sm,
                        fontWeight: FontWeight.w600,
                        color: AppColors.foregroundCtx(context),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    _formatTime(r.timestamp),
                    style: TextStyle(
                      fontSize: AppFontSize.xs,
                      color: AppColors.foregroundMutedCtx(context),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),

              // ── Match preview with highlighting ──
              _buildHighlightedText(r.preview, query, context),
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconForField(_MatchField field) {
    switch (field) {
      case _MatchField.title:
        return Icons.chat_bubble_outline_rounded;
      case _MatchField.toolName:
      case _MatchField.toolContent:
        return Icons.build_outlined;
      case _MatchField.content:
      default:
        return Icons.textsms_outlined;
    }
  }

  Widget _buildHighlightedText(String text, String query, BuildContext context) {
    if (query.isEmpty) {
      return Text(
        text,
        style: TextStyle(
          fontSize: AppFontSize.sm,
          color: AppColors.foregroundMutedCtx(context),
        ),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      );
    }

    final spans = <TextSpan>[];
    final lower = text.toLowerCase();
    var start = 0;

    while (true) {
      final idx = lower.indexOf(query, start);
      if (idx < 0) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }
      if (idx > start) {
        spans.add(TextSpan(text: text.substring(start, idx)));
      }
      spans.add(TextSpan(
        text: text.substring(idx, idx + query.length),
        style: TextStyle(
          backgroundColor: AppColors.accentCtx(context).withAlpha(40),
          color: AppColors.accentCtx(context),
          fontWeight: FontWeight.w600,
        ),
      ));
      start = idx + query.length;
    }

    return RichText(
      text: TextSpan(
        style: TextStyle(
          fontSize: AppFontSize.sm,
          color: AppColors.foregroundMutedCtx(context),
          height: 1.4,
        ),
        children: spans,
      ),
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
    );
  }

  String _formatTime(int epoch) {
    if (epoch <= 0) return '';
    final now = DateTime.now();
    final date = DateTime.fromMillisecondsSinceEpoch(epoch);
    final diff = now.difference(date);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    if (diff.inHours < 24) return '${diff.inHours} 小时前';
    if (diff.inDays < 7) return '${diff.inDays} 天前';
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$m/$d';
  }
}
