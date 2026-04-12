import 'dart:math';
import 'package:flutter/material.dart';

class Particles extends StatefulWidget {
  const Particles({Key? key}) : super(key: key);

  @override
  State<Particles> createState() => _ParticlesState();
}

class _ParticlesState extends State<Particles>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<ParticleModel> particles = [];
  final Random random = Random();

  @override
  void initState() {
    super.initState();
    for (int i = 0; i < 40; i++) {
      particles.add(ParticleModel(random));
    }
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )
      ..addListener(() {
        setState(() {
          for (var p in particles) {
            p.update();
          }
        });
      })
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: ParticlePainter(particles),
      size: Size.infinite,
    );
  }
}

class ParticleModel {
  double x;
  double y;
  double size;
  double speed;
  double opacity;
  Random random;

  ParticleModel(this.random)
      : x = random.nextDouble(),
        y = random.nextDouble(),
        size = random.nextDouble() * 3 + 1,
        speed = random.nextDouble() * 0.002 + 0.001,
        opacity = random.nextDouble() * 0.4 + 0.1;

  void update() {
    y -= speed;
    if (y < 0) {
      y = 1.0;
      x = random.nextDouble();
    }
  }
}

class ParticlePainter extends CustomPainter {
  final List<ParticleModel> particles;

  ParticlePainter(this.particles);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.orange.withValues(alpha: 0.3);

    for (var p in particles) {
      canvas.drawCircle(
        Offset(p.x * size.width, p.y * size.height),
        p.size,
        paint..color = Colors.orange.withValues(alpha: p.opacity),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
