import 'package:flutter/material.dart';

import '../constants/theme.dart';
import '../models/ws_protocol.dart';

class PermissionSheetWidget extends StatelessWidget {
  final PendingPermission permission;
  final void Function(String optionId) onSelect;

  const PermissionSheetWidget({
    super.key,
    required this.permission,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.md, AppSpacing.xl, AppSpacing.lg),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('权限请求', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.sm),
          Text(
            permission.toolCall,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.foregroundMuted,
                ),
          ),
          const SizedBox(height: AppSpacing.md),
          ...permission.options.map((opt) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: SizedBox(
                  width: double.infinity,
                  child: Material(
                    color: AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      onTap: () => onSelect(opt.optionId),
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: Text(
                          opt.name,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ),
                    ),
                  ),
                ),
              )),
        ],
      ),
    );
  }
}
