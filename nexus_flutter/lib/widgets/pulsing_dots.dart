import 'package:flutter/material.dart';
import '../constants/theme.dart';

/// Pulsing dots animation for streaming/loading state
class PulsingDots extends StatefulWidget {
  final Color? color;
  final double size;

  const PulsingDots({super.key, this.color, this.size = 6});

  @override
  State<PulsingDots> createState() => _PulsingDotsState();
}

class _PulsingDotsState extends State<PulsingDots> with SingleTickerProviderStateMixin {
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
    final color = widget.color ?? AppColors.foregroundM(context);
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) {
        final t = _controller.value;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final phase = (t + i * 0.33) % 1.0;
            final opacity = phase < 0.5 ? phase * 2.0 : (1.0 - phase) * 2.0;
            return Padding(
              padding: EdgeInsets.only(left: i == 0 ? 0 : 4),
              child: Opacity(
                opacity: 0.3 + opacity * 0.7,
                child: Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
