import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/theme.dart';
import '../models/chat_state.dart';
import '../providers/chat_provider.dart';

/// Full-screen standalone workspace file browser with hierarchical directory navigation,
/// breadcrumbs, Git diff & commit history review.
class WorkspaceFilesPage extends StatefulWidget {
  final String? initialFilePath;

  const WorkspaceFilesPage({super.key, this.initialFilePath});

  @override
  State<WorkspaceFilesPage> createState() => _WorkspaceFilesPageState();
}

class _WorkspaceFilesPageState extends State<WorkspaceFilesPage> {
  String _currentDir = '';
  bool _onlyChanged = false;
  bool _showCommitHistory = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = context.read<ChatProvider>();
      if (widget.initialFilePath != null && widget.initialFilePath!.isNotEmpty) {
        provider.requestFileDiff(widget.initialFilePath!);
      } else {
        provider.requestWorkspaceFiles();
      }
    });
  }

  void _navigateUp() {
    if (_currentDir.isEmpty) return;
    final parts = _currentDir.split('/');
    if (parts.length <= 1) {
      setState(() => _currentDir = '');
    } else {
      setState(() => _currentDir = parts.sublist(0, parts.length - 1).join('/'));
    }
  }

  List<_FsEntry> _computeDirectChildren(List<Map<String, dynamic>> allFiles) {
    final normCurrent = _currentDir.replaceAll('\\', '/').replaceAll(RegExp(r'^/+|/+$'), '');
    final dirs = <String, _FsEntry>{};
    final files = <_FsEntry>[];

    for (final f in allFiles) {
      final rawPath = (f['path'] as String? ?? '').replaceAll('\\', '/').replaceAll(RegExp(r'^/+|/+$'), '');
      if (rawPath.isEmpty) continue;

      if (normCurrent.isNotEmpty) {
        if (!rawPath.startsWith('$normCurrent/')) continue;
      }

      final rel = normCurrent.isNotEmpty ? rawPath.substring(normCurrent.length + 1) : rawPath;
      final parts = rel.split('/');

      if (parts.length == 1) {
        if (f['type'] == 'directory') {
          dirs.putIfAbsent(
            parts[0],
            () => _FsEntry(
              name: parts[0],
              path: rawPath,
              isDirectory: true,
            ),
          );
        } else {
          files.add(_FsEntry(
            name: parts[0],
            path: rawPath,
            isDirectory: false,
            status: f['status'] as String? ?? '',
          ));
        }
      } else {
        final dirName = parts[0];
        final dirPath = normCurrent.isNotEmpty ? '$normCurrent/$dirName' : dirName;
        final entry = dirs.putIfAbsent(
          dirName,
          () => _FsEntry(
            name: dirName,
            path: dirPath,
            isDirectory: true,
          ),
        );
        if ((f['status'] as String? ?? '').isNotEmpty) {
          entry.hasChanges = true;
        }
        if (f['type'] != 'directory') {
          entry.fileCount++;
        }
      }
    }

    final sortedDirs = dirs.values.toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final sortedFiles = files..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return [...sortedDirs, ...sortedFiles];
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ChatProvider>();
    final state = provider.state;
    final fg = AppColors.foregroundCtx(context);
    final muted = AppColors.foregroundMutedCtx(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final isDiffMode = state.selectedFilePath != null;
    final fileName = isDiffMode ? state.selectedFilePath!.split('/').last : '';
    final workspaceName = state.currentWorkspace.isNotEmpty
        ? state.currentWorkspace.split('/').where((p) => p.isNotEmpty).lastOrNull ?? '工作区'
        : '文件浏览器';

    final changedFiles = state.workspaceFiles
        .where((f) => f['status'] != null && (f['status'] as String).isNotEmpty && f['type'] != 'directory')
        .toList();

    return Scaffold(
      backgroundColor: AppColors.backgroundCtx(context),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, size: 22),
          onPressed: () {
            if (isDiffMode) {
              provider.requestWorkspaceFiles();
            } else if (_currentDir.isNotEmpty && !_onlyChanged) {
              _navigateUp();
            } else {
              Navigator.pop(context);
            }
          },
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isDiffMode
                  ? fileName
                  : (_onlyChanged
                      ? 'Git 变更文件'
                      : (_currentDir.isEmpty
                          ? workspaceName
                          : _currentDir.split('/').last)),
              style: TextStyle(fontSize: AppFontSize.md, fontWeight: FontWeight.w600, color: fg),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (isDiffMode && state.selectedFilePath != null)
              Text(
                state.selectedFilePath!,
                style: TextStyle(fontSize: AppFontSize.xxs, color: muted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        actions: [
          if (isDiffMode) ...[
            IconButton(
              icon: Icon(
                _showCommitHistory ? Icons.history_toggle_off_rounded : Icons.history_rounded,
                size: 22,
                color: _showCommitHistory ? AppColors.accent : fg,
              ),
              tooltip: '提交历史',
              onPressed: () {
                setState(() => _showCommitHistory = !_showCommitHistory);
                if (_showCommitHistory && state.selectedFilePath != null) {
                  provider.requestFileLog(state.selectedFilePath!);
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 22),
              tooltip: '刷新改动',
              onPressed: () {
                if (state.selectedFilePath != null) {
                  provider.requestFileDiff(state.selectedFilePath!);
                }
              },
            ),
          ] else ...[
            if (changedFiles.isNotEmpty)
              TextButton.icon(
                onPressed: () => setState(() => _onlyChanged = !_onlyChanged),
                icon: Icon(
                  _onlyChanged ? Icons.account_tree_rounded : Icons.filter_alt_outlined,
                  size: 18,
                  color: _onlyChanged ? AppColors.accent : muted,
                ),
                label: Text(
                  _onlyChanged ? '树状目录' : '改动 (${changedFiles.length})',
                  style: TextStyle(
                    fontSize: AppFontSize.xs,
                    color: _onlyChanged ? AppColors.accent : muted,
                    fontWeight: _onlyChanged ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
            IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 22),
              tooltip: '刷新文件',
              onPressed: () => provider.requestWorkspaceFiles(),
            ),
          ],
        ],
      ),
      body: isDiffMode
          ? _buildDiffView(context, provider, state, fg, muted, isDark)
          : Column(
              children: [
                if (!_onlyChanged) _buildBreadcrumbs(workspaceName, fg, muted, isDark),
                Expanded(
                  child: _onlyChanged
                      ? _buildFlatChangedList(context, provider, state, changedFiles, fg, muted, isDark)
                      : _buildDirectoryList(context, provider, state, fg, muted, isDark),
                ),
              ],
            ),
    );
  }

  /// Horizontal scrolling breadcrumb bar
  Widget _buildBreadcrumbs(String rootName, Color fg, Color muted, bool isDark) {
    final parts = _currentDir.isEmpty ? <String>[] : _currentDir.split('/');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs + 2),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1D21) : const Color(0xFFF4F6F8),
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.08),
            width: 0.8,
          ),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => setState(() => _currentDir = ''),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _currentDir.isEmpty
                      ? (isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.08))
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.home_rounded, size: 15, color: _currentDir.isEmpty ? fg : muted),
                    const SizedBox(width: 5),
                    Text(
                      rootName,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: _currentDir.isEmpty ? FontWeight.w700 : FontWeight.w500,
                        color: _currentDir.isEmpty ? fg : muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            for (int i = 0; i < parts.length; i++) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: Icon(Icons.chevron_right_rounded, size: 16, color: muted.withValues(alpha: 0.6)),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () {
                  final target = parts.sublist(0, i + 1).join('/');
                  setState(() => _currentDir = target);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: i == parts.length - 1
                        ? (isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.08))
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    parts[i],
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: i == parts.length - 1 ? FontWeight.w700 : FontWeight.w500,
                      color: i == parts.length - 1 ? fg : muted,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Directory-aware hierarchical explorer view
  Widget _buildDirectoryList(
    BuildContext context,
    ChatProvider provider,
    ChatState state,
    Color fg,
    Color muted,
    bool isDark,
  ) {
    if (state.loadingFiles) {
      return const Center(
        child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    final children = _computeDirectChildren(state.workspaceFiles);

    if (children.isEmpty) {
      final hasError = state.fileError.isNotEmpty;
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasError ? Icons.error_outline_rounded : Icons.folder_open_outlined,
              size: 48,
              color: hasError ? AppColors.error : muted,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              hasError ? state.fileError : '此文件夹为空',
              style: TextStyle(
                fontSize: AppFontSize.base,
                color: hasError ? AppColors.error : muted,
              ),
              textAlign: TextAlign.center,
            ),
            if (_currentDir.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              TextButton.icon(
                onPressed: _navigateUp,
                icon: const Icon(Icons.arrow_upward_rounded, size: 16),
                label: const Text('返回上级目录'),
              ),
            ],
          ],
        ),
      );
    }

    final totalItems = (_currentDir.isNotEmpty ? 1 : 0) + children.length;

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      itemCount: totalItems,
      separatorBuilder: (_, __) => Divider(
        color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.04),
        height: 1,
      ),
      itemBuilder: (context, index) {
        if (_currentDir.isNotEmpty && index == 0) {
          return ListTile(
            dense: true,
            leading: Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(Icons.arrow_upward_rounded, size: 18, color: muted),
            ),
            title: Text('..', style: TextStyle(fontSize: AppFontSize.base, fontWeight: FontWeight.bold, color: fg)),
            subtitle: Text('返回上一级', style: TextStyle(fontSize: AppFontSize.xxs, color: muted)),
            onTap: _navigateUp,
          );
        }

        final itemIndex = _currentDir.isNotEmpty ? index - 1 : index;
        final entry = children[itemIndex];

        if (entry.isDirectory) {
          return ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.xxs),
            leading: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: (entry.hasChanges ? const Color(0xFFE6A817) : AppColors.accent)
                        .withValues(alpha: isDark ? 0.15 : 0.08),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Icon(
                    Icons.folder_rounded,
                    size: 20,
                    color: entry.hasChanges ? const Color(0xFFE6A817) : AppColors.accent,
                  ),
                ),
                if (entry.hasChanges)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFFE6A817),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
            title: Text(
              entry.name,
              style: TextStyle(fontSize: AppFontSize.base, fontWeight: FontWeight.w600, color: fg),
            ),
            subtitle: entry.fileCount > 0
                ? Text('${entry.fileCount} 个项', style: TextStyle(fontSize: AppFontSize.xxs, color: muted))
                : null,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (entry.hasChanges)
                  Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE6A817).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      '含改动',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFE6A817),
                      ),
                    ),
                  ),
                const Icon(Icons.chevron_right_rounded, size: 18, color: Colors.grey),
              ],
            ),
            onTap: () {
              setState(() => _currentDir = entry.path);
            },
          );
        }

        // File Item
        final status = entry.status;
        IconData iconData;
        Color statusColor;
        String statusLabel = '';

        switch (status) {
          case 'M':
            iconData = Icons.edit_note_rounded;
            statusColor = const Color(0xFFE6A817);
            statusLabel = '已修改';
            break;
          case 'A':
            iconData = Icons.add_circle_outline_rounded;
            statusColor = const Color(0xFF2DA44E);
            statusLabel = '新增';
            break;
          case 'D':
            iconData = Icons.remove_circle_outline_rounded;
            statusColor = const Color(0xFFCF222E);
            statusLabel = '已删除';
            break;
          case '??':
            iconData = Icons.help_outline_rounded;
            statusColor = muted;
            statusLabel = '未追踪';
            break;
          default:
            iconData = _getIconForExtension(entry.name);
            statusColor = muted;
            break;
        }

        return ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.xxs),
          leading: Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: isDark ? 0.15 : 0.08),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(iconData, size: 18, color: statusColor),
          ),
          title: Text(
            entry.name,
            style: TextStyle(
              fontSize: AppFontSize.base,
              fontWeight: status.isNotEmpty ? FontWeight.w600 : FontWeight.normal,
              color: fg,
            ),
          ),
          trailing: statusLabel.isNotEmpty
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: statusColor.withValues(alpha: 0.3), width: 0.5),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      fontSize: AppFontSize.xxs,
                      fontWeight: FontWeight.w600,
                      color: statusColor,
                    ),
                  ),
                )
              : const Icon(Icons.chevron_right_rounded, size: 18, color: Colors.grey),
          onTap: () {
            provider.requestFileDiff(entry.path);
          },
        );
      },
    );
  }

  /// Flat list of changed files across the entire workspace
  Widget _buildFlatChangedList(
    BuildContext context,
    ChatProvider provider,
    ChatState state,
    List<Map<String, dynamic>> changedFiles,
    Color fg,
    Color muted,
    bool isDark,
  ) {
    if (changedFiles.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline_rounded, size: 48, color: Colors.green.shade400),
            const SizedBox(height: AppSpacing.md),
            Text('工作区暂无任何 Git 变更', style: TextStyle(fontSize: AppFontSize.base, color: muted)),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      itemCount: changedFiles.length,
      separatorBuilder: (_, __) => Divider(
        color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.04),
        height: 1,
      ),
      itemBuilder: (context, index) {
        final f = changedFiles[index];
        final path = f['path'] as String? ?? '';
        final name = f['name'] as String? ?? (path.split('/').lastOrNull ?? '');
        final status = f['status'] as String? ?? '';

        Color statusColor;
        String statusLabel = '';

        switch (status) {
          case 'M':
            statusColor = const Color(0xFFE6A817);
            statusLabel = '已修改';
            break;
          case 'A':
            statusColor = const Color(0xFF2DA44E);
            statusLabel = '新增';
            break;
          case 'D':
            statusColor = const Color(0xFFCF222E);
            statusLabel = '已删除';
            break;
          case '??':
            statusColor = muted;
            statusLabel = '未追踪';
            break;
          default:
            statusColor = muted;
            break;
        }

        return ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.xxs),
          leading: Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: isDark ? 0.15 : 0.08),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(Icons.edit_note_rounded, size: 18, color: statusColor),
          ),
          title: Text(
            name,
            style: TextStyle(fontSize: AppFontSize.base, fontWeight: FontWeight.w600, color: fg),
          ),
          subtitle: Text(
            path,
            style: TextStyle(fontSize: AppFontSize.xxs, color: muted),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 2),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: statusColor.withValues(alpha: 0.3), width: 0.5),
            ),
            child: Text(
              statusLabel,
              style: TextStyle(
                fontSize: AppFontSize.xxs,
                fontWeight: FontWeight.w600,
                color: statusColor,
              ),
            ),
          ),
          onTap: () {
            provider.requestFileDiff(path);
          },
        );
      },
    );
  }

  Widget _buildDiffView(
    BuildContext context,
    ChatProvider provider,
    ChatState state,
    Color fg,
    Color muted,
    bool isDark,
  ) {
    if (state.fileDiff == null) {
      return const Center(
        child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    final diffContent = state.fileDiff!;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Collapsible Commit History Section
          if (_showCommitHistory) ...[
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              margin: const EdgeInsets.only(bottom: AppSpacing.md),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.history_rounded, size: 16, color: fg),
                      const SizedBox(width: AppSpacing.xs),
                      Text('最近提交记录', style: TextStyle(fontSize: AppFontSize.sm, fontWeight: FontWeight.w600, color: fg)),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  if (state.fileLogEntries.isEmpty)
                    Text(
                      state.fileGitWarning.isNotEmpty ? state.fileGitWarning : '暂无提交历史',
                      style: TextStyle(fontSize: AppFontSize.xs, color: muted),
                    )
                  else
                    ...state.fileLogEntries.take(8).map((e) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: AppColors.accent.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  (e['hash'] as String? ?? '').take(7),
                                  style: TextStyle(
                                    fontSize: AppFontSize.xxs,
                                    color: AppColors.accent,
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Text(
                                  e['message'] as String? ?? '',
                                  style: TextStyle(fontSize: AppFontSize.xs, color: fg),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                e['date'] as String? ?? '',
                                style: TextStyle(fontSize: AppFontSize.xxs, color: muted),
                              ),
                            ],
                          ),
                        )),
                ],
              ),
            ),
          ],

          // Git unavailable is an explicit degradation, not an empty diff.
          if (diffContent.isEmpty && state.fileGitWarning.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 16, color: muted),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      state.fileGitWarning,
                      style: TextStyle(fontSize: AppFontSize.xs, color: muted),
                    ),
                  ),
                ],
              ),
            ),

          // Non-Git file error or size limit error
          if (state.fileError.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded, size: 16, color: AppColors.error),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      state.fileError,
                      style: const TextStyle(fontSize: AppFontSize.xs, color: AppColors.error),
                    ),
                  ),
                ],
              ),
            ),

          // Full-screen Diff Container
          if (diffContent.isNotEmpty)
            Container(
              width: double.infinity,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF161B22) : const Color(0xFFF6F8FA),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? const Color(0xFF30363D) : const Color(0xFFD0D7DE),
                  width: 0.8,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // IDE Style Title Bar
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs + 2),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF0D1117) : const Color(0xFFEAEEF2),
                      border: Border(
                        bottom: BorderSide(
                          color: isDark ? const Color(0xFF30363D) : const Color(0xFFD0D7DE),
                          width: 0.8,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.code_rounded, size: 14, color: muted),
                        const SizedBox(width: 6),
                        Text(
                          'Git 变更对比 (Unified Diff)',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: muted,
                            letterSpacing: 0.2,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${diffContent.split('\n').length} 行',
                          style: TextStyle(fontSize: 10, color: muted, fontFamily: 'monospace'),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SelectableText.rich(
                        _buildColoredDiff(diffContent, isDark),
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.xxl),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.02),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.check_circle_outline_rounded, size: 40, color: Colors.green.shade400),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      '此文件暂无代码改动',
                      style: TextStyle(fontSize: AppFontSize.base, color: muted),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  TextSpan _buildColoredDiff(String diff, bool isDark) {
    final lines = diff.split('\n');
    final spans = <TextSpan>[];

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      Color? fg;
      Color? bg;

      if (line.startsWith('+++') || line.startsWith('---')) {
        fg = isDark ? Colors.grey.shade400 : Colors.grey.shade700;
      } else if (line.startsWith('+')) {
        fg = isDark ? const Color(0xFF7EE787) : const Color(0xFF1A7F37);
        bg = isDark ? const Color(0x25238636) : const Color(0x252DA44E);
      } else if (line.startsWith('-')) {
        fg = isDark ? const Color(0xFFFFA198) : const Color(0xFFCF222E);
        bg = isDark ? const Color(0x25DA3633) : const Color(0x20FFEBE9);
      } else if (line.startsWith('@@')) {
        fg = isDark ? const Color(0xFF79C0FF) : const Color(0xFF0969DA);
        bg = isDark ? const Color(0x20388BFD) : const Color(0x150969DA);
      } else {
        fg = isDark ? const Color(0xFFC9D1D9) : const Color(0xFF24292F);
      }

      spans.add(
        TextSpan(
          text: '$line\n',
          style: TextStyle(
            color: fg,
            backgroundColor: bg,
          ),
        ),
      );
    }

    return TextSpan(children: spans);
  }

  IconData _getIconForExtension(String filename) {
    final ext = filename.split('.').lastOrNull?.toLowerCase() ?? '';
    switch (ext) {
      case 'dart':
        return Icons.flutter_dash;
      case 'ts':
      case 'js':
      case 'mts':
      case 'mjs':
        return Icons.javascript;
      case 'json':
      case 'json5':
        return Icons.data_object_rounded;
      case 'md':
        return Icons.description_outlined;
      case 'yaml':
      case 'yml':
        return Icons.tune_rounded;
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'svg':
        return Icons.image_outlined;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }
}

class _FsEntry {
  final String name;
  final String path;
  final bool isDirectory;
  final String status;
  bool hasChanges = false;
  int fileCount = 0;

  _FsEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
    this.status = '',
  });
}

extension _StringExtension on String {
  String take(int n) => length <= n ? this : substring(0, n);
}
