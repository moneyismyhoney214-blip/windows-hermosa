// ignore_for_file: avoid_dynamic_calls
// JSON wire-boundary / message-dispatch layer — dynamic accesses accepted pending typed-model refactor.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:lucide_icons/lucide_icons.dart';

import '../locator.dart';
import '../models.dart';
import '../services/api/api_constants.dart';
import '../services/api/auth_service.dart';
import '../services/api/device_service.dart';
import '../services/api/filter_service.dart';
import '../services/api/report_service.dart';
import '../services/app_themes.dart';
import '../services/language_service.dart';
import '../services/logger_service.dart';
import '../services/printer_language_settings_service.dart';
import '../services/printer_role_registry.dart';
import '../services/zatca_printer_service.dart';
import '../utils/ui_feedback.dart';
import '../widgets/daily_closing_report_html_template.dart';

part 'reports_screen_parts/reports_screen.cards.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final ReportService _reportService = getIt<ReportService>();
  final FilterService _filterService = getIt<FilterService>();
  final AuthService _authService = AuthService();
  final NumberFormat _formatter = NumberFormat('#,##0.00', 'ar');

  static const Color _accent = Color(0xFFF58220);

  DateTime _dateFrom = DateTime.now();
  DateTime _dateTo = DateTime.now();

  String _selectedReportType = 'salesPay';

  // Owner-only per-cashier filter (mirrors web /allCashiers dropdown).
  late final bool _isOwner = _authService.isOwner();
  // "دخل الموظفين" is salon-only.
  bool get _isSalon => ApiConstants.branchModule == 'salons';
  List<Map<String, dynamic>> _cashiers = const [];
  bool _cashiersLoading = false;
  String? _selectedCashierId;

  bool _isLoading = true;
  bool _isPrinting = false;
  String? _error;

  Map<String, dynamic>? _currentReport;

  // Per-cashier employee income keyed by cashier id; raw `data` block from /categories.
  final Map<String, Map<String, dynamic>> _employeesIncome = {};

  @override
  void initState() {
    super.initState();
    translationService.addListener(_onLanguageChanged);
    if (_isOwner) {
      _loadCashiers();
    }
    _loadData();
  }

  Future<void> _loadCashiers() async {
    setState(() => _cashiersLoading = true);
    try {
      final response = await _filterService.getAllCashiers();
      final raw = response['data'];
      final list = <Map<String, dynamic>>[];
      if (raw is List) {
        for (final item in raw) {
          if (item is Map) {
            list.add(item.map((k, v) => MapEntry(k.toString(), v)));
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _cashiers = list;
        _cashiersLoading = false;
      });
    } catch (e) {
      Log.d('catch', 'non-fatal: $e');
      if (!mounted) return;
      setState(() => _cashiersLoading = false);
    }
  }

  @override
  void dispose() {
    translationService.removeListener(_onLanguageChanged);
    super.dispose();
  }

  void _onLanguageChanged() {
    if (mounted) setState(() {});
  }

  /// Fans out one `/categories?type=employees&cashier_id=X` per cashier; returns a synthetic single-cashier-shaped report.
  Future<Map<String, dynamic>> _loadEmployeesIncome({
    required String dateFromStr,
    required String dateToStr,
    String? acceptLanguage,
  }) async {
    // Salon-only backstop in case future caller bypasses the gated chip (see CLAUDE.md).
    assert(_isSalon,
        'employees-income is salon-only; branchModule=${ApiConstants.branchModule}');
    _employeesIncome.clear();
    if (_cashiers.isEmpty) {
      return {
        'data': {
          'title': translationService.t('employees_income'),
          'chart': {
            'pieCharts': [
              {
                'title': translationService.t('employees_income'),
                'chartData': const [],
              }
            ],
          },
          'chartCount': 0,
          'chartTotal': 0,
        }
      };
    }

    final futures = <Future<MapEntry<String, Map<String, dynamic>>?>>[];
    for (final cashier in _cashiers) {
      final id = (cashier['value'] ?? cashier['id'])?.toString().trim() ?? '';
      if (id.isEmpty) continue;
      futures.add(() async {
        try {
          final resp = await _reportService.getEmployeesSalesReport(
            dateFrom: dateFromStr,
            dateTo: dateToStr,
            cashierId: id,
            acceptLanguage: acceptLanguage,
          );
          final data = resp['data'];
          if (data is Map) {
            return MapEntry(
                id, data.map((k, v) => MapEntry(k.toString(), v)));
          }
        } catch (e) {
          Log.d('ReportsScreen', 'per-cashier employees-sales report fetch failed (non-fatal): $e');
        }
        return null;
      }());
    }

    final results = await Future.wait(futures);
    for (final entry in results) {
      if (entry != null) _employeesIncome[entry.key] = entry.value;
    }

    final chartData = <Map<String, dynamic>>[];
    double grandTotal = 0;
    int grandCount = 0;
    for (final cashier in _cashiers) {
      final id = (cashier['value'] ?? cashier['id'])?.toString().trim() ?? '';
      if (id.isEmpty) continue;
      final label = (cashier['label'] ??
              cashier['fullname'] ??
              cashier['name'] ??
              cashier['username'] ??
              id)
          .toString();
      final data = _employeesIncome[id];
      final total = _parseDouble(data?['chartTotal']);
      final count = (data?['chartCount'] is num)
          ? (data!['chartCount'] as num).toInt()
          : int.tryParse(data?['chartCount']?.toString() ?? '') ?? 0;
      grandTotal += total;
      grandCount += count;
      // Tack on `count` alongside label/value for custom invoice-count branches.
      chartData.add({
        'label': label,
        'value': total,
        'count': count,
      });
    }

    // Rank employees by revenue (top earner first); consumed in order by renderer + buildReportLines.
    chartData.sort(
        (a, b) => _parseDouble(b['value']).compareTo(_parseDouble(a['value'])));

    return {
      'data': {
        'title': translationService.t('employees_income'),
        'chart': {
          'pieCharts': [
            {
              'title': translationService.t('employees_income'),
              'chartData': chartData,
            }
          ],
        },
        'chartCount': grandCount,
        'chartTotal': grandTotal,
      }
    };
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final dateFromStr = DateFormat('yyyy-MM-dd').format(_dateFrom);
      final dateToStr = DateFormat('yyyy-MM-dd').format(_dateTo);

      // Force Accept-Language to printer language so backend returns receipt-matching names.
      final printerLang = printerLanguageSettings.primary;
      Map<String, dynamic> result;
      switch (_selectedReportType) {
        case 'salesPay':
          result = await _reportService.getDailyClosingSalesPayReport(
            dateFrom: dateFromStr,
            dateTo: dateToStr,
            cashierId: _selectedCashierId,
            acceptLanguage: printerLang,
          );
          break;
        case 'categoriesSales':
          result = await _reportService.getCategoriesSalesReport(
            dateFrom: dateFromStr,
            dateTo: dateToStr,
            cashierId: _selectedCashierId,
            acceptLanguage: printerLang,
          );
          break;
        case 'employeesIncome':
          // Per-cashier fan-out aggregated into synthetic chart block for buildReportLines.
          result = await _loadEmployeesIncome(
            dateFromStr: dateFromStr,
            dateToStr: dateToStr,
            acceptLanguage: printerLang,
          );
          break;
        default:
          result = await _reportService.getDailyClosingSalesPayReport(
            dateFrom: dateFromStr,
            dateTo: dateToStr,
            cashierId: _selectedCashierId,
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

  Future<void> _printReport() async {
    // Snapshot report + type so a mid-print async refresh can't swap data under us.
    final reportType = _selectedReportType;
    final report = _currentReport;
    if (report == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 3),
          content: Text(translationService.t('no_data_for_closing')),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final lines = _buildReportLines(report);
    if (lines.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 3),
          content: Text(translationService.t('no_data_for_print')),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

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
      UiFeedback.error(
        context,
        translationService.t(
          'printers_load_failed',
          args: {'reason': '$e'},
        ),
      );
      return;
    }

    if (printers.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 3),
          content: Text('⚠️ ${translationService.t('no_printers_added')}'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    DeviceConfig selected;
    if (printers.length == 1) {
      selected = printers.first;
    } else {
      DeviceConfig? preferred;
      try {
        final roleRegistry = getIt<PrinterRoleRegistry>();
        await roleRegistry.initialize();
        for (final p in printers) {
          if (roleRegistry.resolveRole(p) == PrinterRole.cashierReceipt) {
            preferred = p;
            break;
          }
        }
      } catch (_) {}
      selected = preferred ?? printers.first;
    }

    setState(() => _isPrinting = true);
    try {
      final fmt = NumberFormat('0.00', 'en');
      final df = DateFormat('yyyy-MM-dd');
      final fromStr = df.format(_dateFrom);
      final toStr = df.format(_dateTo);


      // Resolve printer-language trio so labels follow invoice/kitchen locale rules.
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
      // Secondary-language resolver kept for future bilingual layouts.
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

      // Derive title locally so invoice language wins over backend `title`.
      final String reportTitle;
      switch (reportType) {
        case 'categoriesSales':
          reportTitle = reportPick(
              ar: 'تقرير الفئات',
              en: 'Categories Report',
              hi: 'श्रेणी रिपोर्ट',
              ur: 'زمروں کی رپورٹ',
              es: 'Reporte de Categorías',
              tr: 'Kategori Raporu');
          break;
        case 'employeesIncome':
          reportTitle = reportPick(
              ar: 'دخل الموظفين',
              en: 'Employees Income',
              hi: 'कर्मचारी आय',
              ur: 'ملازمین کی آمدنی',
              es: 'Ingresos de Empleados',
              tr: 'Çalışan Geliri');
          break;
        default:
          reportTitle = reportPick(
              ar: 'إقفالية مبيعات',
              en: 'Sales Closing',
              hi: 'बिक्री समापन',
              ur: 'سیلز کلوزنگ',
              es: 'Cierre de Ventas',
              tr: 'Satış Kapanışı');
      }
      final reportFrom = report['from']?.toString() ?? fromStr;
      final reportTo = report['to']?.toString() ?? toStr;
      final taxPercentage = _parseDouble(report['tax_percentage'] ?? 15);

      final String columnHeader;
      switch (reportType) {
        case 'categoriesSales':
          columnHeader = reportPick(
              ar: 'التصنيف',
              en: 'Category',
              hi: 'श्रेणी',
              ur: 'زمرہ',
              es: 'Categoría',
              tr: 'Kategori');
          break;
        case 'employeesIncome':
          columnHeader = reportPick(
              ar: 'الموظف',
              en: 'Employee',
              hi: 'कर्मचारी',
              ur: 'ملازم',
              es: 'Empleado',
              tr: 'Çalışan');
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

      Widget cell(String text, {bool bold = false, double fontSize = 18}) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Text(text,
              style: TextStyle(fontSize: fontSize, fontWeight: bold ? FontWeight.bold : FontWeight.normal),
              textAlign: TextAlign.center),
        );
      }

      // Thermal printers can't render white; force black-on-white regardless of theme.
      final reportWidget = Directionality(
        textDirection: TextDirection.rtl,
        child: DefaultTextStyle(
          style: const TextStyle(
            color: Colors.black,
            fontSize: 16,
            fontFamily: 'sans-serif',
          ),
          child: IconTheme(
            data: const IconThemeData(color: Colors.black),
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.all(12),
              child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Text(reportTitle, textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Table(
                border: TableBorder.all(color: Colors.black, width: 1),
                children: [
                  TableRow(children: [
                    cell(reportTo),
                    cell(reportPick(
                        ar: 'إلى',
                        en: 'To',
                        hi: 'तक',
                        ur: 'تک',
                        es: 'Hasta',
                        tr: 'Bitiş')),
                  ]),
                  TableRow(children: [
                    cell(reportFrom),
                    cell(reportPick(
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
              Table(
                border: TableBorder.all(color: Colors.black, width: 1),
                columnWidths: const {0: FlexColumnWidth(1), 1: FlexColumnWidth(1)},
                children: [
                  TableRow(children: [
                    cell(
                        reportPick(
                            ar: 'المبلغ',
                            en: 'Amount',
                            hi: 'राशि',
                            ur: 'رقم',
                            es: 'Monto',
                            tr: 'Tutar'),
                        bold: true),
                    cell(columnHeader, bold: true),
                  ]),
                  ...lines.map((line) => TableRow(children: [
                    cell(fmt.format(line.amount)),
                    cell(line.label),
                  ])),
                  TableRow(children: [
                    cell(fmt.format(total), bold: true),
                    cell(
                        reportPick(
                            ar: 'الاجمالي',
                            en: 'Total',
                            hi: 'कुल',
                            ur: 'کل',
                            es: 'Total',
                            tr: 'Toplam'),
                        bold: true),
                  ]),
                  // Suppress tax for employees-income (per-employee revenue, not VAT).
                  if (reportType != 'employeesIncome')
                    TableRow(children: [
                      cell(fmt.format(tax), bold: true),
                      cell(
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
          ),
        ),
      );

      await ZatcaPrinterService().printWidget(selected, reportWidget);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 3),
            content: Text('✅ ${translationService.t('closing_report_printed')}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        UiFeedback.error(
          context,
          translationService.t(
            'print_failed_with_reason',
            args: {'reason': '$e'},
          ),
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
      body: SafeArea(
        child: _isLoading
            ? _buildLoadingView()
            : _error != null
                ? _buildErrorView()
                : _buildContent(),
      ),
    );
  }

  Widget _buildLoadingView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: _accent),
          const SizedBox(height: 16),
          Text(
            translationService.t('loading'),
            style: TextStyle(color: context.appTextMuted, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(LucideIcons.alertTriangle,
                  size: 44, color: Colors.red.shade400),
            ),
            const SizedBox(height: 20),
            Text(
              translationService.t('error'),
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: context.appText,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? '',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.appTextMuted, fontSize: 13),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(translationService.t('try_again')),
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    return Column(
      children: [
        _buildHeader(),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: context.appCardBg,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(LucideIcons.barChart2,
                    color: _accent, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      translationService.t('reports'),
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                        color: context.appText,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      _currentReportTitle(),
                      style: TextStyle(
                        fontSize: 12,
                        color: context.appTextMuted,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              _headerIconButton(
                icon: Icons.refresh,
                tooltip: translationService.t('refresh'),
                onPressed: _loadData,
              ),
              const SizedBox(width: 8),
              _headerIconButton(
                icon: Icons.print,
                tooltip: translationService.t('print'),
                color: _accent,
                busy: _isPrinting,
                onPressed: _isPrinting ? null : _printReport,
              ),
            ],
          ),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _reportTypeChip(
                    'salesPay',
                    translationService.t('sales_report_title'),
                    LucideIcons.receipt),
                const SizedBox(width: 8),
                _reportTypeChip('categoriesSales',
                    translationService.t('categories'), LucideIcons.layers),
                if (_isOwner && _isSalon) ...[
                  const SizedBox(width: 8),
                  _reportTypeChip(
                      'employeesIncome',
                      translationService.t('employees_income'),
                      LucideIcons.users),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Current report title; shown as header subtitle and body heading.
  String _currentReportTitle() {
    switch (_selectedReportType) {
      case 'categoriesSales':
        return translationService.t('categories');
      case 'employeesIncome':
        return translationService.t('employees_income');
      default:
        return translationService.t('sales_report_title');
    }
  }

  Widget _headerIconButton({
    required IconData icon,
    String? tooltip,
    Color? color,
    bool busy = false,
    VoidCallback? onPressed,
  }) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      icon: busy
          ? const SizedBox(
              width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
          : Icon(icon, size: 20),
      style: IconButton.styleFrom(
        backgroundColor: color != null
            ? color.withValues(alpha: 0.12)
            : context.appSurfaceAlt,
        foregroundColor: color ?? context.appTextMuted,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget _reportTypeChip(String value, String label, IconData icon) {
    final selected = _selectedReportType == value;
    return ChoiceChip(
      selected: selected,
      showCheckmark: false,
      avatar: Icon(icon,
          size: 16, color: selected ? Colors.white : context.appTextMuted),
      label: Text(label),
      labelStyle: TextStyle(
        fontSize: 13,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        color: selected ? Colors.white : context.appText,
      ),
      selectedColor: _accent,
      backgroundColor: context.appSurfaceAlt,
      side: BorderSide(color: selected ? _accent : context.appBorder),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      onSelected: (v) {
        if (!v || selected) return;
        setState(() => _selectedReportType = value);
        _loadData();
      },
    );
  }


  /// "خيارات الفلتر" dialog: date range + owner-only cashier picker; applies on "تطبيق الفلتر".
  Future<void> _showFilterDialog() async {
    DateTime tempFrom = _dateFrom;
    DateTime tempTo = _dateTo;
    String? tempCashierId = _selectedCashierId;
    final df = DateFormat('yyyy-MM-dd');

    final applied = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setLocalState) {
            return AlertDialog(
              backgroundColor: context.appCardBg,
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              titlePadding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              title: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, size: 22),
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                  ),
                  Expanded(
                    child: Text(
                      translationService.t('filter_options'),
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: context.appText,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      translationService.t('booking_date'),
                      style: TextStyle(
                        fontSize: 13,
                        color: context.appTextMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () async {
                        final picked = await showDateRangePicker(
                          context: dialogContext,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                          initialDateRange:
                              DateTimeRange(start: tempFrom, end: tempTo),
                          builder: (context, child) => Theme(
                            data: Theme.of(context).copyWith(
                              colorScheme:
                                  const ColorScheme.light(primary: _accent),
                            ),
                            child: child!,
                          ),
                        );
                        if (picked != null) {
                          setLocalState(() {
                            tempFrom = picked.start;
                            tempTo = picked.end;
                          });
                        }
                      },
                      child: InputDecorator(
                        decoration: InputDecoration(
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                          suffixIcon:
                              const Icon(Icons.calendar_today, size: 18),
                        ),
                        child: Text(
                          '${df.format(tempFrom)}    -    ${df.format(tempTo)}',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                    if (_isOwner) ...[
                      const SizedBox(height: 16),
                      Text(
                        translationService.t('cashier'),
                        style: TextStyle(
                          fontSize: 13,
                          color: context.appTextMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      InputDecorator(
                        decoration: InputDecoration(
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String?>(
                            value: tempCashierId,
                            isExpanded: true,
                            hint: Text(translationService.t('select_cashier')),
                            items: <DropdownMenuItem<String?>>[
                              DropdownMenuItem<String?>(
                                value: null,
                                child:
                                    Text(translationService.t('all_cashiers')),
                              ),
                              ..._cashiers.map((c) {
                                final id =
                                    (c['value'] ?? c['id'])?.toString() ?? '';
                                final label = (c['label'] ??
                                        c['fullname'] ??
                                        c['name'] ??
                                        c['username'] ??
                                        id)
                                    .toString();
                                return DropdownMenuItem<String?>(
                                  value: id,
                                  child:
                                      Text(label, overflow: TextOverflow.ellipsis),
                                );
                              }),
                            ],
                            onChanged: _cashiersLoading
                                ? null
                                : (v) =>
                                    setLocalState(() => tempCashierId = v),
                          ),
                        ),
                      ),
                      if (_cashiersLoading) ...[
                        const SizedBox(height: 8),
                        const LinearProgressIndicator(minHeight: 2),
                      ],
                    ],
                  ],
                ),
              ),
              actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              actions: [
                OutlinedButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(translationService.t('cancel')),
                ),
                ElevatedButton.icon(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  icon: const Icon(Icons.filter_alt, size: 18),
                  label: Text(translationService.t('apply_filter')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    if (applied == true) {
      final changed = tempFrom != _dateFrom ||
          tempTo != _dateTo ||
          tempCashierId != _selectedCashierId;
      setState(() {
        _dateFrom = tempFrom;
        _dateTo = tempTo;
        _selectedCashierId = tempCashierId;
      });
      if (changed) unawaited(_loadData());
    }
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

  /// Best localized label for chart item; prefer invoice language → English → Arabic → fallback.
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
      final rawLabel = (item['label'] ?? item['name'])?.toString().trim() ?? '';
      // "عربي - English" combined strings: split so English wins for non-Arabic primaries.
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

  /// Translate payment-method key into the printer's active language.
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

  Widget _buildBody() {
    final report = _currentReport;
    final statistics = report?['statistics'] as Map<String, dynamic>?;
    final hasStatistics = statistics != null && statistics.isNotEmpty;
    final lines = (report == null || hasStatistics)
        ? const <DailyClosingReportLine>[]
        : _buildReportLines(report);
    final hasContent = hasStatistics || lines.isNotEmpty;

    // Grand total: prefer API aggregate, fall back to summing visible lines.
    double total = 0;
    if (hasStatistics && statistics['total'] != null) {
      total = _parseDouble(statistics['total']);
    } else if (report?['chartTotal'] != null) {
      total = _parseDouble(report!['chartTotal']);
    } else if (hasStatistics) {
      total = statistics.entries
          .where((e) => e.key != 'total')
          .fold<double>(0.0, (s, e) => s + _parseDouble(e.value));
    } else if (lines.isNotEmpty) {
      total = lines.fold<double>(0.0, (s, l) => s + l.amount);
    }

    return RefreshIndicator(
      color: _accent,
      onRefresh: _loadData,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
        children: [
          _buildTabHeader(),
          const SizedBox(height: 14),
          if (!hasContent)
            Padding(
              padding: const EdgeInsets.only(top: 40),
              child: _buildEmptyState(),
            )
          else ...[
            _buildTotalHero(total),
            const SizedBox(height: 22),
            if (hasStatistics)
              _buildStatisticsCards(context, statistics)
            else
              ...lines.map((line) => _buildBreakdownCard(line, total)),
          ],
        ],
      ),
    );
  }

  /// Per-tab header: title + filter button.
  Widget _buildTabHeader() {
    return Row(
      children: [
        Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(
            color: _accent,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            _currentReportTitle(),
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: context.appText,
            ),
          ),
        ),
        const SizedBox(width: 12),
        ElevatedButton.icon(
          onPressed: _showFilterDialog,
          icon: const Icon(LucideIcons.slidersHorizontal, size: 16),
          label: Text(translationService.t('filter_options')),
          style: ElevatedButton.styleFrom(
            backgroundColor: _accent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _buildTotalHero(double total) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF58220), Color(0xFFFFA94D)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _accent.withValues(alpha: 0.30),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(LucideIcons.trendingUp, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  translationService.t('total_amount'),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.92),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    '${_formatter.format(total)} ${ApiConstants.currency}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                      height: 1.1,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_formatDate(_dateFrom)}  —  ${_formatDate(_dateTo)}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBreakdownCard(DailyClosingReportLine line, double total) {
    final percent = total > 0 ? (line.amount / total * 100).clamp(0.0, 100.0) : 0.0;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.appCardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.appBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  line.label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: context.appText,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${_formatter.format(line.amount)} ${ApiConstants.currency}',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: _accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: percent / 100,
                    backgroundColor: context.appBorder,
                    valueColor: const AlwaysStoppedAnimation(_accent),
                    minHeight: 7,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${percent.toStringAsFixed(1)}%',
                style: TextStyle(fontSize: 11.5, color: context.appTextMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
