import 'package:flutter/material.dart';
import '../constants/theme.dart';

/// Reconnect/disconnected banner for chat page
class ReconnectBanner extends StatelessWidget {
  final String phase;
  final VoidCallback? onRetry;

  const ReconnectBanner({super.key, required this.phase, this.onRetry});

  @override
  Widget build(BuildContext context) {
    String text;
    Color color;
    IconData icon;

    switch (phase) {
      case 'connecting':
        text = '正在连接主机...';
        color = AppColors.warning;
        icon = Icons.sync;
        break;
      case 'reconnecting':
        text = '正在重连中...';
        color = AppColors.warning;
        icon = Icons.sync;
        break;
      case 'syncing':
        text = '正在同步消息...';
        color = AppColors.warning;
        icon = Icons.sync;
        break;
      case 'error':
        text = '连接失败（请检查网络或 Tailscale）';
        color = AppColors.error;
        icon = Icons.error_outline;
        break;
      case 'waiting_host':
        text = '等待主机响应...';
        color = AppColors.warning;
        icon = Icons.hourglass_empty;
        break;
      case 'disconnected':
      case 'offline':
        text = '主机离线';
        color = AppColors.error;
        icon = Icons.cloud_off;
        break;
      default:
        return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      color: color.withOpacity(0.1),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: AppFontSize.sm, color: color)),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              child: Text('Retry', style: TextStyle(fontSize: AppFontSize.sm, color: color)),
            ),
        ],
      ),
    );
  }
}
