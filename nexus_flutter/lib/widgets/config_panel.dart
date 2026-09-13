import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/theme.dart';
import '../models/chat_state.dart';
import '../models/ws_protocol.dart';
import '../providers/chat_provider.dart';
import '../utils/agent_utils.dart';
import 'agent_logo.dart';

/// Modernized modal bottom sheet for configuring Agent, Model, and Mode.
/// Features Bento-styled summary cards, search filter, and refined selection rows.
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
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = context.read<ChatProvider>();
      if (provider.state.models.isEmpty) {
        provider.refreshModels();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final state = chatProvider.state;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceElevatedCtx(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: isDark ? const Color(0x60000000) : const Color(0x18000000),
            blurRadius: 24,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: AppSpacing.md),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
              ),
            ),

            // Animated view transition
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
                    ? _buildSummaryView(context, state, chatProvider, isDark)
                    : _buildSelectionView(context, state, isDark),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Summary View (Bento Grid) ──

  Widget _buildSummaryView(BuildContext context, ChatState state, ChatProvider provider, bool isDark) {
    final fg = AppColors.foregroundCtx(context);
    final muted = AppColors.foregroundMutedCtx(context);

    final agentName = state.selectedAgentName.isNotEmpty
        ? state.selectedAgentName
        : (state.agentNames.isNotEmpty ? state.agentNames.first : '未选择');

    String modelName = '点击选择模型';
    if (state.sessionCurrentModelId.isNotEmpty) {
      final currentId = state.sessionCurrentModelId;
      bool matched = false;
      for (final m in state.models) {
        if (m.id == currentId ||
            m.modelId == currentId ||
            m.id.endsWith('/$currentId') ||
            currentId.endsWith('/${m.id}') ||
            m.name.toLowerCase() == currentId.toLowerCase()) {
          modelName = m.name;
          matched = true;
          break;
        }
      }
      if (!matched) {
        final simple = currentId.contains('/') ? currentId.split('/').last : currentId;
        final formatted = simple
            .split('-')
            .map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '')
            .join(' ');
        modelName = formatted.isNotEmpty ? formatted : simple;
      }
    } else if (state.modelIndex >= 0 && state.modelIndex < state.models.length) {
      final item = state.models[state.modelIndex];
      modelName = item.name.isNotEmpty ? item.name : item.id;
    } else if (state.models.isNotEmpty) {
      modelName = '未选择 (共 ${state.models.length} 个可用)';
    }

    String modeName = '默认模式';
    if (state.modeIndex >= 0 && state.modeIndex < state.modes.length) {
      final item = state.modes[state.modeIndex];
      modeName = item.name.isNotEmpty ? item.name : item.id;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '配置环境 & 模型',
                  style: TextStyle(
                    fontSize: AppFontSize.lg,
                    fontWeight: FontWeight.bold,
                    color: fg,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '选择执行智能体、模型规格与交互模式',
                  style: TextStyle(fontSize: AppFontSize.xs, color: muted),
                ),
              ],
            ),
            IconButton(
              icon: Icon(Icons.refresh_rounded, size: 20, color: muted),
              tooltip: '重新拉取模型列表',
              onPressed: () {
                provider.refreshModels();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('已向服务端刷新模型列表'),
                    duration: Duration(milliseconds: 1000),
                  ),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),

        // Bento Cards
        _bentoCard(
          context,
          iconWidget: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            alignment: Alignment.center,
            child: AgentLogo(agentName: agentName, size: 22, color: fg),
          ),
          category: '执行智能体 (Agent)',
          title: AgentUtils.getDisplayName(agentName),
          badge: '已安装',
          isDark: isDark,
          onTap: () {
            _searchQuery = '';
            _searchController.clear();
            setState(() => _view = 'agents');
          },
        ),
        const SizedBox(height: AppSpacing.sm),

        _bentoCard(
          context,
          iconWidget: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFF0969DA).withValues(alpha: isDark ? 0.2 : 0.1),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.memory_rounded, size: 20, color: Color(0xFF2188FF)),
          ),
          category: '语言模型 (Model)',
          title: modelName,
          badge: state.models.isNotEmpty ? '${state.models.length} 个候选' : '未加载',
          isDark: isDark,
          onTap: () {
            _searchQuery = '';
            _searchController.clear();
            setState(() => _view = 'models');
            if (state.models.isEmpty) {
              provider.refreshModels();
            }
          },
        ),
        const SizedBox(height: AppSpacing.sm),

        _bentoCard(
          context,
          iconWidget: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFF8250DF).withValues(alpha: isDark ? 0.2 : 0.1),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.tune_rounded, size: 20, color: Color(0xFFA371F7)),
          ),
          category: '交互模式 (Mode)',
          title: modeName,
          badge: state.modes.length > 1 ? '${state.modes.length} 种模式' : '标准',
          isDark: isDark,
          onTap: () {
            _searchQuery = '';
            _searchController.clear();
            setState(() => _view = 'modes');
          },
        ),
        for (final option in state.configOptions.where(
          (option) => option.category != 'model' && option.category != 'mode',
        )) ...[
          const SizedBox(height: AppSpacing.sm),
          _bentoCard(
            context,
            iconWidget: Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              child: Icon(Icons.settings_suggest_outlined, color: fg),
            ),
            category: option.description ?? 'Agent 配置',
            title: '${option.name}：${option.currentValue}',
            badge: option.type == 'boolean' ? '开关' : '${option.options.length} 项',
            isDark: isDark,
            onTap: () async {
              if (option.type == 'boolean') {
                provider.setConfigOption(option.id, option.currentValue != true);
                return;
              }
              final value = await _selectConfigValue(context, option);
              if (value != null) provider.setConfigOption(option.id, value);
            },
          ),
        ],
        for (final method in state.authMethods) ...[
          const SizedBox(height: AppSpacing.sm),
          _bentoCard(
            context,
            iconWidget: Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              child: Icon(Icons.login_rounded, color: fg),
            ),
            category: method['description'] ?? 'Agent 认证',
            title: method['name'] ?? method['id'] ?? '登录',
            badge: '认证',
            isDark: isDark,
            onTap: () {
              final methodId = method['id'];
              if (methodId != null) provider.authenticate(methodId);
            },
          ),
        ],
      ],
    );
  }

  Future<String?> _selectConfigValue(
    BuildContext context,
    ConfigOption option,
  ) {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(option.name),
        children: option.options
            .map((value) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(dialogContext, value.value),
                  child: Text(value.name ?? value.value),
                ))
            .toList(),
      ),
    );
  }

  Widget _bentoCard(
    BuildContext context, {
    required Widget iconWidget,
    required String category,
    required String title,
    required String badge,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    final fg = AppColors.foregroundCtx(context);
    final muted = AppColors.foregroundMutedCtx(context);

    return Material(
      color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm + 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
              width: 0.8,
            ),
          ),
          child: Row(
            children: [
              iconWidget,
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category,
                      style: TextStyle(
                        fontSize: AppFontSize.xxs,
                        color: muted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: AppFontSize.base,
                        fontWeight: FontWeight.w600,
                        color: fg,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Text(
                  badge,
                  style: TextStyle(
                    fontSize: AppFontSize.xxs,
                    color: muted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, size: 18, color: muted),
            ],
          ),
        ),
      ),
    );
  }

  // ── Selection View ──

  Widget _buildSelectionView(BuildContext context, ChatState state, bool isDark) {
    final fg = AppColors.foregroundCtx(context);
    final muted = AppColors.foregroundMutedCtx(context);

    String title = '';
    String subtitle = '';
    List<dynamic> rawItems = [];
    int selectedIndex = -1;
    void Function(int index) onSelect = (_) {};

    if (_view == 'agents') {
      title = '选择 Agent';
      rawItems = state.agentNames;
      subtitle = '共 ${rawItems.length} 个可用执行智能体';
      selectedIndex = state.agentNames.indexOf(state.selectedAgentName);
      onSelect = (i) {
        final name = rawItems[i] as String;
        widget.onSelectAgent?.call(name);
        setState(() => _view = 'summary');
      };
    } else if (_view == 'models') {
      title = '选择 Model';
      rawItems = state.models;
      subtitle = '共 ${rawItems.length} 个可用大语言模型';
      selectedIndex = state.modelIndex;
      onSelect = (i) {
        widget.onSelectModel?.call(i);
        setState(() => _view = 'summary');
      };
    } else if (_view == 'modes') {
      title = '选择 Mode';
      rawItems = state.modes;
      subtitle = '共 ${rawItems.length} 种运行模式';
      selectedIndex = state.modeIndex;
      onSelect = (i) {
        widget.onSelectMode?.call(i);
        setState(() => _view = 'summary');
      };
    }

    // Filter items by search query
    final query = _searchQuery.trim().toLowerCase();
    final indexedItems = rawItems.asMap().entries.where((entry) {
      if (query.isEmpty) return true;
      final item = entry.value;
      if (item is String) {
        return item.toLowerCase().contains(query) || AgentUtils.getDisplayName(item).toLowerCase().contains(query);
      }
      final name = (item.name?.toString() ?? '').toLowerCase();
      final id = (item.id?.toString() ?? '').toLowerCase();
      return name.contains(query) || id.contains(query);
    }).toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Selection Header with Round Back Button
        Row(
          children: [
            Material(
              color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => setState(() => _view = 'summary'),
                child: const Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(Icons.arrow_back_rounded, size: 20),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: AppFontSize.lg,
                    fontWeight: FontWeight.bold,
                    color: fg,
                    letterSpacing: -0.2,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: AppFontSize.xxs, color: muted),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),

        // Search Bar (if more than 5 items)
        if (rawItems.length > 5) ...[
          Container(
            height: 38,
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
                width: 0.8,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Row(
              children: [
                Icon(Icons.search_rounded, size: 18, color: muted),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    style: TextStyle(fontSize: AppFontSize.sm, color: fg),
                    decoration: InputDecoration(
                      hintText: '搜索 $title...',
                      hintStyle: TextStyle(fontSize: AppFontSize.sm, color: muted),
                      isCollapsed: true,
                      border: InputBorder.none,
                    ),
                    onChanged: (val) => setState(() => _searchQuery = val),
                  ),
                ),
                if (_searchQuery.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                    child: Icon(Icons.close_rounded, size: 16, color: muted),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],

        // Items List
        if (rawItems.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxxl),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    '正在获取可用列表，请稍候...',
                    style: TextStyle(fontSize: AppFontSize.sm, color: muted),
                  ),
                ],
              ),
            ),
          )
        else if (indexedItems.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxxl),
            child: Center(
              child: Text(
                '未找到匹配 "$_searchQuery" 的项目',
                style: TextStyle(fontSize: AppFontSize.sm, color: muted),
              ),
            ),
          )
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 360),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: indexedItems.length,
              separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.xs),
              itemBuilder: (context, idx) {
                final originalIndex = indexedItems[idx].key;
                final item = indexedItems[idx].value;
                final isSelected = originalIndex == selectedIndex;

                String primaryLabel = '';
                String subLabel = '';
                String tag = '';

                if (item is String) {
                  primaryLabel = AgentUtils.getDisplayName(item);
                  subLabel = item;
                } else if (item != null) {
                  primaryLabel = item.name?.toString().isNotEmpty == true
                      ? item.name.toString()
                      : (item.id?.toString() ?? '');
                  subLabel = item.id?.toString() ?? '';
                  tag = _extractProviderTag(subLabel);
                }

                return Material(
                  color: isSelected
                      ? AppColors.accent.withValues(alpha: isDark ? 0.18 : 0.08)
                      : (isDark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02)),
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => onSelect(originalIndex),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.sm + 2,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.accent.withValues(alpha: 0.6)
                              : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05)),
                          width: isSelected ? 1.2 : 0.6,
                        ),
                      ),
                      child: Row(
                        children: [
                          if (_view == 'agents') ...[
                            AgentLogo(
                              agentName: subLabel.isNotEmpty ? subLabel : primaryLabel,
                              size: 22,
                              color: isSelected ? AppColors.accent : muted,
                            ),
                            const SizedBox(width: AppSpacing.md),
                          ],
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        primaryLabel,
                                        style: TextStyle(
                                          fontSize: AppFontSize.base,
                                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                                          color: isSelected ? AppColors.accent : fg,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (tag.isNotEmpty) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                        decoration: BoxDecoration(
                                          color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          tag,
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.w600,
                                            color: muted,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                if (subLabel.isNotEmpty && subLabel != primaryLabel) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    subLabel,
                                    style: TextStyle(
                                      fontSize: AppFontSize.xxs,
                                      color: muted,
                                      fontFamily: 'monospace',
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Icon(
                            isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                            size: 20,
                            color: isSelected ? AppColors.accent : muted.withValues(alpha: 0.5),
                          ),
                        ],
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

  String _extractProviderTag(String modelId) {
    final lower = modelId.toLowerCase();
    if (lower.contains('claude') || lower.contains('anthropic')) return 'Anthropic';
    if (lower.contains('gpt') || lower.contains('openai') || lower.contains('o1') || lower.contains('o3')) {
      return 'OpenAI';
    }
    if (lower.contains('gemini') || lower.contains('google')) return 'Google';
    if (lower.contains('deepseek')) return 'DeepSeek';
    if (lower.contains('qwen')) return 'Qwen';
    if (lower.contains('kimi') || lower.contains('moonshot')) return 'Moonshot';
    if (lower.contains('grok') || lower.contains('xai')) return 'xAI';
    if (lower.contains('glm') || lower.contains('zhipu')) return 'Zhipu';
    return '';
  }
}
