import 'package:flutter/material.dart';

import '../constants/theme.dart';
import 'agent_logo.dart';

class ChatInputBar extends StatefulWidget {
  final bool disabled;
  final bool showCancel;
  final String configLabel;
  final void Function(String text) onSend;
  final VoidCallback onCancel;
  final VoidCallback onOpenConfig;

  const ChatInputBar({
    super.key,
    required this.disabled,
    required this.showCancel,
    this.configLabel = '选择模型',
    required this.onSend,
    required this.onCancel,
    required this.onOpenConfig,
  });

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar>
    with SingleTickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  bool _hasText = false;
  bool _showAddSheet = false;

  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 340),
  );
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, 0.14),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _entrance, curve: Curves.easeOutCubic));
  late final Animation<double> _fade = CurvedAnimation(
    parent: _entrance,
    curve: Curves.easeOut,
  );

  @override
  void initState() {
    super.initState();
    _entrance.forward();
  }

  @override
  void dispose() {
    _entrance.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    if (!mounted) return;
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    if (!mounted) return;
    widget.onSend(text);
    if (mounted) setState(() => _hasText = false);
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final muted = AppColors.foregroundMutedCtx(context);
    final glyphColor = AppColors.foregroundCtx(context);

    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Action Sheet Popup (+ button) ──
              if (_showAddSheet) ...[
                _buildAddActionSheet(context),
                const SizedBox(height: AppSpacing.sm),
              ],

              // ── Main Large Input Box Capsule ──
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevatedCtx(context),
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                  border: Border.all(
                    color: dark
                        ? Colors.white.withOpacity(0.08)
                        : Colors.black.withOpacity(0.06),
                    width: 0.8,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: dark
                          ? const Color(0x30000000)
                          : const Color(0x10000000),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.sm,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top: Text Input Area
                    TextField(
                      controller: _controller,
                      enabled: !widget.disabled,
                      maxLines: 5,
                      minLines: 2,
                      textInputAction: TextInputAction.send,
                      cursorColor: glyphColor,
                      cursorWidth: 2,
                      cursorRadius: const Radius.circular(2),
                      style: TextStyle(
                        fontSize: AppFontSize.md,
                        color: AppColors.foregroundCtx(context),
                        height: 1.35,
                      ),
                      decoration: InputDecoration(
                        isCollapsed: true,
                        filled: false,
                        hintText: widget.disabled ? '连接中...' : '输入消息...',
                        hintStyle: TextStyle(
                          fontSize: AppFontSize.md,
                          color: muted,
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onChanged: (v) =>
                          setState(() => _hasText = v.trim().isNotEmpty),
                      onSubmitted: (_) => _send(),
                    ),

                    const SizedBox(height: AppSpacing.md),

                    // Bottom Row: [Attachment] [Model Selector Chip in bottom-left] ... [Send Button]
                    Row(
                      children: [
                        // Attachment + button
                        Material(
                          color: Colors.transparent,
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () =>
                                setState(() => _showAddSheet = !_showAddSheet),
                            child: Padding(
                              padding: const EdgeInsets.all(AppSpacing.xs),
                              child: Icon(
                                _showAddSheet
                                    ? Icons.close_rounded
                                    : Icons.add_rounded,
                                size: 22,
                                color: muted,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),

                        // Model Selector Chip in the bottom-left corner
                        _modelChip(
                          context,
                          label: widget.configLabel,
                          onTap: widget.disabled ? null : widget.onOpenConfig,
                        ),

                        const Spacer(),

                        // Send / Stop / Mic Button on the right
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: widget.showCancel
                              ? _discButton(
                                  key: const ValueKey('stop'),
                                  icon: Icons.stop_rounded,
                                  discColor: AppColors.error,
                                  glyphColor: Colors.white,
                                  size: 32,
                                  onTap: widget.onCancel,
                                )
                              : _hasText
                                  ? _discButton(
                                      key: const ValueKey('send'),
                                      icon: Icons.arrow_upward_rounded,
                                      discColor: glyphColor,
                                      glyphColor:
                                          AppColors.surfaceElevatedCtx(context),
                                      size: 32,
                                      onTap: _send,
                                    )
                                  : _discButton(
                                      key: const ValueKey('mic'),
                                      icon: Icons.mic_none_rounded,
                                      discColor: Colors.transparent,
                                      glyphColor: muted,
                                      size: 32,
                                      onTap: null,
                                    ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Model selector pill chip in the bottom-left corner of the input box
  Widget _modelChip(
    BuildContext context, {
    required String label,
    required VoidCallback? onTap,
  }) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final muted = AppColors.foregroundMutedCtx(context);

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.full),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.full),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm + 2,
            vertical: AppSpacing.xxs + 1,
          ),
          decoration: BoxDecoration(
            color: dark ? const Color(0x18FFFFFF) : const Color(0x0F000000),
            borderRadius: BorderRadius.circular(AppRadius.full),
            border: Border.all(
              color: dark
                  ? Colors.white.withOpacity(0.06)
                  : Colors.black.withOpacity(0.05),
              width: 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AgentLogo(
                agentName: label,
                size: 13,
                color: muted,
              ),
              const SizedBox(width: AppSpacing.xxs + 2),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppFontSize.xs,
                    fontWeight: FontWeight.w500,
                    color: muted,
                  ),
                ),
              ),
              const SizedBox(width: 2),
              Icon(Icons.expand_more_rounded, size: 14, color: muted),
            ],
          ),
        ),
      ),
    );
  }

  /// Floating Action Sheet popup (opened by + button)
  Widget _buildAddActionSheet(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fg = AppColors.foregroundCtx(context);
    return Container(
      constraints: const BoxConstraints(maxHeight: 300),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevatedCtx(context),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(
          color: dark
              ? Colors.white.withOpacity(0.08)
              : Colors.black.withOpacity(0.06),
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: dark ? const Color(0x40000000) : const Color(0x15000000),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          children: [
            _sheetItem(
              icon: Icons.photo_library_outlined,
              title: '上传照片',
              onTap: () {
                setState(() => _showAddSheet = false);
              },
              fg: fg,
            ),
            _sheetItem(
              icon: Icons.checklist_rounded,
              title: '计划模式',
              onTap: () {
                setState(() => _showAddSheet = false);
              },
              fg: fg,
            ),
          ],
        ),
      ),
    );
  }

  Widget _sheetItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    required Color fg,
  }) {
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      leading: Icon(icon, size: 20, color: fg),
      title: Text(
        title,
        style: TextStyle(
          fontSize: AppFontSize.sm,
          fontWeight: FontWeight.w500,
          color: fg,
        ),
      ),
      onTap: onTap,
    );
  }

  Widget _discButton({
    Key? key,
    required IconData icon,
    required Color discColor,
    required Color glyphColor,
    required double size,
    required VoidCallback? onTap,
  }) {
    return Material(
      key: key,
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
            color: discColor,
          ),
          child: Icon(icon, size: size * 0.6, color: glyphColor),
        ),
      ),
    );
  }
}
