import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:lucide_icons/lucide_icons.dart';
import '../models.dart';
import '../services/api/report_service.dart';
import '../services/api/device_service.dart';
import '../services/language_service.dart';
import '../services/app_themes.dart';
import '../services/api/api_constants.dart';
import '../services/zatca_printer_service.dart';
import '../services/printer_role_registry.dart';
import '../services/printer_language_settings_service.dart';
import '../widgets/daily_closing_report_html_template.dart';
import '../locator.dart';
import 'closing_report_preview_screen.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen>
    with SingleTickerProviderStateMixin {
  final ReportService _reportService = getIt<ReportService>();
  late TabController _tabController;
  final NumberFormat _formatter = NumberFormat('#,##0.00', 'ar');

  DateTime _dateFrom = DateTime.now();
  DateTime _dateTo = DateTime.now();

  // Report type filter
  String _selectedReportType = 'salesPay'; // Default to sales report

  bool _isLoading = true;
  bool _isPrinting = false;
  String? _error;

  Map<String, dynamic>? _currentReport;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 1, vsync: this);
    translationService.addListener(_onLanguageChanged);
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

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final dateFromStr = DateFormat('yyyy-MM-dd').format(_dateFrom);
      final dateToStr = DateFormat('yyyy-MM-dd').format(_dateTo);

      // Force the fetch's Accept-Language to the printer language via an
      // explicit per-request header. This guarantees the backend returns
      // category / meal names in the language the receipt will actually
      // print, regardless of the app's current UI language. The scoped
      // cache bucket inside `_offlineGet` keeps per-language responses
      // separate so a reprint never gets served the wrong-language reply.
      final printerLang = printerLanguageSettings.primary;
      Map<String, dynamic> result;
      switch (_selectedReportType) {
        case 'salesPay':
          result = await _reportService.getDailyClosingSalesPayReport(
            dateFrom: dateFromStr,
            dateTo: dateToStr,
            acceptLanguage: printerLang,
          );
          break;
        case 'categoriesSales':
          result = await _reportService.getCategoriesSalesReport(
            dateFrom: dateFromStr,
            dateTo: dateToStr,
            acceptLanguage: printerLang,
          );
          break;
        default:
          result = await _reportService.getDailyClosingSalesPayReport(
            dateFrom: dateFromStr,
            dateTo: dateToStr,
            acceptLanguage: printerLang,
          );
      }

      if (mounted) {
        setState(() {
          _currentReport = result['data'];
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
    final phoneController = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(translationService.t('send_report_via_whatsapp')),
        content: TextField(
          controller: phoneController,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(
            labelText: translationService.t('phone_number_label'),
            hintText: '9665XXXXXXXX',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(translationService.t('cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, phoneController.text),
            child: Text(translationService.t('send')),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      try {
        final dateFromStr = DateFormat('yyyy-MM-dd').format(_dateFrom);
        final dateToStr = DateFormat('yyyy-MM-dd').format(_dateTo);
        await _reportService.sendReportViaWhatsApp(
          dateFrom: dateFromStr,
          dateTo: dateToStr,
          phoneNumber: result,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(translationService.t('report_sent_successfully'))),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(translationService.t('report_send_failed', args: {'error': e.toString()}))),
          );
        }
      }
    }
  }

  void _openReportPreview() {
    if (_currentReport == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(translationService.t('no_data_for_preview')),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final lines = _buildReportLines(_currentReport!);
    if (lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا توجد بيانات قابلة للطباعة.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ClosingReportPreviewScreen(
          lines: lines,
          dateFrom: _dateFrom,
          dateTo: _dateTo,
        ),
      ),
    );
  }

  Future<void> _printReport() async {
    if (_currentReport == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا توجد بيانات لطباعة الإقفالية.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final lines = _buildReportLines(_currentReport!);
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

    // Fetch printers
    List<DeviceConfig> printers = [];
    try {
      final deviceService = getIt<DeviceService>();
      final devices = await deviceService.getDevices();
      printers = devices.where((d) {
        final normalized = d.type.trim().toLowerCase();
        if (d.id.startsWith('kitchen:')) return false;
        if (normalized != 'printer') return false;
        if (d.connectionType == PrinterConnectionType.bluetooth) {
          return d.bluetoothAddress?.trim().isNotEmpty == true;
        }
        return d.ip.trim().isNotEmpty;
      }).toList(growable: false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر تحميل الطابعات: $e'), backgroundColor: Colors.red),
      );
      return;
    }

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

    // Pick printer
    DeviceConfig? selected;
    if (printers.length == 1) {
      selected = printers.first;
    } else {
      try {
        final roleRegistry = getIt<PrinterRoleRegistry>();
        await roleRegistry.initialize();
        for (final p in printers) {
          if (roleRegistry.resolveRole(p) == PrinterRole.cashierReceipt) {
            selected = p;
            break;
          }
        }
      } catch (_) {}
      selected ??= printers.first;
    }

    if (selected == null) return;

    // Print
    setState(() => _isPrinting = true);
    try {
      final fmt = NumberFormat('0.00', 'en');
      final df = DateFormat('yyyy-MM-dd');
      final fromStr = df.format(_dateFrom);
      final toStr = df.format(_dateTo);


      // Resolve report metadata from API
      final report = _currentReport ?? {};
      final branch = report['branch'] is Map
          ? (report['branch'] as Map).map((k, v) => MapEntry(k.toString(), v))
          : <String, dynamic>{};
      // Resolve the printer-language trio so every report label follows the
      // same locale rules as the invoice/kitchen tickets instead of hardcoded
      // Arabic. `_reportPick` returns the primary value; `_reportSec` returns
      // an empty string when no distinct secondary is configured, letting
      // callers render a bilingual header only when it makes sense.
      final lang = printerLanguageSettings.primary;
      final langSec = printerLanguageSettings.allowSecondary &&
              printerLanguageSettings.secondary != lang
          ? printerLanguageSettings.secondary
          : '';
      String reportPickLang(String code,
          {required String ar,
          required String en,
          String? hi,
          String? ur,
          String? tr,
          String? es}) {
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

      String reportPick(
              {required String ar,
              required String en,
              String? hi,
              String? ur,
              String? tr,
              String? es}) =>
          reportPickLang(lang,
              ar: ar, en: en, hi: hi, ur: ur, tr: tr, es: es);
      // Secondary-language resolver kept alive for future bilingual layouts.
      // Today's 2-column report table has no room for a stacked translation,
      // so we only call `reportPick` (primary) — this helper stays under an
      // analyzer opt-out so adding a third header column later stays a
      // one-liner instead of plumbing the locals in again.
      // ignore: unused_element
      String reportPickSecondary(
          {required String ar,
          required String en,
          String? hi,
          String? ur,
          String? tr,
          String? es}) {
        if (langSec.isEmpty) return '';
        return reportPickLang(langSec,
            ar: ar, en: en, hi: hi, ur: ur, tr: tr, es: es);
      }

      // Always derive the report title locally so the invoice language wins
      // over whatever locale the backend decided to return in `title`. The
      // API used to stamp "إقفالية مبيعات" regardless of cashier prefs,
      // which leaked Arabic into es/en/tr receipts.
      final reportTitle = _selectedReportType == 'categoriesSales'
          ? reportPick(
              ar: 'تقرير الفئات',
              en: 'Categories Report',
              hi: 'श्रेणी रिपोर्ट',
              ur: 'زمروں کی رپورٹ',
              es: 'Reporte de Categorías',
              tr: 'Kategori Raporu')
          : reportPick(
              ar: 'إقفالية مبيعات',
              en: 'Sales Closing',
              hi: 'बिक्री समापन',
              ur: 'سیلز کلوزنگ',
              es: 'Cierre de Ventas',
              tr: 'Satış Kapanışı');
      final reportDate = report['date']?.toString() ?? toStr;
      final reportTime = report['time']?.toString() ?? '';
      final reportFrom = report['from']?.toString() ?? fromStr;
      final reportTo = report['to']?.toString() ?? toStr;
      final address = branch['address']?.toString() ?? '';
      final district = branch['district']?.toString() ?? '';
      final cashier = report['cashier']?.toString();
      final taxPercentage = _parseDouble(report['tax_percentage'] ?? 15);

      final String columnHeader;
      switch (_selectedReportType) {
        case 'categoriesSales':
          columnHeader = reportPick(
              ar: 'التصنيف',
              en: 'Category',
              hi: 'श्रेणी',
              ur: 'زمرہ',
              es: 'Categoría',
              tr: 'Kategori');
          break;
        default:
          columnHeader = reportPick(
              ar: 'طرق الدفع',
              en: 'Payment Methods',
              hi: 'भुगतान विधियाँ',
              ur: 'ادائیگی کے طریقے',
              es: 'Métodos de Pago',
              tr: 'Ödeme Yöntemleri');
      }

      final apiTotal = _parseDouble(report['chartTotal'] ?? report['statistics']?['total']);
      final total = apiTotal > 0 ? apiTotal : lines.fold<double>(0.0, (s, l) => s + l.amount);
      final tax = total * (taxPercentage / 100);

      Widget _cell(String text, {bool bold = false, double fontSize = 18}) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Text(text,
              style: TextStyle(fontSize: fontSize, fontWeight: bold ? FontWeight.bold : FontWeight.normal),
              textAlign: TextAlign.center),
        );
      }

      final reportWidget = Directionality(
        textDirection: TextDirection.rtl,
        child: Container(
          color: context.appCardBg,
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              // Title
              Text(reportTitle, textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              // From / To — localized. Using the secondary language in a
              // stacked second line would break the 2-column table layout,
              // so we just render the primary label here.
              Table(
                border: TableBorder.all(color: Colors.black, width: 1),
                children: [
                  TableRow(children: [
                    _cell(reportTo),
                    _cell(reportPick(
                        ar: 'إلى',
                        en: 'To',
                        hi: 'तक',
                        ur: 'تک',
                        es: 'Hasta',
                        tr: 'Bitiş')),
                  ]),
                  TableRow(children: [
                    _cell(reportFrom),
                    _cell(reportPick(
                        ar: 'من',
                        en: 'From',
                        hi: 'से',
                        ur: 'سے',
                        es: 'Desde',
                        tr: 'Başlangıç')),
                  ]),
                ],
              ),
              const SizedBox(height: 8),
              // Data table
              Table(
                border: TableBorder.all(color: Colors.black, width: 1),
                columnWidths: const {0: FlexColumnWidth(1), 1: FlexColumnWidth(1)},
                children: [
                  // Header
                  TableRow(children: [
                    _cell(
                        reportPick(
                            ar: 'المبلغ',
                            en: 'Amount',
                            hi: 'राशि',
                            ur: 'رقم',
                            es: 'Monto',
                            tr: 'Tutar'),
                        bold: true),
                    _cell(columnHeader, bold: true),
                  ]),
                  // Data rows
                  ...lines.map((line) => TableRow(children: [
                    _cell(fmt.format(line.amount)),
                    _cell(line.label),
                  ])),
                  // Total
                  TableRow(children: [
                    _cell(fmt.format(total), bold: true),
                    _cell(
                        reportPick(
                            ar: 'الاجمالي',
                            en: 'Total',
                            hi: 'कुल',
                            ur: 'کل',
                            es: 'Total',
                            tr: 'Toplam'),
                        bold: true),
                  ]),
                  // Tax
                  TableRow(children: [
                    _cell(fmt.format(tax), bold: true),
                    _cell(
                        reportPick(
                            ar: 'الضريبة',
                            en: 'Tax',
                            hi: 'कर',
                            ur: 'ٹیکس',
                            es: 'Impuesto',
                            tr: 'Vergi'),
                        bold: true),
                  ]),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                reportPick(
                    ar: 'شكراً لثقتكم بنا',
                    en: 'Thank you for your trust',
                    hi: 'आपके विश्वास के लिए धन्यवाद',
                    ur: 'اعتماد پر شکریہ',
                    es: 'Gracias por su confianza',
                    tr: 'Güveniniz için teşekkürler'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                reportPick(
                    ar: 'برنامج هيرموسا المحاسبي المتكامل',
                    en: 'Hermosa Integrated Accounting System',
                    hi: 'हर्मोसा एकीकृत लेखा प्रणाली',
                    ur: 'ہرموسا مربوط اکاؤنٹنگ سسٹم',
                    es: 'Sistema Contable Integral Hermosa',
                    tr: 'Hermosa Entegre Muhasebe Sistemi'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      );

      await ZatcaPrinterService().printWidget(selected, reportWidget);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ تم طباعة الإقفالية'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل الطباعة: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appBg,
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
            translationService.t('error'),
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
            label: Text(translationService.t('try_again')),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          children: [
            _buildHeader(),
            _buildTabBar(),
            Expanded(
              child: _buildTabContent(),
            ),
          ],
        );
      },
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: context.appCardBg,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isSmallScreen = constraints.maxWidth < 600;
          
          if (isSmallScreen) {
            // عرض مضغوط للشاشات الصغيرة
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  translationService.t('daily_closing_report'),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_formatDate(_dateFrom)} - ${_formatDate(_dateTo)}',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 12),
                // Report type filter
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: DropdownButton<String>(
                    value: _selectedReportType,
                    isExpanded: true,
                    underline: const SizedBox(),
                    style: const TextStyle(fontSize: 13, color: Colors.black87),
                    items: [
                      DropdownMenuItem(
                        value: 'salesPay',
                        child: Text(translationService.t('sales_report_title')),
                      ),
                      DropdownMenuItem(
                        value: 'categoriesSales',
                        child: Text(translationService.t('categories')),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _selectedReportType = value;
                        });
                        _loadData();
                      }
                    },
                  ),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: _selectDateRange,
                        icon: const Icon(Icons.calendar_today, size: 14),
                        label: Text(translationService.t('period'), style: TextStyle(fontSize: 12)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFF58220),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: _loadData,
                        icon: const Icon(Icons.refresh, size: 18),
                        padding: EdgeInsets.all(8),
                        constraints: BoxConstraints(),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.grey.shade100,
                          foregroundColor: Colors.grey.shade700,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: _sendReportViaWhatsApp,
                        icon: const Icon(LucideIcons.messageCircle, size: 18),
                        padding: EdgeInsets.all(8),
                        constraints: BoxConstraints(),
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xFF25D366).withValues(alpha: 0.1),
                          foregroundColor: const Color(0xFF25D366),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: _isPrinting ? null : _printReport,
                        icon: _isPrinting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.print, size: 18),
                        padding: EdgeInsets.all(8),
                        constraints: BoxConstraints(),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.grey.shade100,
                          foregroundColor: Colors.grey.shade700,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }
          
          // عرض عادي للشاشات الكبيرة
          return Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      translationService.t('daily_closing_report'),
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_formatDate(_dateFrom)} - ${_formatDate(_dateTo)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              // Report type filter
              Container(
                width: 200,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: DropdownButton<String>(
                  value: _selectedReportType,
                  isExpanded: true,
                  underline: const SizedBox(),
                  style: const TextStyle(fontSize: 14, color: Colors.black87),
                  items: [
                    DropdownMenuItem(
                      value: 'salesPay',
                      child: Text(translationService.t('sales_report_title')),
                    ),
                    DropdownMenuItem(
                      value: 'categoriesSales',
                      child: Text(translationService.t('categories')),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _selectedReportType = value;
                      });
                      _loadData();
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: _selectDateRange,
                icon: const Icon(Icons.calendar_today, size: 16),
                label: Text(translationService.t('period'), style: TextStyle(fontSize: 13)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF58220),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _loadData,
                icon: const Icon(Icons.refresh, size: 20),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.grey.shade100,
                  foregroundColor: Colors.grey.shade700,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _sendReportViaWhatsApp,
                icon: const Icon(LucideIcons.messageCircle, size: 20),
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFF25D366).withValues(alpha: 0.1),
                  foregroundColor: const Color(0xFF25D366),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _isPrinting ? null : _printReport,
                icon: _isPrinting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.print, size: 20),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.grey.shade100,
                  foregroundColor: Colors.grey.shade700,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  List<DailyClosingReportLine> _buildReportLines(
    Map<String, dynamic> report,
  ) {
    final lines = <DailyClosingReportLine>[];
    final statistics = report['statistics'] as Map<String, dynamic>?;
    if (statistics != null && statistics.isNotEmpty) {
      for (final entry in statistics.entries) {
        // Skip 'total' — it will be calculated from the sum of other lines
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

  /// Pick the best localized label for a chart data item (category / meal
  /// / whatever the pieChart endpoint returns). The API now ships parallel
  /// locale keys like `label_en` / `name_ar` / a nested `localizedNames`
  /// map, plus a bilingual "عربي - English" combo in `label` / `name`.
  /// We prefer the exact invoice-language match, then fall back through
  /// English → Arabic → whatever string we can find.
  String _localizedChartLabel(Map item) {
    final primary = printerLanguageSettings.primary.trim().toLowerCase();

    String? tryLocalized(dynamic source, String code) {
      if (source is! Map) return null;
      final direct = source[code];
      if (direct is String && direct.trim().isNotEmpty) return direct.trim();
      final langNested = source[code.toLowerCase()];
      if (langNested is String && langNested.trim().isNotEmpty) return langNested.trim();
      return null;
    }

    String? readKey(String code) {
      // Parallel keys: label_en / name_en / category_name_en / title_en.
      for (final suffix in const ['label', 'name', 'category_name', 'title']) {
        final raw = item['${suffix}_$code'];
        if (raw is String && raw.trim().isNotEmpty) return raw.trim();
      }
      // Nested maps: localizedNames / translations / name / label.
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
      final rawLabel = (item['label'] ?? item['name'])?.toString().trim() ?? '';
      // Catalog backends commonly pack "عربي - English" into one string.
      // Split it so the English side can win for non-Arabic primaries.
      if (rawLabel.contains(' - ')) {
        final parts = rawLabel.split(' - ');
        if (primary == 'ar') {
          resolved = parts.first.trim();
        } else {
          resolved = parts.last.trim();
        }
      } else {
        resolved = rawLabel;
      }
    }
    return resolved.isNotEmpty ? resolved : '—';
  }

  /// Translate a payment-method key into the printer's active language.
  /// The report prints this label directly, so following the invoice
  /// language keeps the closing receipt consistent with the rest of the
  /// tickets.
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final isSmallScreen = constraints.maxWidth < 600;
        
        return Container(
          color: context.appCardBg,
          child: TabBar(
            controller: _tabController,
            labelColor: context.appPrimary,
            unselectedLabelColor: context.appTextMuted,
            indicatorColor: const Color(0xFFF58220),
            isScrollable: true,
            labelStyle: TextStyle(fontSize: isSmallScreen ? 12 : 14),
            unselectedLabelStyle: TextStyle(fontSize: isSmallScreen ? 12 : 14),
            tabs: [
              Tab(text: translationService.t('sales_summary')),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTabContent() {
    return TabBarView(
      controller: _tabController,
      children: [
        _buildSalesSummaryTab(),
      ],
    );
  }

  Widget _buildSalesSummaryTab() {
    if (_currentReport == null) return _buildEmptyState();

    final report = _currentReport!;

    // Extract statistics from API response
    final statistics = report['statistics'] as Map<String, dynamic>?;

    if (statistics != null && statistics.isNotEmpty) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              report['title']?.toString() ?? translationService.t('report_summary'),
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _buildStatisticsCards(statistics),
          ],
        ),
      );
    }

    // Handle chart-based response (categories, etc.)
    final lines = _buildReportLines(report);
    if (lines.isNotEmpty) {
      final fmt = NumberFormat('0.00', 'en');
      final total = lines.fold<double>(0.0, (s, l) => s + l.amount);
      return SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              report['title']?.toString() ?? translationService.t('report_summary'),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            // Total
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
                  Text(translationService.t('total_amount'),
                      style: const TextStyle(fontSize: 14, color: Color(0xFF64748B))),
                  const SizedBox(height: 4),
                  Text('${fmt.format(total)} ${ApiConstants.currency}',
                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFFF58220))),
                ],
              ),
            ),
            const SizedBox(height: 20),
            ...lines.map((line) {
              final percent = total > 0 ? (line.amount / total * 100) : 0.0;
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: context.appCardBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.appBorder),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(line.label,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
                          const SizedBox(height: 4),
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
                          Text('${percent.toStringAsFixed(1)}%',
                              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text('${fmt.format(line.amount)} ${ApiConstants.currency}',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFFF58220))),
                  ],
                ),
              );
            }),
          ],
        ),
      );
    }

    return _buildEmptyState();
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

    statistics.forEach((key, value) {
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

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            LucideIcons.fileText,
            size: 64,
            color: Colors.grey.shade300,
          ),
          const SizedBox(height: 16),
          Text(
            translationService.t('no_data_available'),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            translationService.t('select_period_to_view_reports'),
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade500,
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final isSmallScreen = constraints.maxWidth < 400;
        
        return Container(
          padding: EdgeInsets.all(isSmallScreen ? 14 : 20),
          decoration: BoxDecoration(
            color: context.appCardBg,
            borderRadius: BorderRadius.circular(16),
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
              Container(
                width: isSmallScreen ? 48 : 56,
                height: isSmallScreen ? 48 : 56,
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: color,
                  size: isSmallScreen ? 24 : 28,
                ),
              ),
              SizedBox(width: isSmallScreen ? 12 : 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: isSmallScreen ? 12 : 14,
                      ),
                    ),
                    SizedBox(height: isSmallScreen ? 2 : 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        '${_formatter.format(value)} ${ApiConstants.currency}',
                        style: TextStyle(
                          color: isNegative ? Colors.red : Colors.black87,
                          fontSize: isSmallScreen ? 16 : 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }


}
