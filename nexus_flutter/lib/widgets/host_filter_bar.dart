import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/theme.dart';
import '../models/device_entry.dart';
import '../services/host_store.dart';

class HostFilterBar extends StatelessWidget {
  final List<DeviceEntry> devices;
  final String selectedKey;
  final int statusRevision;
  final void Function(String key) onSelect;

  const HostFilterBar({
    super.key,
    required this.devices,
    required this.selectedKey,
    required this.statusRevision,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    if (devices.isEmpty) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        itemCount: devices.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, index) {
          final device = devices[index];
          final hostStore = context.watch<HostStore>();
          final phase = hostStore.getPhase(device.hostId);
          final isSelected = device.hostId == selectedKey || device.name == selectedKey;

          Color dotColor;
          if (phase == 'online') {
            dotColor = AppColors.success;
          } else if (phase == 'connecting' || phase == 'reconnecting' || phase == 'waiting_host') {
            dotColor = AppColors.warning;
          } else {
            dotColor = AppColors.foregroundLight;
          }

          return FilterChip(
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: dotColor,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  device.name.length > 16
                      ? '${device.name.substring(0, 16)}…'
                      : device.name,
                ),
              ],
            ),
            selected: isSelected,
            onSelected: (_) => onSelect(device.hostId),
          );
        },
      ),
    );
  }
}
