import 'package:flutter/material.dart';
import '../constants/theme.dart';

/// Date divider widget for chat messages — mirrors ArkTS date separators
class DateDivider extends StatelessWidget {
  final int timestamp;
  final int? previousTimestamp;

  const DateDivider({super.key, required this.timestamp, this.previousTimestamp});

  @override
  Widget build(BuildContext context) {
    final show = _shouldShowDivider();
    if (!show) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.surface1(context),
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Text(
            _formatDate(),
            style: TextStyle(
              fontSize: AppFontSize.xxs,
              color: AppColors.foregroundM(context),
            ),
          ),
        ),
      ),
    );
  }

  bool _shouldShowDivider() {
    if (previousTimestamp == null) return true;
    final prev = DateTime.fromMillisecondsSinceEpoch(previousTimestamp!);
    final curr = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return prev.day != curr.day || prev.month != curr.month || prev.year != curr.year;
  }

  String _formatDate() {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final msgDate = DateTime(date.year, date.month, date.day);

    if (msgDate == today) return 'Today';
    if (msgDate == yesterday) return 'Yesterday';
    return '${date.month}/${date.day}';
  }
}
