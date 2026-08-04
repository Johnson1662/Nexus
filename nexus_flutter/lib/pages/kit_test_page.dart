import 'package:flutter/material.dart';
import '../services/live_view_service.dart';
import '../services/notification_service.dart';
import '../constants/theme.dart';

class KitTestPage extends StatefulWidget {
  const KitTestPage({super.key});
  @override
  State<KitTestPage> createState() => _KitTestPageState();
}

class _KitTestPageState extends State<KitTestPage> {
  String _result = '';

  void _log(String msg) {
    if (!mounted) return;
    setState(() => _result += '$msg\n');
  }

  Future<void> _testPureDart() async {
    _log('>>> 纯 Dart 测试 (无 MethodChannel)...');
    await Future.delayed(const Duration(seconds: 1));
    _log('✅ 纯 Dart 测试通过，UI 和按钮正常工作');
  }

  Future<void> _testLiveView() async {
    _log('>>> 测试 LiveViewKit 实况窗...');
    try {
      final success = await LiveViewService.updateProgress(
        progress: 0.65,
        statusText: '正在重构 SessionManager.mts',
        title: 'Nexus AI 远程编程',
      );
      _log(success ? '✅ LiveViewKit 实况窗已创建' : '❌ LiveViewKit 创建失败，检查实况窗开关和 AGC Push Kit 配置');
    } catch (e) {
      _log('❌ LiveViewKit 失败: $e');
    }
  }

  Future<void> _stopLiveView() async {
    _log('>>> 停止 LiveView...');
    try {
      final success = await LiveViewService.stop();
      _log(success ? '✅ LiveViewKit 已停止' : '❌ LiveViewKit 停止失败');
    } catch (e) {
      _log('❌ 停止失败: $e');
    }
  }

  Future<void> _testNotification() async {
    _log('>>> 测试 NotificationKit 推送通知...');
    try {
      final success = await NotificationService.showPermissionNotification(
        requestId: 'test_${DateTime.now().millisecondsSinceEpoch}',
        toolName: 'Bash',
        command: 'git commit -m "feat: add LiveViewKit support"',
        path: '/data/project',
      );
      _log(success ? '✅ NotificationKit 通知已发送' : '❌ NotificationKit 发送失败，请允许系统通知授权');
    } catch (e) {
      _log('❌ NotificationKit 失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kit 通道测试')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton.icon(
              onPressed: _testPureDart,
              icon: const Icon(Icons.check_circle),
              label: const Text('纯 Dart 测试 (确认 UI 正常)'),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _testLiveView,
              icon: const Icon(Icons.live_tv),
              label: const Text('测试 LiveViewKit 实况窗'),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _stopLiveView,
              icon: const Icon(Icons.stop),
              label: const Text('停止 LiveView'),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _testNotification,
              icon: const Icon(Icons.notifications_active),
              label: const Text('测试 NotificationKit 推送'),
            ),
            const Divider(height: 30),
            const Text('结果:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevatedCtx(context),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    _result.isEmpty ? '点击上方按钮开始测试...' : _result,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
