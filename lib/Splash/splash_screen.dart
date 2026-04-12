import 'package:flutter/material.dart';
import 'dart:async';
import 'particles.dart';
import 'butterfly_logo.dart';
import '../screens/login_screen.dart';
import '../screens/main_screen.dart';

class SplashScreen extends StatefulWidget {
  final bool isAuthenticated;

  const SplashScreen({super.key, required this.isAuthenticated});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _floatController;
  late AnimationController _textController;
  Timer? _navigationTimer;

  final String text = "HERMOSA";

  @override
  void initState() {
    super.initState();

    // Floating animation for the logo
    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);

    // Staggered text animation
    _textController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    );

    // Start text animation after logo finishes drawing
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) _textController.forward();
    });

    _navigationTimer = Timer(const Duration(milliseconds: 4200), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) =>
              widget.isAuthenticated ? const MainScreen() : const LoginScreen(),
        ),
      );
    });
  }

  @override
  void dispose() {
    _navigationTimer?.cancel();
    _floatController.dispose();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: LayoutBuilder(
          builder: (context, constraints) {
            // حساب الأحجام المتجاوبة بناءً على أصغر بُعد
            final screenWidth = constraints.maxWidth;
            final screenHeight = constraints.maxHeight;
            final minDimension = screenWidth < screenHeight ? screenWidth : screenHeight;
            
            // تصنيف حجم الشاشة
            final isVerySmallScreen = minDimension < 400;
            final isSmallScreen = minDimension < 600;
            final isMediumScreen = minDimension < 800;
            
            // حجم اللوجو (نسبة من أصغر بُعد)
            final logoSize = isVerySmallScreen 
                ? minDimension * 0.35
                : (isSmallScreen 
                    ? minDimension * 0.32
                    : (isMediumScreen ? minDimension * 0.28 : minDimension * 0.25));
            
            // حجم الـ glow
            final glowSize = logoSize * 1.5;
            
            // حجم الخط (نسبة من عرض الشاشة)
            final fontSize = isVerySmallScreen 
                ? screenWidth * 0.09
                : (isSmallScreen 
                    ? screenWidth * 0.08
                    : (isMediumScreen ? screenWidth * 0.06 : screenWidth * 0.05));
            
            // المسافة بين اللوجو والنص
            final spacing = isVerySmallScreen ? 8.0 : (isSmallScreen ? 12.0 : 20.0);
            
            // حجم الحركة العمودية
            final floatOffset = isVerySmallScreen ? 8.0 : (isSmallScreen ? 12.0 : 15.0);
            
            // المسافة بين الحروف
            final letterSpacing = fontSize * 0.12;
            final horizontalPadding = fontSize * 0.03;
            
            return Stack(
              children: [
                // 1. Particles Background
                const Positioned.fill(child: Particles()),

                // 2. Centered Content Container
                Center(
                  child: SingleChildScrollView(
                    physics: const NeverScrollableScrollPhysics(),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: screenHeight,
                        maxWidth: screenWidth,
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Glowing Background Effects
                          Positioned(
                            child: Container(
                              width: glowSize,
                              height: glowSize,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.orange.withValues(alpha: 0.15),
                                    blurRadius: glowSize * 0.3,
                                    spreadRadius: glowSize * 0.125,
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // Main Content
                          Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: screenWidth * 0.05,
                              vertical: screenHeight * 0.05,
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Animated Floating Logo
                                AnimatedBuilder(
                                  animation: _floatController,
                                  builder: (context, child) {
                                    return Transform.translate(
                                      offset: Offset(
                                          0,
                                          -floatOffset *
                                              Curves.easeInOut
                                                  .transform(_floatController.value)),
                                      child: child,
                                    );
                                  },
                                  child: SizedBox(
                                    width: logoSize,
                                    height: logoSize,
                                    child: ButterflyLogo(size: logoSize),
                                  ),
                                ),

                                SizedBox(height: spacing),

                                // Staggered Text Animation
                                ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: screenWidth * 0.9,
                                  ),
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Padding(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: screenWidth * 0.02,
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        mainAxisSize: MainAxisSize.min,
                                        children: List.generate(text.length, (index) {
                                          // Calculate staggered interval for each letter
                                          final double start = index * 0.1;
                                          final double end = (start + 0.4).clamp(0.0, 1.0);

                                          final Animation<double> letterAnimation = CurvedAnimation(
                                            parent: _textController,
                                            curve: Interval(start, end, curve: Curves.easeOutBack),
                                          );

                                          final Animation<double> fadeAnimation = CurvedAnimation(
                                            parent: _textController,
                                            curve: Interval(start, end, curve: Curves.easeIn),
                                          );

                                          return AnimatedBuilder(
                                            animation: _textController,
                                            builder: (context, child) {
                                              return Transform.translate(
                                                offset: Offset(0, fontSize * 0.6 * (1 - letterAnimation.value)),
                                                child: Transform.scale(
                                                  scale: 0.8 + (0.2 * letterAnimation.value),
                                                  child: Opacity(
                                                    opacity: fadeAnimation.value,
                                                    child: child,
                                                  ),
                                                ),
                                              );
                                            },
                                            child: Padding(
                                              padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                                              child: ShaderMask(
                                                shaderCallback: (bounds) => const LinearGradient(
                                                  colors: [
                                                    Color(0xFFFB923C),
                                                    Color(0xFFF97316),
                                                    Color(0xFFEA580C)
                                                  ],
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                ).createShader(bounds),
                                                child: Text(
                                                  text[index],
                                                  style: TextStyle(
                                                    fontSize: fontSize,
                                                    fontWeight: FontWeight.w300,
                                                    letterSpacing: letterSpacing,
                                                    color: Colors.white,
                                                    height: 1.0,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          );
                                        }),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
