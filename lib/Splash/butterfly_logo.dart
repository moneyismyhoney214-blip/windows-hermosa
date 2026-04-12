import 'package:flutter/material.dart';

class ButterflyLogo extends StatefulWidget {
  final double size;

  const ButterflyLogo({super.key, this.size = 300});

  @override
  State<ButterflyLogo> createState() => _ButterflyLogoState();
}

class _ButterflyLogoState extends State<ButterflyLogo>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _drawAnimation;
  late Animation<double> _fillAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );

    _drawAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.7, curve: Curves.easeOutCubic),
      ),
    );

    _fillAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.5, 1.0, curve: Curves.easeInOut),
      ),
    );

    _controller.forward();
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
        return CustomPaint(
          size: Size(widget.size, widget.size),
          painter: ButterflyPainter(
            drawProgress: _drawAnimation.value,
            fillProgress: _fillAnimation.value,
          ),
        );
      },
    );
  }
}

class ButterflyPainter extends CustomPainter {
  final double drawProgress;
  final double fillProgress;

  ButterflyPainter({required this.drawProgress, required this.fillProgress});

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 240.0;
    canvas.scale(scale, scale);

    const Rect bounds = Rect.fromLTWH(0, 0, 240, 240);
    const gradient = LinearGradient(
      colors: [Color(0xFFFDBA74), Color(0xFFF97316), Color(0xFFEA580C)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );

    final strokePaint = Paint()
      ..shader = gradient.createShader(bounds)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final antennaPaint = Paint()
      ..shader = gradient.createShader(bounds)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint()
      ..shader = gradient.createShader(bounds)
      ..style = PaintingStyle.fill
      ..color = Colors.white.withValues(alpha: fillProgress);

    // Original custom logo shape
    final bottomWing = Path()
      ..moveTo(95, 165)
      ..cubicTo(130, 150, 160, 155, 185, 175)
      ..cubicTo(150, 190, 120, 185, 110, 205)
      ..cubicTo(105, 190, 100, 175, 95, 165)
      ..close();

    final body = Path()
      ..moveTo(80, 145)
      ..cubicTo(75, 160, 85, 190, 115, 210)
      ..cubicTo(105, 195, 95, 170, 90, 150)
      ..cubicTo(90, 145, 85, 142, 80, 145)
      ..close();

    final topAntenna = Path()
      ..moveTo(55, 115)
      ..quadraticBezierTo(70, 130, 80, 138);

    final bottomAntenna = Path()
      ..moveTo(45, 128)
      ..quadraticBezierTo(60, 140, 73, 148);

    void drawAnimatedSegment(Path path, Paint paint, double start, double end) {
      final local = ((drawProgress - start) / (end - start)).clamp(0.0, 1.0);
      if (local <= 0) return;
      for (final metric in path.computeMetrics()) {
        final segment = metric.extractPath(0, metric.length * local);
        canvas.drawPath(segment, paint);
      }
    }

    if (fillProgress > 0) {
      canvas.drawPath(bottomWing, fillPaint);
      canvas.drawPath(body, fillPaint);
    }

    // Keep progressive animation while using your original paths
    drawAnimatedSegment(topAntenna, antennaPaint, 0.0, 0.22);
    drawAnimatedSegment(bottomAntenna, antennaPaint, 0.12, 0.34);
    drawAnimatedSegment(body, strokePaint, 0.24, 0.66);
    drawAnimatedSegment(bottomWing, strokePaint, 0.46, 1.00);
  }

  @override
  bool shouldRepaint(covariant ButterflyPainter oldDelegate) {
    return oldDelegate.drawProgress != drawProgress ||
        oldDelegate.fillProgress != fillProgress;
  }
}
