import 'dart:io';
import 'dart:typed_data';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ESC/POS receipt simulation — prints to local TCP and decodes output', () async {
    // ── 1. Start TCP server ──
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = server.port;

    final receivedFuture = server.first.then((socket) async {
      final chunks = <int>[];
      await for (final data in socket) {
        chunks.addAll(data);
      }
      return chunks;
    });

    // ── 2. Build receipt (matching Hermosa PDF) ──
    final profile = await CapabilityProfile.load();
    final paper = PaperSize.mm80;
    final gen = Generator(paper, profile);
    final bytes = <int>[];

    bytes.addAll(gen.setGlobalCodeTable('CP864'));

    // HEADER
    bytes.addAll(gen.text('LUQMA & KHUBZA',
        styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2)));
    bytes.addAll(gen.text('Saudi Arabia, Al Ahsa',
        styles: const PosStyles(align: PosAlign.center)));
    bytes.addAll(gen.text('+966543939551',
        styles: const PosStyles(align: PosAlign.center)));
    bytes.addAll(gen.hr(ch: '='));

    // Order & Invoice
    bytes.addAll(gen.text('Order# 11',
        styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2)));
    bytes.addAll(gen.feed(1));
    bytes.addAll(gen.text('IN-634',
        styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2)));
    bytes.addAll(gen.hr(ch: '-'));

    // Info
    bytes.addAll(gen.row([
      PosColumn(text: 'Cashier', width: 5, styles: const PosStyles(bold: true)),
      PosColumn(text: 'Takana', width: 7, styles: const PosStyles(align: PosAlign.right)),
    ]));
    bytes.addAll(gen.row([
      PosColumn(text: 'Tax Number', width: 5, styles: const PosStyles(bold: true)),
      PosColumn(text: '312800673600003', width: 7, styles: const PosStyles(align: PosAlign.right)),
    ]));
    bytes.addAll(gen.row([
      PosColumn(text: 'Date', width: 5, styles: const PosStyles(bold: true)),
      PosColumn(text: '2026-04-06', width: 7, styles: const PosStyles(align: PosAlign.right)),
    ]));
    bytes.addAll(gen.row([
      PosColumn(text: 'Time', width: 5, styles: const PosStyles(bold: true)),
      PosColumn(text: '08:53 PM', width: 7, styles: const PosStyles(align: PosAlign.right)),
    ]));
    bytes.addAll(gen.row([
      PosColumn(text: 'order type', width: 5, styles: const PosStyles(bold: true)),
      PosColumn(text: 'pickup', width: 7, styles: const PosStyles(align: PosAlign.right)),
    ]));
    bytes.addAll(gen.hr(ch: '='));

    // Title
    bytes.addAll(gen.text('Simplified Tax Invoice',
        styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2)));
    bytes.addAll(gen.feed(1));
    bytes.addAll(gen.hr(ch: '-'));

    // Items
    bytes.addAll(gen.row([
      PosColumn(text: 'Item', width: 5, styles: const PosStyles(bold: true)),
      PosColumn(text: 'Qty', width: 2, styles: const PosStyles(align: PosAlign.center, bold: true)),
      PosColumn(text: 'Disc', width: 2, styles: const PosStyles(align: PosAlign.center, bold: true)),
      PosColumn(text: 'Price', width: 3, styles: const PosStyles(align: PosAlign.right, bold: true)),
    ]));
    bytes.addAll(gen.hr(ch: '-'));

    for (var i = 0; i < 3; i++) {
      bytes.addAll(gen.row([
        PosColumn(text: 'Hamis pottery', width: 5),
        PosColumn(text: '1', width: 2, styles: const PosStyles(align: PosAlign.center)),
        PosColumn(text: '0.00', width: 2, styles: const PosStyles(align: PosAlign.center)),
        PosColumn(text: '20.87', width: 3, styles: const PosStyles(align: PosAlign.right)),
      ]));
    }
    bytes.addAll(gen.hr(ch: '-'));

    // Totals
    bytes.addAll(gen.row([
      PosColumn(text: 'Total Before Tax', width: 7),
      PosColumn(text: '62.61 SAR', width: 5, styles: const PosStyles(align: PosAlign.right)),
    ]));
    bytes.addAll(gen.row([
      PosColumn(text: 'Tax Amount', width: 7),
      PosColumn(text: '9.39 SAR', width: 5, styles: const PosStyles(align: PosAlign.right)),
    ]));
    bytes.addAll(gen.hr(ch: '='));
    bytes.addAll(gen.row([
      PosColumn(text: 'Total After Tax', width: 7, styles: const PosStyles(bold: true)),
      PosColumn(text: '72.00 SAR', width: 5, styles: const PosStyles(align: PosAlign.right)),
    ]));
    bytes.addAll(gen.row([
      PosColumn(text: 'Paid', width: 7),
      PosColumn(text: '72.00 SAR', width: 5, styles: const PosStyles(align: PosAlign.right)),
    ]));
    bytes.addAll(gen.row([
      PosColumn(text: 'Remaining', width: 7),
      PosColumn(text: '0.00 SAR', width: 5, styles: const PosStyles(align: PosAlign.right)),
    ]));
    bytes.addAll(gen.hr(ch: '-'));
    bytes.addAll(gen.row([
      PosColumn(text: 'Payment Methods', width: 7, styles: const PosStyles(bold: true)),
      PosColumn(text: 'Cash', width: 5, styles: const PosStyles(align: PosAlign.right)),
    ]));
    bytes.addAll(gen.feed(1));

    // QR
    bytes.addAll(gen.qrcode('https://hermosaapp.com/test', size: QRSize.size6, align: PosAlign.center));
    bytes.addAll(gen.feed(1));
    bytes.addAll(gen.hr(ch: '='));
    bytes.addAll(gen.text('Thank you for trusting us',
        styles: const PosStyles(align: PosAlign.center, bold: true)));
    bytes.addAll(gen.text('Integrated Accounting Program Hermosa',
        styles: const PosStyles(align: PosAlign.center)));
    bytes.addAll(gen.feed(2));
    bytes.addAll(gen.cut());

    // ── 3. Send to simulator ──
    final socket = await Socket.connect('127.0.0.1', port);
    socket.add(Uint8List.fromList(bytes));
    await socket.flush();
    await socket.close();

    // ── 4. Verify ──
    final received = await receivedFuture;
    await server.close();

    expect(received.length, equals(bytes.length));
    expect(received.length, greaterThan(500)); // Real receipt has substance

    // Extract readable ASCII text
    final text = _extractText(received);

    // Verify all sections present
    expect(text, contains('LUQMA & KHUBZA'));
    expect(text, contains('966543939551'));
    expect(text, contains('Order# 11'));
    expect(text, contains('IN-634'));
    expect(text, contains('Cashier'));
    expect(text, contains('Tax Number'));
    expect(text, contains('312800673600003'));
    expect(text, contains('2026-04-06'));
    expect(text, contains('Simplified Tax Invoice'));
    expect(text, contains('Item'));
    expect(text, contains('Hamis pottery'));
    expect(text, contains('Total Before Tax'));
    expect(text, contains('62.61 SAR'));
    expect(text, contains('Tax Amount'));
    expect(text, contains('9.39 SAR'));
    expect(text, contains('Total After Tax'));
    expect(text, contains('72.00 SAR'));
    expect(text, contains('Paid'));
    expect(text, contains('Remaining'));
    expect(text, contains('0.00 SAR'));
    expect(text, contains('Payment Methods'));
    expect(text, contains('Cash'));
    expect(text, contains('Thank you for trusting us'));
    expect(text, contains('Integrated Accounting Program Hermosa'));

    // Print visual representation
    print('\n${'=' * 48}');
    print('  SIMULATED THERMAL RECEIPT (80mm)');
    print('${'=' * 48}');
    _printVisual(received);
    print('${'=' * 48}\n');
    print('Total bytes: ${received.length}');
    print('All content verified OK');
  });
}

String _extractText(List<int> bytes) {
  final buf = StringBuffer();
  for (final b in bytes) {
    if (b >= 0x20 && b <= 0x7E) buf.writeCharCode(b);
    else if (b == 0x0A) buf.write(' ');
  }
  return buf.toString();
}

void _printVisual(List<int> bytes) {
  final line = StringBuffer();
  var i = 0;
  while (i < bytes.length) {
    final b = bytes[i];
    if (b == 0x1B || b == 0x1D) {
      // Skip ESC/GS commands
      i++;
      if (i >= bytes.length) break;
      final cmd = bytes[i];
      if (cmd == 0x56) {
        // Cut
        if (line.isNotEmpty) { print(line); line.clear(); }
        print('------------ CUT ------------');
      } else if ((cmd == 0x61 || cmd == 0x45 || cmd == 0x21 || cmd == 0x74 || cmd == 0x64) && i + 1 < bytes.length) {
        if (cmd == 0x64) {
          if (line.isNotEmpty) { print(line); line.clear(); }
          final n = bytes[i + 1];
          for (var f = 0; f < n; f++) print('');
        }
        i++;
      } else if (cmd == 0x28 && i + 2 < bytes.length) {
        i++;
        final pL = bytes[i]; i++; final pH = bytes[i];
        final len = pL + (pH << 8);
        i += len;
        if (line.isNotEmpty) { print(line); line.clear(); }
        print('         [QR CODE]');
      }
      i++;
      continue;
    }
    if (b == 0x0A) {
      print(line);
      line.clear();
      i++;
      continue;
    }
    if (b == 0x0D) { i++; continue; }
    if (b >= 0x20 && b <= 0x7E) {
      line.writeCharCode(b);
    }
    i++;
  }
  if (line.isNotEmpty) print(line);
}
