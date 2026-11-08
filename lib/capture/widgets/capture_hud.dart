import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../capture_session_controller.dart';
import '../dots/capture_dots.dart';
import '../dots/dot_capture_director.dart';

/// Dot-target capture HUD, ported from the original app's capture screen:
///
///  * a layout of green target dots projected around the current aim
///    (opacity 1 for the active target, 0.4 for the others — the original's
///    `TransformedGreenTarget` worklet);
///  * hold-to-capture: an amber progress ring fills while the aim stays on
///    the target, and the frame is taken automatically when full;
///  * a direction arrow near the reticle that hides close to the target
///    and points straight up/down for the ceiling/floor dots;
///  * the original's target outlines: a rectangle for normal dots and a
///    circle for the polar (ceiling/floor) dots, shown when on aim;
///  * a captured-dots counter and the yaw coverage ring.
class CaptureHud extends StatelessWidget {
  const CaptureHud({super.key, required this.controller});

  final CaptureSessionController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => IgnorePointer(
        child: CustomPaint(
          painter: _DotHudPainter(controller: controller),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _DotHudPainter extends CustomPainter {
  _DotHudPainter({required this.controller});

  final CaptureSessionController controller;

  static const _green = Color(0xFF4CAF50);
  static const _greenDim = Color(0x664CAF50);
  static const _amber = Color(0xFFFFB300);
  static const _track = Color(0x33FFFFFF);

  @override
  void paint(Canvas canvas, Size size) {
    final director = controller.director;
    final center = Offset(size.width / 2, size.height / 2);
    final capturing = controller.phase == CapturePhase.capturing;

    _drawCoverageRing(canvas, size, center);

    if (director == null) return;
    final camYaw = director.camYaw;
    final camPitch = director.camPitch;

    // --- Green target dots (original: opacity 1 target / 0.4 others) ---
    const deltaView2 = 2000.0; // dPitch² + dYaw² visibility radius (original)
    for (var i = 0; i < director.dots.length; i++) {
      final dot = director.dots[i];
      final dYaw = DotCaptureDirector.angleDiff(dot.yawDeg - camYaw);
      final dPitch = dot.pitchDeg - camPitch;
      final vis = dot.isPolar
          ? dPitch * dPitch < deltaView2
          : dPitch * dPitch + dYaw * dYaw < deltaView2;
      if (!vis && i != director.targetId) continue;

      final (tx, ty) = _project(size, dYaw, dPitch, dot.isPolar);
      final pos = center + Offset(tx, ty);
      final status = director.statuses[i];
      final isTarget = i == director.targetId;

      switch (status) {
        case DotStatus.captured:
          _dot(canvas, pos, 9, _green, filled: true);
          _check(canvas, pos, Colors.white);
        case DotStatus.holding when isTarget:
          _dot(canvas, pos, 11, _amber, filled: true);
        case DotStatus.capturing:
          _dot(canvas, pos, 13, _amber, filled: true);
        default:
          _dot(canvas, pos, isTarget ? 11 : 8, isTarget ? _green : _greenDim);
      }
    }

    // --- Hold progress ring around the target dot ---
    final holdFrac = director.holdFraction;
    if (director.holdId >= 0 && holdFrac > 0) {
      final dot = director.dots[director.holdId];
      final dYaw = DotCaptureDirector.angleDiff(dot.yawDeg - camYaw);
      final dPitch = dot.pitchDeg - camPitch;
      final (tx, ty) = _project(size, dYaw, dPitch, dot.isPolar);
      final rect = Rect.fromCircle(center: center + Offset(tx, ty), radius: 18);
      canvas.drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi * holdFrac,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = _amber,
      );
    }

    // --- Target outlines (original: rect 177×255 for normal dots,
    //     circle r 87 for polar dots, scaled by screen ratio) ---
    final ratio = size.shortestSide / 375;
    if (director.nearTarget && director.targetId >= 0) {
      final isPolar = director.dots[director.targetId].isPolar;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = _green.withValues(alpha: 0.9);
      if (isPolar) {
        canvas.drawCircle(center, 87 * ratio, paint);
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: center, width: 177 * ratio, height: 255 * ratio),
            const Radius.circular(12),
          ),
          paint,
        );
      }
    }

    // --- Direction arrow (original: hides near the target, polar up/down) ---
    if (capturing) {
      final (visible, angleDeg) = director.arrowGuidance();
      if (visible) {
        final arrowRadius = 74.0;
        final rad = (angleDeg - 90) * math.pi / 180;
        final tip = center +
            Offset(arrowRadius * math.cos(rad), arrowRadius * math.sin(rad));
        _arrow(canvas, center + Offset.fromDirection(rad, 34), tip);
      }
    }

    // --- Progress counter ---
    final total = director.dots.length;
    final captured = director.capturedCount;
    if (total > 0 && capturing) {
      final tp = TextPainter(
        text: TextSpan(
          text: '$captured / $total',
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas,
          Offset(size.width / 2 - tp.width / 2, size.height - tp.height - 96));
    }
  }

  /// Screen projection of a dot, ported from the original's
  /// `TransformedGreenTarget` worklet: yaw maps with a 1.6× stretch, pitch
  /// maps 1:1, both against an 80-unit viewport; polar dots stay centered.
  (double, double) _project(Size size, double dYaw, double dPitch, bool polar,
      {double stretch = 1.6}) {
    final tx = polar ? 0.0 : dYaw * stretch * size.width / 80;
    final ty = -dPitch * size.height / 80;
    return (tx, ty);
  }

  void _drawCoverageRing(Canvas canvas, Size size, Offset center) {
    final coverage = controller.coverage;
    final radius = (size.shortestSide * 0.34).clamp(110.0, 210.0);
    canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7
          ..color = _track);
    if (coverage == null) return;
    final covPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..color = const Color(0xE64CAF50);
    final lonBins = coverage.lonBins;
    final binArc = 2 * math.pi / lonBins;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final (heading, _) = controller.orientation.cameraAim;
    for (var i = 0; i < lonBins; i++) {
      if (!coverage.isLonBinCovered(i)) continue;
      final startLon = -math.pi + i * binArc;
      canvas.drawArc(
          rect, startLon - math.pi / 2 + heading, binArc, false, covPaint);
    }
  }

  static void _dot(Canvas canvas, Offset c, double r, Color color,
      {bool filled = false}) {
    final p = Paint()
      ..style = filled ? PaintingStyle.fill : PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = color;
    canvas.drawCircle(c, r, p);
  }

  static void _check(Canvas canvas, Offset c, Color color) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(c - const Offset(4, 0), c + const Offset(1, -4), p);
    canvas.drawLine(c + const Offset(1, -4), c + const Offset(6, -8), p);
  }

  static void _arrow(Canvas canvas, Offset from, Offset to) {
    final paint = Paint()
      ..color = _amber
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(from, to, paint);
    final dir = (to - from);
    final len = dir.distance;
    if (len < 1) return;
    final unit = Offset(dir.dx / len, dir.dy / len);
    final perp = Offset(-unit.dy, unit.dx);
    final p1 = to - unit * 12 + perp * 7;
    final p2 = to - unit * 12 - perp * 7;
    canvas.drawLine(to, p1, paint);
    canvas.drawLine(to, p2, paint);
  }

  @override
  bool shouldRepaint(covariant _DotHudPainter old) =>
      old.controller != controller;
}
