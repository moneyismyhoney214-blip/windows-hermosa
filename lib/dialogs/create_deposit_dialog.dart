import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../locator.dart';
import '../models/receipt_data.dart';
import '../services/api/api_constants.dart';
import '../services/api/base_client.dart';
import '../services/api/filter_service.dart';
import '../services/api/salon_employee_service.dart';
import '../services/app_themes.dart';
import '../services/language_service.dart';
import '../services/receipt_builder_service.dart';
import '../utils/ui_feedback.dart';

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

  Map<String, dynamic>? _selectedCustomer;
  final List<_SelectedService> _selectedServices = [];
  DateTime _bookingDate = DateTime.now();
  TimeOfDay _bookingTime = TimeOfDay.now();

  List<Map<String, dynamic>> _payMethods = [];
  String? _selectedPayMethodKey;

  // Deposit amount mirrors the dashboard's `price` field; dashboard HAR sends `pays[i][amount]=0` for every method.
  final TextEditingController _depositAmountController = TextEditingController();

  List<Map<String, dynamic>> _customers = [];
  final TextEditingController _customerSearchController =
      TextEditingController();
  Timer? _customerSearchDebounce;
  bool _isLoadingCustomers = false;

  bool _isLoadingPayMethods = false;
  bool _isCreating = false;
  String? _error;


  // Tax rate follows active branch's `taxObject`; 0.0 when VAT disabled.
  double get _taxRate => ApiConstants.effectiveTaxRate;

  // Subtotal is what the cashier typed (mirrors dashboard `price`); tax/total derive from it.
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
      // /payMethods requires `type ∈ {incomings, outgoings, online}` or it 422s; deposits are incomings.
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
      builder: (ctx) => const _ServicePickerDialog(),
    );
    if (result != null && mounted) {
      setState(() {
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
    if (_selectedCustomer == null) {
      setState(() =>
          _error = translationService.t('please_select_customer'));
      return;
    }
    if (_selectedServices.isEmpty) {
      setState(() =>
          _error = translationService.t('please_select_at_least_one_service'));
      return;
    }
    if (_subtotal <= 0) {
      setState(
          () => _error = translationService.t('total_must_be_positive'));
      return;
    }

    setState(() {
      _isCreating = true;
      _error = null;
    });

    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final bookingDateStr = DateFormat('yyyy-MM-dd').format(_bookingDate);
      // Backend `booking_time` uses Laravel `H:i:s` — pad seconds to `00` or it 422s.
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

      // Dedupe service IDs: `service_deposit` pivot has PK (deposit_id, service_id) — duplicates 1062.
      final seenServiceIds = <String>{};
      int serviceIndex = 0;
      for (final service in _selectedServices) {
        if (!seenServiceIds.add(service.id)) continue;
        fields['services[$serviceIndex]'] = service.id;
        serviceIndex++;
      }

      // Mirror dashboard HAR: every method with amount=0; fall back to single cash row if methods missing (pays required non-empty).
      const zeroAmount = '0';
      if (_payMethods.isEmpty) {
        fields['pays[0][name]'] = translationService.t('cash_payment');
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

      // Await print before pop so the orchestrator's failure snackbars can fire (unawaited silently swallowed them).
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

      // Some backends echo the full detail envelope in the create response — use it to skip the round-trip.
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
      // Surface failure to cashier if we threw before reaching the orchestrator's snackbar.
      if (mounted) {
        UiFeedback.warning(
          context,
          translationService.t('deposit_receipt_print_failed'),
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
                          translationService.t('create_deposit'),
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
                          translationService.t('deposit_subtitle'),
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

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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

                    _buildSectionLabel(
                        translationService.t('customer'), LucideIcons.user),
                    const SizedBox(height: 8),
                    _buildCustomerSelector(),
                    const SizedBox(height: 16),

                    _buildSectionLabel(
                        translationService.t('services'), LucideIcons.scissors),
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
                            translationService.t('no_services_selected_yet'),
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

                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _openServicePicker,
                        icon: const Icon(LucideIcons.plus, size: 16),
                        label: Text(translationService.t('add_service')),
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
                          // Editable deposit amount (dashboard `price`); tax/total recalc live.
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  translationService.t('deposit_amount'),
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
                              translationService.t(
                                'tax_with_percent',
                                args: {'percent': ApiConstants.taxPercentage},
                              ),
                              '${_amountFormatter.format(_tax)} ${ApiConstants.currency}',
                            ),
                          ],
                          const Divider(height: 16),
                          _buildTotalRow(
                            translationService.t('total'),
                            '${_amountFormatter.format(_total)} ${ApiConstants.currency}',
                            isBold: true,
                            color: const Color(0xFFF58220),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildSectionLabel(
                                  translationService.t('booking_date'),
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
                                  translationService.t('booking_time'),
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

                    _buildSectionLabel(
                        translationService.t('payment_method'),
                        LucideIcons.creditCard),
                    const SizedBox(height: 8),
                    _buildPaymentMethodSection(),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),

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
                      child: Text(translationService.t('cancel')),
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
                            ? translationService.t('creating_dots')
                            : translationService.t('create_deposit'),
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

  Widget _buildCustomerSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _customerSearchController,
          onChanged: _onCustomerSearch,
          decoration: InputDecoration(
            hintText: translationService.t('search_customer_dots'),
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
                        translationService.t('no_customers_short'),
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
                tooltip: translationService.t('remove'),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Read-only catalog price; cashier types deposit amount in the totals card.
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
        translationService.t('no_payment_methods'),
        style: TextStyle(color: Colors.grey[400], fontSize: 12),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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

class _SelectedService {
  final String id;
  final String name;
  final double catalogPrice;
  // Inline init satisfies null-safety after `dart fix` removed the ctor param; mutated by +/- controls.
  int quantity = 1;

  _SelectedService({
    required this.id,
    required this.name,
    required this.catalogPrice,
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

class _ServicePickerDialog extends StatefulWidget {
  const _ServicePickerDialog();

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
  // 'services' (regular) or 'packageServices' (bundled); same endpoint/shape as salon main screen.
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

    if (_selectedCategory != 'all') {
      list = list.where((s) {
        final catId = s['category_id']?.toString() ?? '';
        return catId == _selectedCategory;
      }).toList();
    }

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
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _serviceMode == 'packageServices'
                          ? translationService.t('select_package')
                          : translationService.t('select_service'),
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

            // Service-type toggle mirrors salon main screen.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: _modeChip(
                      label: translationService.t('services'),
                      icon: LucideIcons.scissors,
                      isSelected: _serviceMode == 'services',
                      onTap: () => _onModeChanged('services'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _modeChip(
                      label: translationService.t('service_packages'),
                      icon: LucideIcons.package,
                      isSelected: _serviceMode == 'packageServices',
                      onTap: () => _onModeChanged('packageServices'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: _serviceMode == 'packageServices'
                      ? translationService.t('search_packages')
                      : translationService.t('search_services'),
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
                        ? translationService.t('all')
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

            Expanded(
              child: _isLoadingServices
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredServices.isEmpty
                      ? Center(
                          child: Text(
                            _serviceMode == 'packageServices'
                                ? translationService.t('no_packages_found')
                                : translationService.t('no_services_found'),
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
                            // API returns prices like "350.00 ر.س" — strip currency before parsing.
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
