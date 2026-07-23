import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/theme.dart';
import '../providers/chat_provider.dart';

/// Modal bottom sheet for Agent / Model / Mode selection.
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
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: _view == 'summary' ? _buildSummary(context, state) : _buildSelection(context, state),
    );
  }

  Widget _buildSummary(BuildContext context, dynamic state) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('配置', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: AppSpacing.lg),

        // Agent
        _configRow(
          context,
          'Agent',
          state.selectedAgentName.isNotEmpty ? state.selectedAgentName : '未选择',
          () => setState(() => _view = 'agents'),
        ),
        const Divider(),

        // Model
        _configRow(
          context,
          'Model',
          state.modelIndex >= 0 && state.modelIndex < (state.models as List).length
              ? ((state.models as List)[state.modelIndex] as dynamic).name as String
              : '未选择',
          () => setState(() => _view = 'models'),
        ),
        const Divider(),

        // Mode
        _configRow(
          context,
          'Mode',
          state.modeIndex >= 0 && state.modeIndex < state.modes.length
              ? state.modes[state.modeIndex].name
              : '未选择',
          () => setState(() => _view = 'modes'),
        ),
      ],
    );
  }

  Widget _configRow(BuildContext context, String label, String value, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    value,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 20, color: AppColors.foregroundMuted),
          ],
        ),
      ),
    );
  }

  Widget _buildSelection(BuildContext context, dynamic state) {
    final chatProvider = context.read<ChatProvider>();
    final List<String> items = <String>[];
    int currentIndex = -1;

    String title = '';
    void Function(int) onSelect = (int i) {};

    if (_view == 'agents') {
      title = '选择 Agent';
      items.addAll(state.agentNames as List<String>);
      currentIndex = state.agentNames.indexOf(state.selectedAgentName);
      onSelect = (i) {
        widget.onSelectAgent?.call(items[i]);
        setState(() => _view = 'summary');
      };
    } else if (_view == 'models') {
      title = '选择 Model';
      final models = state.models as List<dynamic>;
      items.addAll(models.map((m) => (m as dynamic).name as String));
      currentIndex = state.modelIndex;
      onSelect = (i) {
        widget.onSelectModel?.call(i);
        setState(() => _view = 'summary');
      };
    } else if (_view == 'modes') {
      title = '选择 Mode';
      final modes = state.modes as List<dynamic>;
      items.addAll(modes.map((m) => (m as dynamic).name as String));
      currentIndex = state.modeIndex;
      onSelect = (i) {
        widget.onSelectMode?.call(i);
        setState(() => _view = 'summary');
      };
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: () => setState(() => _view = 'summary'),
            ),
            Text(title, style: Theme.of(context).textTheme.headlineMedium),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.all(AppSpacing.lg),
            child: Text('暂无数据', style: TextStyle(color: AppColors.foregroundMuted)),
          )
        else
          ...List.generate(items.length, (i) {
            final isSelected = i == currentIndex;
            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Material(
                color: isSelected ? AppColors.accentLight : AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  onTap: () => onSelect(i),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            items[i],
                            style: TextStyle(
                              fontSize: AppFontSize.base,
                              color: isSelected ? AppColors.accent : AppColors.foreground,
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                        ),
                        if (isSelected)
                          const Icon(Icons.check, size: 16, color: AppColors.accent),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }
}
