import 'package:flutter/material.dart';
import '../constants/theme.dart';
import '../models/ws_protocol.dart';

/// Plan view widget — shows plan entries with status icons
class PlanView extends StatelessWidget {
  final List<PlanEntry> entries;

  const PlanView({super.key, required this.entries});

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surface1(context),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: entries.map((entry) {
          IconData icon;
          Color color;
          switch (entry.status) {
            case 'completed':
              icon = Icons.check_circle_outline;
              color = AppColors.success;
              break;
            case 'in_progress':
              icon = Icons.sync;
              color = AppColors.accent;
              break;
            default:
              icon = Icons.radio_button_unchecked;
              color = AppColors.foregroundM(context);
          }
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    entry.text,
                    style: TextStyle(
                      fontSize: AppFontSize.sm,
                      color: entry.status == 'completed'
                          ? AppColors.foregroundM(context)
                          : AppColors.foregroundC(context),
                      fontWeight: entry.status == 'in_progress' ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
