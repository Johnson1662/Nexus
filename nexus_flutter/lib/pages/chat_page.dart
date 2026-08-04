import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/theme.dart';
import '../models/chat_state.dart';
import '../models/ws_protocol.dart';
import '../providers/chat_provider.dart';
import '../services/host_store.dart';
import '../utils/agent_utils.dart';
import '../widgets/agent_logo.dart';
import '../widgets/message_bubble.dart';
import '../widgets/chat_input_bar.dart';
import '../widgets/thinking_section.dart';
import '../widgets/config_panel.dart';
import '../widgets/permission_sheet.dart';
import '../widgets/reconnect_banner.dart';
import '../widgets/typing_indicator.dart';

// ── Internal item types for list view construction ──

enum _ItemType { message, streamingThinking, streamingText, agentReplyingIndicator, tokenUsage }

class _ListItem {
  final _ItemType type;
  final int? messageIndex;
  _ListItem({required this.type, this.messageIndex});
}

// ── ChatPage ──

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final ScrollController _scrollController = ScrollController();
  bool _showScrollToBottom = false;
  bool _scrollCallbackScheduled = false;
  String _lastScrollSignature = '';
  PendingPermission? _lastPermission;
  bool _fileDrawerOpen = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  // ── Scroll helpers ──

  void _onScroll() {
    if (!mounted || !_scrollController.hasClients) return;
    final atBottom = _scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 80;
    if (atBottom == _showScrollToBottom) {
      setState(() => _showScrollToBottom = !atBottom);
    }
  }

  void _scrollToBottom() {
    if (!mounted || !_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  void _autoScrollToBottom() {
    _scheduleAutoScroll();
  }

  void _scheduleAutoScroll() {
    if (_scrollCallbackScheduled) return;
    _scrollCallbackScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollCallbackScheduled = false;
      if (!mounted || !_scrollController.hasClients || _showScrollToBottom) {
        return;
      }
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  // ── Item list construction ──

  List<_ListItem> _buildItemList(ChatState state) {
    final items = <_ListItem>[];
    final messages = state.messages;

    for (int i = 0; i < messages.length; i++) {
      items.add(_ListItem(type: _ItemType.message, messageIndex: i));
    }

    // Streaming thinking (before streaming text, typical agent flow)
    if (state.streamingThinking.isNotEmpty && state.turnActive) {
      items.add(_ListItem(type: _ItemType.streamingThinking));
    }

    // Streaming text
    if (state.streamingText.isNotEmpty && state.turnActive) {
      items.add(_ListItem(type: _ItemType.streamingText));
    }

    // Elegant loading animation at the very end of agent reply
    if (state.turnActive) {
      items.add(_ListItem(type: _ItemType.agentReplyingIndicator));
    }

    // Token usage footer (show after turn completes)
    if (state.lastUsage != null && !state.turnActive) {
      items.add(_ListItem(type: _ItemType.tokenUsage));
    }

    return items;
  }

  // ── Permission modal ──

  void _showPermissionModal(PendingPermission permission) {
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => PermissionSheetWidget(
        permission: permission,
        onSelect: (optionId) {
          if (!mounted) return;
          context.read<ChatProvider>().permissionResponse(
                permission.requestId,
                'selected',
                optionId: optionId,
              );
          if (sheetContext.mounted) Navigator.pop(sheetContext);
        },
      ),
    ).then((_) {
      if (!mounted) return;
      // Auto-cancel on dismiss (user closed sheet without choosing)
      _lastPermission = null;
      final chatProvider = context.read<ChatProvider>();
      final current = chatProvider.state.pendingPermission;
      if (current != null && current.requestId == permission.requestId) {
        chatProvider.permissionResponse(
          permission.requestId,
          'cancelled',
        );
      }
    });
  }

  // ── Config panel ──

  void _openConfigPanel() {
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => ConfigPanel(
        onSelectAgent: (name) {
          if (!mounted) return;
          context.read<ChatProvider>().selectAgent(name);
        },
        onSelectModel: (index) {
          if (!mounted) return;
          context.read<ChatProvider>().selectModel(index);
        },
        onSelectMode: (index) {
          if (!mounted) return;
          context.read<ChatProvider>().selectMode(index);
        },
      ),
    );
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final hostStore = context.watch<HostStore>();
    final state = chatProvider.state;

    final hostKey = hostStore.activeHostKey.isNotEmpty
        ? hostStore.activeHostKey
        : state.currentDeviceId;
    final phase = hostStore.getPhase(hostKey);

    // Show permission sheet if pending
    final perm = state.pendingPermission;
    if (perm != null && perm != _lastPermission) {
      _lastPermission = perm;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showPermissionModal(perm);
      });
    } else if (perm == null) {
      _lastPermission = null;
    }

    // Schedule only when visible content changes; unrelated provider rebuilds
    // must not enqueue a post-frame callback.
    final lastMessage = state.messages.isEmpty ? null : state.messages.last;
    final scrollSignature = [
      state.messages.length,
      lastMessage?.id ?? '',
      lastMessage?.content.length ?? 0,
      state.streamingThinking.length,
      state.streamingText.length,
      state.turnActive,
    ].join(':');
    if (_lastScrollSignature != scrollSignature) {
      _lastScrollSignature = scrollSignature;
      _scheduleAutoScroll();
    }

    final items = _buildItemList(state);

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: _buildAppBar(context, state, hostStore, hostKey, phase),
      body: Stack(
        children: [
          Column(
        children: [
          // Reconnect banner
          if (phase == 'offline' || phase == 'reconnecting' || phase == 'error')
            ReconnectBanner(
              phase: phase,
              onRetry: () {
                final matchedDevice = hostStore.devices
                    .where((d) => d.hostId == state.currentDeviceId || d.hostId == hostKey)
                    .firstOrNull;
                final candidates = matchedDevice?.urls ?? (chatProvider.ws.currentUrl.isNotEmpty ? [chatProvider.ws.currentUrl] : []);
                if (candidates.isNotEmpty) {
                  chatProvider.connectBest(candidates, hostKey: hostKey);
                }
              },
            ),

          // Chat content
          Expanded(
            child: state.messages.isEmpty && !state.turnActive
                ? _buildEmptyState(context)
                : Stack(
                    children: [
                      ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.only(
                          left: AppSpacing.lg,
                          right: AppSpacing.lg,
                          top: AppSpacing.md,
                          bottom: AppSpacing.lg,
                        ),
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          return _buildItem(context, state, items[index]);
                        },
                      ),

                      // Jump-to-bottom FAB
                      if (_showScrollToBottom)
                        Positioned(
                          right: AppSpacing.md,
                          bottom: AppSpacing.md,
                          child: Material(
                            elevation: 4,
                            shape: const CircleBorder(),
                            color: AppColors.surface,
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: _scrollToBottom,
                              child: const Padding(
                                padding: EdgeInsets.all(AppSpacing.sm),
                                child: Icon(
                                  Icons.keyboard_arrow_down,
                                  size: 20,
                                  color: AppColors.foreground,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),

          // Input bar (always at bottom)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child:               ChatInputBar(
                disabled: !state.connected || state.loadingSession,
                showCancel: state.turnActive,
                configLabel: _configLabel(state),
                onSend: (text) {
                  chatProvider.sendMessage(text);
                  _autoScrollToBottom();
                },
                onCancel: () {
                  chatProvider.sendMessage('__cancel__');
                },
                onOpenConfig: _openConfigPanel,
              ),
            ),
          ),
        ],
      ),
      _buildFileOverlay(context),
    ],
    )
    );
  }

  // ── Top bar (rounded floating surface) ──

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    ChatState state,
    HostStore hostStore,
    String hostKey,
    String phase,
  ) {
    return AppBar(
      automaticallyImplyLeading: false,
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: 60,
      titleSpacing: 0,
      actions: const [], // prevent Scaffold from auto-adding ≡ button for endDrawer
      title: _buildTopBar(context, state, hostStore, hostKey, phase),
    );
  }

  /// Rounded floating top bar: [back] [title group] on the left,
  /// [history] [files] icons on the right.
  Widget _buildTopBar(
    BuildContext context,
    ChatState state,
    HostStore hostStore,
    String hostKey,
    String phase,
  ) {
    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Component 1: back button — capsule with ripple feedback
          _capsule(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
            alignment: Alignment.center,
            child: _roundIconButton(
              Icons.chevron_left_rounded,
              () => Navigator.maybePop(context),
              size: 36,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          // Component 2: conversation title + host + workspace (capsule)
          Expanded(
            child: GestureDetector(
              onTap: () {
                if (state.currentWorkspace.isNotEmpty) {
                  Navigator.pushNamed(context, '/workspace-detail');
                }
              },
              child: _capsule(
                height: 42,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs,
                ),
                alignment: Alignment.centerLeft,
                child: _titleGroup(context, state, hostStore, hostKey, phase),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          // Component 3: history + files icons inside one capsule
          _capsule(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _roundIconButton(
                  Icons.history_rounded,
                  () => _showHistoryPlaceholder(context),
                  size: 34,
                ),
                _roundIconButton(
                  Icons.folder_open_rounded,
                  () {
                    setState(() => _fileDrawerOpen = true);
                    context.read<ChatProvider>().requestWorkspaceFiles();
                  },
                  size: 34,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Rounded floating capsule surface — each top-bar component is its own capsule.
  /// [height] is fixed so all top-bar components share the same vertical size.
  Widget _capsule({
    required EdgeInsetsGeometry padding,
    required Widget child,
    AlignmentGeometry? alignment,
    double height = 40,
  }) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: height,
      padding: padding,
      alignment: alignment,
      decoration: BoxDecoration(
        color: AppColors.surfaceElevatedCtx(context),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(
          color: dark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.06),
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: dark ? const Color(0x20000000) : const Color(0x0A000000),
            blurRadius: 4,
            offset: const Offset(0, 1.5),
          ),
        ],
      ),
      child: child,
    );
  }

  /// Title group — conversation title + host + workspace, internally left-aligned.
  Widget _titleGroup(
    BuildContext context,
    ChatState state,
    HostStore hostStore,
    String hostKey,
    String phase,
  ) {
    final title = state.sessionTitle.isNotEmpty
        ? state.sessionTitle
        : (state.sessionId.isEmpty
            ? '新对话'
            : state.sessionId.substring(0, 8));

    // Online status color
    Color dotColor;
    switch (phase) {
      case 'online':
      case 'syncing':
        dotColor = AppColors.success; // green
        break;
      case 'connecting':
      case 'reconnecting':
      case 'waiting_host':
        dotColor = AppColors.warning; // yellow
        break;

      case 'error':
      case 'offline':
        dotColor = AppColors.error; // red
        break;
      default:
        dotColor = AppColors.foregroundMutedCtx(context);
    }

    final matchedDevice = hostStore.devices
        .where((d) => d.hostId == state.currentDeviceId || d.hostId == hostKey || d.name == hostKey || d.name == state.currentDeviceId)
        .firstOrNull;
    var deviceLabel = (matchedDevice != null && matchedDevice.name.isNotEmpty)
        ? matchedDevice.name
        : (state.currentDeviceId.isNotEmpty
            ? state.currentDeviceId
            : (hostKey.isNotEmpty ? hostKey : '未连接'));
    if (deviceLabel.startsWith('host_')) {
      if (matchedDevice?.urls.isNotEmpty == true) {
        deviceLabel = matchedDevice!.urls.first.replaceFirst('ws://', '').replaceFirst('wss://', '');
      } else {
        deviceLabel = '远程主机';
      }
    }

    final workspaceName = state.currentWorkspace.isNotEmpty
        ? state.currentWorkspace.split('/').last
        : '';

    final agentName = state.selectedAgentName.isNotEmpty
        ? AgentUtils.getDisplayName(state.selectedAgentName)
        : '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: AppFontSize.sm,
            fontWeight: FontWeight.w600,
            color: AppColors.foregroundCtx(context),
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 1),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: dotColor,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Flexible(
              child: Text(
                deviceLabel,
                style: TextStyle(
                  fontSize: AppFontSize.xxs,
                  color: AppColors.foregroundMutedCtx(context),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (agentName.isNotEmpty) ...[
              const SizedBox(width: AppSpacing.xs),
              Text(
                '/',
                style: TextStyle(
                  fontSize: AppFontSize.xxs,
                  color: AppColors.foregroundMutedCtx(context).withOpacity(0.5),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              AgentLogo(
                agentName: state.selectedAgentName,
                size: 10,
                color: AppColors.foregroundMutedCtx(context),
              ),
              const SizedBox(width: 2),
              Flexible(
                child: Text(
                  agentName,
                  style: TextStyle(
                    fontSize: AppFontSize.xxs,
                    color: AppColors.foregroundMutedCtx(context),
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
            if (workspaceName.isNotEmpty) ...[
              const SizedBox(width: AppSpacing.xs),
              Text(
                '/',
                style: TextStyle(
                  fontSize: AppFontSize.xxs,
                  color: AppColors.foregroundMutedCtx(context).withOpacity(0.5),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Icon(
                Icons.folder_open_outlined,
                size: 10,
                color: AppColors.foregroundMutedCtx(context),
              ),
              const SizedBox(width: 2),
              Flexible(
                child: Text(
                  workspaceName,
                  style: TextStyle(
                    fontSize: AppFontSize.xxs,
                    color: AppColors.foregroundMutedCtx(context),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  /// Circular icon button. When [filled] is true it renders as a solid circle
  /// (used for single-icon components like the back button); otherwise it is a
  /// transparent circular tap target (used inside a capsule).
  Widget _roundIconButton(
    IconData icon,
    VoidCallback? onTap, {
    bool filled = false,
    double size = 38,
  }) {
    final iconColor = AppColors.foregroundCtx(context);
    final Widget iconChild = Icon(icon, size: size * 0.58, color: iconColor);
    if (filled) {
      final dark = Theme.of(context).brightness == Brightness.dark;
      return Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.surfaceElevatedCtx(context),
              boxShadow: [
                BoxShadow(
                  color: dark ? const Color(0x30000000) : const Color(0x10000000),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: iconChild,
          ),
        ),
      );
    }
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: size,
          height: size,
          child: iconChild,
        ),
      ),
    );
  }

  /// History icon placeholder — functionality deferred.
  void _showHistoryPlaceholder(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceElevatedCtx(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('历史记录',
                  style: TextStyle(
                    fontSize: AppFontSize.xxl,
                    fontWeight: FontWeight.bold,
                    color: AppColors.foregroundCtx(context),
                  )),
              const SizedBox(height: AppSpacing.md),
              Text('（待实现）显示你历史输入的提示词',
                  style: TextStyle(
                    fontSize: AppFontSize.sm,
                    color: AppColors.foregroundMutedCtx(context),
                  )),
            ],
          ),
        ),
      ),
    );
  }

  /// Right-side file manager — custom slide-in overlay (no Scaffold endDrawer,
  /// so Flutter won't inject its own ≡ button). UI shell only; deferred.
  static const double _filePanelWidth = 300;

  Widget _buildFileOverlay(BuildContext context) {
    return Stack(
      children: [
        AnimatedOpacity(
          opacity: _fileDrawerOpen ? 1 : 0,
          duration: const Duration(milliseconds: 200),
          child: IgnorePointer(
            ignoring: !_fileDrawerOpen,
            child: GestureDetector(
              onTap: () => setState(() => _fileDrawerOpen = false),
              child: Container(color: Colors.black54),
            ),
          ),
        ),
        AnimatedPositioned(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          right: _fileDrawerOpen ? 0 : -_filePanelWidth,
          top: 0,
          bottom: 0,
          width: _filePanelWidth,
          child: _buildFilePanel(context),
        ),
      ],
    );
  }

  /// File manager panel — real workspace file browser with git diff.
  Widget _buildFilePanel(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final provider = context.watch<ChatProvider>();
    final state = provider.state;
    final fg = AppColors.foregroundCtx(context);
    final muted = AppColors.foregroundMutedCtx(context);

    // Build git-status-aware file list
    final changedFiles = state.workspaceFiles
        .where((f) => f['status'] != null && (f['status'] as String).isNotEmpty)
        .toList();
    final allFiles = state.workspaceFiles;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceElevatedCtx(context),
        borderRadius: const BorderRadius.horizontal(left: Radius.circular(AppRadius.xl)),
        boxShadow: [
          BoxShadow(
            color: dark ? const Color(0x40000000) : const Color(0x20000000),
            blurRadius: 16,
            offset: const Offset(-4, 0),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
              child: Row(
                children: [
                  if (state.selectedFilePath != null)
                    _roundIconButton(Icons.arrow_back_rounded, () {
                      provider.requestWorkspaceFiles();
                    })
                  else
                    Icon(Icons.folder_outlined, size: 20, color: fg),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      state.selectedFilePath != null
                          ? state.selectedFilePath!.split('/').last
                          : '文件浏览器',
                      style: TextStyle(fontSize: AppFontSize.lg, fontWeight: FontWeight.w600, color: fg),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _roundIconButton(Icons.close_rounded, () => setState(() => _fileDrawerOpen = false)),
                ],
              ),
            ),
            Divider(color: AppColors.borderCtx(context), height: 0.5),

            // Content
            Expanded(
              child: _buildFileContent(context, provider, state, changedFiles, allFiles, fg, muted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileContent(
    BuildContext context,
    ChatProvider provider,
    ChatState state,
    List<Map<String, dynamic>> changedFiles,
    List<Map<String, dynamic>> allFiles,
    Color fg,
    Color muted,
  ) {
    // Show diff view for selected file
    if (state.selectedFilePath != null) {
      if (state.fileDiff != null) {
        return ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            // File info
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              margin: const EdgeInsets.only(bottom: AppSpacing.md),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white10 : Colors.black.withOpacity(0.04),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Row(
                children: [
                  Icon(Icons.insert_drive_file_outlined, size: 16, color: muted),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(state.selectedFilePath!, style: TextStyle(fontSize: AppFontSize.xs, color: muted)),
                  ),
                  TextButton.icon(
                    icon: Icon(Icons.history, size: 14, color: fg),
                    label: Text('历史', style: TextStyle(fontSize: AppFontSize.xs, color: fg)),
                    onPressed: () => provider.requestFileLog(state.selectedFilePath!),
                  ),
                ],
              ),
            ),
            // Git log (if loaded)
            if (state.fileLogEntries.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Text('最近提交', style: TextStyle(fontSize: AppFontSize.sm, fontWeight: FontWeight.w600, color: fg)),
              ),
              ...state.fileLogEntries.take(5).map((e) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                    margin: const EdgeInsets.only(bottom: AppSpacing.xxs),
                    child: Row(
                      children: [
                        Text(e['hash'] as String? ?? '', style: TextStyle(fontSize: AppFontSize.xxs, color: AppColors.accent, fontFamily: 'monospace')),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(child: Text(e['message'] as String? ?? '', style: TextStyle(fontSize: AppFontSize.xxs, color: fg), maxLines: 1, overflow: TextOverflow.ellipsis)),
                        Text(e['date'] as String? ?? '', style: TextStyle(fontSize: AppFontSize.xxs, color: muted)),
                      ],
                    ),
                  )),
              const Divider(),
            ],
            // Diff content
            if (state.fileDiff!.isNotEmpty)
              Text(
                state.fileDiff!,
                style: TextStyle(fontSize: AppFontSize.xxs, color: fg, fontFamily: 'monospace', height: 1.5),
              )
            else
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Text('此文件无变更内容', style: TextStyle(fontSize: AppFontSize.sm, color: muted)),
              ),
          ],
        );
      }
      // Loading diff
      return const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)));
    }

    // File list
    if (state.loadingFiles) {
      return const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)));
    }

    if (allFiles.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_open_outlined, size: 40, color: muted),
            const SizedBox(height: AppSpacing.md),
            Text('暂无文件', style: TextStyle(fontSize: AppFontSize.base, color: muted)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.sm),
      itemCount: allFiles.length,
      itemBuilder: (ctx, i) {
        final f = allFiles[i];
        final path = f['path'] as String? ?? '';
        final name = f['name'] as String? ?? '';
        final status = f['status'] as String? ?? '';
        final isDir = f['type'] == 'directory';

        // Skip directories in list view
        if (isDir) return const SizedBox.shrink();

        IconData statusIcon;
        Color statusColor;
        switch (status) {
          case 'M': statusIcon = Icons.edit_outlined; statusColor = const Color(0xFFE6A817); break;
          case 'A': statusIcon = Icons.add_circle_outline; statusColor = const Color(0xFF2DA44E); break;
          case 'D': statusIcon = Icons.remove_circle_outline; statusColor = const Color(0xFFCF222E); break;
          case '??': statusIcon = Icons.help_outline; statusColor = muted; break;
          default: statusIcon = Icons.insert_drive_file_outlined; statusColor = muted; break;
        }

        return ListTile(
          dense: true,
          leading: Icon(statusIcon, size: 16, color: statusColor),
          title: Text(name, style: TextStyle(fontSize: AppFontSize.sm, color: fg)),
          subtitle: path.isNotEmpty ? Text(path, style: TextStyle(fontSize: AppFontSize.xxs, color: muted), maxLines: 1, overflow: TextOverflow.ellipsis) : null,
          onTap: () => provider.requestFileDiff(path),
        );
      },
    );
  }

  // ── List item builder ──

  Widget _buildItem(BuildContext context, ChatState state, _ListItem item) {
    final chatProvider = context.read<ChatProvider>();

    switch (item.type) {
      case _ItemType.message:
        final msg = state.messages[item.messageIndex!];
        final isLastMessage =
            item.messageIndex == state.messages.length - 1;
        final isLastAgent =
            isLastMessage && msg.role == 'assistant' && state.turnActive;

        return MessageBubble(
          key: ValueKey(msg.id),
          message: msg,
          showCursor: isLastAgent,
          onRetry: msg.role == 'user' && msg.sendStatus == 'failed'
              ? () => chatProvider.retryMessage(msg)
              : null,
          planEntries:
              msg.type == 'plan' && state.planEntries.isNotEmpty
                  ? state.planEntries
                  : null,
        );

      case _ItemType.streamingThinking:
        return ThinkingSection(content: state.streamingThinking, isStreaming: true);

      case _ItemType.streamingText:
        return MessageBubble(
          streamingText: state.streamingText,
          showCursor: true,
        );

      case _ItemType.agentReplyingIndicator:
        return const TypingIndicator();

      case _ItemType.tokenUsage:
        return _buildTokenUsage(state.lastUsage!);
    }
  }

  // ── Token usage footer ──

  Widget _buildTokenUsage(UsageInfo usage) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.sm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.memory, size: 14, color: AppColors.foregroundMuted),
          const SizedBox(width: AppSpacing.sm),
          Text(
            'Tokens: 输入 ${_formatTokens(usage.inputTokens)} / 输出 ${_formatTokens(usage.outputTokens)}',
            style: const TextStyle(
              fontSize: AppFontSize.xxs,
              color: AppColors.foregroundMuted,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            '合计 ${_formatTokens(usage.totalTokens)}',
            style: const TextStyle(
              fontSize: AppFontSize.xxs,
              color: AppColors.foregroundLight,
            ),
          ),
        ],
      ),
    );
  }

  String _formatTokens(int tokens) {
    if (tokens >= 1000) {
      return '${(tokens / 1000).toStringAsFixed(1)}k';
    }
    return tokens.toString();
  }

  /// Label for the model chip in the input bar: the current Model name,
  /// falling back to the Agent name, then a neutral prompt.
  String _configLabel(ChatState state) {
    if (state.modelIndex >= 0 &&
        state.modelIndex < state.models.length &&
        state.models[state.modelIndex].name.isNotEmpty) {
      return state.models[state.modelIndex].name;
    }
    if (state.selectedAgentName.isNotEmpty) return state.selectedAgentName;
    return '选择模型';
  }

  // ── Empty state ──

  Widget _buildEmptyState(BuildContext context) {
    final state = context.read<ChatProvider>().state;

    if (state.turnActive) {
      return const Center(child: TypingIndicator());
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.chat_bubble_outline, size: 40, color: AppColors.foregroundMuted),
          const SizedBox(height: AppSpacing.md),
          Text(
            '暂无消息',
            style: TextStyle(
              fontSize: AppFontSize.base,
              color: AppColors.foregroundMuted,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '发送消息开始对话',
            style: TextStyle(
              fontSize: AppFontSize.xs,
              color: AppColors.foregroundLight,
            ),
          ),
        ],
      ),
    );
  }
}
