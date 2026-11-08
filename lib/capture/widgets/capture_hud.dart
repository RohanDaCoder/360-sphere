import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../capture_session_controller.dart';
import '../stitching/equirect_stitcher.dart' show CoverageTracker;

/// Ring + reticle HUD showing yaw coverage, pitch and the next-gap arrow —
/// the same "sweep guide" concept as the original app's capture screen.
class CaptureHud extends StatelessWidget {
  const CaptureHud({super.key, required this.controller});

  final CaptureSessionController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final (heading, elevation) = controller.orientation.cameraAim;
        return IgnorePointer(
          child: Stack(
            children: [
              Center(
                  child: _Reticle(
                      elevation: elevation,
                      heading: heading,
                      controller: controller)),
            ],
          ),
        );
      },
    );
  }
}

class _Reticle extends StatelessWidget {
  const _Reticle(
      {required this.elevation,
      required this.heading,
      required this.controller});

  final double elevation;
  final double heading;
  final CaptureSessionController controller;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final ringRadius = (size.shortestSide * 0.34).clamp(110.0, 210.0);
    final coverage = controller.coverage;
    final gap = controller.nextGap;

    return CustomPaint(
      size: Size.square(ringRadius * 2),
      painter: _HudPainter(
        ringRadius: ringRadius,
        heading: heading,
        elevation: elevation,
        coverage: coverage,
        gap: gap,
        capturing: controller.phase == CapturePhase.capturing,
      ),
    );
  }
}

class _HudPainter extends CustomPainter {
  _HudPainter({
    required this.ringRadius,
    required this.heading,
    required this.elevation,
    required this.coverage,
    required this.gap,
    required this.capturing,
  });

  final double ringRadius;
  final double heading;
  final double elevation;
  final CoverageTracker? coverage;
  final (double, double)? gap;
  final bool capturing;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const track = Color(0x33FFFFFF);
    final active =
        capturing ? const Color(0xFFE64A19) : const Color(0xAAFFFFFF);

    // Yaw coverage ring (top view compass).
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..color = track;
    canvas.drawCircle(center, ringRadius, ringPaint);

    if (coverage != null) {
      final covPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..strokeCap = StrokeCap.butt
        ..color = const Color(0xE6E64A19);
      final lonBins = coverage!.lonBins;
      final binArc = 2 * math.pi / lonBins;
      for (var i = 0; i < lonBins; i++) {
        if (!coverage!.isLonBinCovered(i)) continue;
        final rect = Rect.fromCircle(center: center, radius: ringRadius);
        // Bin i spans lon in [-π + i·Δ, -π + (i+1)·Δ); screen angle measured
        // clockwise from north (up).
        final startLon = -math.pi + i * binArc;
        final a0 = startLon - math.pi / 2;
        canvas.drawArc(rect, a0, binArc, false, covPaint);
      }
    }

    // Heading marker on the ring.
    final hdg = heading - math.pi / 2;
    final marker = Offset(
      center.dx + ringRadius * math.cos(hdg),
      center.dy + ringRadius * math.sin(hdg),
    );
    canvas.drawCircle(marker, 7, Paint()..color = active);

    // Center reticle: crosshair + elevation bar.
    final cross = Paint()
      ..color = active
      ..strokeWidth = 2;
    canvas.drawLine(
        center - const Offset(16, 0), center + const Offset(16, 0), cross);
    canvas.drawLine(
        center - const Offset(0, 16), center + const Offset(0, 16), cross);

    // Next-gap arrow.
    if (gap != null) {
      final (gapHeading, _) = gap!;
      final dLon = _angleDelta(gapHeading, heading);
      final arrowAngle = hdg + dLon;
      final tip = Offset(
        center.dx + (ringRadius - 26) * math.cos(arrowAngle),
        center.dy + (ringRadius - 26) * math.sin(arrowAngle),
      );
      _drawArrow(canvas, center, tip, const Color(0xFFFFB300));
    }
  }

  static double _angleDelta(double target, double current) {
    var d = target - current;
    while (d > math.pi) {
      d -= 2 * math.pi;
    }
    while (d < -math.pi) {
      d += 2 * math.pi;
    }
    return d;
  }

  static void _drawArrow(Canvas canvas, Offset from, Offset to, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(from, to, paint);
    final dir = (to - from);
    final len = dir.distance;
    if (len < 1) return;
    final unit = Offset(dir.dx / len, dir.dy / len);
    final perp = Offset(-unit.dy, unit.dx);
    final head = to;
    final p1 = head - unit * 14 + perp * 8;
    final p2 = head - unit * 14 - perp * 8;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    canvas.drawLine(head, p1, fill);
    canvas.drawLine(head, p2, fill);
  }

  @override
  bool shouldRepaint(covariant _HudPainter old) =>
      old.heading != heading ||
      old.elevation != elevation ||
      old.capturing != capturing ||
      old.gap != gap ||
      old.coverage != coverage;
}
