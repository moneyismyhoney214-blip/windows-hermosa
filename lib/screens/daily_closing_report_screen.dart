import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api/report_service.dart';
import '../services/api/device_service.dart';
import '../services/api/api_constants.dart';
import '../services/language_service.dart';
import '../services/printer_language_settings_service.dart';
import '../services/printer_role_registry.dart';
import '../services/zatca_printer_service.dart';
import '../widgets/daily_closing_report_html_template.dart';
import '../models.dart';
import '../locator.dart';

class DailyClosingReportScreen extends StatefulWidget {
  const DailyClosingReportScreen({super.key});

  @override
  State<DailyClosingReportScreen> createState() =>
      _DailyClosingReportScreenState();
}

class _DailyClosingReportScreenState extends State<DailyClosingReportScreen>
    with SingleTickerProviderStateMixin {
  static const String _closingPrinterIdKey =
      'daily_closing_preferred_printer_v1';
  final ReportService _reportService = getIt<ReportService>();
  late TabController _tabController;

  DateTime _dateFrom = DateTime.now();
  DateTime _dateTo = DateTime.now();
  String? _selectedCashierId;

  bool _isLoading = true;
  String? _error;
  bool _isPrinting = false;
  String? _preferredClosingPrinterId;

  Map<String, dynamic>? _salesPayReport;
  Map<String, dynamic>? _invoiceStatistics;
  Map<String, dynamic>? _depositsStatistics;
  Map<String, dynamic>? _outgoingsStatistics;
  Map<String, dynamic>? _categoriesPayReport;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    translationService.addListener(_onLanguageChanged);
    _loadPreferredClosingPrinter();
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    translationService.removeListener(_onLanguageChanged);
    super.dispose();
  }

  void _onLanguageChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadPreferredClosingPrinter() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getString(_closingPrinterIdKey);
      if (!mounted) return;
      setState(() => _preferredClosingPrinterId = id?.trim().isNotEmpty == true
          ? id!.trim()
          : null);
    } catch (_) {}
  }

  Future<void> _savePreferredClosingPrinter(String? printerId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (printerId == null || printerId.trim().isEmpty) {
        await prefs.remove(_closingPrinterIdKey);
      } else {
        await prefs.setString(_closingPrinterIdKey, printerId.trim());
      }
    } catch (_) {}
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final dateFromStr = DateFormat('yyyy-MM-dd').format(_dateFrom);
      final dateToStr = DateFormat('yyyy-MM-dd').format(_dateTo);

      // Force Accept-Language to the printer language via explicit
      // per-request headers. The fetches that emit category/meal labels
      // (sales-pay + categories-sales) carry the override; statistics-only
      // endpoints don't need it and keep using the default locale so other
      // screens aren't affected.
      final printerLang = printerLanguageSettings.primary;
      final results = await Future.wait([
        _reportService.getDailyClosingSalesPayReport(
          dateFrom: dateFromStr,
          dateTo: dateToStr,
          cashierId: _selectedCashierId,
          acceptLanguage: printerLang,
        ),
        _reportService.getSalesPaySummary(),
        _reportService.getSalesPaySummaryWithTime(),
        _reportService.getInvoiceStatistics(
          dateFrom: dateFromStr,
          dateTo: dateToStr,
        ),
        _reportService.getDepositsStatistics(
          dateFrom: dateFromStr,
          dateTo: dateToStr,
        ),
        _reportService.getOutgoingsStatistics(
          dateFrom: dateFromStr,
          dateTo: dateToStr,
        ),
        _reportService.getCategoriesSalesReport(
          dateFrom: dateFromStr,
          dateTo: dateToStr,
          cashierId: _selectedCashierId,
          acceptLanguage: printerLang,
        ),
      ]);

      if (mounted) {
        setState(() {
          _salesPayReport = results[0]['data'];
          _invoiceStatistics = results[3]['data'];
          _depositsStatistics = results[4]['data'];
          _outgoingsStatistics = results[5]['data'];
          _categoriesPayReport = results[6];
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _dateFrom, end: _dateTo),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFFF58220),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _dateFrom = picked.start;
        _dateTo = picked.end;
      });
      _loadData();
    }
  }

  Future<void> _sendReportViaWhatsApp() async {
    try {
      final dateFromStr = DateFormat('yyyy-MM-dd').format(_dateFrom);
      final dateToStr = DateFormat('yyyy-MM-dd').format(_dateTo);
      
      await _reportService.sendDailyClosingReportWhatsApp(
        dateFrom: dateFromStr,
        dateTo: dateToStr,
        cashierId: _selectedCashierId,
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(translationService.t('closing_report_sent_via_whatsapp')),
            backgroundColor: Color(0xFF10B981),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(translationService.t('report_send_failed', args: {'error': e.toString()})),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Extract category sales lines from categoriesPay API response. Names
  /// are now routed through `_localizedChartLabel` so the cashier's chosen
  /// invoice language wins over whatever default locale the backend happened
  /// to echo back — a Spanish-configured branch shouldn't print Arabic
  /// category names on the closing receipt.
  List<DailyClosingReportLine> _buildCategoriesPayLines() {
    if (_categoriesPayReport == null) return [];
    final lines = <DailyClosingReportLine>[];

    void _extractFromList(List list) {
      for (final item in list) {
        if (item is! Map) continue;
        final name = _localizedChartLabel(item);
        final amount = _parseDouble(item['total'] ?? item['amount'] ?? item['value'] ?? item['total_sales'] ?? item['sum'] ?? 0);
        if (name.isNotEmpty) {
          lines.add(DailyClosingReportLine(name, amount));
        }
      }
    }

    void _extractFromMap(Map map) {
      for (final entry in map.entries) {
        final key = entry.key.toString();
        if (key == 'maintenance' || key == 'status' || key == 'message' || key == 'errors' || key == 'today') continue;
        final val = entry.value;
        if (val is num) {
          lines.add(DailyClosingReportLine(key, val.toDouble()));
        } else if (val is Map) {
          final name = _localizedChartLabel(val, fallbackKey: key);
          final amount = _parseDouble(val['total'] ?? val['amount'] ?? val['value'] ?? val['total_sales'] ?? 0);
          if (name.isNotEmpty) lines.add(DailyClosingReportLine(name, amount));
        }
      }
    }

    // The response could be wrapped in 'data' or be root-level
    final raw = _categoriesPayReport!;
    final data = raw['data'];

    // data is a List of categories
    if (data is List && data.isNotEmpty) {
      _extractFromList(data);
    }
    // data is a Map with nested structure
    else if (data is Map) {
      final nested = data['categories'] ?? data['data'] ?? data['statistics'];
      if (nested is List) {
        _extractFromList(nested);
      } else if (nested is Map) {
        _extractFromMap(nested);
      } else {
        _extractFromMap(data);
      }
    }

    // Try root-level keys if data didn't yield results
    if (lines.isEmpty) {
      final rootCategories = raw['categories'] ?? raw['statistics'];
      if (rootCategories is List) {
        _extractFromList(rootCategories);
      } else if (rootCategories is Map) {
        _extractFromMap(rootCategories);
      }
    }

    // Try chart shape (pieCharts)
    if (lines.isEmpty) {
      final chart = (data is Map ? data['chart'] : raw['chart']);
      final pieCharts = (chart is Map ? chart['pieCharts'] : null);
      if (pieCharts is List && pieCharts.isNotEmpty) {
        final first = pieCharts.first;
        if (first is Map) {
          final chartData = first['chartData'];
          if (chartData is List) _extractFromList(chartData);
        }
      }
    }

    return lines;
  }

  Widget _buildPrintWidget(List<DailyClosingReportLine> lines, DateTime now) {
    final fmt = NumberFormat('0.00', 'en');
    final df = DateFormat('yyyy-MM-dd');
    final fromStr = df.format(_dateFrom);
    final toStr = df.format(_dateTo);
    final dateLabel = fromStr == toStr ? fromStr : '$fromStr - $toStr';
    final categoryLines = _buildCategoriesPayLines();

    // Resolve primary + optional secondary invoice language for this print.
    // Hardcoded Arabic-over-English labels used to force every branch onto
    // the same layout; now the closing receipt mirrors whatever the cashier
    // picked (es/tr/hi/ur all supported).
    final primary = printerLanguageSettings.primary.trim().toLowerCase();
    final secondary = printerLanguageSettings.allowSecondary &&
            printerLanguageSettings.secondary != primary
        ? printerLanguageSettings.secondary.trim().toLowerCase()
        : '';
    String pickLang(String code,
        {required String ar,
        required String en,
        String? hi,
        String? ur,
        String? tr,
        String? es}) {
      switch (code) {
        case 'ar': return ar;
        case 'hi': return hi ?? en;
        case 'ur': return ur ?? en;
        case 'tr': return tr ?? en;
        case 'es': return es ?? en;
        case 'en':
        default: return en;
      }
    }
    String main(
            {required String ar,
            required String en,
            String? hi,
            String? ur,
            String? tr,
            String? es}) =>
        pickLang(primary, ar: ar, en: en, hi: hi, ur: ur, tr: tr, es: es);
    String sec(
        {required String ar,
        required String en,
        String? hi,
        String? ur,
        String? tr,
        String? es}) {
      if (secondary.isEmpty) return '';
      return pickLang(secondary,
          ar: ar, en: en, hi: hi, ur: ur, tr: tr, es: es);
    }

    final titlePrimary = main(
        ar: 'الإقفالية اليومية',
        en: 'Daily Closing Report',
        hi: 'दैनिक समापन रिपोर्ट',
        ur: 'روزانہ کلوزنگ رپورٹ',
        es: 'Cierre Diario',
        tr: 'Günlük Kapanış Raporu');
    final titleSecondary = sec(
        ar: 'الإقفالية اليومية',
        en: 'Daily Closing Report',
        hi: 'दैनिक समापन रिपोर्ट',
        ur: 'روزانہ کلوزنگ رپورٹ',
        es: 'Cierre Diario',
        tr: 'Günlük Kapanış Raporu');
    final byPaymentPrimary = main(
        ar: 'المبيعات حسب طريقة الدفع',
        en: 'Sales by Payment Method',
        hi: 'भुगतान विधि के अनुसार बिक्री',
        ur: 'ادائیگی کے طریقے کے مطابق فروخت',
        es: 'Ventas por Método de Pago',
        tr: 'Ödeme Yöntemine Göre Satışlar');
    final byPaymentSecondary = sec(
        ar: 'المبيعات حسب طريقة الدفع',
        en: 'Sales by Payment Method',
        hi: 'भुगतान विधि के अनुसार बिक्री',
        ur: 'ادائیگی کے طریقے کے مطابق فروخت',
        es: 'Ventas por Método de Pago',
        tr: 'Ödeme Yöntemine Göre Satışlar');
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            titlePrimary,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          if (titleSecondary.isNotEmpty && titleSecondary != titlePrimary) ...[
            const SizedBox(height: 4),
            Text(
              titleSecondary,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black),
            ),
          ],
          const SizedBox(height: 8),
          Text(dateLabel, textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            DateFormat('yyyy-MM-dd hh:mm a').format(now),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black),
          ),
          const SizedBox(height: 12),
          const Divider(thickness: 3, color: Colors.black),
          const SizedBox(height: 12),
          // Sales by payment method
          Text(
            byPaymentPrimary,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          if (byPaymentSecondary.isNotEmpty && byPaymentSecondary != byPaymentPrimary) ...[
            const SizedBox(height: 2),
            Text(
              byPaymentSecondary,
              style: const TextStyle(fontSize: 18, color: Colors.black, fontWeight: FontWeight.bold),
            ),
          ],
          const SizedBox(height: 10),
          ...lines.map((line) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(line.label,
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    ),
                    Text(
                      '${fmt.format(line.amount)} ${ApiConstants.currency}',
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              )),
          // Categories pay section
          if (categoryLines.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Divider(thickness: 3, color: Colors.black),
            const SizedBox(height: 12),
            Text(
              main(
                  ar: 'المبيعات حسب التصنيف',
                  en: 'Sales by Category',
                  hi: 'श्रेणी के अनुसार बिक्री',
                  ur: 'زمرے کے مطابق فروخت',
                  es: 'Ventas por Categoría',
                  tr: 'Kategoriye Göre Satışlar'),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            if (sec(
                    ar: 'المبيعات حسب التصنيف',
                    en: 'Sales by Category',
                    hi: 'श्रेणी के अनुसार बिक्री',
                    ur: 'زمرے کے مطابق فروخت',
                    es: 'Ventas por Categoría',
                    tr: 'Kategoriye Göre Satışlar')
                .isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                sec(
                    ar: 'المبيعات حسب التصنيف',
                    en: 'Sales by Category',
                    hi: 'श्रेणी के अनुसार बिक्री',
                    ur: 'زمرے کے مطابق فروخت',
                    es: 'Ventas por Categoría',
                    tr: 'Kategoriye Göre Satışlar'),
                style: const TextStyle(fontSize: 18, color: Colors.black, fontWeight: FontWeight.bold),
              ),
            ],
            const SizedBox(height: 10),
            ...categoryLines.map((line) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(line.label,
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      ),
                      Text(
                        '${fmt.format(line.amount)} ${ApiConstants.currency}',
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
                )),
          ],
          const SizedBox(height: 8),
          const Divider(thickness: 3, color: Colors.black),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Future<void> _showPrintPreviewDialog() async {
    if (_salesPayReport == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا توجد بيانات لطباعة الإقفالية.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    List<DeviceConfig> printers = [];
    try {
      final deviceService = getIt<DeviceService>();
      final devices = await deviceService.getDevices();
      printers = devices.where(_isUsablePrinter).toList(growable: false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر تحميل الطابعات: $e'), backgroundColor: Colors.red),
      );
      return;
    }

    if (!mounted) return;

    final lines = _buildReportLines(_salesPayReport!);

    // Pick best default printer
    DeviceConfig? defaultPrinter;
    if (_preferredClosingPrinterId != null) {
      for (final p in printers) {
        if (p.id == _preferredClosingPrinterId) {
          defaultPrinter = p;
          break;
        }
      }
    }
    if (defaultPrinter == null && printers.isNotEmpty) {
      try {
        final roleRegistry = getIt<PrinterRoleRegistry>();
        await roleRegistry.initialize();
        for (final p in printers) {
          if (roleRegistry.resolveRole(p) == PrinterRole.cashierReceipt) {
            defaultPrinter = p;
            break;
          }
        }
      } catch (_) {}
      defaultPrinter ??= printers.isNotEmpty ? printers.first : null;
    }

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => _ClosingPrintPreviewDialog(
        lines: lines,
        printers: printers,
        initialPrinter: defaultPrinter,
        dateFrom: _dateFrom,
        dateTo: _dateTo,
        onPrint: (printer, saveAsDefault) async {
          if (saveAsDefault) {
            await _savePreferredClosingPrinter(printer.id);
            if (mounted) setState(() => _preferredClosingPrinterId = printer.id);
          }
          await _executePrint([printer], lines);
        },
      ),
    );
  }

  Future<void> _executePrint(
    List<DeviceConfig> targetPrinters,
    List<DailyClosingReportLine> lines,
  ) async {
    if (_isPrinting) return;
    if (mounted) setState(() => _isPrinting = true);
    try {
      if (lines.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('لا توجد بيانات قابلة للطباعة.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      final now = DateTime.now();
      final reportWidget = _buildPrintWidget(lines, now);
      var successCount = 0;
      for (final printer in targetPrinters) {
        await ZatcaPrinterService().printWidget(printer, reportWidget);
        successCount += 1;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ تم طباعة الإقفالية على $successCount طابعة'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل طباعة الإقفالية: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(translationService.t('daily_closing_report')),
        backgroundColor: const Color(0xFFF58220),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildErrorView()
              : _buildContent(),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: Colors.red.shade300),
          const SizedBox(height: 16),
          Text(
            translationService.t('error_occurred'),
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.red.shade700,
            ),
          ),
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(color: Colors.grey.shade600)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh),
            label: Text(translationService.t('retry')),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return Column(
      children: [
        _buildHeader(),
        const SizedBox(height: 16),
        _buildTabBar(),
        Expanded(child: _buildTabContent()),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  translationService.t('daily_closing_report'),
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_formatDate(_dateFrom)} - ${_formatDate(_dateTo)}',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton.icon(
            onPressed: _selectDateRange,
            icon: const Icon(Icons.calendar_today, size: 18),
            label: Text(translationService.t('change_period')),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF58220),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(width: 12),
          IconButton(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh),
            tooltip: translationService.t('refresh'),
            style: IconButton.styleFrom(
              backgroundColor: Colors.grey.shade100,
              foregroundColor: Colors.grey.shade700,
            ),
          ),
          const SizedBox(width: 12),
          IconButton(
            onPressed: _sendReportViaWhatsApp,
            icon: const Icon(LucideIcons.messageCircle),
            tooltip: translationService.t('send_via_whatsapp'),
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFF25D366).withValues(alpha: 0.1),
              foregroundColor: const Color(0xFF25D366),
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: _isPrinting ? null : _showPrintPreviewDialog,
            icon: _isPrinting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.print),
            label: const Text('طباعة'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF58220),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
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

  List<DailyClosingReportLine> _buildReportLines(
    Map<String, dynamic> report,
  ) {
    final lines = <DailyClosingReportLine>[];
    final statistics = report['statistics'] as Map<String, dynamic>?;
    if (statistics != null && statistics.isNotEmpty) {
      for (final entry in statistics.entries) {
        if (entry.key == 'total') continue;
        final label = _paymentLabelForKey(entry.key);
        final amount = _parseDouble(entry.value);
        lines.add(DailyClosingReportLine(label, amount));
      }
      return lines;
    }

    final chart = report['chart'] as Map<String, dynamic>?;
    final pieCharts = chart?['pieCharts'] as List<dynamic>?;
    if (pieCharts != null && pieCharts.isNotEmpty) {
      final first = pieCharts.first as Map<String, dynamic>?;
      final chartData = first?['chartData'] as List<dynamic>? ?? const [];
      for (final item in chartData) {
        if (item is! Map) continue;
        final label = _localizedChartLabel(item);
        final value = _parseDouble(item['value'] ?? item['amount']);
        lines.add(DailyClosingReportLine(label, value));
      }
      return lines;
    }

    final totalSales = _parseDouble(report['total_sales']);
    if (totalSales > 0) {
      lines.add(
        DailyClosingReportLine(
          translationService.t('total_sales'),
          totalSales,
        ),
      );
    }
    return lines;
  }

  /// Pick the best localized label for a chart/category item so the report
  /// respects the cashier's invoice language. The backend ships parallel
  /// `label_en` / `name_ar` keys and sometimes a nested `localizedNames`
  /// or `translations` map — we probe each in order, then fall back through
  /// English → Arabic → the raw string before returning a dash-placeholder
  /// (or the caller-supplied key).
  String _localizedChartLabel(Map item, {String? fallbackKey}) {
    final primary = printerLanguageSettings.primary.trim().toLowerCase();

    String? tryLocalized(dynamic source, String code) {
      if (source is! Map) return null;
      final direct = source[code];
      if (direct is String && direct.trim().isNotEmpty) return direct.trim();
      final lower = source[code.toLowerCase()];
      if (lower is String && lower.trim().isNotEmpty) return lower.trim();
      return null;
    }

    String? readKey(String code) {
      for (final suffix in const ['label', 'name', 'category_name', 'title']) {
        final raw = item['${suffix}_$code'];
        if (raw is String && raw.trim().isNotEmpty) return raw.trim();
      }
      for (final nestedKey in const [
        'localizedNames',
        'localized_names',
        'translations',
        'name',
        'label',
      ]) {
        final v = tryLocalized(item[nestedKey], code);
        if (v != null) return v;
      }
      return null;
    }

    String? resolved = readKey(primary);
    resolved ??= readKey('en');
    resolved ??= readKey('ar');
    if (resolved == null) {
      final rawLabel =
          (item['label'] ?? item['name'] ?? item['category_name'] ?? item['category'])?.toString().trim() ?? '';
      if (rawLabel.contains(' - ')) {
        final parts = rawLabel.split(' - ');
        resolved = primary == 'ar' ? parts.first.trim() : parts.last.trim();
      } else {
        resolved = rawLabel;
      }
    }
    if (resolved.isEmpty) return fallbackKey ?? '';
    return resolved;
  }

  /// Translate a payment-method key into the printer's active language.
  /// The report prints this label directly, so following the invoice language
  /// keeps the closing receipt consistent with the rest of the tickets.
  String _paymentLabelForKey(String key) {
    final code = printerLanguageSettings.primary.trim().toLowerCase();
    String pick({
      required String ar,
      required String en,
      String? hi,
      String? ur,
      String? tr,
      String? es,
    }) {
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

    switch (key) {
      case 'cash':
        return pick(ar: 'دفع نقدي', en: 'Cash', hi: 'नकद', ur: 'نقد', es: 'Efectivo', tr: 'Nakit');
      case 'card':
        return pick(ar: 'بطاقة ائتمان', en: 'Card', hi: 'कार्ड', ur: 'کارڈ', es: 'Tarjeta', tr: 'Kart');
      case 'benefit':
        return pick(ar: 'بينيفت باي', en: 'Benefit Pay', es: 'Benefit Pay');
      case 'stc':
        return 'STC Pay';
      case 'bank_transfer':
        return pick(ar: 'تحويل بنكي', en: 'Bank Transfer', hi: 'बैंक ट्रांसफर', ur: 'بینک ٹرانسفر', es: 'Transferencia Bancaria', tr: 'Banka Transferi');
      case 'wallet':
        return pick(ar: 'محفظة', en: 'Wallet', hi: 'वॉलेट', ur: 'والیٹ', es: 'Billetera', tr: 'Cüzdan');
      case 'cheque':
        return pick(ar: 'شيك', en: 'Cheque', hi: 'चेक', ur: 'چیک', es: 'Cheque', tr: 'Çek');
      case 'petty_cash':
        return pick(ar: 'صندوق نثرية', en: 'Petty Cash', hi: 'पेटी कैश', ur: 'پیٹی کیش', es: 'Caja Chica', tr: 'Küçük Kasa');
      case 'pay_later':
        return pick(ar: 'دفع لاحق', en: 'Pay Later', hi: 'बाद में भुगतान', ur: 'بعد میں ادائیگی', es: 'Pagar Después', tr: 'Sonra Öde');
      case 'tabby':
        return 'Tabby';
      case 'tamara':
        return 'Tamara';
      case 'keeta':
      case 'kita':
        return 'Keeta';
      case 'my_fatoorah':
        return pick(ar: 'ماي فاتورة', en: 'MyFatoorah', es: 'MyFatoorah');
      case 'jahez':
      case 'gahez':
        return pick(ar: 'جاهز', en: 'Jahez', es: 'Jahez', hi: 'जाहेज़', ur: 'جاہز', tr: 'Jahez');
      case 'talabat':
        return pick(ar: 'طلبات', en: 'Talabat', es: 'Talabat', hi: 'तलबात', ur: 'طلبات', tr: 'Talabat');
      case 'hunger_station':
      case 'hungerstation':
        return pick(ar: 'هنقر ستيشن', en: 'HungerStation', es: 'HungerStation', hi: 'हंगरस्टेशन', ur: 'ہنگر سٹیشن', tr: 'HungerStation');
      case 'total':
        return pick(ar: 'الاجمالي', en: 'Total', hi: 'कुल', ur: 'کل', es: 'Total', tr: 'Toplam');
      default:
        return key;
    }
  }

  Widget _buildTabBar() {
    return Container(
      color: Colors.white,
      child: TabBar(
        controller: _tabController,
        labelColor: const Color(0xFFF58220),
        unselectedLabelColor: Colors.grey.shade600,
        indicatorColor: const Color(0xFFF58220),
        isScrollable: true,
        tabs: [
          Tab(text: translationService.t('sales_summary')),
          Tab(text: translationService.t('categories')),
          Tab(text: translationService.t('invoices')),
          Tab(text: translationService.t('deposits')),
          Tab(text: translationService.t('outgoings')),
        ],
      ),
    );
  }

  Widget _buildTabContent() {
    return TabBarView(
      controller: _tabController,
      children: [
        _buildSummaryTab(),
        _buildCategoriesTab(),
        _buildInvoicesTab(),
        _buildDepositsTab(),
        _buildOutgoingsTab(),
      ],
    );
  }

  Widget _buildCategoriesTab() {
    final categoryLines = _buildCategoriesPayLines();
    if (categoryLines.isEmpty) {
      return _buildEmptyState();
    }
    final fmt = NumberFormat('0.00', 'en');
    final total = categoryLines.fold<double>(0.0, (s, l) => s + l.amount);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            translationService.t('categories'),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          // Total card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFF58220).withValues(alpha: 0.3)),
            ),
            child: Column(
              children: [
                Text(
                  translationService.t('total_amount'),
                  style: const TextStyle(fontSize: 14, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 4),
                Text(
                  '${fmt.format(total)} ${ApiConstants.currency}',
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFFF58220)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // Category cards
          ...categoryLines.map((line) {
            final percent = total > 0 ? (line.amount / total * 100) : 0.0;
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          line.label,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                        ),
                        const SizedBox(height: 4),
                        // Progress bar
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: percent / 100,
                            backgroundColor: const Color(0xFFE2E8F0),
                            valueColor: const AlwaysStoppedAnimation(Color(0xFFF58220)),
                            minHeight: 6,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${percent.toStringAsFixed(1)}%',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    '${fmt.format(line.amount)} ${ApiConstants.currency}',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFFF58220)),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildSummaryTab() {
    if (_salesPayReport == null) return _buildEmptyState();

    final report = _salesPayReport!;
    
    // Extract statistics from API response
    final statistics = report['statistics'] as Map<String, dynamic>?;
    
    if (statistics != null && statistics.isNotEmpty) {
      // Display statistics as cards
      return SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              translationService.t('sales_summary'),
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _buildStatisticsCards(statistics),
            const SizedBox(height: 24),
            _buildBranchInfo(report),
          ],
        ),
      );
    }

    // Fallback to old structure if statistics not available
    final totalSales = _parseDouble(report['total_sales']);
    final totalTax = _parseDouble(report['total_tax']);
    final netSales = _parseDouble(report['net_sales']);
    final totalRefunds = _parseDouble(report['total_refunds']);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildSummaryCard(
                  title: translationService.t('total_sales'),
                  value: totalSales,
                  icon: LucideIcons.trendingUp,
                  color: const Color(0xFF10B981),
                  bgColor: const Color(0xFFECFDF5),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildSummaryCard(
                  title: translationService.t('net_sales'),
                  value: netSales,
                  icon: LucideIcons.wallet,
                  color: const Color(0xFFF58220),
                  bgColor: const Color(0xFFFFF7ED),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildSummaryCard(
                  title: translationService.t('tax'),
                  value: totalTax,
                  icon: LucideIcons.percent,
                  color: const Color(0xFF3B82F6),
                  bgColor: const Color(0xFFEFF6FF),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildSummaryCard(
                  title: translationService.t('refunds'),
                  value: totalRefunds,
                  icon: LucideIcons.arrowDownCircle,
                  color: const Color(0xFFEF4444),
                  bgColor: const Color(0xFFFEF2F2),
                  isNegative: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildBranchInfo(report),
        ],
      ),
    );
  }

  Widget _buildStatisticsCards(Map<String, dynamic> statistics) {
    final cards = <Widget>[];
    
    // Map of payment methods to their display info
    final paymentMethodsInfo = {
      'cash': {
        'label': translationService.t('cash_payment'),
        'icon': LucideIcons.banknote,
        'color': const Color(0xFF10B981),
        'bgColor': const Color(0xFFECFDF5),
      },
      'card': {
        'label': translationService.t('card_payment'),
        'icon': LucideIcons.creditCard,
        'color': const Color(0xFF3B82F6),
        'bgColor': const Color(0xFFEFF6FF),
      },
      'benefit': {
        'label': translationService.t('benefit_pay'),
        'icon': LucideIcons.smartphone,
        'color': const Color(0xFF8B5CF6),
        'bgColor': const Color(0xFFF3E8FF),
      },
      'stc': {
        'label': translationService.t('stc_pay'),
        'icon': LucideIcons.wallet,
        'color': const Color(0xFFF59E0B),
        'bgColor': const Color(0xFFFEF3C7),
      },
      'bank_transfer': {
        'label': translationService.t('bank_transfer'),
        'icon': LucideIcons.send,
        'color': const Color(0xFF0EA5E9),
        'bgColor': const Color(0xFFE0F2FE),
      },
      'wallet': {
        'label': translationService.t('wallet'),
        'icon': LucideIcons.wallet,
        'color': const Color(0xFF14B8A6),
        'bgColor': const Color(0xFFCCFBF1),
      },
      'cheque': {
        'label': translationService.t('cheque'),
        'icon': LucideIcons.fileCheck,
        'color': const Color(0xFF92400E),
        'bgColor': const Color(0xFFFEF3C7),
      },
      'petty_cash': {
        'label': translationService.t('petty_cash'),
        'icon': LucideIcons.banknote,
        'color': const Color(0xFF0F766E),
        'bgColor': const Color(0xFFCCFBF1),
      },
      'pay_later': {
        'label': translationService.t('pay_later'),
        'icon': LucideIcons.clock,
        'color': const Color(0xFF6366F1),
        'bgColor': const Color(0xFFE0E7FF),
      },
      'tabby': {
        'label': translationService.t('tabby'),
        'icon': LucideIcons.creditCard,
        'color': const Color(0xFF64748B),
        'bgColor': const Color(0xFFE2E8F0),
      },
      'tamara': {
        'label': translationService.t('tamara'),
        'icon': LucideIcons.creditCard,
        'color': const Color(0xFF7C3AED),
        'bgColor': const Color(0xFFF3E8FF),
      },
      'keeta': {
        'label': translationService.t('keeta'),
        'icon': LucideIcons.truck,
        'color': const Color(0xFFF97316),
        'bgColor': const Color(0xFFFEE2E2),
      },
      'kita': {
        'label': translationService.t('keeta'),
        'icon': LucideIcons.truck,
        'color': const Color(0xFFF97316),
        'bgColor': const Color(0xFFFEE2E2),
      },
      'my_fatoorah': {
        'label': translationService.t('my_fatoorah'),
        'icon': LucideIcons.wallet,
        'color': const Color(0xFF06B6D4),
        'bgColor': const Color(0xFFCFFAFE),
      },
      'jahez': {
        'label': translationService.t('jahez'),
        'icon': LucideIcons.truck,
        'color': const Color(0xFF16A34A),
        'bgColor': const Color(0xFFDCFCE7),
      },
      'gahez': {
        'label': translationService.t('jahez'),
        'icon': LucideIcons.truck,
        'color': const Color(0xFF16A34A),
        'bgColor': const Color(0xFFDCFCE7),
      },
      'talabat': {
        'label': translationService.t('talabat'),
        'icon': LucideIcons.shoppingBag,
        'color': const Color(0xFFDC2626),
        'bgColor': const Color(0xFFFEE2E2),
      },
      'hunger_station': {
        'label': translationService.t('hunger_station'),
        'icon': LucideIcons.truck,
        'color': const Color(0xFFEA580C),
        'bgColor': const Color(0xFFFFF7ED),
      },
      'hungerstation': {
        'label': translationService.t('hunger_station'),
        'icon': LucideIcons.truck,
        'color': const Color(0xFFEA580C),
        'bgColor': const Color(0xFFFFF7ED),
      },
      'total': {
        'label': translationService.t('total_amount'),
        'icon': LucideIcons.trendingUp,
        'color': const Color(0xFFF58220),
        'bgColor': const Color(0xFFFFF7ED),
      },
    };

    const paymentMethodKeys = {
      'cash', 'card', 'benefit', 'stc', 'bank_transfer', 'wallet',
      'cheque', 'petty_cash', 'pay_later', 'tabby', 'tamara',
      'keeta', 'my_fatoorah', 'jahez', 'talabat',
    };

    statistics.forEach((key, value) {
      if (paymentMethodKeys.contains(key)) return;
      final info = paymentMethodsInfo[key] ?? {
        'label': key,
        'icon': LucideIcons.dollarSign,
        'color': const Color(0xFF64748B),
        'bgColor': const Color(0xFFF1F5F9),
      };

      cards.add(
        _buildSummaryCard(
          title: info['label'] as String,
          value: _parseDouble(value),
          icon: info['icon'] as IconData,
          color: info['color'] as Color,
          bgColor: info['bgColor'] as Color,
        ),
      );
    });

    // Display cards in a grid (2 columns)
    final rows = <Widget>[];
    for (var i = 0; i < cards.length; i += 2) {
      rows.add(
        Row(
          children: [
            Expanded(child: cards[i]),
            if (i + 1 < cards.length) ...[
              const SizedBox(width: 16),
              Expanded(child: cards[i + 1]),
            ] else
              const Expanded(child: SizedBox()),
          ],
        ),
      );
      if (i + 2 < cards.length) {
        rows.add(const SizedBox(height: 16));
      }
    }

    return Column(children: rows);
  }

  Widget _buildInvoicesTab() {
    if (_invoiceStatistics == null) return _buildEmptyState();

    final stats = _invoiceStatistics!;
    final totalInvoices = stats['total_invoices']?.toString() ?? '0';
    final totalAmount = _parseDouble(stats['total_amount']);
    final averageInvoice = _parseDouble(stats['average_invoice']);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          _buildStatCard(
            title: translationService.t('invoice_count'),
            value: totalInvoices,
            icon: LucideIcons.fileText,
            color: const Color(0xFF8B5CF6),
            bgColor: const Color(0xFFF3E8FF),
          ),
          const SizedBox(height: 16),
          _buildSummaryCard(
            title: translationService.t('total_amount'),
            value: totalAmount,
            icon: LucideIcons.dollarSign,
            color: const Color(0xFF10B981),
            bgColor: const Color(0xFFECFDF5),
          ),
          const SizedBox(height: 16),
          _buildSummaryCard(
            title: translationService.t('average_invoice'),
            value: averageInvoice,
            icon: LucideIcons.calculator,
            color: const Color(0xFFF59E0B),
            bgColor: const Color(0xFFFEF3C7),
          ),
        ],
      ),
    );
  }

  Widget _buildDepositsTab() {
    if (_depositsStatistics == null) return _buildEmptyState();

    final stats = _depositsStatistics!;
    final totalDeposits = stats['total_deposits']?.toString() ?? '0';
    final totalAmount = _parseDouble(stats['total_amount']);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          _buildStatCard(
            title: translationService.t('deposits_count'),
            value: totalDeposits,
            icon: LucideIcons.bookmark,
            color: const Color(0xFF3B82F6),
            bgColor: const Color(0xFFEFF6FF),
          ),
          const SizedBox(height: 16),
          _buildSummaryCard(
            title: translationService.t('total_amount'),
            value: totalAmount,
            icon: LucideIcons.dollarSign,
            color: const Color(0xFF10B981),
            bgColor: const Color(0xFFECFDF5),
          ),
        ],
      ),
    );
  }

  Widget _buildOutgoingsTab() {
    if (_outgoingsStatistics == null) return _buildEmptyState();

    final stats = _outgoingsStatistics!;
    final totalOutgoings = stats['total_outgoings']?.toString() ?? '0';
    final totalAmount = _parseDouble(stats['total_amount']);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          _buildStatCard(
            title: translationService.t('outgoings_count'),
            value: totalOutgoings,
            icon: LucideIcons.arrowUpCircle,
            color: const Color(0xFFEF4444),
            bgColor: const Color(0xFFFEF2F2),
          ),
          const SizedBox(height: 16),
          _buildSummaryCard(
            title: translationService.t('total_amount'),
            value: totalAmount,
            icon: LucideIcons.dollarSign,
            color: const Color(0xFFEF4444),
            bgColor: const Color(0xFFFEF2F2),
            isNegative: true,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            translationService.t('no_data_available'),
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard({
    required String title,
    required double value,
    required IconData icon,
    required Color color,
    required Color bgColor,
    bool isNegative = false,
  }) {
    final formatter = NumberFormat('#,##0.00', 'ar');

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDecoration(),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${formatter.format(value)} ${ApiConstants.currency}',
                  style: TextStyle(
                    color: isNegative ? Colors.red : Colors.black87,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required Color bgColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDecoration(),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.black87,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBranchInfo(Map<String, dynamic> report) {
    final branchName = report['branch_name']?.toString() ?? '-';
    final cashierName = report['cashier_name']?.toString() ?? '-';
    final dateRange = report['date_range']?.toString() ?? '-';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            translationService.t('report_info'),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          _buildInfoRow(translationService.t('branch'), branchName, LucideIcons.building),
          const SizedBox(height: 12),
          _buildInfoRow(translationService.t('cashier'), cashierName, LucideIcons.user),
          const SizedBox(height: 12),
          _buildInfoRow(translationService.t('period'), dateRange, LucideIcons.calendar),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 20, color: const Color(0xFFF58220)),
        const SizedBox(width: 12),
        Text(
          '$label: ',
          style: TextStyle(
            color: Colors.grey.shade600,
            fontWeight: FontWeight.w500,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.05),
          blurRadius: 10,
          offset: const Offset(0, 2),
        ),
      ],
    );
  }

  double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  String _formatDate(DateTime date) {
    return DateFormat('yyyy/MM/dd', 'ar').format(date);
  }
}

// ─────────────────────────────────────────────────────────
// Print Preview Dialog
// ─────────────────────────────────────────────────────────

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
                                if (mounted) Navigator.pop(context);
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
