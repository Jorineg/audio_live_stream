import 'package:flutter/material.dart';
import 'dart:math';

class CircularWaveformPainter extends CustomPainter {
  final List<int> samples;
  final Color color;
  final double strokeWidth;
  final bool isMicMuted;

  CircularWaveformPainter({
    required this.samples,
    this.color = Colors.blueAccent,
    this.strokeWidth = 2.0,
    required this.isMicMuted,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (isMicMuted || samples.isEmpty) return;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(center.dx, center.dy);
    final anglePerSample = (2 * pi) / samples.length;

    final path = Path();
    for (int i = 0; i < samples.length; i++) {
      final sample = samples[i];
      final normalizedSample = sample / 32768.0;
      final sampleRadius = radius * 0.7 + (radius * 1.0 * normalizedSample.abs());
      final angle = i * anglePerSample;
      final x = center.dx + sampleRadius * cos(angle);
      final y = center.dy + sampleRadius * sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
} 