import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:screenshot/screenshot.dart';

import '../models.dart';
import '../services/api/api_constants.dart';
import '../services/api/device_service.dart';
import '../services/language_service.dart';
import '../services/zatca_printer_service.dart';
import '../locator.dart';
import '../widgets/daily_closing_report_html_template.dart';

class ClosingReportPreviewScreen extends StatefulWidget {
  final List<DailyClosingReportLine> lines;
  final DateTime dateFrom;
  final DateTime dateTo;

  const ClosingReportPreviewScreen({
    super.key,
    required this.lines,
    required this.dateFrom,
    required this.dateTo,
  });

  @override
  State<ClosingReportPreviewScreen> createState() =>
      _ClosingReportPreviewScreenState();
}

class _ClosingReportPreviewScreenState
    extends State<ClosingReportPreviewScreen> {
  final ScreenshotController _screenshotController = ScreenshotController();
  bool _isPrinting = false;

  Future<void> _choosePrinterAndPrint() async {
    final deviceService = getIt<DeviceService>();
    final devices = await deviceService.getDevices();
    final printers = devices.where(_isUsablePrinter).toList(growable: false);

    if (printers.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ لا توجد طابعات مضافة'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    DeviceConfig? selected;

    if (printers.length == 1) {
      selected = printers.first;
    } else {
      if (!mounted) return;
      selected = await showModalBottomSheet<DeviceConfig>(
        context: context,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) => _PrinterPickerSheet(printers: printers),
      );
    }

    if (selected == null) return;

    setState(() => _isPrinting = true);
    try {
      await ZatcaPrinterService()
          .printZatcaReceipt(selected, _screenshotController);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ تم إرسال التقرير للطابعة'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل الطباعة: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  bool _isUsablePrinter(DeviceConfig device) {
    final normalized = device.type.trim().toLowerCase();
    if (device.id.startsWith('kitchen:')) return false;
    if (normalized != 'printer') return false;
    if (device.connectionType == PrinterConnectionType.bluetooth) {
      return device.bluetoothAddress?.trim().isNotEmpty == true;
    }
    return device.ip.trim().isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        title: Text(
          translationService.t('daily_closing_report'),
          style: const TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.black87),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _isPrinting
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFFF58220),
                      ),
                    ),
                  )
                : ElevatedButton.icon(
                    onPressed: _choosePrinterAndPrint,
                    icon: const Icon(Icons.print, size: 18),
                    label: const Text('اختر طابعة'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF58220),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Screenshot(
                controller: _screenshotController,
                child: _buildReportContent(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReportContent() {
    final fmt = NumberFormat('0.00', 'en');
    final df = DateFormat('yyyy-MM-dd');
    final fromStr = df.format(widget.dateFrom);
    final toStr = df.format(widget.dateTo);
    final dateLabel = fromStr == toStr ? fromStr : '$fromStr - $toStr';
    final now = DateTime.now();

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            translationService.t('daily_closing_report'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            dateLabel,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, color: Colors.grey),
          ),
          const Divider(height: 24),
          ...widget.lines.map(
            (line) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      line.label,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                  Text(
                    '${fmt.format(line.amount)} ${ApiConstants.currency}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 24),
          Text(
            DateFormat('yyyy-MM-dd HH:mm').format(now),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

class _PrinterPickerSheet extends StatelessWidget {
  final List<DeviceConfig> printers;

  const _PrinterPickerSheet({required this.printers});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 12),
        Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'اختر طابعة',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ...printers.map(
          (p) => ListTile(
            leading: const Icon(Icons.print, color: Color(0xFFF58220)),
            title: Text(p.name.isNotEmpty ? p.name : p.ip),
            subtitle: Text(
              p.connectionType == PrinterConnectionType.bluetooth
                  ? 'Bluetooth'
                  : p.ip,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
            onTap: () => Navigator.pop(context, p),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
