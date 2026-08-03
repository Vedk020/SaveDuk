import 'dart:math';
import 'package:flutter/material.dart';
import '../config/constants.dart';

/// Animated circular progress indicator with gradient
class GradientProgressIndicator extends StatefulWidget {
  final double progress; // 0.0 - 1.0, or -1 for indeterminate
  final double size;
  final double strokeWidth;
  final Widget? child;

  const GradientProgressIndicator({
    super.key,
    required this.progress,
    this.size = 80,
    this.strokeWidth = 4,
    this.child,
  });

  @override
  State<GradientProgressIndicator> createState() =>
      _GradientProgressIndicatorState();
}

class _GradientProgressIndicatorState extends State<GradientProgressIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    if (widget.progress < 0) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(GradientProgressIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.progress < 0 && !_controller.isAnimating) {
      _controller.repeat();
    } else if (widget.progress >= 0 && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: CustomPaint(
            painter: _ProgressPainter(
              progress: widget.progress >= 0 ? widget.progress : 0.3,
              strokeWidth: widget.strokeWidth,
              rotation: widget.progress < 0 ? _controller.value * 2 * pi : 0,
            ),
            child: Center(child: widget.child),
          ),
        );
      },
    );
  }
}

class _ProgressPainter extends CustomPainter {
  final double progress;
  final double strokeWidth;
  final double rotation;

  _ProgressPainter({
    required this.progress,
    required this.strokeWidth,
    this.rotation = 0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Background track
    final bgPaint = Paint()
      ..color = AppColors.surface
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, bgPaint);

    final progressPaint = Paint()
      ..color = AppColors.textPrimary
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      rect,
      -pi / 2 + rotation,
      2 * pi * progress,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(_ProgressPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.rotation != rotation;
  }
}
