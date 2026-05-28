part of '../daily_closing_report_screen.dart';

// Extracted from daily_closing_report_screen.dart (was ~400 LOC at the tail
// of the host file). Behaviour unchanged — the dialog stays a library-private
// `_ClosingPrintPreviewDialog` so external callers can't construct it; only
// `_DailyClosingReportScreenState` opens it via `showDialog`.

class _ClosingPrintPreviewDialog extends StatefulWidget {
  final List<DailyClosingReportLine> lines;
  final List<DeviceConfig> printers;
  final DeviceConfig? initialPrinter;
  final DateTime dateFrom;
  final DateTime dateTo;
  final Future<void> Function(DeviceConfig printer, bool saveAsDefault) onPrint;

  const _ClosingPrintPreviewDialog({
    required this.lines,
    required this.printers,
    required this.initialPrinter,
    required this.dateFrom,
    required this.dateTo,
    required this.onPrint,
  });

  @override
  State<_ClosingPrintPreviewDialog> createState() =>
      _ClosingPrintPreviewDialogState();
}

class _ClosingPrintPreviewDialogState
    extends State<_ClosingPrintPreviewDialog> {
  /// Resolve labels inside the preview dialog using the same invoice-language
  /// rules as the printed receipt.
  String _previewLangPick({
    required String ar,
    required String en,
    String? hi,
    String? ur,
    String? tr,
    String? es,
  }) {
    final code = printerLanguageSettings.primary.trim().toLowerCase();
    switch (code) {
      case 'ar':
        return ar;
      case 'hi':
        return hi ?? en;
      case 'ur':
        return ur ?? en;
      case 'tr':
        return tr ?? en;
      case 'es':
        return es ?? en;
      case 'en':
      default:
        return en;
    }
  }

  DeviceConfig? _selectedPrinter;
  bool _saveAsDefault = false;
  bool _isPrinting = false;

  @override
  void initState() {
    super.initState();
    _selectedPrinter = widget.initialPrinter;
  }

  String _printerLabel(DeviceConfig p) {
    if (p.connectionType == PrinterConnectionType.bluetooth) {
      final mac = p.bluetoothAddress?.trim() ?? '';
      return '${p.name}${mac.isNotEmpty ? ' ($mac)' : ''} • بلوتوث';
    }
    final port = p.port.trim().isEmpty ? '9100' : p.port.trim();
    return '${p.name} • ${p.ip}:$port';
  }

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat('#,##0.00', 'ar');
    final dateFormat = DateFormat('yyyy/MM/dd');

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 480,
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header ──────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 12, 20),
              decoration: const BoxDecoration(
                color: Color(0xFFF58220),
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.print, color: Colors.white),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'معاينة وطباعة الإقفالية',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),

            // ── Scrollable body ──────────────────────────
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Receipt preview card
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: Colors.grey.shade200),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          // Receipt header
                          Container(
                            padding: const EdgeInsets.symmetric(
                                vertical: 16, horizontal: 16),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(12)),
                            ),
                            child: Column(
                              children: [
                                // Preview title follows the same invoice
                                // language as the actual printed receipt so
                                // the cashier sees a faithful preview, not
                                // hardcoded Arabic.
                                Text(
                                  _previewLangPick(
                                    ar: 'إقفالية المبيعات',
                                    en: 'Sales Closing',
                                    hi: 'बिक्री समापन',
                                    ur: 'سیلز کلوزنگ',
                                    es: 'Cierre de Ventas',
                                    tr: 'Satış Kapanışı',
                                  ),
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${dateFormat.format(widget.dateFrom)} – ${dateFormat.format(widget.dateTo)}',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                          const Divider(height: 1),

                          // Lines
                          if (widget.lines.isEmpty)
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                'لا توجد بيانات',
                                style:
                                    TextStyle(color: Colors.grey.shade500),
                                textAlign: TextAlign.center,
                              ),
                            )
                          else
                            ...widget.lines.map((line) {
                              final isTotal =
                                  line.label.contains('الإجمالي') ||
                                      line.label.contains('المجموع') ||
                                      line.label.toLowerCase().contains('total');
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 10),
                                decoration: BoxDecoration(
                                  color: isTotal
                                      ? const Color(0xFFFFF7ED)
                                      : null,
                                  border: Border(
                                    bottom: BorderSide(
                                        color: Colors.grey.shade100),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        line.label,
                                        style: TextStyle(
                                          fontWeight: isTotal
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                          fontSize: isTotal ? 15 : 14,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      '${formatter.format(line.amount)} ${ApiConstants.currency}',
                                      style: TextStyle(
                                        fontWeight: isTotal
                                            ? FontWeight.bold
                                            : FontWeight.w500,
                                        fontSize: isTotal ? 15 : 14,
                                        color: isTotal
                                            ? const Color(0xFFF58220)
                                            : Colors.black87,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),

                          // Timestamp
                          Padding(
                            padding:
                                const EdgeInsets.fromLTRB(16, 8, 16, 12),
                            child: Text(
                              'وقت الإنشاء: ${DateFormat('yyyy/MM/dd hh:mm a').format(DateTime.now())}',
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey.shade400),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // ── Printer selection ─────────────────
                    Text(
                      'اختر الطابعة',
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 8),
                    if (widget.printers.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.warning_amber,
                                color: Colors.orange, size: 20),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'لا توجد طابعات متاحة. يرجى إضافة طابعة من الإعدادات.',
                                style: TextStyle(color: Colors.orange),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      DropdownButtonFormField<DeviceConfig>(
                        initialValue: _selectedPrinter,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide:
                                BorderSide(color: Colors.grey.shade300),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 14),
                          prefixIcon: const Icon(Icons.print),
                        ),
                        hint: const Text('اختر طابعة'),
                        items: widget.printers
                            .map((p) => DropdownMenuItem(
                                  value: p,
                                  child: Text(_printerLabel(p),
                                      overflow: TextOverflow.ellipsis),
                                ))
                            .toList(),
                        onChanged: (p) =>
                            setState(() => _selectedPrinter = p),
                      ),
                    if (widget.printers.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Checkbox(
                            value: _saveAsDefault,
                            activeColor: const Color(0xFFF58220),
                            onChanged: (v) =>
                                setState(() => _saveAsDefault = v ?? false),
                          ),
                          const Text('حفظ كطابعة افتراضية للإقفالية'),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // ── Action buttons ───────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('إغلاق'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: (widget.printers.isEmpty ||
                              _selectedPrinter == null ||
                              _isPrinting)
                          ? null
                          : () async {
                              setState(() => _isPrinting = true);
                              try {
                                await widget.onPrint(
                                    _selectedPrinter!, _saveAsDefault);
                                // Use the dialog's own context.mounted —
                                // the State's `mounted` belongs to the
                                // host screen and would let the dialog
                                // try to Pop a torn-down route.
                                if (context.mounted) Navigator.pop(context);
                              } catch (_) {
                                if (mounted) {
                                  setState(() => _isPrinting = false);
                                }
                              }
                            },
                      icon: _isPrinting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.print),
                      label:
                          Text(_isPrinting ? 'جاري الطباعة...' : 'طباعة'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF58220),
                        foregroundColor: Colors.white,
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
