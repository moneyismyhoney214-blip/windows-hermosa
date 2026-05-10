import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../services/api/api_constants.dart';
import '../services/api/base_client.dart';
import '../services/api/salon_employee_service.dart';
import '../services/api/filter_service.dart';
import '../services/language_service.dart';
import '../locator.dart';
import '../services/app_themes.dart';
import '../services/receipt_builder_service.dart';
import '../models/receipt_data.dart';

class CreateDepositDialog extends StatefulWidget {
  /// Auto-print callback fired right after the deposit is created on the
  /// server. Wired by [DepositsScreen] from the main screen's
  /// `_autoPrintReceiptCopies` so we reuse the same printer-discovery,
  /// timeout, and second-copy orchestration the cashier flow uses. When
  /// null the dialog still creates the deposit but skips printing.
  final Future<void> Function({
    required OrderReceiptData receiptData,
    String? invoiceId,
  })? onPrintReceipt;

  const CreateDepositDialog({super.key, this.onPrintReceipt});

  @override
  State<CreateDepositDialog> createState() => _CreateDepositDialogState();
}

class _CreateDepositDialogState extends State<CreateDepositDialog> {
  final SalonEmployeeService _salonService = getIt<SalonEmployeeService>();
  final FilterService _filterService = getIt<FilterService>();
  final NumberFormat _amountFormatter = NumberFormat('#,##0.##');

  // Form data
  Map<String, dynamic>? _selectedCustomer;
  final List<_SelectedService> _selectedServices = [];
  DateTime _bookingDate = DateTime.now();
  TimeOfDay _bookingTime = TimeOfDay.now();

  // Payment data
  List<Map<String, dynamic>> _payMethods = [];
  String? _selectedPayMethodKey;

  // Deposit amount typed by the cashier — matches the web dashboard's
  // `price` field. Service catalog prices are no longer editable; the
  // cashier picks the services (just to attach them to the booking) and
  // then types whatever amount the customer is putting down. The dashboard
  // HAR shows it sends `pays[i][amount] = 0` for every method (the
  // payment-amount input lives elsewhere in their flow), so we mirror that
  // — there's no separate "amount paid" field in this dialog.
  final TextEditingController _depositAmountController = TextEditingController();

  // Customer search
  List<Map<String, dynamic>> _customers = [];
  final TextEditingController _customerSearchController =
      TextEditingController();
  Timer? _customerSearchDebounce;
  bool _isLoadingCustomers = false;

  bool _isLoadingPayMethods = false;
  bool _isCreating = false;
  String? _error;

  String get _langCode =>
      translationService.currentLanguageCode.trim().toLowerCase();
  bool get _useArabicUi =>
      _langCode.startsWith('ar') || _langCode.startsWith('ur');
  String _tr(String ar, String en) => _useArabicUi ? ar : en;

  // Tax rate now follows the active branch's `taxObject` via ApiConstants.
  // Returns 0.0 when the branch has VAT disabled, so the deposit total
  // collapses to the bare subtotal automatically.
  double get _taxRate => ApiConstants.effectiveTaxRate;

  // Computed totals — the deposit amount is what the cashier typed in the
  // amount field; tax + total derive from it. Mirrors the web dashboard,
  // which sends `price` straight from a single input rather than summing
  // per-service prices.
  double get _subtotal => _parseServerPrice(_depositAmountController.text);

  double get _tax => _subtotal * _taxRate;
  double get _total => _subtotal + _tax;

  @override
  void initState() {
    super.initState();
    _loadCustomers();
    _loadPayMethods();
  }

  @override
  void dispose() {
    _customerSearchController.dispose();
    _depositAmountController.dispose();
    _customerSearchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _loadCustomers({String? search}) async {
    setState(() => _isLoadingCustomers = true);
    try {
      final response = await _filterService.getCustomers(search: search);
      final data = response['data'];
      if (data is List && mounted) {
        setState(() {
          _customers = data
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          _isLoadingCustomers = false;
        });
      } else {
        if (mounted) setState(() => _isLoadingCustomers = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingCustomers = false);
    }
  }

  Future<void> _loadPayMethods() async {
    setState(() => _isLoadingPayMethods = true);
    try {
      // The /payMethods endpoint requires `type ∈ {incomings, outgoings,
      // online}` and 422s when it's missing — that 422 is what was leaving
      // the chips list empty. Deposits are incoming money, so request that
      // bucket explicitly.
      final response =
          await _filterService.getPaymentMethods(type: 'incomings');
      final data = response['data'];
      if (data is List && mounted) {
        final methods = data
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        setState(() {
          _payMethods = methods;
          _isLoadingPayMethods = false;
          if (methods.isNotEmpty) {
            _selectedPayMethodKey =
                methods.first['value']?.toString() ??
                    methods.first['id']?.toString() ??
                    '';
          }
        });
      } else {
        if (mounted) setState(() => _isLoadingPayMethods = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingPayMethods = false);
    }
  }

  void _onCustomerSearch(String value) {
    _customerSearchDebounce?.cancel();
    _customerSearchDebounce = Timer(const Duration(milliseconds: 400), () {
      _loadCustomers(search: value.isEmpty ? null : value);
    });
  }

  Future<void> _pickBookingDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _bookingDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && mounted) {
      setState(() => _bookingDate = picked);
    }
  }

  Future<void> _pickBookingTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _bookingTime,
    );
    if (picked != null && mounted) {
      setState(() => _bookingTime = picked);
    }
  }

  void _openServicePicker() async {
    final result = await showDialog<_SelectedService>(
      context: context,
      builder: (ctx) => _ServicePickerDialog(tr: _tr),
    );
    if (result != null && mounted) {
      setState(() {
        // Check if already exists, bump quantity if so
        final existing = _selectedServices.indexWhere(
            (s) => s.id == result.id);
        if (existing >= 0) {
          _selectedServices[existing].quantity += 1;
        } else {
          _selectedServices.add(result);
        }
      });
    }
  }

  Future<void> _createDeposit() async {
    // Validation
    if (_selectedCustomer == null) {
      setState(() =>
          _error = _tr('يرجى اختيار العميل', 'Please select a customer'));
      return;
    }
    if (_selectedServices.isEmpty) {
      setState(() =>
          _error = _tr('يرجى اختيار خدمة واحدة على الأقل', 'Please select at least one service'));
      return;
    }
    if (_subtotal <= 0) {
      setState(
          () => _error = _tr('الإجمالي يجب أن يكون أكبر من صفر', 'Total must be greater than zero'));
      return;
    }

    setState(() {
      _isCreating = true;
      _error = null;
    });

    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final bookingDateStr = DateFormat('yyyy-MM-dd').format(_bookingDate);
      // Backend validates `booking_time` against Laravel's `H:i:s` rule —
      // sending only `HH:mm` triggers a 422. Always pad the seconds to `00`
      // since the time picker doesn't expose them.
      final bookingTimeStr =
          '${_bookingTime.hour.toString().padLeft(2, '0')}:'
          '${_bookingTime.minute.toString().padLeft(2, '0')}:00';

      final fields = <String, String>{
        'customer_id':
            (_selectedCustomer!['value'] ?? _selectedCustomer!['id'] ?? '')
                .toString(),
        'price': _subtotal.toStringAsFixed(ApiConstants.digitsNumber),
        'total': _total.toStringAsFixed(ApiConstants.digitsNumber),
        'date': dateStr,
        'booking_date': bookingDateStr,
        'booking_time': bookingTimeStr,
      };

      // Add services[] array — dedupe IDs.
      //
      // The backend stores the link in a `service_deposit` pivot table
      // with `PRIMARY KEY (deposit_id, service_id)`, so sending the same
      // service ID twice (the cashier added quantity ≥ 2 of the same row)
      // crashed with a 1062 duplicate-key error. Quantity is conceptual
      // for the deposit's service list — the pivot only records whether a
      // service is attached, not how many times. Send each unique ID
      // once.
      final seenServiceIds = <String>{};
      int serviceIndex = 0;
      for (final service in _selectedServices) {
        if (!seenServiceIds.add(service.id)) continue;
        fields['services[$serviceIndex]'] = service.id;
        serviceIndex++;
      }

      // Add pays — match the dashboard HAR exactly: every available method
      // is sent with `amount = 0`. The dashboard doesn't expose a
      // payment-amount input on the deposit form (only the deposit
      // `price`), and its HAR posts captures all `pays[i][amount] = 0`. We
      // mirror that so the cash-app records deposits with the same shape
      // the web dashboard does.
      //
      // The backend still requires the `pays` field to be present and
      // non-empty; if `getPaymentMethods` failed (offline / network blip)
      // we fall back to a single cash row so the create can still go
      // through.
      const zeroAmount = '0';
      if (_payMethods.isEmpty) {
        fields['pays[0][name]'] = _tr('دفع نقدي', 'Cash');
        fields['pays[0][pay_method]'] = 'cash';
        fields['pays[0][amount]'] = zeroAmount;
        fields['pays[0][index]'] = '0';
      } else {
        int payIndex = 0;
        for (final method in _payMethods) {
          final key =
              method['value']?.toString() ?? method['id']?.toString() ?? '';
          final label = method['label']?.toString() ?? key;

          fields['pays[$payIndex][name]'] = label;
          fields['pays[$payIndex][pay_method]'] = key;
          fields['pays[$payIndex][amount]'] = zeroAmount;
          fields['pays[$payIndex][index]'] = payIndex.toString();
          payIndex++;
        }
      }

      final response = await _salonService.createDeposit(fields);

      // Print the deposit receipt BEFORE closing the dialog. Earlier we
      // tried `unawaited(...)` so the dialog could pop instantly, but that
      // swallowed any exception silently (no detail-fetch result, no
      // printer-resolution result) and made the "doesn't print" symptom
      // impossible to diagnose. Awaiting here keeps the State alive for
      // the auto-print orchestrator and surfaces failures via its own
      // snackbars (`_showMissingPrinterSnackBar`, `_showPrintFailureSnackBar`).
      if (mounted) {
        final printCb = widget.onPrintReceipt;
        if (printCb != null) {
          debugPrint('🧾 [Deposit] auto-print starting for response: '
              '${response['data']}');
          await _printDepositReceipt(response, printCb);
        } else {
          debugPrint(
              '⚠️ [Deposit] onPrintReceipt callback is null — host did not '
              'wire the print orchestrator');
        }
        if (mounted) {
          Navigator.of(context).pop(true);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isCreating = false;
          _error = e.toString();
        });
      }
    }
  }

  /// Resolve the freshly-created deposit's full detail and hand it to the
  /// host's auto-print callback. The POST response usually only carries
  /// `data.id` / `data.invoice_number`, so we re-fetch the detail endpoint
  /// (which mirrors the dashboard layout) before building the receipt.
  Future<void> _printDepositReceipt(
    Map<String, dynamic> createResponse,
    Future<void> Function({
      required OrderReceiptData receiptData,
      String? invoiceId,
    }) printCb,
  ) async {
    try {
      final responseData = createResponse['data'];
      Map<String, dynamic>? envelope;

      // Some backends echo the full detail envelope inside the create
      // response — try that first to avoid the second round-trip.
      if (responseData is Map &&
          (responseData['invoice'] is Map || responseData['branch'] is Map)) {
        envelope = Map<String, dynamic>.from(responseData);
      }

      if (envelope == null) {
        final depositId = _extractDepositId(createResponse);
        if (depositId == null) {
          debugPrint(
              '⚠️ [Deposit] no id in create response — skipping auto-print '
              'response=$createResponse');
          return;
        }
        debugPrint(
            '🧾 [Deposit] fetching detail for id=$depositId to build receipt');
        final client = BaseClient();
        final detail =
            await client.get(ApiConstants.depositDetailsEndpoint(depositId));
        if (detail is Map<String, dynamic>) {
          final inner = detail['data'];
          if (inner is Map) {
            envelope = inner.map((k, v) => MapEntry(k.toString(), v));
          } else {
            envelope = detail;
          }
        }
      }

      if (envelope == null) {
        debugPrint('⚠️ [Deposit] detail envelope unavailable — skipping print');
        return;
      }

      final receipt = ReceiptBuilderService.buildDepositReceipt(
        envelope: envelope,
      );
      debugPrint(
          '🧾 [Deposit] dispatching to printer: invoice=${receipt.invoiceNumber} '
          'items=${receipt.items.length} total=${receipt.totalInclVat}');
      await printCb(
        receiptData: receipt,
        invoiceId: receipt.invoiceNumber,
      );
      debugPrint('✅ [Deposit] auto-print completed');
    } catch (e, stack) {
      debugPrint('⚠️ [Deposit] auto-print failed: $e\n$stack');
      // Surface a hint to the cashier — the standard print-failure snackbar
      // only fires from inside the orchestrator, but if we threw before
      // reaching it (e.g. detail fetch crashed) the user would see nothing.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_tr(
              'تعذر طباعة فاتورة العربون',
              'Failed to print deposit receipt',
            )),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  int? _extractDepositId(Map<String, dynamic> response) {
    int? parse(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v);
      return null;
    }

    final candidates = <dynamic>[
      response['id'],
      response['data'] is Map ? (response['data'] as Map)['id'] : null,
      response['data'] is Map
          ? ((response['data'] as Map)['deposit'] is Map
              ? ((response['data'] as Map)['deposit'] as Map)['id']
              : null)
          : null,
    ];
    for (final c in candidates) {
      final parsed = parse(c);
      if (parsed != null && parsed > 0) return parsed;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isCompact = size.width < 700;
    final insetPadding = EdgeInsets.symmetric(
      horizontal: isCompact ? 12 : 24,
      vertical: isCompact ? 16 : 24,
    );
    final dialogWidth =
        (size.width - insetPadding.horizontal).clamp(280.0, 760.0).toDouble();
    final dialogHeight =
        (size.height - insetPadding.vertical).clamp(420.0, 820.0).toDouble();

    return Dialog(
      insetPadding: insetPadding,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Column(
          children: [
            // ── Header ──
            Container(
              padding: EdgeInsets.all(isCompact ? 16 : 24),
              decoration: const BoxDecoration(
                color: Color(0xFFF58220),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _tr('إنشاء عربون', 'Create Deposit'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: isCompact ? 18 : 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _tr('اختر الخدمات وأكمل البيانات',
                              'Select services and fill in details'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _isCreating
                        ? null
                        : () => Navigator.pop(context, false),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),

            // ── Body ──
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Error message
                    if (_error != null)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.red[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red[200]!),
                        ),
                        child: Text(
                          _error!,
                          style:
                              TextStyle(color: Colors.red[700], fontSize: 12),
                        ),
                      ),

                    // ── 1. Customer Selector ──
                    _buildSectionLabel(
                        _tr('العميل', 'Customer'), LucideIcons.user),
                    const SizedBox(height: 8),
                    _buildCustomerSelector(),
                    const SizedBox(height: 16),

                    // ── 2. Selected Services List ──
                    _buildSectionLabel(
                        _tr('الخدمات', 'Services'), LucideIcons.scissors),
                    const SizedBox(height: 8),
                    if (_selectedServices.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        decoration: BoxDecoration(
                          color: context.appBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: context.appBorder),
                        ),
                        child: Center(
                          child: Text(
                            _tr('لم يتم اختيار خدمات بعد',
                                'No services selected yet'),
                            style: TextStyle(
                                color: Colors.grey.shade400, fontSize: 13),
                          ),
                        ),
                      )
                    else
                      ...List.generate(_selectedServices.length, (index) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _buildEditableServiceCard(
                              _selectedServices[index]),
                        );
                      }),
                    const SizedBox(height: 8),

                    // ── 3. Add Service Button ──
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _openServicePicker,
                        icon: const Icon(LucideIcons.plus, size: 16),
                        label: Text(_tr('إضافة خدمة', 'Add Service')),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFF58220),
                          side: const BorderSide(color: Color(0xFFF58220)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── 4. Deposit amount + auto-calculated tax/total ──
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: context.appBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: context.appBorder),
                      ),
                      child: Column(
                        children: [
                          // Editable deposit amount — matches the web
                          // dashboard's `price` field. Tax + total below
                          // recalculate live as the cashier types.
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _tr('مبلغ العربون', 'Deposit Amount'),
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF475569),
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 140,
                                child: TextField(
                                  controller: _depositAmountController,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  textAlign: TextAlign.end,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFFF58220),
                                  ),
                                  decoration: InputDecoration(
                                    isDense: true,
                                    contentPadding:
                                        const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 10),
                                    suffixText: ApiConstants.currency,
                                    suffixStyle: TextStyle(
                                      color: Colors.grey.shade500,
                                      fontSize: 11,
                                    ),
                                    hintText: '0.${'0' * ApiConstants.digitsNumber}',
                                    border: OutlineInputBorder(
                                      borderRadius:
                                          BorderRadius.circular(8),
                                      borderSide: const BorderSide(
                                          color: Color(0xFFE2E8F0)),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius:
                                          BorderRadius.circular(8),
                                      borderSide: const BorderSide(
                                          color: Color(0xFFE2E8F0)),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius:
                                          BorderRadius.circular(8),
                                      borderSide: const BorderSide(
                                          color: Color(0xFFF58220)),
                                    ),
                                  ),
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                            ],
                          ),
                          if (ApiConstants.isTaxActive) ...[
                            const SizedBox(height: 6),
                            _buildTotalRow(
                              _tr(
                                'الضريبة (${ApiConstants.taxPercentage}%)',
                                'Tax (${ApiConstants.taxPercentage}%)',
                              ),
                              '${_amountFormatter.format(_tax)} ${ApiConstants.currency}',
                            ),
                          ],
                          const Divider(height: 16),
                          _buildTotalRow(
                            _tr('الإجمالي', 'Total'),
                            '${_amountFormatter.format(_total)} ${ApiConstants.currency}',
                            isBold: true,
                            color: const Color(0xFFF58220),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── 5. Booking Date & Time ──
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildSectionLabel(
                                  _tr('تاريخ الحجز', 'Booking Date'),
                                  LucideIcons.calendarDays),
                              const SizedBox(height: 8),
                              InkWell(
                                onTap: _pickBookingDate,
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: context.appCardBg,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                        color: context.appBorder),
                                  ),
                                  child: Text(
                                    DateFormat('yyyy-MM-dd')
                                        .format(_bookingDate),
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildSectionLabel(
                                  _tr('وقت الحجز', 'Booking Time'),
                                  LucideIcons.clock),
                              const SizedBox(height: 8),
                              InkWell(
                                onTap: _pickBookingTime,
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: context.appCardBg,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                        color: context.appBorder),
                                  ),
                                  child: Text(
                                    '${_bookingTime.hour.toString().padLeft(2, '0')}:${_bookingTime.minute.toString().padLeft(2, '0')}',
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ── 6. Payment Method ──
                    _buildSectionLabel(
                        _tr('طريقة الدفع', 'Payment Method'),
                        LucideIcons.creditCard),
                    const SizedBox(height: 8),
                    _buildPaymentMethodSection(),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),

            // ── Footer ──
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: context.appBg,
                border: Border(top: BorderSide(color: Colors.grey[200]!)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isCreating
                          ? null
                          : () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(_tr('إلغاء', 'Cancel')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isCreating ? null : _createDeposit,
                      icon: _isCreating
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(LucideIcons.check, size: 16),
                      label: Text(
                        _isCreating
                            ? _tr('جارٍ الإنشاء...', 'Creating...')
                            : _tr('إنشاء عربون', 'Create Deposit'),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF58220),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
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
    );
  }

  // ── Section label ──
  Widget _buildSectionLabel(String label, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 15, color: const Color(0xFF64748B)),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Color(0xFF475569),
          ),
        ),
      ],
    );
  }

  // ── Customer selector ──
  Widget _buildCustomerSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Search field
        TextField(
          controller: _customerSearchController,
          onChanged: _onCustomerSearch,
          decoration: InputDecoration(
            hintText: _tr('ابحث عن عميل...', 'Search customer...'),
            hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
            prefixIcon: const Icon(Icons.search, size: 18),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFF58220)),
            ),
            filled: true,
            fillColor: Colors.white,
            isDense: true,
          ),
        ),
        const SizedBox(height: 6),
        // Customer dropdown list
        Container(
          constraints: const BoxConstraints(maxHeight: 120),
          decoration: BoxDecoration(
            border: Border.all(color: context.appBorder),
            borderRadius: BorderRadius.circular(10),
            color: Colors.white,
          ),
          child: _isLoadingCustomers
              ? const Center(
                  child: Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                ))
              : _customers.isEmpty
                  ? Center(
                      child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        _tr('لا يوجد عملاء', 'No customers'),
                        style:
                            TextStyle(color: Colors.grey[400], fontSize: 12),
                      ),
                    ))
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: _customers.length,
                      padding: EdgeInsets.zero,
                      itemBuilder: (ctx, idx) {
                        final c = _customers[idx];
                        final name = c['label']?.toString() ??
                            c['name']?.toString() ??
                            '';
                        final id = c['value'] ?? c['id'];
                        final isSelected =
                            _selectedCustomer?['value'] == id ||
                                _selectedCustomer?['id'] == id;
                        return InkWell(
                          onTap: () => setState(() => _selectedCustomer = c),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFFF58220)
                                      .withValues(alpha: 0.08)
                                  : null,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  isSelected
                                      ? LucideIcons.checkCircle
                                      : LucideIcons.circle,
                                  size: 16,
                                  color: isSelected
                                      ? const Color(0xFFF58220)
                                      : Colors.grey[400],
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    name,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: isSelected
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                      color: context.appText,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ),
        // Selected customer badge
        if (_selectedCustomer != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF22C55E).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(LucideIcons.checkCircle,
                      size: 14, color: Color(0xFF22C55E)),
                  const SizedBox(width: 6),
                  Text(
                    _selectedCustomer!['label']?.toString() ??
                        _selectedCustomer!['name']?.toString() ??
                        '',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF22C55E),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  // ── Editable service card (like _buildEditableItemCard) ──
  Widget _buildEditableServiceCard(_SelectedService service) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.appCardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.appBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Service name + delete button
          Row(
            children: [
              Expanded(
                child: Text(
                  service.name,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: context.appText,
                  ),
                ),
              ),
              IconButton(
                onPressed: () {
                  setState(() {
                    _selectedServices.remove(service);
                  });
                },
                icon: const Icon(LucideIcons.trash2, size: 16),
                color: const Color(0xFFEF4444),
                tooltip: _tr('حذف', 'Remove'),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Quantity +/- and read-only catalog price. The web dashboard
          // doesn't let cashiers edit per-service prices on a deposit —
          // they pick services for the booking record and type the deposit
          // amount in the totals card below.
          Row(
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _QtyButton(
                    icon: LucideIcons.minus,
                    onPressed: () {
                      setState(() {
                        service.quantity =
                            (service.quantity - 1).clamp(1, 9999);
                      });
                    },
                  ),
                  const SizedBox(width: 8),
                  Text(
                    service.quantity.toString(),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 8),
                  _QtyButton(
                    icon: LucideIcons.plus,
                    onPressed: () {
                      setState(() {
                        service.quantity =
                            (service.quantity + 1).clamp(1, 9999);
                      });
                    },
                  ),
                ],
              ),
              const Spacer(),
              Text(
                '${_amountFormatter.format(service.catalogPrice * service.quantity)} ${ApiConstants.currency}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFF58220),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Totals row ──
  Widget _buildTotalRow(String label, String value,
      {bool isBold = false, Color? color}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            color: color ?? const Color(0xFF475569),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: isBold ? 15 : 13,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            color: color ?? context.appText,
          ),
        ),
      ],
    );
  }

  // ── Payment method section (chips + amount) ──
  Widget _buildPaymentMethodSection() {
    if (_isLoadingPayMethods) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }

    if (_payMethods.isEmpty) {
      return Text(
        _tr('لا توجد طرق دفع', 'No payment methods'),
        style: TextStyle(color: Colors.grey[400], fontSize: 12),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Payment method chips
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _payMethods.map((method) {
            final key =
                method['value']?.toString() ?? method['id']?.toString() ?? '';
            final label = method['label']?.toString() ?? key;
            final isSelected = _selectedPayMethodKey == key;

            return ChoiceChip(
              selected: isSelected,
              label: Text(label),
              onSelected: (_) {
                setState(() => _selectedPayMethodKey = key);
              },
              selectedColor: const Color(0xFFF58220).withValues(alpha: 0.18),
              backgroundColor: const Color(0xFFF8FAFC),
              labelStyle: TextStyle(
                color: isSelected
                    ? const Color(0xFFF58220)
                    : const Color(0xFF475569),
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
              side: BorderSide(
                color: isSelected
                    ? const Color(0xFFF58220)
                    : const Color(0xFFE2E8F0),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

// ── Quantity Button (same as edit_order_dialog) ──
class _QtyButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;

  const _QtyButton({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: context.appSurfaceAlt,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: context.appBorder),
        ),
        child: Icon(icon, size: 14, color: context.appText),
      ),
    );
  }
}

// ── Selected Service model ──
class _SelectedService {
  final String id;
  final String name;
  final double catalogPrice;
  int quantity;

  _SelectedService({
    required this.id,
    required this.name,
    required this.catalogPrice,
    this.quantity = 1,
  });
}

/// Strip currency suffix / thousand separators / RTL marks the API may
/// return alongside numbers (e.g. "350.00 ر.س", "1,250.50 ر.س") and parse
/// to double. Falls back to 0.0 for non-numeric input.
double _parseServerPrice(dynamic value) {
  if (value == null) return 0.0;
  if (value is num) return value.toDouble();
  var cleaned = value.toString().replaceAll(RegExp(r'[^\d.\-]'), '');
  if (cleaned.isEmpty) return 0.0;
  final dotIndex = cleaned.indexOf('.');
  if (dotIndex >= 0) {
    cleaned = cleaned.substring(0, dotIndex + 1) +
        cleaned.substring(dotIndex + 1).replaceAll('.', '');
  }
  return double.tryParse(cleaned) ?? 0.0;
}

// ── Service Picker Dialog (like _ProductPickerDialog) ──
class _ServicePickerDialog extends StatefulWidget {
  final String Function(String ar, String en) tr;

  const _ServicePickerDialog({required this.tr});

  @override
  State<_ServicePickerDialog> createState() => _ServicePickerDialogState();
}

class _ServicePickerDialogState extends State<_ServicePickerDialog> {
  final BaseClient _client = BaseClient();
  final TextEditingController _searchController = TextEditingController();
  final NumberFormat _amountFormatter = NumberFormat('#,##0.##');

  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _services = [];
  String _selectedCategory = 'all';
  bool _isLoadingServices = false;
  // Type toggle: 'services' (regular) or 'packageServices' (bundled
  // packages). Uses the same endpoint the salon main screen uses
  // (`bookingCreateMetadataEndpoint?type=...`) so both lists carry the
  // same shape (`id`, `name`, `price`, `category_id`).
  String _serviceMode = 'services';

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _loadServices();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    try {
      final response =
          await _client.get(ApiConstants.serviceCategoriesEndpoint);
      final data =
          response is Map<String, dynamic> ? response['data'] : response;
      if (data is List && mounted) {
        setState(() {
          _categories = data
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        });
      }
    } catch (_) {
      // Categories are optional; ignore errors
    }
  }

  Future<void> _loadServices() async {
    setState(() {
      _isLoadingServices = true;
      _services = [];
    });
    try {
      final endpoint =
          '${ApiConstants.bookingCreateMetadataEndpoint}?type=$_serviceMode&page=1&per_page=100';
      final response = await _client.get(endpoint);
      List<Map<String, dynamic>> items = [];
      dynamic data =
          response is Map<String, dynamic> ? (response['data'] ?? response) : response;
      if (data is Map<String, dynamic>) {
        if (data['collection'] is Map &&
            (data['collection'] as Map)['data'] is List) {
          data = (data['collection'] as Map)['data'];
        } else if (data['services'] is List) {
          data = data['services'];
        } else if (data['data'] is List) {
          data = data['data'];
        }
      }
      if (data is List) {
        items = data
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
      if (mounted) {
        setState(() {
          _services = items;
          _isLoadingServices = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingServices = false);
    }
  }

  void _onModeChanged(String mode) {
    if (mode == _serviceMode) return;
    setState(() {
      _serviceMode = mode;
      _selectedCategory = 'all';
      _searchController.clear();
    });
    _loadServices();
  }

  List<Map<String, dynamic>> get _filteredServices {
    var list = _services;

    // Filter by category
    if (_selectedCategory != 'all') {
      list = list.where((s) {
        final catId = s['category_id']?.toString() ?? '';
        return catId == _selectedCategory;
      }).toList();
    }

    // Filter by search
    final query = _searchController.text.trim().toLowerCase();
    if (query.isNotEmpty) {
      list = list.where((s) {
        final name = (s['name'] ?? s['label'] ?? '').toString().toLowerCase();
        return name.contains(query);
      }).toList();
    }

    return list;
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isCompact = size.width < 700;
    final dialogWidth = isCompact ? size.width * 0.92 : size.width * 0.7;
    final dialogHeight = isCompact ? size.height * 0.82 : size.height * 0.75;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _serviceMode == 'packageServices'
                          ? widget.tr('اختيار باقة', 'Select a Package')
                          : widget.tr('اختيار خدمة', 'Select a Service'),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: context.appText,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),

            // Service-type toggle (Services / Service Packages) — mirrors
            // the salon main screen so the cashier can pick from either
            // catalogue when creating a deposit booking.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: _modeChip(
                      label: widget.tr('الخدمات', 'Services'),
                      icon: LucideIcons.scissors,
                      isSelected: _serviceMode == 'services',
                      onTap: () => _onModeChanged('services'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _modeChip(
                      label: widget.tr('باقات الخدمات', 'Service Packages'),
                      icon: LucideIcons.package,
                      isSelected: _serviceMode == 'packageServices',
                      onTap: () => _onModeChanged('packageServices'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Search field
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: _serviceMode == 'packageServices'
                      ? widget.tr('ابحث عن باقة', 'Search packages')
                      : widget.tr('ابحث عن خدمة', 'Search services'),
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: context.appSurfaceAlt,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Category chips
            if (_categories.isNotEmpty)
              SizedBox(
                height: 40,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: _categories.length + 1,
                  itemBuilder: (context, index) {
                    final isAll = index == 0;
                    final category = isAll ? null : _categories[index - 1];
                    final label = isAll
                        ? widget.tr('الكل', 'All')
                        : category?['label']?.toString() ??
                            category?['name']?.toString() ??
                            '';
                    final value = isAll
                        ? 'all'
                        : category?['value']?.toString() ??
                            category?['id']?.toString() ??
                            '';
                    final selected = _selectedCategory == value;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        selected: selected,
                        label: Text(label),
                        onSelected: (_) {
                          setState(() => _selectedCategory = value);
                        },
                        selectedColor:
                            const Color(0xFFF58220).withValues(alpha: 0.18),
                        labelStyle: TextStyle(
                          color: selected
                              ? const Color(0xFFF58220)
                              : const Color(0xFF475569),
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                        side: BorderSide(
                          color: selected
                              ? const Color(0xFFF58220)
                              : const Color(0xFFE2E8F0),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 8),

            // Services list
            Expanded(
              child: _isLoadingServices
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredServices.isEmpty
                      ? Center(
                          child: Text(
                            _serviceMode == 'packageServices'
                                ? widget.tr('لا توجد باقات', 'No packages found')
                                : widget.tr('لا توجد خدمات', 'No services found'),
                            style: const TextStyle(color: Colors.grey),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _filteredServices.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1, color: Color(0xFFE2E8F0)),
                          itemBuilder: (context, index) {
                            final service = _filteredServices[index];
                            final label =
                                (service['name'] ?? service['label'] ?? '')
                                    .toString();
                            // The API returns prices as a localised string
                            // ("350.00 ر.س"), not a raw number — strip the
                            // currency suffix before parsing so the picker
                            // doesn't show every service as "0".
                            final price =
                                _parseServerPrice(service['price']);
                            final serviceId =
                                (service['id'] ?? service['value'] ?? '')
                                    .toString();

                            return InkWell(
                              onTap: () {
                                Navigator.pop(
                                  context,
                                  _SelectedService(
                                    id: serviceId,
                                    name: label,
                                    catalogPrice: price,
                                  ),
                                );
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 12, horizontal: 4),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF58220)
                                            .withValues(alpha: 0.1),
                                        borderRadius:
                                            BorderRadius.circular(8),
                                      ),
                                      child: const Icon(
                                        LucideIcons.scissors,
                                        size: 16,
                                        color: Color(0xFFF58220),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        label,
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: context.appText,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      '${_amountFormatter.format(price)} ${ApiConstants.currency}',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFFF58220),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _modeChip({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    const brand = Color(0xFFF58220);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected ? brand.withValues(alpha: 0.12) : context.appCardBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? brand : context.appBorder,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 16,
                color: isSelected ? brand : context.appTextMuted),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? brand : context.appText,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
