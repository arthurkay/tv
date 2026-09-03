import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The Vieo mark: a play triangle with two broadcast arcs off its apex.
///
/// Geometry is authored in a 100 x 100 space and scaled to the requested
/// height. The mark is wider than it is tall, so callers size it by height and
/// ask [widthFor] for the matching width.
class VieoMark extends StatelessWidget {
  /// Tight bounds of the full mark in the authored space: x 14..83.5,
  /// y 22.9..77.1. The reduced mark is narrower and simply carries a little
  /// more right margin, which keeps layout stable across the switch.
  static const _originX = 14.0;
  static const _originY = 22.9;
  static const _boxWidth = 69.5;
  static const _boxHeight = 54.2;

  /// Below this height the outer arc is dropped and the remaining stroke
  /// thickens: at small sizes two thin arcs merge into a smudge.
  static const reducedBelow = 32.0;

  final double height;
  final Color color;

  const VieoMark({
    super.key,
    this.height = 40,
    this.color = AppTheme.textPrimary,
  });

  static double widthFor(double height) => height * _boxWidth / _boxHeight;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widthFor(height),
      height: height,
      child: CustomPaint(
        painter: _VieoMarkPainter(
          color: color,
          reduced: height < reducedBelow,
        ),
      ),
    );
  }
}

class _VieoMarkPainter extends CustomPainter {
  final Color color;
  final bool reduced;

  const _VieoMarkPainter({required this.color, required this.reduced});

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.height / VieoMark._boxHeight;
    Offset at(double x, double y) => Offset(
          (x - VieoMark._originX) * scale,
          (y - VieoMark._originY) * scale,
        );

    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    if (reduced) {
      canvas.drawPath(
        Path()
          ..moveTo(at(17, 25).dx, at(17, 25).dy)
          ..lineTo(at(57, 50).dx, at(57, 50).dy)
          ..lineTo(at(17, 75).dx, at(17, 75).dy)
          ..close(),
        fill,
      );
      _arc(canvas, at(57, 50), 15 * scale, 55, 9.5 * scale);
      return;
    }

    canvas.drawPath(
      Path()
        ..moveTo(at(14, 24).dx, at(14, 24).dy)
        ..lineTo(at(50, 50).dx, at(50, 50).dy)
        ..lineTo(at(14, 76).dx, at(14, 76).dy)
        ..close(),
      fill,
    );
    // 15 and 30 against a 7.0 stroke: the clear gap stays wider than the
    // strokes, so the arcs never merge into a blob.
    _arc(canvas, at(50, 50), 15 * scale, 52, 7.0 * scale);
    _arc(canvas, at(50, 50), 30 * scale, 52, 7.0 * scale);
  }

  /// An arc centred on the triangle's apex, opening to the right, spanning
  /// [halfAngleDegrees] either side of horizontal.
  void _arc(
    Canvas canvas,
    Offset center,
    double radius,
    double halfAngleDegrees,
    double strokeWidth,
  ) {
    final half = halfAngleDegrees * math.pi / 180;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -half,
      half * 2,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(covariant _VieoMarkPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.reduced != reduced;
}
