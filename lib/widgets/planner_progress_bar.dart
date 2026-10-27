import 'dart:math' as math;

import 'package:flutter/material.dart';

Color plannerProgressColor(double progress) {
  if (progress > 1) return const Color(0xFFDC2626);
  if (progress >= 0.8) return const Color(0xFFF59E0B);
  return const Color(0xFF16A34A);
}

double plannerProgressFillWidth({
  required double progress,
  required double availableWidth,
  double minimumVisibleWidth = 4,
}) {
  if (progress <= 0 || availableWidth <= 0) return 0;
  if (progress > 1) return availableWidth;
  return math.min(
    availableWidth,
    math.max(minimumVisibleWidth, availableWidth * progress),
  );
}

class PlannerProgressBar extends StatelessWidget {
  const PlannerProgressBar({
    super.key,
    required this.progress,
    required this.trackColor,
    this.height = 6,
    this.animate = false,
  });

  final double progress;
  final Color trackColor;
  final double height;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    if (animate && !MediaQuery.disableAnimationsOf(context)) {
      return TweenAnimationBuilder<double>(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        tween: Tween(end: progress),
        builder: (context, value, _) => _bar(value),
      );
    }
    return _bar(progress);
  }

  Widget _bar(double value) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final fillWidth = plannerProgressFillWidth(
            progress: value,
            availableWidth: constraints.maxWidth,
          );
          return ClipRRect(
            borderRadius: BorderRadius.circular(height / 2),
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: trackColor),
                if (fillWidth > 0)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      width: fillWidth,
                      color: plannerProgressColor(value),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
