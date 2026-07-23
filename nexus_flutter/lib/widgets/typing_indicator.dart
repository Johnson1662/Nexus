import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../constants/theme.dart';

/// A minimalist, elegant animated typing/thinking indicator for Agent responses.
/// Renders 3 subtle pulsing dots at the very end of the active turn stream.
class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key});

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final dotBaseColor = AppColors.foregroundCtx(context);

    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.sm,
        horizontal: AppSpacing.xs,
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: dark
                ? const Color(0x18FFFFFF)
                : const Color(0x0A000000),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: dark
                  ? Colors.white.withOpacity(0.06)
                  : Colors.black.withOpacity(0.04),
              width: 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(3, (index) {
              return AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  // Phase delay per dot for wave effect
                  final delay = index * 0.22;
                  final value = math.sin((_controller.value * 2 * math.pi) - delay);
                  // Map sine [-1, 1] → [0, 1]
                  final normalized = (value + 1) / 2;

                  final opacity = 0.3 + (normalized * 0.7);
                  final scale = 0.85 + (normalized * 0.3);

                  return Container(
                    margin: EdgeInsets.only(
                      right: index < 2 ? AppSpacing.xs : 0,
                    ),
                    child: Transform.scale(
                      scale: scale,
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: dotBaseColor.withOpacity(opacity),
                        ),
                      ),
                    ),
                  );
                },
              );
            }),
          ),
        ),
      ),
    );
  }
}
