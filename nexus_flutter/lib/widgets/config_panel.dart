import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/theme.dart';
import '../providers/chat_provider.dart';

/// Fine-tuned modal bottom sheet for configuring Agent, Model, and Mode.
class ConfigPanel extends StatefulWidget {
  final void Function(String agentName)? onSelectAgent;
  final void Function(int index)? onSelectModel;
  final void Function(int index)? onSelectMode;

  const ConfigPanel({
    super.key,
    this.onSelectAgent,
    this.onSelectModel,
    this.onSelectMode,
  });

  @override
  State<ConfigPanel> createState() => _ConfigPanelState();
}

class _ConfigPanelState extends State<ConfigPanel> {
  String _view = 'summary'; // 'summary' | 'agents' | 'models' | 'modes'

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final state = chatProvider.state;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceElevatedCtx(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.xxl,
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Top drag handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.foregroundMutedCtx(context).withAlpha(60),
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
              ),
            ),

            // Smooth animated switcher between summary & selection views
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0.04, 0),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                );
              },
              child: KeyedSubtree(
                key: ValueKey(_view),
                child: _view == 'summary'
                    ? _buildSummaryView(context, state)
                    : _buildSelectionView(context, state),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Summary View ──

  Widget _buildSummaryView(BuildContext context, dynamic state) {
    final fg = AppColors.foregroundCtx(context);
    final muted = AppColors.foregroundMutedCtx(context);
    final dark = Theme.of(context).brightness == Brightness.dark;

    final agentName = state.selectedAgentName.isNotEmpty
        ? state.selectedAgentName
        : (state.agentNames.isNotEmpty ? state.agentNames.first : '未选择');

    String modelName = '未选择';
    if (state.modelIndex >= 0 &&
        state.modelIndex < (state.models as List).length) {
      final item = (state.models as List)[state.modelIndex];
      modelName = item.name.isNotEmpty ? item.name : item.modelId;
    }

    String modeName = '默认模式';
    if (state.modeIndex >= 0 &&
        state.modeIndex < (state.modes as List).length) {
      final item = (state.modes as List)[state.modeIndex];
      modeName = item.name;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Clean Header (without × close button)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Text(
            '配置 Agent & Model',
            style: TextStyle(
              fontSize: AppFontSize.lg,
              fontWeight: FontWeight.bold,
              color: fg,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        // Grouped Config Card
        Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceCtx(context),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: dark
                  ? Colors.white.withOpacity(0.06)
                  : Colors.black.withOpacity(0.05),
              width: 0.8,
            ),
          ),
          child: Column(
            children: [
              // Agent Row
              _summaryRow(
                context,
                icon: Icons.smart_toy_outlined,
                label: 'Agent',
                value: agentName,
                onTap: () => setState(() => _view = 'agents'),
              ),
              const Divider(height: 1),

              // Model Row
              _summaryRow(
                context,
                icon: Icons.memory_outlined,
                label: 'Model',
                value: modelName,
                onTap: () => setState(() => _view = 'models'),
              ),
              const Divider(height: 1),

              // Mode Row
              _summaryRow(
                context,
                icon: Icons.tune_outlined,
                label: 'Mode',
                value: modeName,
                onTap: () => setState(() => _view = 'modes'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _summaryRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    final fg = AppColors.foregroundCtx(context);
    final muted = AppColors.foregroundMutedCtx(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: muted),
            const SizedBox(width: AppSpacing.md),
            Text(
              label,
              style: TextStyle(
                fontSize: AppFontSize.base,
                fontWeight: FontWeight.w500,
                color: fg,
              ),
            ),
            const Spacer(),
            Text(
              value,
              style: TextStyle(
                fontSize: AppFontSize.sm,
                color: muted,
                fontWeight: FontWeight.w400,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Icon(Icons.chevron_right_rounded, size: 18, color: muted),
          ],
        ),
      ),
    );
  }

  // ── Selection View ──

  Widget _buildSelectionView(BuildContext context, dynamic state) {
    final fg = AppColors.foregroundCtx(context);
    final muted = AppColors.foregroundMutedCtx(context);

    String title = '';
    List<dynamic> items = [];
    int selectedIndex = -1;
    void Function(int index) onSelect = (_) {};

    if (_view == 'agents') {
      title = '选择 Agent';
      items = (state.agentNames as List<dynamic>);
      selectedIndex = (state.agentNames as List<String>).indexOf(state.selectedAgentName);
      onSelect = (i) {
        final name = items[i] as String;
        widget.onSelectAgent?.call(name);
        setState(() => _view = 'summary');
      };
    } else if (_view == 'models') {
      title = '选择 Model';
      items = (state.models as List<dynamic>);
      selectedIndex = state.modelIndex;
      onSelect = (i) {
        widget.onSelectModel?.call(i);
        setState(() => _view = 'summary');
      };
    } else if (_view == 'modes') {
      title = '选择 Mode';
      items = (state.modes as List<dynamic>);
      selectedIndex = state.modeIndex;
      onSelect = (i) {
        widget.onSelectMode?.call(i);
        setState(() => _view = 'summary');
      };
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Selection Header (with back button, without × close button)
        Row(
          children: [
            IconButton(
              icon: Icon(Icons.arrow_back_rounded, size: 20, color: fg),
              onPressed: () => setState(() => _view = 'summary'),
            ),
            Text(
              title,
              style: TextStyle(
                fontSize: AppFontSize.lg,
                fontWeight: FontWeight.bold,
                color: fg,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),

        // List
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxxl),
            child: Center(
              child: Text(
                '暂无可选列表',
                style: TextStyle(fontSize: AppFontSize.sm, color: muted),
              ),
            ),
          )
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 340),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: items.length,
              itemBuilder: (context, index) {
                final isSelected = index == selectedIndex;
                String label = '';
                final item = items[index];
                if (item is String) {
                  label = item;
                } else if (item != null) {
                  label = item.name?.toString().isNotEmpty == true
                      ? item.name.toString()
                      : (item.modelId?.toString() ?? '');
                }

                return Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Material(
                    color: isSelected
                        ? AppColors.accentLight.withAlpha(60)
                        : AppColors.surfaceCtx(context),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      onTap: () => onSelect(index),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg,
                          vertical: AppSpacing.md,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                label,
                                style: TextStyle(
                                  fontSize: AppFontSize.base,
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                  color: isSelected
                                      ? AppColors.accentCtx(context)
                                      : fg,
                                ),
                              ),
                            ),
                            if (isSelected)
                              Icon(
                                Icons.check_circle_rounded,
                                size: 18,
                                color: AppColors.accentCtx(context),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
