import 'dart:ui';

import 'package:flutter/material.dart';

/// Slight backdrop blur used behind dialogs and bottom sheets.
class BarrierBlur extends StatelessWidget {
  const BarrierBlur({
    super.key,
    required this.child,
    this.alignment = Alignment.center,
    this.sigma = 5,
  });

  final Widget child;
  final AlignmentGeometry alignment;
  final double sigma;

  static const defaultSigma = 5.0;

  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
      child: Container(
        width: double.infinity,
        height: double.infinity,
        color: Colors.transparent,
        alignment: alignment,
        child: child,
      ),
    );
  }
}

/// Wraps [child] so popup builders stay concise.
Widget withBarrierBlur(
  Widget child, {
  AlignmentGeometry alignment = Alignment.center,
  double sigma = BarrierBlur.defaultSigma,
}) {
  return BarrierBlur(alignment: alignment, sigma: sigma, child: child);
}
