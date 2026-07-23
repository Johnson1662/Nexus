import 'package:flutter/material.dart';

import '../constants/theme.dart';

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

  // Entrance: the whole bar lifts + fades in on mount.
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
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSend(text);
    _controller.clear();
    setState(() => _hasText = false);
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final muted = AppColors.foregroundMutedCtx(context);
    final borderColor = AppColors.borderCtx(context);
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
              // ── Top Action Sheet Popup (when + is clicked) ──
              if (_showAddSheet) ...[
                _buildAddActionSheet(context),
                const SizedBox(height: AppSpacing.sm),
              ],

              // ── Chips row (above input pill) ──
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs, left: AppSpacing.xs, right: AppSpacing.xs),
                child: Row(
                  children: [
                    // Left: Model / Agent chip
                    _pillChip(
                      context,
                      label: widget.configLabel,
                      onTap: widget.disabled ? null : widget.onOpenConfig,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    // Right: Permission chip
                    _pillChip(
                      context,
                      label: '默认权限',
                      onTap: () {
                        // Toggle or open permission settings
                      },
                    ),
                  ],
                ),
              ),

              // ── Main Input Capsule ──
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevatedCtx(context),
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                  border: Border.all(
                    color: dark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.06),
                    width: 0.8,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: dark ? const Color(0x30000000) : const Color(0x10000000),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Left: + button to toggle action sheet
                    Material(
                      color: Colors.transparent,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => setState(() => _showAddSheet = !_showAddSheet),
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: Icon(
                            _showAddSheet ? Icons.close_rounded : Icons.add_rounded,
                            size: 22,
                            color: muted,
                          ),
                        ),
                      ),
                    ),

                    // Center: Input TextField
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        enabled: !widget.disabled,
                        maxLines: 3,
                        minLines: 1,
                        textInputAction: TextInputAction.send,
                        cursorColor: glyphColor,
                        cursorWidth: 2,
                        cursorRadius: const Radius.circular(2),
                        style: TextStyle(
                          fontSize: AppFontSize.md,
                          color: AppColors.foregroundCtx(context),
                          height: 1.3,
                        ),
                        decoration: InputDecoration(
                          isCollapsed: true,
                          filled: false,
                          hintText: '向 Codex 提问',
                          hintStyle: TextStyle(
                            fontSize: AppFontSize.md,
                            color: muted,
                          ),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        onChanged: (v) =>
                            setState(() => _hasText = v.trim().isNotEmpty),
                        onSubmitted: (_) => _send(),
                      ),
                    ),

                    const SizedBox(width: AppSpacing.xs),

                    // Right: Stop / Send / Voice Button
                    Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.sm),
                      child: AnimatedSwitcher(
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
                                    glyphColor: AppColors.surfaceElevatedCtx(context),
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

  /// Floating pill chip for Model and Permission selectors (Codex style)
  Widget _pillChip(
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
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xxs,
          ),
          decoration: BoxDecoration(
            color: dark ? const Color(0x18FFFFFF) : const Color(0x0F000000),
            borderRadius: BorderRadius.circular(AppRadius.full),
            border: Border.all(
              color: dark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.05),
              width: 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
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
              Icon(Icons.expand_more, size: 14, color: muted),
            ],
          ),
        ),
      ),
    );
  }

  /// Codex style floating Action Sheet popup (opened by + button)
  Widget _buildAddActionSheet(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fg = AppColors.foregroundCtx(context);
    final muted = AppColors.foregroundMutedCtx(context);

    return Container(
      constraints: const BoxConstraints(maxHeight: 300),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevatedCtx(context),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(
          color: dark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.06),
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
              child: Divider(
                height: 1,
                color: dark ? Colors.white10 : Colors.black12,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: AppSpacing.md, top: AppSpacing.xxs, bottom: AppSpacing.xxs),
              child: Text(
                '插件',
                style: TextStyle(
                  fontSize: AppFontSize.xxs,
                  fontWeight: FontWeight.w600,
                  color: muted,
                ),
              ),
            ),
            _pluginItem(
              icon: Icons.description_outlined,
              title: 'Documents',
              subtitle: 'Create and edit document artifacts',
              onTap: () => setState(() => _showAddSheet = false),
              fg: fg,
              muted: muted,
            ),
            _pluginItem(
              icon: Icons.picture_as_pdf_outlined,
              title: 'PDF',
              subtitle: 'Read, create, and verify PDF files',
              onTap: () => setState(() => _showAddSheet = false),
              fg: fg,
              muted: muted,
            ),
            _pluginItem(
              icon: Icons.table_chart_outlined,
              title: 'Spreadsheets',
              subtitle: 'Create and edit spreadsheet files',
              onTap: () => setState(() => _showAddSheet = false),
              fg: fg,
              muted: muted,
            ),
            _pluginItem(
              icon: Icons.slideshow_outlined,
              title: 'Presentations',
              subtitle: 'Create and edit presentation slides',
              onTap: () => setState(() => _showAddSheet = false),
              fg: fg,
              muted: muted,
            ),
            _pluginItem(
              icon: Icons.language_outlined,
              title: 'Browser',
              subtitle: 'Automate Chrome browser actions',
              onTap: () => setState(() => _showAddSheet = false),
              fg: fg,
              muted: muted,
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

  Widget _pluginItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required Color fg,
    required Color muted,
  }) {
    return ListTile(
      dense: true,
      leading: Icon(icon, size: 20, color: fg),
      title: Text(
        title,
        style: TextStyle(
          fontSize: AppFontSize.sm,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: AppFontSize.xxs,
          color: muted,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: onTap,
    );
  }

  /// A clean solid disc button (ChatGPT-style send/cancel): a filled
  /// circle with a contrasting arrow/close glyph centered in it. No glow,
  /// no outline — monochrome, matching the original's minimal look.
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
