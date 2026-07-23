import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/theme.dart';
import '../providers/chat_provider.dart';
import '../services/host_store.dart';
import '../services/ws_client.dart';
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
    final ipController = TextEditingController();
    final portController = TextEditingController(text: '12138');
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppColors.surfaceCtx(context),
        titlePadding: const EdgeInsets.fromLTRB(
          AppSpacing.xl, AppSpacing.xl, AppSpacing.xl, 0,
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
          AppSpacing.xl, AppSpacing.md, AppSpacing.xl, 0,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ipController,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                hintText: '192.168.1.2',
                labelText: 'IP 地址',
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: portController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                hintText: '12138',
                labelText: '端口',
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
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text(
              '取消',
              style: TextStyle(
                color: AppColors.foregroundMutedCtx(context),
              ),
            ),
          ),
          TextButton(
            onPressed: () async {
              final ip = ipController.text.trim();
              final port = portController.text.trim();
              if (ip.isEmpty || port.isEmpty) return;
              final url = 'ws://$ip:$port';
              final name = ip;
              final hostId =
                  'host_${name}_${DateTime.now().millisecondsSinceEpoch}';
              final device = DeviceEntry(
                hostId: hostId,
                name: name,
                urls: [url],
              );
              final hostStore = context.read<HostStore>();
              hostStore.addOrUpdateDevice(device);
              await hostStore.saveToDisk();
              Navigator.pop(dialogCtx);
            },
            child: const Text('添加'),
          ),
        ],
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
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceCtx(context),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: dark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.05),
          width: 0.8,
        ),
      ),
      child: Column(
        children: [
          // Add Host button
          ListTile(
            leading: Icon(
              Icons.add_link,
              size: 20,
              color: AppColors.foregroundCtx(context),
            ),
            title: Text(
              '添加主机',
              style: TextStyle(
                color: AppColors.foregroundCtx(context),
              ),
            ),
            trailing: Icon(
              Icons.add_circle_outline,
              size: 20,
              color: AppColors.foregroundCtx(context),
            ),
            onTap: _showAddHostDialog,
          ),

          // Device list
          if (hostStore.devices.isNotEmpty) ...[
            const Divider(height: 1),
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

    return Dismissible(
      key: ValueKey('device_${device.hostId.isNotEmpty ? device.hostId : device.name}_$index'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppSpacing.lg),
        color: AppColors.error,
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      confirmDismiss: (_) async {
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
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.md,
              ),
              child: Row(
                children: [
                  // Online status dot
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: dotColor,
                      boxShadow: dotColor == AppColors.success
                          ? [
                              BoxShadow(
                                color: AppColors.success.withAlpha(80),
                                blurRadius: 4,
                                spreadRadius: 1,
                              ),
                            ]
                          : null,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  // Name and URL
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          device.name,
                          style: TextStyle(
                            color: AppColors.foregroundCtx(context),
                            fontSize: AppFontSize.base,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (device.urls.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.xxs),
                          Text(
                            device.urls.length > 1
                                ? '${device.urls.first} (共 ${device.urls.length} 个候选地址)'
                                : device.urls.first,
                            style: TextStyle(
                              color: AppColors.foregroundMutedCtx(context),
                              fontSize: AppFontSize.xs,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  // Phase label
                  Text(
                    _phaseLabel(phase),
                    style: TextStyle(
                      fontSize: AppFontSize.xxs,
                      color: dotColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  // Connect icon button
                  Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(AppRadius.full),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppRadius.full),
                      onTap: () {
                        final urls = device.urls;
                        if (urls.isNotEmpty) {
                          final chatProvider = context.read<ChatProvider>();
                          chatProvider.connectBest(urls, hostKey: device.hostId);
                          Navigator.pushNamed(context, '/chat');
                        }
                      },
                      child: const Padding(
                        padding: EdgeInsets.all(AppSpacing.sm),
                        child: Icon(Icons.play_arrow, size: 20, color: AppColors.accent),
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

            // ── Expanded detail ──
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  0,
                  AppSpacing.md,
                  AppSpacing.md,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? AppColors.surface2Ctx(context)
                      : AppColors.surface2,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(AppRadius.md),
                    bottomRight: Radius.circular(AppRadius.md),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _detailRow(
                      context,
                      '连接类型',
                      'WebSocket',
                    ),
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
                      device.hostId.startsWith('host_') ? '自动映射' : device.hostId,
                    ),
                    _detailRow(
                      context,
                      '当前地址',
                      runtimeState != null && runtimeState.activeUrl.isNotEmpty
                          ? '${runtimeState.activeUrl} (活跃)'
                          : (device.urls.isNotEmpty
                              ? device.urls.first
                              : '—'),
                    ),
                    if (device.urls.length > 1)
                      _detailRow(
                        context,
                        '全部地址',
                        device.urls.join('\n'),
                      ),
                    _detailRow(
                      context,
                      '延迟',
                      runtimeState != null && runtimeState.latencyMs > 0
                          ? '${runtimeState.latencyMs} ms'
                          : '—',
                    ),
                    if (runtimeState != null &&
                        runtimeState.lastError.isNotEmpty)
                      _detailRow(
                        context,
                        '最后错误',
                        runtimeState.lastError,
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
              const Divider(height: 1),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: TextStyle(
                fontSize: AppFontSize.xxs,
                color: AppColors.foregroundMutedCtx(context),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: AppFontSize.xxs,
                color: AppColors.foregroundCtx(context),
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
          color: dark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.05),
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
          color: dark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.05),
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
          color: dark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.05),
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
