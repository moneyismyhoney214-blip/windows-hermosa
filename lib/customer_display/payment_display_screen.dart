import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'display_provider.dart';

/// Payment Display Screen for CDS
/// This is shown on the Customer Display when payment is initiated
class PaymentDisplayScreen extends StatefulWidget {
  const PaymentDisplayScreen({super.key});

  @override
  State<PaymentDisplayScreen> createState() => _PaymentDisplayScreenState();
}

class _PaymentDisplayScreenState extends State<PaymentDisplayScreen> {
  VideoPlayerController? _successController;
  bool _successAnimationReady = false;
  bool _hasPinnedLastFrame = false;

  @override
  void initState() {
    super.initState();
    _initSuccessAnimation();
  }

  Future<void> _initSuccessAnimation() async {
    final candidateAssets = <String>[
      'assets/animation/Success.webm',
      'assets/animation/Success.mp4',
    ];
    for (final assetPath in candidateAssets) {
      try {
        final controller = VideoPlayerController.asset(assetPath);
        await controller.initialize();
        controller
          ..setLooping(false)
          ..setVolume(0)
          ..play();
        controller.addListener(() async {
          if (_hasPinnedLastFrame) return;
          if (!controller.value.isInitialized) return;
          final duration = controller.value.duration;
          if (duration == Duration.zero) return;
          final position = controller.value.position;
          final reachedEnd =
              position >= duration - const Duration(milliseconds: 50);
          if (!reachedEnd) return;
          _hasPinnedLastFrame = true;
          await controller.pause();
          await controller.seekTo(duration);
        });
        if (!mounted) {
          await controller.dispose();
          return;
        }
        setState(() {
          _successController = controller;
          _successAnimationReady = true;
        });
        return;
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() => _successAnimationReady = false);
  }

  @override
  void dispose() {
    _successController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DisplayProvider>(
      builder: (context, provider, child) {
        final paymentData = provider.paymentData;
        final amount = _parseAmount(paymentData['amount']);
        final orderNumber = paymentData['orderNumber'] ?? '';

        return Scaffold(
          backgroundColor: const Color(0xFF0F172A),
          body: SafeArea(
            child: Column(
              children: [
                // Header
                _buildHeader(amount, orderNumber),

                // Main Content
                Expanded(child: _buildContent(provider)),

                // Footer
                _buildFooter(provider),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(double amount, String orderNumber) {
    return Container(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          // Logo/Icon
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF58220).withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              LucideIcons.creditCard,
              color: Color(0xFFF58220),
              size: 48,
            ),
          ),

          const SizedBox(height: 24),

          // Amount
          Text(
            '${amount.toStringAsFixed(2)} ر.س',
            style: GoogleFonts.tajawal(
              fontSize: 64,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),

          const SizedBox(height: 8),

          // Order Number
          if (orderNumber.isNotEmpty)
            Text(
              'طلب رقم: $orderNumber',
              style: GoogleFonts.tajawal(fontSize: 18, color: Colors.white60),
            ),
        ],
      ),
    );
  }

  double _parseAmount(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  Widget _buildContent(DisplayProvider provider) {
    switch (provider.paymentStatus) {
      case PaymentDisplayStatus.processing:
        return _buildProcessingView();
      case PaymentDisplayStatus.success:
        return _buildSuccessView();
      case PaymentDisplayStatus.failed:
        return _buildFailedView(provider);
      case PaymentDisplayStatus.cancelled:
        return _buildCancelledView();
      case PaymentDisplayStatus.idle:
        return _buildIdleView();
    }
  }

  Widget _buildProcessingView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Animated NFC icon
          Container(
            width: 150,
            height: 150,
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.2),
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFF10B981).withValues(alpha: 0.5),
                width: 3,
              ),
            ),
            child: const Icon(
              LucideIcons.nfc,
              color: Color(0xFF10B981),
              size: 72,
            ),
          ),

          const SizedBox(height: 48),

          Text(
            'اقرب البطاقة أو الجوال',
            style: GoogleFonts.tajawal(
              fontSize: 36,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),

          const SizedBox(height: 16),

          Text(
            'لإتمام عملية الدفع',
            style: GoogleFonts.tajawal(fontSize: 20, color: Colors.white60),
          ),

          const SizedBox(height: 48),

          // Processing indicator
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildDot(0),
              const SizedBox(width: 8),
              _buildDot(1),
              const SizedBox(width: 8),
              _buildDot(2),
            ],
          ),

          const SizedBox(height: 24),

          Text(
            'جاري معالجة الدفع...',
            style: GoogleFonts.tajawal(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDot(int index) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: const Color(0xFFF58220),
        shape: BoxShape.circle,
      ),
    );
  }

  Widget _buildSuccessView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Success icon
          Container(
            width: 150,
            height: 150,
            decoration: const BoxDecoration(
              color: Color(0xFF10B981),
              shape: BoxShape.circle,
            ),
            child: ClipOval(
              child: _successAnimationReady && _successController != null
                  ? FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: _successController!.value.size.width,
                        height: _successController!.value.size.height,
                        child: VideoPlayer(_successController!),
                      ),
                    )
                  : const Icon(
                      LucideIcons.check,
                      color: Colors.white,
                      size: 80,
                    ),
            ),
          ),

          const SizedBox(height: 48),

          Text(
            'تم الدفع بنجاح!',
            style: GoogleFonts.tajawal(
              fontSize: 48,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),

          const SizedBox(height: 16),

          Text(
            'شكراً لاختيارك هيرموسا',
            style: GoogleFonts.tajawal(fontSize: 20, color: Colors.white60),
          ),
        ],
      ),
    );
  }

  Widget _buildFailedView(DisplayProvider provider) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Error icon
          Container(
            width: 150,
            height: 150,
            decoration: BoxDecoration(
              color: const Color(0xFFEF4444).withValues(alpha: 0.2),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFEF4444), width: 3),
            ),
            child: const Icon(
              LucideIcons.xCircle,
              color: Color(0xFFEF4444),
              size: 80,
            ),
          ),

          const SizedBox(height: 48),

          Text(
            'فشلت عملية الدفع',
            style: GoogleFonts.tajawal(
              fontSize: 36,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),

          const SizedBox(height: 16),

          if (provider.paymentMessage != null)
            Text(
              provider.paymentMessage!,
              textAlign: TextAlign.center,
              style: GoogleFonts.tajawal(fontSize: 18, color: Colors.white60),
            ),
        ],
      ),
    );
  }

  Widget _buildCancelledView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Cancelled icon
          Container(
            width: 150,
            height: 150,
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(LucideIcons.ban, color: Colors.grey, size: 80),
          ),

          const SizedBox(height: 48),

          Text(
            'تم إلغاء الدفع',
            style: GoogleFonts.tajawal(
              fontSize: 36,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),

          const SizedBox(height: 16),

          Text(
            'يمكنك المحاولة مرة أخرى',
            style: GoogleFonts.tajawal(fontSize: 18, color: Colors.white60),
          ),
        ],
      ),
    );
  }

  Widget _buildIdleView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            LucideIcons.creditCard,
            size: 80,
            color: Colors.white.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 24),
          Text(
            'بانتظار بدء الدفع',
            style: GoogleFonts.tajawal(
              fontSize: 24,
              color: Colors.white.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(DisplayProvider provider) {
    return Container(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          // Payment method icons
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildPaymentIcon(LucideIcons.nfc, 'Tap to Pay'),
              const SizedBox(width: 24),
              _buildPaymentIcon(LucideIcons.creditCard, 'Card'),
              const SizedBox(width: 24),
              _buildPaymentIcon(LucideIcons.smartphone, 'Mobile'),
            ],
          ),

          const SizedBox(height: 24),

          // Security message
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                LucideIcons.shieldCheck,
                color: Color(0xFF10B981),
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'دفع آمن ومحمي',
                style: GoogleFonts.tajawal(
                  fontSize: 14,
                  color: Colors.white.withValues(alpha: 0.4),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentIcon(IconData icon, String label) {
    return Column(
      children: [
        Icon(icon, color: Colors.white.withValues(alpha: 0.3), size: 32),
        const SizedBox(height: 4),
        Text(
          label,
          style: GoogleFonts.tajawal(
            fontSize: 12,
            color: Colors.white.withValues(alpha: 0.3),
          ),
        ),
      ],
    );
  }
}
