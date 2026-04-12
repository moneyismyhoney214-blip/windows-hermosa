import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

class QRScannerScreen extends StatefulWidget {
  final Function(String ip, int port, String mode) onConnect;

  const QRScannerScreen({
    Key? key,
    required this.onConnect,
  }) : super(key: key);

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  bool _isScanning = true;
  String? _errorMessage;
  MobileScannerController? _controller;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (!_isScanning) return;

    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null || barcode.rawValue == null) return;

    try {
      final data = jsonDecode(barcode.rawValue!);

      // التحقق من أن الكود من تطبيق Display App
      if (data['app'] != 'hermosa_pos_display') {
        setState(() {
          _errorMessage = 'كود QR غير صالح';
        });
        return;
      }

      final ip = data['ip'] as String;
      final port = data['port'] as int;
      final mode = data['mode'] as String;

      setState(() {
        _isScanning = false;
      });

      _controller?.stop();

      // إغلاق الماسح والاتصال
      Navigator.pop(context);
      widget.onConnect(ip, port, mode);
    } catch (e) {
      setState(() {
        _errorMessage = 'تعذر قراءة الكود';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'مسح QR Code',
          style: GoogleFonts.tajawal(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: () => _controller?.toggleTorch(),
            icon: ValueListenableBuilder(
              valueListenable: _controller!.torchState,
              builder: (context, state, child) {
                return Icon(
                  state == TorchState.off ? Icons.flash_off : Icons.flash_on,
                );
              },
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // رسالة الخطأ
          if (_errorMessage != null)
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error, color: Colors.red),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: GoogleFonts.tajawal(color: Colors.red),
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      setState(() {
                        _errorMessage = null;
                        _isScanning = true;
                      });
                    },
                    icon: const Icon(Icons.refresh, color: Colors.red),
                  ),
                ],
              ),
            ),

          // الماسح الضوئي
          Expanded(
            child: MobileScanner(
              controller: _controller!,
              onDetect: _onDetect,
              overlay: Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Colors.white,
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                margin: const EdgeInsets.all(48),
                child: const Center(
                  child: Icon(
                    Icons.qr_code_scanner,
                    color: Colors.white54,
                    size: 80,
                  ),
                ),
              ),
            ),
          ),

          // تعليمات
          Container(
            padding: const EdgeInsets.all(24),
            color: const Color(0xFFF58220),
            child: Row(
              children: [
                const Icon(
                  LucideIcons.info,
                  color: Colors.white,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'وجه الكاميرا نحو QR Code في شاشة العرض',
                    style: GoogleFonts.tajawal(
                      color: Colors.white,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
