// ignore_for_file: unused_element, unused_element_parameter, dead_code
part of '../invoice_print_widget.dart';

extension InvoicePrintWidgetFooterQr on InvoicePrintWidget {
  Widget _buildFooter() {
    return Container(
      margin: const EdgeInsets.only(top: 3),
      child: Column(
        children: [
          _buildQrSection(),
          if (returnPolicy != null && returnPolicy!.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 2),
              padding: const EdgeInsets.only(bottom: 2),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.black38)),
              ),
              child: Column(
                children: [
                  Text(
                    _ml(ar: 'سياسة الاسترجاع والاستبدال', en: 'Return Policy', hi: 'वापसी नीति', ur: 'واپسی پالیسی', es: 'Política de Devolución', tr: 'İade Politikası'),
                    style: GoogleFonts.tajawal(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black),
                    textAlign: TextAlign.center,
                  ),
                  if (_sl(ar: 'سياسة الاسترجاع والاستبدال', en: 'Return Policy', hi: 'वापसी नीति', ur: 'واپسی پالیسی', es: 'Política de Devolución', tr: 'İade Politikası').isNotEmpty)
                    Text(
                      _sl(ar: 'سياسة الاسترجاع والاستبدال', en: 'Return Policy', hi: 'वापसी नीति', ur: 'واپسی پالیسی', es: 'Política de Devolución', tr: 'İade Politikası'),
                      style: GoogleFonts.tajawal(
                          fontSize: 13, color: Colors.black, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                  Text(
                    returnPolicy!,
                    style: GoogleFonts.tajawal(
                        fontSize: 15, color: Colors.black, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          Container(
            margin: const EdgeInsets.only(top: 2),
            child: Column(
              children: [
                Text(
                  _ml(ar: 'شكرا لثقتكم بنا', en: 'Thank you for trusting us', hi: 'हम पर भरोसा करने के लिए धन्यवाद', ur: 'ہم پر بھروسہ کرنے کا شکریہ', es: 'Gracias por confiar en nosotros', tr: 'Bize güvendiğiniz için teşekkürler'),
                  style: GoogleFonts.tajawal(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: Colors.black),
                  textAlign: TextAlign.center,
                ),
                if (_sl(ar: 'شكرا لثقتكم بنا', en: 'Thank you for trusting us', hi: 'हम पर भरोसा करने के लिए धन्यवाद', ur: 'ہم پر بھروسہ کرنے کا شکریہ', es: 'Gracias por confiar en nosotros', tr: 'Bize güvendiğiniz için teşekkürler').isNotEmpty)
                  Text(
                    _sl(ar: 'شكرا لثقتكم بنا', en: 'Thank you for trusting us', hi: 'हम पर भरोसा करने के लिए धन्यवाद', ur: 'ہم پر بھروسہ کرنے کا شکریہ', es: 'Gracias por confiar en nosotros', tr: 'Bize güvendiğiniz için teşekkürler'),
                    style: GoogleFonts.tajawal(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.black),
                    textAlign: TextAlign.center,
                  ),

                const SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.black38),
                  ),
                  child: Column(
                    children: [
                      Text(
                        _ml(ar: 'برنامج هيرموسا المحاسبي المتكامل', en: 'Hermosa Accounting Software', hi: 'हरमोसा लेखा सॉफ्टवेयर', ur: 'ہرموسا اکاؤنٹنگ سافٹ ویئر', es: 'Hermosa Contable', tr: 'Hermosa Muhasebe'),
                        style: GoogleFonts.tajawal(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.black),
                        textAlign: TextAlign.center,
                      ),
                      if (_sl(ar: 'برنامج هيرموسا المحاسبي المتكامل', en: 'Hermosa Accounting Software', hi: 'हरमोसा लेखा सॉफ्टवेयर', ur: 'ہرموسا اکاؤنٹنگ سافٹ ویئر', es: 'Hermosa Contable', tr: 'Hermosa Muhasebe').isNotEmpty)
                        Text(
                          _sl(ar: 'برنامج هيرموسا المحاسبي المتكامل', en: 'Hermosa Accounting Software', hi: 'हरमोसा लेखा सॉफ्टवेयर', ur: 'ہرموسا اکاؤنٹنگ سافٹ ویئر', es: 'Hermosa Contable', tr: 'Hermosa Muhasebe'),
                          style: GoogleFonts.tajawal(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.black),
                          textAlign: TextAlign.center,
                        ),
                      Text(
                        'hermosaapp.com',
                        style: GoogleFonts.tajawal(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.black),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQrSection() {
    final zatcaImage = data?.zatcaQrImage?.trim() ?? '';
    final rawQr = data?.qrCodeBase64.trim() ?? '';
    Widget? qrWidget;

    // Highest priority: Generate the QR synchronously to avoid screenshot timing issues
    if (rawQr.isNotEmpty && !rawQr.startsWith('http') && !rawQr.startsWith('data:')) {
      try {
        // Decode base64 to ensure it builds correctly for ZATCA format
        final bytes = base64Decode(rawQr);
        final tlvString = String.fromCharCodes(bytes);
        qrWidget = QrImageView(
          data: tlvString,
          version: QrVersions.auto,
          size: 150,
          gapless: true,
          backgroundColor: Colors.white,
        );
      } catch (_) {
        qrWidget = QrImageView(
          data: rawQr,
          version: QrVersions.auto,
          size: 150,
          gapless: true,
          backgroundColor: Colors.white,
        );
      }
    } else if (rawQr.startsWith('data:image')) {
      // Synchronous data image
      try {
        final parts = rawQr.split(',');
        final base64Part = parts.length > 1 ? parts.last : '';
        if (base64Part.isNotEmpty) {
          final bytes = base64Decode(base64Part);
          qrWidget = Image.memory(
            bytes,
            width: 150,
            height: 150,
            fit: BoxFit.contain,
            gaplessPlayback: true,
          );
        }
      } catch (_) {
        qrWidget = null;
      }
    } else if (zatcaImage.isNotEmpty) {
      // Fallback: network image (risks being missed by screenshot if slow)
      qrWidget = Image.network(
        zatcaImage,
        width: 150,
        height: 150,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      );
    } else if (rawQr.startsWith('http')) {
      qrWidget = Image.network(
        rawQr,
        width: 150,
        height: 150,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      );
    }

    if (qrWidget == null || qrWidget is SizedBox) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 3),
      color: Colors.white,
      padding: const EdgeInsets.all(2),
      child: Center(child: qrWidget),
    );
  }
}
