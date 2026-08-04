import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../constants/theme.dart';

/// Three subtle pulsing dots at the end of the active turn stream.
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
    final dotColor = AppColors.foregroundM(context);

    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.sm,
        horizontal: AppSpacing.xs,
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (index) {
                final phase = (_controller.value * 2 * math.pi) - index * 0.55;
                final strength = (math.sin(phase) + 1) / 2;

                return Padding(
                  padding: EdgeInsets.only(
                    right: index < 2 ? AppSpacing.xs : 0,
                  ),
                  child: Transform.scale(
                    scale: 0.82 + strength * 0.18,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: dotColor.withValues(
                          alpha: 0.32 + strength * 0.52,
                        ),
                      ),
                      child: const SizedBox(width: 6, height: 6),
                    ),
                  ),
                );
              }),
            );
          },
        ),
      ),
    );
  }
}
