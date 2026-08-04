import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/theme.dart';
import '../providers/chat_provider.dart';
import '../services/host_store.dart';
import '../services/app_preference_service.dart';
import '../models/device_entry.dart';
import '../models/host_runtime_state.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _prefs = AppPreferenceService();

  late String _language;
  late String _colorMode;
  late bool _thinkingExpanded;
  late bool _toolCallExpanded;

  final Set<String> _expandedHostIds = {};

  @override
  void initState() {
    super.initState();
    _language = AppPreferenceService.normalizeLanguage(_prefs.language);
    _colorMode = AppPreferenceService.normalizeColorMode(_prefs.colorMode);
    _thinkingExpanded = _prefs.thinkingExpanded;
    _toolCallExpanded = _prefs.toolCallExpanded;
  }

  // ── Helpers ──

  void _toggleExpanded(String hostId) {
    setState(() {
      if (_expandedHostIds.contains(hostId)) {
        _expandedHostIds.remove(hostId);
      } else {
        _expandedHostIds.add(hostId);
      }
    });
  }

  Color _phaseDotColor(HostPhase phase, BuildContext context) {
    switch (phase) {
      case HostPhase.online:
      case HostPhase.syncing:
        return AppColors.success;
      case HostPhase.connecting:
      case HostPhase.waitingHost:
      case HostPhase.reconnecting:
        return AppColors.warning;
      case HostPhase.error:
        return AppColors.error;
      case HostPhase.offline:
      case HostPhase.unknown:
      default:
        return AppColors.foregroundLight;
    }
  }

  void _showAddHostDialog() {
    if (!mounted) return;
    final hostStore = context.read<HostStore>();
    showDialog(
      context: context,
      builder: (_) => _AddHostDialog(
        onAdd: (ip, port, token) async {
          final device = DeviceEntry(
            hostId: 'host_${ip}_${DateTime.now().millisecondsSinceEpoch}',
            name: ip,
            urls: ['ws://$ip:$port'],
            authToken: token.isEmpty ? null : token,
          );
          hostStore.addOrUpdateDevice(device);
          await hostStore.saveToDisk();
        },
      ),
    );
  }

  void _showEditTokenDialog(DeviceEntry device) {
    if (!mounted) return;
    final hostStore = context.read<HostStore>();
    showDialog(
      context: context,
      builder: (_) => _EditHostTokenDialog(
        initialToken: device.authToken ?? '',
        onSave: (token) async {
          device.authToken = token.isEmpty ? null : token;
          hostStore.addOrUpdateDevice(device);
          await hostStore.saveToDisk();
        },
      ),
    );
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    final hostStore = context.watch<HostStore>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          // ── Section 1: Connection & Hosts ──
          _sectionHeader(context, '连接与主机'),
          _buildConnectionSection(context, hostStore),
          const SizedBox(height: AppSpacing.xxl),

          // ── Section 2: Display ──
          _sectionHeader(context, '显示'),
          _buildDisplaySection(context),
          const SizedBox(height: AppSpacing.xxl),

          // ── Section 3: Preferences ──
          _sectionHeader(context, '偏好设置'),
          _buildPreferencesSection(context),
          const SizedBox(height: AppSpacing.xxl),

          // ── Section 4: About ──
          _sectionHeader(context, '关于'),
          _buildAboutSection(context),
        ],
      ),
    );
  }

  // ── Section header ──

  Widget _sectionHeader(BuildContext context, String title) {
    return Padding(
      padding:
          const EdgeInsets.only(left: AppSpacing.sm, bottom: AppSpacing.sm),
      child: Text(
        title,
        style: TextStyle(
          color: AppColors.foregroundMutedCtx(context),
          fontSize: AppFontSize.xs,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  // ── Section 1: Connection & Hosts ──

  Widget _buildConnectionSection(
    BuildContext context,
    HostStore hostStore,
  ) {
    final muted = AppColors.foregroundMutedCtx(context);

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surfaceCtx(context),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: AppColors.borderCtx(context),
          width: 0.8,
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '主机',
                        style: TextStyle(
                          color: AppColors.foregroundCtx(context),
                          fontSize: AppFontSize.base,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        hostStore.devices.isEmpty
                            ? '还没有保存主机'
                            : '${hostStore.devices.length} 台已保存主机',
                        style: TextStyle(
                          color: muted,
                          fontSize: AppFontSize.xs,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: _showAddHostDialog,
                  icon: const Icon(Icons.add, size: 17),
                  label: const Text('添加'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.foregroundCtx(context),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ),
          if (hostStore.devices.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '添加 PC 地址后即可开始连接',
                  style: TextStyle(
                    color: muted,
                    fontSize: AppFontSize.xs,
                  ),
                ),
              ),
            ),
          if (hostStore.devices.isNotEmpty) ...[
            Divider(height: 1, color: AppColors.borderCtx(context)),
            ...hostStore.devices.asMap().entries.map((entry) {
              final idx = entry.key;
              final device = entry.value;
              return _buildDeviceCard(
                context,
                hostStore,
                device,
                idx,
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildDeviceCard(
    BuildContext context,
    HostStore hostStore,
    DeviceEntry device,
    int index,
  ) {
    final runtimeStore = HostRuntimeStore();
    final phase = runtimeStore.getDevicePhase(device.hostId);
    final runtimeState = runtimeStore.getStatusOrNull(device.hostId);
    final isExpanded = _expandedHostIds.contains(device.hostId);
    final dotColor = _phaseDotColor(phase, context);
    final endpoint = device.urls.isEmpty
        ? '未配置连接地址'
        : device.urls.length > 1
            ? '${device.urls.first} · ${device.urls.length} 个候选地址'
            : device.urls.first;

    return Dismissible(
      key: ValueKey(
          'device_${device.hostId.isNotEmpty ? device.hostId : device.name}_$index'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppSpacing.lg),
        color: AppColors.error,
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        if (!mounted) return false;
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.surfaceCtx(context),
            title: Text(
              '确认删除',
              style: TextStyle(color: AppColors.foregroundCtx(context)),
            ),
            content: Text(
              '确定要删除主机 "${device.name}"？',
              style: TextStyle(color: AppColors.foregroundCtx(context)),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(
                  '取消',
                  style: TextStyle(
                    color: AppColors.foregroundMutedCtx(context),
                  ),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text(
                  '删除',
                  style: TextStyle(color: AppColors.error),
                ),
              ),
            ],
          ),
        );
        if (!mounted) return false;
        return confirmed ?? false;
      },
      onDismissed: (_) async {
        hostStore.removeDevice(index);
        await hostStore.saveToDisk();
      },
      child: InkWell(
        onTap: () => _toggleExpanded(device.hostId),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
              ),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: dotColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          device.name,
                          style: TextStyle(
                            color: AppColors.foregroundCtx(context),
                            fontSize: AppFontSize.base,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          endpoint,
                          style: TextStyle(
                            color: AppColors.foregroundMutedCtx(context),
                            fontSize: AppFontSize.xs,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Text(
                    _phaseLabel(phase),
                    style: TextStyle(
                      fontSize: AppFontSize.xxs,
                      color: dotColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(AppRadius.full),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppRadius.full),
                      onTap: () {
                        final urls = device.urls;
                        if (urls.isNotEmpty) {
                          final chatProvider = context.read<ChatProvider>();
                          chatProvider.connectBest(urls,
                              hostKey: device.hostId);
                          Navigator.pushNamed(context, '/chat');
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        child: Icon(
                          Icons.play_arrow_rounded,
                          size: 19,
                          color: AppColors.foregroundCtx(context),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  AnimatedRotation(
                    turns: isExpanded ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.expand_more,
                      size: 20,
                      color: AppColors.foregroundMutedCtx(context),
                    ),
                  ),
                ],
              ),
            ),
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  0,
                  AppSpacing.lg,
                  AppSpacing.lg,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surface2Ctx(context),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(AppRadius.md),
                    bottomRight: Radius.circular(AppRadius.md),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(
                        top: AppSpacing.md,
                        bottom: AppSpacing.md,
                      ),
                      child: Row(
                        children: [
                          Text(
                            '连接状态',
                            style: TextStyle(
                              color: AppColors.foregroundMutedCtx(context),
                              fontSize: AppFontSize.xs,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Text(
                            _phaseLabel(phase),
                            style: TextStyle(
                              color: dotColor,
                              fontSize: AppFontSize.xs,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const Spacer(),
                          if (runtimeState != null &&
                              runtimeState.latencyMs > 0)
                            Text(
                              '${runtimeState.latencyMs} ms',
                              style: TextStyle(
                                color: AppColors.foregroundMutedCtx(context),
                                fontSize: AppFontSize.xs,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Divider(height: 1, color: AppColors.borderCtx(context)),
                    const SizedBox(height: AppSpacing.md),
                    _detailRow(context, '连接类型', 'WebSocket'),
                    _detailRow(
                      context,
                      'Relay',
                      device.relayUrl != null && device.relayUrl!.isNotEmpty
                          ? '已启用'
                          : '未启用',
                    ),
                    _detailRow(
                      context,
                      '主机标识',
                      device.hostId.startsWith('host_')
                          ? '自动映射'
                          : device.hostId,
                    ),
                    _detailRow(
                      context,
                      '当前地址',
                      runtimeState != null && runtimeState.activeUrl.isNotEmpty
                          ? '${runtimeState.activeUrl} (活跃)'
                          : (device.urls.isNotEmpty ? device.urls.first : '—'),
                    ),
                    if (device.urls.length > 1)
                      _detailRow(context, '全部地址', device.urls.join('\n')),
                    if (runtimeState != null &&
                        runtimeState.lastError.isNotEmpty)
                      _detailRow(context, '最后错误', runtimeState.lastError),
                    const SizedBox(height: AppSpacing.xs),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _showEditTokenDialog(device),
                        icon: const Icon(Icons.key_outlined, size: 17),
                        label: Text(
                          device.authToken == null ? '设置认证 Token' : '更新认证 Token',
                          style: const TextStyle(fontSize: AppFontSize.xs),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.foregroundCtx(context),
                          side: BorderSide(color: AppColors.borderCtx(context)),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          context.read<ChatProvider>().listRegistryAgents();
                          Navigator.pushNamed(context, '/agent-manage');
                        },
                        icon: const Icon(Icons.extension_outlined, size: 17),
                        label: const Text(
                          '管理 Agent / 商店',
                          style: TextStyle(fontSize: AppFontSize.xs),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.foregroundCtx(context),
                          side: BorderSide(
                            color: AppColors.borderCtx(context),
                          ),
                          padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.md,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.md),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              crossFadeState: isExpanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 200),
            ),
            if (index < hostStore.devices.length - 1)
              Divider(height: 1, color: AppColors.borderCtx(context)),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: TextStyle(
                fontSize: AppFontSize.xs,
                color: AppColors.foregroundMutedCtx(context),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: AppFontSize.xs,
                color: AppColors.foregroundCtx(context),
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _phaseLabel(HostPhase phase) {
    switch (phase) {
      case HostPhase.online:
      case HostPhase.syncing:
        return '在线';
      case HostPhase.connecting:
        return '连接中';
      case HostPhase.waitingHost:
        return '等待';
      case HostPhase.reconnecting:
        return '重连';
      case HostPhase.error:
        return '错误';
      case HostPhase.offline:
        return '离线';
      case HostPhase.unknown:
      default:
        return '未知';
    }
  }

  // ── Section 2: Display ──

  Widget _buildDisplaySection(BuildContext context) {
    const validLangs = ['system', 'zh-Hans', 'en-US'];
    const validModes = ['system', 'light', 'dark'];

    final safeLang = validLangs.contains(_language) ? _language : 'system';
    final safeMode = validModes.contains(_colorMode) ? _colorMode : 'system';
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Container(
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
          // Language picker
          ListTile(
            leading: Icon(
              Icons.language,
              size: 20,
              color: AppColors.foregroundCtx(context),
            ),
            title: Text(
              '语言',
              style: TextStyle(color: AppColors.foregroundCtx(context)),
            ),
            trailing: DropdownButton<String>(
              value: safeLang,
              underline: const SizedBox(),
              style: TextStyle(
                color: AppColors.foregroundCtx(context),
                fontSize: AppFontSize.sm,
              ),
              isDense: true,
              onChanged: (val) {
                if (val == null) return;
                _prefs.setLanguage(val);
                setState(() => _language = val);
              },
              items: const [
                DropdownMenuItem(
                  value: 'system',
                  child: Text('跟随系统'),
                ),
                DropdownMenuItem(
                  value: 'zh-Hans',
                  child: Text('简体中文'),
                ),
                DropdownMenuItem(
                  value: 'en-US',
                  child: Text('English'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Color mode picker
          ListTile(
            leading: Icon(
              Icons.brightness_6_outlined,
              size: 20,
              color: AppColors.foregroundCtx(context),
            ),
            title: Text(
              '颜色模式',
              style: TextStyle(color: AppColors.foregroundCtx(context)),
            ),
            trailing: DropdownButton<String>(
              value: safeMode,
              underline: const SizedBox(),
              style: TextStyle(
                color: AppColors.foregroundCtx(context),
                fontSize: AppFontSize.sm,
              ),
              isDense: true,
              onChanged: (val) {
                if (val == null) return;
                _prefs.setColorMode(val);
                setState(() => _colorMode = val);
              },
              items: const [
                DropdownMenuItem(
                  value: 'system',
                  child: Text('跟随系统'),
                ),
                DropdownMenuItem(
                  value: 'light',
                  child: Text('浅色'),
                ),
                DropdownMenuItem(
                  value: 'dark',
                  child: Text('深色'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Section 3: Preferences ──

  Widget _buildPreferencesSection(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Container(
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
          SwitchListTile(
            value: _thinkingExpanded,
            onChanged: (val) {
              _prefs.setThinkingExpanded(val);
              setState(() => _thinkingExpanded = val);
            },
            title: Text(
              '默认展开思考过程',
              style: TextStyle(
                color: AppColors.foregroundCtx(context),
                fontSize: AppFontSize.base,
              ),
            ),
            subtitle: Text(
              '新会话中自动展开 AI 思考内容',
              style: TextStyle(
                fontSize: AppFontSize.xs,
                color: AppColors.foregroundMutedCtx(context),
              ),
            ),
            activeColor: AppColors.foregroundCtx(context),
            secondary: Icon(
              Icons.psychology_outlined,
              size: 20,
              color: _thinkingExpanded
                  ? AppColors.foregroundCtx(context)
                  : AppColors.foregroundMutedCtx(context),
            ),
          ),
          const Divider(height: 1),
          SwitchListTile(
            value: _toolCallExpanded,
            onChanged: (val) {
              _prefs.setToolCallExpanded(val);
              setState(() => _toolCallExpanded = val);
            },
            title: Text(
              '默认展开工具调用详情',
              style: TextStyle(
                color: AppColors.foregroundCtx(context),
                fontSize: AppFontSize.base,
              ),
            ),
            subtitle: Text(
              '新会话中自动展开工具调用卡片详情',
              style: TextStyle(
                fontSize: AppFontSize.xs,
                color: AppColors.foregroundMutedCtx(context),
              ),
            ),
            activeColor: AppColors.foregroundCtx(context),
            secondary: Icon(
              Icons.build_outlined,
              size: 20,
              color: _toolCallExpanded
                  ? AppColors.foregroundCtx(context)
                  : AppColors.foregroundMutedCtx(context),
            ),
          ),
        ],
      ),
    );
  }

  // ── Section 4: About ──

  Widget _buildAboutSection(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Container(
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
          ListTile(
            leading: Icon(
              Icons.info_outline,
              size: 20,
              color: AppColors.foregroundCtx(context),
            ),
            title: Text(
              'Nexus',
              style: TextStyle(
                color: AppColors.foregroundCtx(context),
              ),
            ),
            subtitle: Text(
              '随时随地连接你的开发环境',
              style: TextStyle(
                fontSize: AppFontSize.xs,
                color: AppColors.foregroundMutedCtx(context),
              ),
            ),
          ),
          const Divider(height: 1),
          const ListTile(
            leading: Icon(Icons.tag, size: 20),
            title: Text('版本'),
            trailing: Text(
              '1.0.0',
              style: TextStyle(
                color: AppColors.foregroundMuted,
                fontSize: AppFontSize.base,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddHostDialog extends StatefulWidget {
  final Future<void> Function(String ip, String port, String token) onAdd;

  const _AddHostDialog({required this.onAdd});

  @override
  State<_AddHostDialog> createState() => _AddHostDialogState();
}

class _AddHostDialogState extends State<_AddHostDialog> {
  final _ipController = TextEditingController();
  final _portController = TextEditingController(text: '12138');
  final _tokenController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final ip = _ipController.text.trim();
    final port = _portController.text.trim();
    if (ip.isEmpty || port.isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      await widget.onAdd(ip, port, _tokenController.text.trim());
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surfaceCtx(context),
      titlePadding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.xl,
        0,
      ),
      title: Text(
        '添加主机',
        style: TextStyle(
          color: AppColors.foregroundCtx(context),
          fontSize: AppFontSize.lg,
          fontWeight: FontWeight.w600,
        ),
      ),
      contentPadding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.md,
        AppSpacing.xl,
        0,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _ipController,
            autofocus: true,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              hintText: '192.168.1.2',
              labelText: 'IP 地址',
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _portController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              hintText: '12138',
              labelText: '端口',
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _tokenController,
            obscureText: true,
            keyboardType: TextInputType.visiblePassword,
            decoration: const InputDecoration(
              hintText: '可选',
              labelText: 'Token',
            ),
          ),
        ],
      ),
      actionsPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: Text(
            '取消',
            style: TextStyle(color: AppColors.foregroundMutedCtx(context)),
          ),
        ),
        TextButton(
          onPressed: _saving ? null : _submit,
          child: const Text('添加'),
        ),
      ],
    );
  }
}

class _EditHostTokenDialog extends StatefulWidget {
  final String initialToken;
  final Future<void> Function(String token) onSave;

  const _EditHostTokenDialog({
    required this.initialToken,
    required this.onSave,
  });

  @override
  State<_EditHostTokenDialog> createState() => _EditHostTokenDialogState();
}

class _EditHostTokenDialogState extends State<_EditHostTokenDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialToken);
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.onSave(_controller.text.trim());
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surfaceCtx(context),
      title: Text(
        '认证 Token',
        style: TextStyle(color: AppColors.foregroundCtx(context)),
      ),
      content: TextField(
        controller: _controller,
        obscureText: true,
        autofocus: true,
        enabled: !_saving,
        decoration: const InputDecoration(
          labelText: 'Token',
          hintText: '留空以清除',
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: _saving ? null : _submit,
          child: const Text('保存'),
        ),
      ],
    );
  }
}
