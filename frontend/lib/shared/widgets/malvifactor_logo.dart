import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:malvifactor/core/theme/app_theme.dart';

class MalviFactorLogo extends StatelessWidget {
  const MalviFactorLogo({
    super.key,
    this.size = 64,
    this.progress = 1.0,
  });

  final double size;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _MalviFactorLogoPainter(
          progress: progress.clamp(0.0, 1.0),
        ),
      ),
    );
  }
}

class MalviFactorWordmark extends StatelessWidget {
  const MalviFactorWordmark({
    super.key,
    this.fontSize = 26,
  });

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
          color: AppColors.textPrimary,
        ),
        children: const [
          TextSpan(text: 'MALVI'),
          TextSpan(
            text: 'FACTOR',
            style: TextStyle(color: AppColors.calories),
          ),
        ],
      ),
    );
  }
}

class _MalviFactorLogoPainter extends CustomPainter {
  _MalviFactorLogoPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final center = Offset(cx, cy);
    final radius = size.width * 0.42;
    final ringStroke = size.width * 0.085;
    final rect = Rect.fromCircle(center: center, radius: radius);

    const arcColors = [
      AppColors.calories,
      AppColors.protein,
      AppColors.fat,
      AppColors.carbs,
    ];

    const gapRad = 22.0 * math.pi / 180.0;
    const spanRad = (2 * math.pi - 4 * gapRad) / 4.0;
    const startBase = -math.pi / 2 + gapRad / 2;

    final ringProgress = (progress * 1.25).clamp(0.0, 1.0);
    for (var i = 0; i < 4; i++) {
      final start = startBase + i * (spanRad + gapRad);
      final paint = Paint()
        ..color = arcColors[i]
        ..style = PaintingStyle.stroke
        ..strokeWidth = ringStroke
        ..strokeCap = StrokeCap.round;

      if (ringProgress > 0) {
        canvas.drawArc(
          rect,
          start,
          spanRad * ringProgress,
          false,
          paint,
        );
      }
    }

    final mProgress = ((progress - 0.15) / 0.85).clamp(0.0, 1.0);
    if (mProgress <= 0) return;

    final mw = size.width * 0.40;
    final mh = size.height * 0.34;
    final mStroke = size.width * 0.092;

    final leftX = cx - mw / 2;
    final rightX = cx + mw / 2;
    final topY = cy - mh / 2;
    final botY = cy + mh / 2;
    final midY = cy + mh * 0.08;

    final path = Path()
      ..moveTo(leftX, botY)
      ..lineTo(leftX, topY)
      ..lineTo(cx, midY)
      ..lineTo(rightX, topY)
      ..lineTo(rightX, botY);

    final mPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [AppColors.calories, AppColors.weight],
      ).createShader(Rect.fromLTRB(leftX, topY, rightX, botY))
      ..style = PaintingStyle.stroke
      ..strokeWidth = mStroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final metrics = path.computeMetrics().first;
    final partial = metrics.extractPath(0, metrics.length * mProgress);
    canvas.drawPath(partial, mPaint);
  }

  @override
  bool shouldRepaint(covariant _MalviFactorLogoPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
