import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../dialogs/invoice_details_dialog.dart';
import '../dialogs/invoice_refund_dialog.dart';
import '../models/booking_invoice.dart';
import '../models/receipt_data.dart';
import '../services/api/api_constants.dart';
import '../services/api/base_client.dart';
import '../services/api/error_handler.dart';
import '../services/api/order_service.dart';
import '../services/api/branch_service.dart';
import '../services/display_app_service.dart';
import '../services/invoice_preview_helper.dart';
import '../services/language_service.dart';
import '../locator.dart';

class InvoicesScreen extends StatefulWidget {
  final VoidCallback onBack;

  const InvoicesScreen({
    super.key,
    required this.onBack,
  });

  @override
  State<InvoicesScreen> createState() => _InvoicesScreenState();
}

class _InvoicesScreenState extends State<InvoicesScreen> {
  final OrderService _orderService = getIt<OrderService>();
  final DisplayAppService _displayAppService = getIt<DisplayAppService>();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  final NumberFormat _amountFormatter = NumberFormat('#,##0.##');

  List<Invoice> _invoices = [];
  final Set<int> _refundingInvoiceIds = <int>{};
  Timer? _autoRefreshTimer;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _isSendingWhatsApp = false;
  bool _invoiceHelperSupported = true;
  bool _hasMore = true;
  String? _error;
  String _activeDate = '';

  int _page = 1;
  static const int _perPage = 20;

  String _searchQuery = '';

  String get _langCode =>
      translationService.currentLanguageCode.trim().toLowerCase();
  bool get _useArabicUi =>
      _langCode.startsWith('ar') || _langCode.startsWith('ur');
  String _tr(String ar, String nonArabic) => _useArabicUi ? ar : nonArabic;

  @override
  void initState() {
    super.initState();
    _activeDate = _todayForApi();
    _scrollController.addListener(_onScroll);
    _loadInvoices(reset: true);
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!_isLoading && !_isLoadingMore && mounted) {
        _loadInvoices(reset: true);
      }
    });
  }

  void _onScroll() {
    if (!_hasMore || _isLoadingMore || _isLoading) return;
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 200) {
      _loadInvoices(reset: false);
    }
  }

  Future<void> _loadInvoices({required bool reset}) async {
    final todayDate = _todayForApi();
    final shouldReset = reset || _activeDate != todayDate;
    if (_activeDate != todayDate) {
      _activeDate = todayDate;
    }

    if (shouldReset) {
      setState(() {
        _isLoading = true;
        _error = null;
        _page = 1;
        _hasMore = true;
      });
    } else {
      setState(() => _isLoadingMore = true);
    }

    try {
      final response = await _orderService.getInvoices(
        dateFrom: _activeDate,
        dateTo: _activeDate,
        search: _resolveApiSearchQuery(),
        page: _page,
        perPage: _perPage,
      );

      final nextInvoices = _invoicesFromResponse(response);
      final hasMore = _resolveHasMore(response, nextInvoices.length);

      if (!mounted) return;
      setState(() {
        if (shouldReset) {
          _invoices = nextInvoices;
        } else {
          _invoices = [..._invoices, ...nextInvoices];
        }
        _isLoading = false;
        _isLoadingMore = false;
        _hasMore = hasMore;
        if (_hasMore) _page += 1;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isLoadingMore = false;
        _error = e.toString();
      });
    }
  }

  List<Invoice> _invoicesFromResponse(dynamic response) {
    final list = _extractListResponse(response);
    if (list is! List) return const <Invoice>[];
    return list
        .whereType<Map>()
        .map((e) => Invoice.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  dynamic _extractListResponse(dynamic response) {
    if (response is List) return response;
    if (response is Map) {
      final direct = response['data'];
      if (direct is List) return direct;
      if (direct is Map && direct['data'] is List) {
        return direct['data'];
      }
    }
    return const [];
  }

  bool _resolveHasMore(dynamic response, int fetchedCount) {
    int? parseInt(dynamic value) {
      if (value == null) return null;
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value.toString());
    }

    if (response is Map) {
      final meta = response['meta'] is Map ? response['meta'] as Map : null;
      if (meta != null) {
        final current = parseInt(meta['current_page']);
        final last = parseInt(meta['last_page']);
        if (current != null && last != null) {
          return current < last;
        }
      }
      final data = response['data'];
      if (data is Map) {
        final meta = data['meta'] is Map ? data['meta'] as Map : null;
        if (meta != null) {
          final current = parseInt(meta['current_page']);
          final last = parseInt(meta['last_page']);
          if (current != null && last != null) {
            return current < last;
          }
        }
      }
    }

    return fetchedCount >= _perPage;
  }

  String _todayForApi() => DateFormat('yyyy-MM-dd').format(DateTime.now());

  String _normalizeSearchToken(String value) {
    return value
        .toString()
        .toLowerCase()
        .replaceAll('#', '')
        .replaceAll(RegExp(r'\s+'), '')
        .trim();
  }

  bool _hasLetters(String value) {
    return RegExp(r'[A-Za-z]').hasMatch(value);
  }

  String? _resolveApiSearchQuery() {
    final query = _searchQuery.trim();
    if (query.isEmpty) return null;
    return _hasLetters(query) ? query : null;
  }

  Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), v));
    }
    return null;
  }

  double _parseNum(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    final text =
        value.toString().replaceAll(RegExp(r'[^0-9.\\-]'), '').trim();
    return double.tryParse(text) ?? 0.0;
  }

  String _cleanText(dynamic value) {
    final raw = value?.toString() ?? '';
    if (raw.isEmpty) return '';
    return raw.replaceAll(RegExp(r'[\u0000-\u001F\u007F]'), '').trim();
  }

  String? _firstNonEmptyText(
    List<dynamic> values, {
    bool allowZero = true,
  }) {
    for (final raw in values) {
      final text = _cleanText(raw);
      if (text.isNotEmpty && text.toLowerCase() != 'null') {
        if (!allowZero && (text == '0' || text == '#0')) continue;
        return text;
      }
    }
    return null;
  }

  String _resolvePaymentMethodLabel(dynamic paysRaw) {
    final pays = paysRaw is List ? paysRaw : const [];
    final labels = <String>{};
    for (final pay in pays) {
      final map = _asMap(pay);
      final method = (map?['pay_method'] ?? map?['method'] ?? map?['name'])
          ?.toString()
          .trim()
          .toLowerCase();
      switch (method) {
        case 'cash':
        case 'نقدي':
        case 'كاش':
          labels.add('نقدي');
          break;
        case 'card':
        case 'mada':
        case 'visa':
        case 'benefit':
        case 'benefit_pay':
        case 'benefit pay':
        case 'بطاقة':
        case 'مدى':
        case 'فيزا':
        case 'ماستر':
        case 'ماستر كارد':
        case 'بينيفت':
        case 'بينيفت باي':
          labels.add('بطاقة');
          break;
        case 'stc':
        case 'stc_pay':
        case 'stc pay':
        case 'اس تي سي':
        case 'اس تي سي باي':
          labels.add('STC Pay');
          break;
        case 'bank_transfer':
        case 'bank':
        case 'bank transfer':
        case 'تحويل بنكي':
        case 'تحويل بنكى':
          labels.add('تحويل بنكي');
          break;
        case 'wallet':
        case 'المحفظة':
        case 'المحفظة الالكترونية':
        case 'المحفظة الإلكترونية':
          labels.add('محفظة');
          break;
        case 'cheque':
        case 'check':
        case 'شيك':
          labels.add('شيك');
          break;
        case 'petty_cash':
        case 'petty cash':
        case 'بيتي كاش':
          labels.add('بيتي كاش');
          break;
        case 'pay_later':
        case 'postpaid':
        case 'deferred':
        case 'pay later':
        case 'الدفع بالآجل':
        case 'الدفع بالاجل':
          labels.add('الدفع بالآجل');
          break;
        case 'tabby':
        case 'تابي':
          labels.add('تابي');
          break;
        case 'tamara':
        case 'تمارا':
          labels.add('تمارا');
          break;
        case 'keeta':
        case 'كيتا':
          labels.add('كيتا');
          break;
        case 'my_fatoorah':
        case 'myfatoorah':
        case 'my fatoorah':
        case 'ماي فاتورة':
        case 'ماي فاتوره':
          labels.add('ماي فاتورة');
          break;
        case 'jahez':
        case 'جاهز':
          labels.add('جاهز');
          break;
        case 'talabat':
        case 'طلبات':
          labels.add('طلبات');
          break;
      }
    }
    if (labels.isEmpty) return 'دفع';
    return labels.join(' + ');
  }

  List<ReceiptPayment> _resolvePaymentsList(dynamic paysRaw) {
    final pays = paysRaw is List ? paysRaw : const [];
    final payments = <ReceiptPayment>[];
    for (final pay in pays) {
      final map = _asMap(pay);
      if (map == null) continue;
      final method = (map['pay_method'] ?? map['method'] ?? map['name'])
          ?.toString()
          .trim()
          .toLowerCase();
      final numericAmount = _parseNum(map['amount'] ?? map['value'] ?? map['paid'] ?? map['total']);
      if (method == null || method.isEmpty) continue;

      String label = 'دفع';
      switch (method) {
        case 'cash':
        case 'نقدي':
        case 'كاش':
          label = 'نقدي';
          break;
        case 'card':
        case 'mada':
        case 'visa':
        case 'benefit':
        case 'benefit_pay':
        case 'benefit pay':
        case 'بطاقة':
        case 'مدى':
        case 'فيزا':
        case 'ماستر':
        case 'ماستر كارد':
        case 'بينيفت':
        case 'بينيفت باي':
          label = 'بطاقة';
          break;
        case 'stc':
        case 'stc_pay':
        case 'stc pay':
        case 'اس تي سي':
        case 'اس تي سي باي':
          label = 'STC Pay';
          break;
        case 'bank_transfer':
        case 'bank':
        case 'bank transfer':
        case 'تحويل بنكي':
        case 'تحويل بنكى':
          label = 'تحويل بنكي';
          break;
        case 'wallet':
        case 'المحفظة':
        case 'المحفظة الالكترونية':
        case 'المحفظة الإلكترونية':
          label = 'محفظة';
          break;
        case 'cheque':
        case 'check':
        case 'شيك':
          label = 'شيك';
          break;
        case 'petty_cash':
        case 'petty cash':
        case 'بيتي كاش':
          label = 'بيتي كاش';
          break;
        case 'pay_later':
        case 'postpaid':
        case 'deferred':
        case 'pay later':
        case 'الدفع بالآجل':
        case 'الدفع بالاجل':
          label = 'الدفع بالآجل';
          break;
        case 'tabby':
        case 'تابي':
          label = 'تابي';
          break;
        case 'tamara':
        case 'تمارا':
          label = 'تمارا';
          break;
        case 'keeta':
        case 'كيتا':
          label = 'كيتا';
          break;
        case 'my_fatoorah':
        case 'myfatoorah':
        case 'my fatoorah':
        case 'ماي فاتورة':
        case 'ماي فاتوره':
          label = 'ماي فاتورة';
          break;
        case 'jahez':
        case 'جاهز':
          label = 'جاهز';
          break;
        case 'talabat':
        case 'طلبات':
          label = 'طلبات';
          break;
        default:
          label = method;
      }
      payments.add(ReceiptPayment(methodLabel: label, amount: numericAmount));
    }
    return payments;
  }

  List<ReceiptItem> _extractInvoiceReceiptItems(
    Map<String, dynamic> payload,
    Map<String, dynamic> invoiceMap,
  ) {
    const keys = [
      'items',
      'invoice_items',
      'meals',
      'booking_meals',
      'booking_products',
      'sales_meals',
      'card',
      'cart',
    ];
    for (final key in keys) {
      final raw = invoiceMap[key] ?? payload[key];
      if (raw is! List) continue;
      final items = raw
          .whereType<Map>()
          .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
          .map((item) {
        final qty =
            _parseNum(item['quantity']) > 0 ? _parseNum(item['quantity']) : 1.0;
        final unitPrice = _parseNum(
          item['unit_price'] ?? item['unitPrice'] ?? item['price'],
        );
        final parsedTotal = _parseNum(item['total'] ?? item['price']);
        final total = parsedTotal > 0 ? parsedTotal : unitPrice * qty;
        final name = _firstNonEmptyText([
              item['meal_name'],
              item['item_name'],
              item['name'],
            ]) ??
            '-';
        return ReceiptItem(
          nameAr: name,
          nameEn: name,
          quantity: qty,
          unitPrice: unitPrice,
          total: total,
        );
      }).toList(growable: false);
      if (items.isNotEmpty) return items;
    }
    return const [];
  }

  OrderReceiptData _buildReceiptDataFromInvoiceDetails(
    Map<String, dynamic> details,
    int invoiceId,
  ) {
    final payload = _asMap(details['data']) ?? details;
    final invoiceMap = _asMap(payload['invoice']) ?? payload;
    final branchMap = _asMap(payload['branch']) ?? _asMap(invoiceMap['branch']);
    final sellerMap = _asMap(payload['seller']) ?? _asMap(branchMap?['seller']);
    final items = _extractInvoiceReceiptItems(payload, invoiceMap);

    final total = _parseNum(
      invoiceMap['total'] ??
          invoiceMap['grand_total'] ??
          invoiceMap['invoice_total'] ??
          payload['total'],
    );
    final vat = _parseNum(
      invoiceMap['tax'] ??
          invoiceMap['vat'] ??
          invoiceMap['tax_value'] ??
          payload['tax'],
    );
    final subtotal = (total - vat).clamp(0.0, double.infinity);

    String? logoUrl = _firstNonEmptyText([
      branchMap?['logo'],
      _asMap(branchMap?['seller'])?['logo'],
      _asMap(branchMap?['original_seller'])?['logo'],
    ]);
    if (logoUrl != null && logoUrl.startsWith('/')) {
      logoUrl = 'https://portal.hermosaapp.com$logoUrl';
    }

    return OrderReceiptData(
      invoiceNumber: _firstNonEmptyText(
            [
              invoiceMap['invoice_number'],
              payload['invoice_number'],
              invoiceMap['id'],
              payload['id'],
              invoiceId,
            ],
            allowZero: false,
          ) ??
          invoiceId.toString(),
      issueDateTime: _firstNonEmptyText(
            [
              invoiceMap['ISO8601'],
              invoiceMap['created_at'],
              payload['ISO8601'],
              payload['created_at'],
              invoiceMap['date'],
            ],
          ) ??
          DateTime.now().toIso8601String(),
      sellerNameAr: _firstNonEmptyText(
            [
              branchMap?['seller_name'],
              sellerMap?['name'],
              branchMap?['name'],
              invoiceMap['seller_name'],
              payload['seller_name'],
            ],
          ) ??
          '',
      sellerNameEn: _firstNonEmptyText(
            [
              branchMap?['seller_name'],
              sellerMap?['name'],
              branchMap?['name'],
              invoiceMap['seller_name'],
              payload['seller_name'],
            ],
          ) ??
          '',
      vatNumber: _firstNonEmptyText(
            [
              branchMap?['tax_number'],
              sellerMap?['tax_number'],
              invoiceMap['tax_number'],
              branchMap?['vat_number'],
              sellerMap?['vat_number'],
              invoiceMap['vat_number'],
            ],
          ) ??
          '',
      branchName: _firstNonEmptyText(
            [branchMap?['seller_name'], branchMap?['name']],
          ) ??
          '',
      carNumber: _firstNonEmptyText(
            [
              _asMap(invoiceMap['type_extra'])?['car_number'],
              invoiceMap['car_number'],
            ],
          ) ??
          '',
      items: items,
      totalExclVat: subtotal,
      vatAmount: vat,
      totalInclVat: total,
      paymentMethod:
          _resolvePaymentMethodLabel(invoiceMap['pays'] ?? payload['pays']),
      payments: _resolvePaymentsList(invoiceMap['pays'] ?? payload['pays']),
      qrCodeBase64:
          (invoiceMap['qr_image'] ?? payload['qr_image'])?.toString() ?? '',
      sellerLogo: logoUrl,
      zatcaQrImage: _firstNonEmptyText([
        invoiceMap['zatca_qr_image'],
        payload['zatca_qr_image'],
      ]),
      branchAddress: _firstNonEmptyText([
        branchMap?['address'],
        branchMap?['district'],
        sellerMap?['address'],
      ]),
      branchMobile: _firstNonEmptyText([
        branchMap?['mobile'],
        branchMap?['telephone'],
        branchMap?['phone'],
        sellerMap?['mobile'],
        sellerMap?['phone'],
      ]),
      cashierName: _firstNonEmptyText([
        _asMap(invoiceMap['cashier'])?['name'],
        invoiceMap['cashier_name'],
        payload['cashier_name'],
      ]),
      clientName: _firstNonEmptyText([
        _asMap(invoiceMap['client'])?['name'],
        invoiceMap['client_name'],
        payload['client_name'],
      ]),
      clientPhone: _firstNonEmptyText([
        _asMap(invoiceMap['client'])?['mobile'],
        _asMap(invoiceMap['client'])?['phone'],
        invoiceMap['client_phone'],
      ]),
      tableNumber: _firstNonEmptyText([
        _asMap(invoiceMap['type_extra'])?['table_number'],
        invoiceMap['table_number'],
        payload['table_number'],
      ]),
      orderType: _firstNonEmptyText(
        [
          invoiceMap['type'],
          invoiceMap['order_type'],
          invoiceMap['booking_type'],
          payload['type'],
        ],
      ),
      orderNumber: _firstNonEmptyText(
        [
          invoiceMap['order_number'],
          invoiceMap['daily_order_number'],
          payload['order_number'],
          payload['daily_order_number'],
        ],
        allowZero: false,
      ),
      commercialRegisterNumber: _firstNonEmptyText(
        [
          branchMap?['commercial_number'],
          branchMap?['commercial_register'],
          branchMap?['commercial_register_number'],
          sellerMap?['commercial_register'],
          sellerMap?['commercial_number'],
          sellerMap?['commercial_register_number'],
          invoiceMap['commercial_register_number'],
        ],
      ),
    );
  }

  OrderReceiptData _withSellerLogo(
    OrderReceiptData data,
    String logoUrl,
  ) {
    return OrderReceiptData(
      invoiceNumber: data.invoiceNumber,
      issueDateTime: data.issueDateTime,
      sellerNameAr: data.sellerNameAr,
      sellerNameEn: data.sellerNameEn,
      vatNumber: data.vatNumber,
      branchName: data.branchName,
      carNumber: data.carNumber,
      items: data.items,
      totalExclVat: data.totalExclVat,
      vatAmount: data.vatAmount,
      totalInclVat: data.totalInclVat,
      paymentMethod: data.paymentMethod,
      qrCodeBase64: data.qrCodeBase64,
      sellerLogo: logoUrl,
      payments: data.payments,
      zatcaQrImage: data.zatcaQrImage,
      branchAddress: data.branchAddress,
      branchMobile: data.branchMobile,
      issueDate: data.issueDate,
      issueTime: data.issueTime,
      commercialRegisterNumber: data.commercialRegisterNumber,
      cashierName: data.cashierName,
      orderDiscountAmount: data.orderDiscountAmount,
      orderDiscountPercentage: data.orderDiscountPercentage,
      orderDiscountName: data.orderDiscountName,
      orderType: data.orderType,
      orderNumber: data.orderNumber,
    );
  }

  Future<OrderReceiptData> _ensureReceiptLogo(
    OrderReceiptData data,
    Map<String, dynamic> details,
  ) async {
    if (data.sellerLogo != null && data.sellerLogo!.isNotEmpty) {
      return data;
    }
    final payload = _asMap(details['data']) ?? details;
    final invoiceMap = _asMap(payload['invoice']) ?? payload;
    final branchMap = _asMap(payload['branch']) ?? _asMap(invoiceMap['branch']);
    final branchId = _parseNum(branchMap?['id']).toInt();
    if (branchId <= 0) return data;
    try {
      final logoUrl = await getIt<BranchService>().getBranchLogoUrl(branchId);
      if (logoUrl.isEmpty) return data;
      return _withSellerLogo(data, logoUrl);
    } catch (_) {
      return data;
    }
  }

  Future<void> _openInvoicePreview(Invoice invoice) async {
    try {
      Map<String, dynamic> invoiceDetails;
      try {
        invoiceDetails = await _orderService.getInvoice(invoice.id.toString());
      } catch (_) {
        invoiceDetails =
            await _orderService.getInvoiceHelper(invoice.id.toString());
      }

      var receiptData =
          _buildReceiptDataFromInvoiceDetails(invoiceDetails, invoice.id);
      receiptData = await _ensureReceiptLogo(receiptData, invoiceDetails);

      if (!mounted) return;
      await InvoicePreviewHelper.open(
        context: context,
        receiptData: receiptData,
        invoiceId: invoice.id.toString(),
        orderType: receiptData.orderType,
        promptPrinterSelectionOnOpen: false,
        forcePreferredPrinter: true,
        printButtonLabel: 'طباعة',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ErrorHandler.toUserMessage(
              e,
              fallback: _tr(
                'تعذر توليد الفاتورة حالياً.',
                'Unable to generate invoice right now.',
              ),
            ),
          ),
        ),
      );
    }
  }

  /// True only when ALL items have been refunded (status = refunded/4).
  bool _isInvoiceFullyRefunded(Invoice invoice) {
    final normalizedStatus = invoice.status.trim().toLowerCase();
    final display = invoice.statusDisplay.trim().toLowerCase();

    if (display.contains('جزئي') || display.contains('partial')) return false;
    if (normalizedStatus == 'refunded') return true;
    if (display == 'مسترجع' || display == 'refunded') return true;
    return false;
  }

  /// True when the invoice is cancelled (status 4 / "تم الالغاء").
  /// Cancelled invoices should NOT allow refund.
  bool _isInvoiceCancelled(Invoice invoice) {
    final normalizedStatus = invoice.status.trim().toLowerCase();
    final display = invoice.statusDisplay.trim().toLowerCase();
    return normalizedStatus == '4' ||
        normalizedStatus == 'cancelled' ||
        normalizedStatus == 'canceled' ||
        display == 'تم الالغاء' ||
        display == 'ملغي' ||
        display == 'cancelled' ||
        display == 'canceled';
  }

  /// True when some (but not all) items have been refunded.
  bool _hasPartialRefund(Invoice invoice) {
    if (_isInvoiceFullyRefunded(invoice)) return false;

    bool isTruthy(dynamic value) {
      if (value == null) return false;
      if (value is bool) return value;
      if (value is num) return value != 0;
      final s = value.toString().trim().toLowerCase();
      return s == '1' || s == 'true' || s == 'yes';
    }

    final raw = invoice.raw;
    final hasRefundEvidence = isTruthy(
      raw['has_refund'] ?? raw['refund_id'] ?? raw['refund_status'],
    );

    // Status 4 / "تم الالغاء": only treat as partial refund if there is
    // concrete evidence a refund happened (has_refund, refund_id, etc.).
    // Otherwise it is a genuine cancellation — no refund allowed.
    if (_isInvoiceCancelled(invoice)) {
      return hasRefundEvidence;
    }

    if (hasRefundEvidence) return true;

    final display = invoice.statusDisplay.trim().toLowerCase();
    if (display.contains('جزئي') || display.contains('partial')) return true;

    final normalizedStatus = invoice.status.trim().toLowerCase();
    if (normalizedStatus == 'partially_refunded' ||
        normalizedStatus == 'partial_refund') return true;

    return false;
  }

  bool _isInvoicePaid(Invoice invoice) {
    bool isTruthy(dynamic value) {
      if (value == null) return false;
      if (value is bool) return value;
      if (value is num) return value != 0;
      final normalized = value.toString().trim().toLowerCase();
      if (normalized.isEmpty || normalized == 'null') return false;
      return normalized == '1' || normalized == 'true' || normalized == 'yes';
    }

    final normalizedStatus = invoice.status.trim().toLowerCase();
    if (normalizedStatus == 'paid' ||
        normalizedStatus == '2' ||
        normalizedStatus == '7' ||
        normalizedStatus == 'completed') {
      return true;
    }

    final display = invoice.statusDisplay.trim().toLowerCase();
    if (display.contains('مدفوع') || display.contains('paid')) return true;

    final raw = invoice.raw;
    return isTruthy(
      raw['is_paid'] ??
          raw['paid'] ??
          raw['payment_status'] ??
          raw['payment_state'] ??
          raw['pay_status'] ??
          raw['pay_status_id'],
    );
  }

  String _formatInvoiceNumber(Invoice invoice) {
    final raw = invoice.invoiceNumber.trim();
    if (raw.isEmpty || raw == '0') {
      return '#${invoice.id}';
    }
    return raw.startsWith('#') ? raw : '#$raw';
  }

  String _formatInvoiceIdDisplay(String? rawValue) {
    final raw = rawValue?.trim() ?? '';
    if (raw.isEmpty || raw == '0') return '';
    final clean = raw.replaceAll('#', '').trim();
    if (clean.isEmpty || clean == '0') return '';
    if (_hasLetters(clean)) return clean;
    return '#$clean';
  }

  String _formatOrderNumberDisplay(String? rawValue) {
    final raw = rawValue?.trim() ?? '';
    if (raw.isEmpty || raw == '0') return '';
    final clean = raw.replaceAll('#', '').trim();
    if (clean.isEmpty || clean == '0') return '';
    return '#$clean';
  }

  String? _resolveInvoiceId(Invoice invoice) {
    return _firstNonEmptyText(
      [
        invoice.invoiceNumber,
        invoice.raw['invoice_number'],
        invoice.raw['invoice_id'],
        invoice.raw['id'],
        invoice.id,
      ],
      allowZero: false,
    );
  }

  String? _resolveDailyOrderNumber(Invoice invoice) {
    final raw = invoice.raw;
    final orderMap =
        raw['order'] is Map ? Map<String, dynamic>.from(raw['order']) : null;
    final bookingMap =
        raw['booking'] is Map ? Map<String, dynamic>.from(raw['booking']) : null;
    return _firstNonEmptyText(
      [
        raw['daily_order_number'],
        orderMap?['daily_order_number'],
        bookingMap?['daily_order_number'],
        raw['order_number'],
        orderMap?['order_number'],
        bookingMap?['order_number'],
        raw['booking_number'],
        bookingMap?['booking_number'],
      ],
      allowZero: false,
    );
  }

  bool _matchesSearchQuery(String? candidate, String query) {
    if (candidate == null || candidate.trim().isEmpty) return false;
    final normalizedCandidate = _normalizeSearchToken(candidate);
    final normalizedQuery = _normalizeSearchToken(query);
    if (normalizedQuery.isEmpty) return false;
    return normalizedCandidate.contains(normalizedQuery);
  }

  bool _invoiceMatchesSearch(Invoice invoice, String query) {
    final invoiceId = _resolveInvoiceId(invoice);
    final dailyOrder = _resolveDailyOrderNumber(invoice);
    final candidates = [
      invoiceId,
      dailyOrder,
      invoice.id.toString(),
      invoice.raw['invoice_number']?.toString(),
      invoice.raw['invoice_id']?.toString(),
      invoice.raw['order_number']?.toString(),
      invoice.raw['daily_order_number']?.toString(),
    ];
    return candidates.any((value) => _matchesSearchQuery(value, query));
  }

  Widget _buildInvoiceHeaderIds(Invoice invoice) {
    final invoiceId = _formatInvoiceIdDisplay(_resolveInvoiceId(invoice));
    final dailyOrder =
        _formatOrderNumberDisplay(_resolveDailyOrderNumber(invoice));
    final invoiceLabel =
        invoiceId.isNotEmpty ? '${_tr('فاتورة', 'Invoice')} $invoiceId' : '';
    final orderLabel =
        dailyOrder.isNotEmpty ? '${_tr('طلب', 'Order')} $dailyOrder' : '';

    if (invoiceLabel.isNotEmpty && orderLabel.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            orderLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            invoiceLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      );
    }

    final singleLabel = orderLabel.isNotEmpty ? orderLabel : invoiceLabel;
    return Text(
      singleLabel.isNotEmpty ? singleLabel : _tr('فاتورة', 'Invoice'),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: Color(0xFF0F172A),
      ),
    );
  }

  String _formatInvoiceDate(Invoice invoice) {
    final raw = invoice.date.trim().isNotEmpty
        ? invoice.date
        : invoice.createdAt;
    if (raw.isEmpty) return _tr('بدون تاريخ', 'No date');
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    final hasTime = raw.contains(':');
    final local = parsed.toLocal();
    final timeLabel = DateFormat('HH:mm').format(local);
    if (!hasTime || timeLabel == '00:00') {
      return DateFormat('yyyy-MM-dd').format(local);
    }
    return timeLabel;
  }

  Color _statusColor(String status) {
    return const Color(0xFF64748B);
  }

  Future<String?> _showWhatsAppMessageDialog({
    required String title,
    required String initialMessage,
  }) async {
    final controller = TextEditingController(text: initialMessage);
    final message = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          minLines: 2,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: _tr('نص الرسالة', 'Message'),
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(translationService.t('cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(_tr('إرسال', 'Send')),
          ),
        ],
      ),
    );
    controller.dispose();
    return message;
  }

  String _normalizeWhatsAppMessage(String message) {
    final trimmed = message.trim();
    final atCount = '@'.allMatches(trimmed).length;
    if (atCount >= 2) return trimmed;

    final needed = 2 - atCount;
    final suffix = List<String>.filled(needed, '@@').join(' ');
    return '$trimmed $suffix'.trim();
  }

  Future<void> _sendWhatsAppForOrder({
    required int orderId,
    required String orderLabel,
  }) async {
    final message = await _showWhatsAppMessageDialog(
      title: _tr('إرسال واتساب للطلب $orderLabel',
          'Send WhatsApp for order $orderLabel'),
      initialMessage: _tr('طلبك جاهز للاستلام', 'Your order is ready'),
    );
    if (message == null || message.isEmpty) return;

    setState(() => _isSendingWhatsApp = true);
    try {
      final normalizedMessage = _normalizeWhatsAppMessage(message);
      await _orderService.sendOrderWhatsApp(
        orderId: orderId.toString(),
        message: normalizedMessage,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tr('تم إرسال واتساب للطلب $orderLabel',
                'WhatsApp sent for order $orderLabel'),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final userMessage = ErrorHandler.toUserMessage(
        e,
        fallback: _tr('تعذر إرسال واتساب', 'Failed to send WhatsApp'),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userMessage)),
      );
    } finally {
      if (mounted) setState(() => _isSendingWhatsApp = false);
    }
  }

  int? _resolveOrderIdFromInvoice(Invoice invoice) {
    int? parseInt(dynamic value) {
      if (value == null) return null;
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value.toString());
    }

    final direct = invoice.orderId;
    if (direct != null && direct > 0) return direct;

    final raw = invoice.raw;
    final candidates = [
      raw['order_id'],
      raw['booking_id'],
      raw['order'] is Map ? (raw['order'] as Map)['id'] : null,
      raw['booking'] is Map ? (raw['booking'] as Map)['id'] : null,
    ];
    for (final candidate in candidates) {
      final parsed = parseInt(candidate);
      if (parsed != null && parsed > 0) return parsed;
    }
    return null;
  }

  int? _extractOrderIdFromPayload(dynamic payload) {
    int? parseInt(dynamic value) {
      if (value == null) return null;
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value.toString());
    }

    if (payload is Map) {
      final map = payload.map((k, v) => MapEntry(k.toString(), v));
      final directCandidates = [
        map['order_id'],
        map['booking_id'],
        map['orderId'],
        map['bookingId'],
      ];
      for (final candidate in directCandidates) {
        final parsed = parseInt(candidate);
        if (parsed != null && parsed > 0) return parsed;
      }

      final bookingMap = map['booking'];
      if (bookingMap is Map) {
        final parsed = parseInt(bookingMap['id'] ?? bookingMap['order_id']);
        if (parsed != null && parsed > 0) return parsed;
      }

      final orderMap = map['order'];
      if (orderMap is Map) {
        final parsed = parseInt(orderMap['id']);
        if (parsed != null && parsed > 0) return parsed;
      }

      final invoiceMap = map['invoice'];
      if (invoiceMap is Map) {
        final parsed = _extractOrderIdFromPayload(invoiceMap);
        if (parsed != null && parsed > 0) return parsed;
      }

      final dataMap = map['data'];
      if (dataMap is Map) {
        final parsed = _extractOrderIdFromPayload(dataMap);
        if (parsed != null && parsed > 0) return parsed;
      }
    }
    return null;
  }

  bool _isRouteNotFound(ApiException e) {
    final msg = e.message.toLowerCase();
    final user = (e.userMessage ?? '').toLowerCase();
    return msg.contains('route_not_found') ||
        user.contains('الخدمة المطلوبة') ||
        user.contains('غير متاحة');
  }

  Future<int?> _resolveOrderIdForInvoiceAsync(Invoice invoice) async {
    final direct = _resolveOrderIdFromInvoice(invoice);
    if (direct != null && direct > 0) return direct;
    try {
      final details = await _orderService.getInvoice(invoice.id.toString());
      final extracted = _extractOrderIdFromPayload(details);
      if (extracted != null && extracted > 0) return extracted;
    } catch (_) {
      // Continue to helper endpoint
    }
    if (!_invoiceHelperSupported) return null;
    try {
      final helper = await _orderService.getInvoiceHelper(invoice.id.toString());
      final extracted = _extractOrderIdFromPayload(helper);
      if (extracted != null && extracted > 0) return extracted;
    } on ApiException catch (e) {
      if (e.statusCode == 404 && _isRouteNotFound(e)) {
        if (mounted) {
          setState(() => _invoiceHelperSupported = false);
        } else {
          _invoiceHelperSupported = false;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> _showUpdateStatusDialogForOrder({
    required int orderId,
    required String orderLabel,
    required String currentStatus,
  }) async {
    int selectedStatus = _normalizeStatusToApiValue(currentStatus);
    final statusOptions = <Map<String, dynamic>>[
      {
        'value': 1,
        'label': _tr('حجز مؤكد', 'Confirmed'),
        'color': const Color(0xFFF59E0B),
      },
      {
        'value': 2,
        'label': _tr('بدأ', 'Started'),
        'color': const Color(0xFF3B82F6),
      },
      {
        'value': 3,
        'label': _tr('انتهي', 'Ended'),
        'color': const Color(0xFF22C55E),
      },
      {
        'value': 4,
        'label': _tr('جاري التحضير', 'Preparing'),
        'color': const Color(0xFF3B82F6),
      },
      {
        'value': 5,
        'label': _tr('جاهز للتوصيل', 'Ready for delivery'),
        'color': const Color(0xFF16A34A),
      },
      {
        'value': 6,
        'label': _tr('قيد التوصيل', 'On the way'),
        'color': const Color(0xFF0EA5E9),
      },
      {
        'value': 7,
        'label': _tr('مكتمل', 'Completed'),
        'color': const Color(0xFF15803D),
      },
      {
        'value': 8,
        'label': _tr('ملغي', 'Cancelled'),
        'color': const Color(0xFFEF4444),
      },
    ];

    final result = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          _tr(
            'تحديث حالة الطلب $orderLabel',
            'Update order status $orderLabel',
          ),
        ),
        content: StatefulBuilder(
          builder: (context, setDialogState) {
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: statusOptions.map((option) {
                final value = option['value'] as int;
                final color = option['color'] as Color;
                final selected = selectedStatus == value;
                return ChoiceChip(
                  label: Text(option['label'] as String),
                  selected: selected,
                  onSelected: (_) =>
                      setDialogState(() => selectedStatus = value),
                  selectedColor: color.withValues(alpha: 0.18),
                  backgroundColor: const Color(0xFFF8FAFC),
                  labelStyle: TextStyle(
                    color: selected ? color : const Color(0xFF475569),
                    fontWeight: FontWeight.bold,
                  ),
                  side: BorderSide(color: color),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                );
              }).toList(),
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(translationService.t('cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, selectedStatus),
            child: Text(translationService.t('save')),
          ),
        ],
      ),
    );

    if (result == null) return;

    try {
      await _orderService.updateBookingStatus(
        orderId: orderId.toString(),
        status: result,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_tr('تم تحديث حالة الطلب بنجاح',
              'Order status updated successfully')),
        ),
      );
      _displayAppService.sendOrderStatusUpdateToDisplay(
        orderId: orderId.toString(),
        status: result,
      );
      _loadInvoices(reset: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(_tr('تعذر تحديث حالة الطلب: $e',
                'Unable to update order status: $e'))),
      );
    }
  }

  int _normalizeStatusToApiValue(String status) {
    switch (status.toLowerCase()) {
      case '1':
      case 'confirmed':
      case 'pending':
      case 'new':
        return 1;
      case '2':
      case 'started':
      case 'start':
      case 'in_progress':
        return 2;
      case '3':
      case 'ended':
        return 3;
      case '4':
      case 'preparing':
      case 'processing':
        return 4;
      case '5':
      case 'ready':
      case 'ready_for_delivery':
        return 5;
      case '6':
      case 'on_the_way':
      case 'out_for_delivery':
        return 6;
      case '7':
      case 'finished':
      case 'done':
      case 'completed':
        return 7;
      case '8':
      case 'cancelled':
      case 'canceled':
        return 8;
      default:
        return 1;
    }
  }


  Future<void> _showRefundedMealsForInvoice(Invoice invoice) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final refundedMeals = await _orderService.getRefundedMeals(
        invoiceId: invoice.id.toString(),
      );
      if (!mounted) return;
      Navigator.pop(context); // dismiss loading

      if (refundedMeals.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_tr(
              'لا توجد مرتجعات لهذه الفاتورة',
              'No refunds for this invoice',
            )),
          ),
        );
        return;
      }

      showDialog(
        context: context,
        builder: (context) => _RefundedMealsDialog(
          title: _tr(
            'مرتجعات الفاتورة #${invoice.id}',
            'Refunds - Invoice #${invoice.id}',
          ),
          refundedMeals: refundedMeals,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // dismiss loading
      final userMessage = ErrorHandler.toUserMessage(
        e,
        fallback: _tr('تعذر جلب المرتجعات', 'Failed to load refunds'),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userMessage)),
      );
    }
  }

  Future<void> _showInvoiceRefundOptions(Invoice invoice) async {
    if (_refundingInvoiceIds.contains(invoice.id)) return;
    // Allow refund for paid or partially-refunded invoices
    if (!_isInvoicePaid(invoice) && !_hasPartialRefund(invoice)) return;
    if (_isInvoiceFullyRefunded(invoice)) return;
    setState(() => _refundingInvoiceIds.add(invoice.id));

    try {
      await showInvoiceRefundDialog(
        context: context,
        invoiceId: invoice.id.toString(),
        invoiceLabel: _formatInvoiceNumber(invoice),
      );
      // Always reload to sync state across cashiers
      await _loadInvoices(reset: true);
    } catch (e) {
      if (!mounted) return;
      final userMessage = ErrorHandler.toUserMessage(
        e,
        fallback: _tr('تعذر تنفيذ الاسترجاع', 'Failed to process refund'),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userMessage)),
      );
    } finally {
      if (mounted) {
        setState(() => _refundingInvoiceIds.remove(invoice.id));
      }
    }
  }

  Future<bool> _openInvoiceDetails(
    Invoice invoice, {
    bool autoOpenRefund = false,
    bool autoOpenSingleItemRefund = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => InvoiceDetailsDialog(
        invoiceId: invoice.id.toString(),
        autoOpenRefund: autoOpenRefund,
        autoOpenSingleItemRefund: autoOpenSingleItemRefund,
      ),
    );
    if (result == true) {
      await _loadInvoices(reset: true);
    }
    return result == true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _buildErrorView()
                    : _buildInvoicesList(),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final width = MediaQuery.sizeOf(context).width;
    final isCompact = width < 900;
    final searchWidth = (width * 0.25).clamp(180.0, 280.0).toDouble();

    final searchField = TextField(
      controller: _searchController,
      onChanged: (value) => setState(() => _searchQuery = value.trim()),
      onSubmitted: (_) => _loadInvoices(reset: true),
      decoration: InputDecoration(
        hintText: _tr(
          'بحث برقم الفاتورة أو رقم الطلب',
          'Search by invoice or order number',
        ),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        prefixIcon: const Icon(Icons.search, size: 18),
        suffixIcon: _searchController.text.isNotEmpty
            ? IconButton(
                onPressed: () {
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                  _loadInvoices(reset: true);
                },
                icon: const Icon(Icons.clear, size: 18),
              )
            : null,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );

    final headerContent = isCompact
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: widget.onBack,
                    icon: const Icon(LucideIcons.chevronRight, size: 24),
                    color: const Color(0xFFF58220),
                  ),
                  Expanded(
                    child: Text(
                      translationService.t('invoices'),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => _loadInvoices(reset: true),
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              searchField,
            ],
          )
        : Row(
            children: [
              TextButton.icon(
                onPressed: widget.onBack,
                icon: const Icon(LucideIcons.chevronRight, size: 28),
                label: Text(
                  translationService.t('back'),
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFF58220),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
              const Spacer(),
              Text(
                translationService.t('invoices'),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF1E293B),
                ),
              ),
              const Spacer(),
              SizedBox(width: searchWidth, child: searchField),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () => _loadInvoices(reset: true),
                icon: const Icon(Icons.refresh),
              ),
            ],
          );

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 12 : 16,
        vertical: 12,
      ),
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
      child: headerContent,
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.alertCircle, size: 40, color: Colors.red.shade400),
          const SizedBox(height: 8),
          Text(
            _tr('تعذر تحميل الفواتير', 'Unable to load invoices'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          if (_error != null) ...[
            const SizedBox(height: 6),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: () => _loadInvoices(reset: true),
            icon: const Icon(Icons.refresh),
            label: Text(_tr('إعادة المحاولة', 'Retry')),
          ),
        ],
      ),
    );
  }

  Widget _buildInvoicesList() {
    final query = _searchQuery.trim();
    final displayItems = query.isEmpty
        ? _invoices
        : _invoices.where((item) => _invoiceMatchesSearch(item, query)).toList();

    if (displayItems.isEmpty) {
      return Center(
        child: Text(
          _tr('لا توجد فواتير', 'No invoices found'),
          style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadInvoices(reset: true),
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        itemCount: displayItems.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= displayItems.length) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: _isLoadingMore
                    ? const CircularProgressIndicator()
                    : const SizedBox.shrink(),
              ),
            );
          }

          final invoice = displayItems[index];
          final statusLabel = invoice.statusDisplay.trim();
          final showStatusBadge =
              statusLabel.isNotEmpty && statusLabel.toLowerCase() != 'null';
          final statusColor = _statusColor(statusLabel);
          final isFullyRefunded = _isInvoiceFullyRefunded(invoice);
          final hasPartialRefund = _hasPartialRefund(invoice);
          final isRefunding = _refundingInvoiceIds.contains(invoice.id);
          final isPaid = _isInvoicePaid(invoice);
          final canRefund = (isPaid || hasPartialRefund) && !isFullyRefunded;
          final orderId = _resolveOrderIdFromInvoice(invoice);
          final canOrderActions = invoice.id > 0;
          final totalValue = invoice.grandTotal > 0
              ? invoice.grandTotal
              : (invoice.total > 0 ? invoice.total : invoice.paid);

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _buildInvoiceHeaderIds(invoice),
                    ),
                    if (showStatusBadge)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          invoice.statusDisplay,
                          style: TextStyle(
                            color: statusColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _formatInvoiceDate(invoice),
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                if (invoice.customerName != null &&
                    invoice.customerName!.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(LucideIcons.user, size: 16, color: Colors.grey[500]),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          invoice.customerName!.trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Colors.grey.shade700),
                        ),
                      ),
                    ],
                  ),
                ],
                const Divider(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _tr('الإجمالي', 'Total'),
                            style: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${_amountFormatter.format(totalValue)} ${ApiConstants.currency}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFF58220),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: () => _openInvoiceDetails(invoice),
                      icon: const Icon(LucideIcons.fileText, size: 16),
                      label: Text(_tr('عرض التفاصيل', 'View details')),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF2563EB),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _openInvoicePreview(invoice),
                      icon: const Icon(LucideIcons.eye, size: 16),
                      label: Text(_tr('معاينة الفاتورة', 'Invoice preview')),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF0EA5E9),
                        side: const BorderSide(color: Color(0xFF0EA5E9)),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: canOrderActions && !_isSendingWhatsApp
                          ? () async {
                              final resolvedOrderId =
                                  orderId ?? await _resolveOrderIdForInvoiceAsync(invoice);
                              if (resolvedOrderId == null || resolvedOrderId <= 0) {
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(_tr(
                                      'تعذر تحديد رقم الطلب لهذه الفاتورة',
                                      'Unable to resolve order for this invoice',
                                    )),
                                  ),
                                );
                                return;
                              }
                              await _sendWhatsAppForOrder(
                                orderId: resolvedOrderId,
                                orderLabel: _formatInvoiceNumber(invoice),
                              );
                            }
                          : null,
                      icon: const Icon(LucideIcons.messageCircle, size: 16),
                      label: Text(_tr('واتساب', 'WhatsApp')),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF16A34A),
                        side: const BorderSide(color: Color(0xFF16A34A)),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: canOrderActions
                          ? () async {
                              final resolvedOrderId =
                                  orderId ?? await _resolveOrderIdForInvoiceAsync(invoice);
                              if (resolvedOrderId == null || resolvedOrderId <= 0) {
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(_tr(
                                      'تعذر تحديد رقم الطلب لهذه الفاتورة',
                                      'Unable to resolve order for this invoice',
                                    )),
                                  ),
                                );
                                return;
                              }
                              await _showUpdateStatusDialogForOrder(
                                orderId: resolvedOrderId,
                                orderLabel: _formatInvoiceNumber(invoice),
                                currentStatus:
                                    invoice.raw['order_status']?.toString() ??
                                        invoice.raw['status']?.toString() ??
                                        '1',
                              );
                            }
                          : null,
                      icon: const Icon(LucideIcons.edit, size: 16),
                      label: Text(_tr('تغيير الحالة', 'Change status')),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF0EA5E9),
                        side: const BorderSide(color: Color(0xFF0EA5E9)),
                      ),
                    ),
                    if (canRefund)
                      OutlinedButton.icon(
                        onPressed: isRefunding
                            ? null
                            : () => _showInvoiceRefundOptions(invoice),
                        icon: isRefunding
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(LucideIcons.refreshCw, size: 16),
                        label: Text(
                          hasPartialRefund
                              ? _tr('استرجاع إضافي', 'Refund More')
                              : _tr('استرجاع', 'Refund'),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFEF4444),
                          side: const BorderSide(color: Color(0xFFEF4444)),
                        ),
                      ),
                    if (isFullyRefunded)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEE2E2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(LucideIcons.checkCircle,
                                size: 14, color: Color(0xFFDC2626)),
                            const SizedBox(width: 4),
                            Text(
                              _tr('مسترجع بالكامل', 'Fully Refunded'),
                              style: const TextStyle(
                                color: Color(0xFFDC2626),
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    OutlinedButton.icon(
                      onPressed: () => _showRefundedMealsForInvoice(invoice),
                      icon: const Icon(LucideIcons.list, size: 16),
                      label: Text(_tr('المرتجعات', 'Refunds')),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFB45309),
                        side: const BorderSide(color: Color(0xFFB45309)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _RefundedMealsDialog extends StatelessWidget {
  final String title;
  final List<Map<String, dynamic>> refundedMeals;

  const _RefundedMealsDialog({
    required this.title,
    required this.refundedMeals,
  });

  bool get _useArabicUi {
    final code = translationService.currentLanguageCode.trim().toLowerCase();
    return code.startsWith('ar') || code.startsWith('ur');
  }

  String _tr(String ar, String en) => _useArabicUi ? ar : en;

  double _parsePrice(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString().replaceAll(',', '')) ?? 0;
  }

  bool _isTruthy(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is num) return value != 0;
    final s = value.toString().trim().toLowerCase();
    return s == '1' || s == 'true' || s == 'yes';
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isCompact = size.width < 700;

    double totalRefunded = 0;
    for (final meal in refundedMeals) {
      totalRefunded += _parsePrice(meal['total'] ?? meal['price']);
    }

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: isCompact ? 16 : 40,
        vertical: isCompact ? 24 : 40,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: size.height * 0.75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Color(0xFFDC2626),
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(
                children: [
                  const Icon(LucideIcons.refreshCw,
                      color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${refundedMeals.length} ${_tr('صنف', 'items')}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Items list
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.all(16),
                itemCount: refundedMeals.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 20, color: Color(0xFFE2E8F0)),
                itemBuilder: (context, index) {
                  final meal = refundedMeals[index];
                  return _buildMealRow(meal);
                },
              ),
            ),

            // Total
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                border:
                    Border(top: BorderSide(color: Colors.grey.shade200)),
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _tr('إجمالي المرتجعات', 'Total Refunded'),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFDC2626),
                        ),
                      ),
                      Text(
                        '${totalRefunded.toStringAsFixed(2)} ${ApiConstants.currency}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFDC2626),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFDC2626),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(
                        _tr('إغلاق', 'Close'),
                        style: const TextStyle(fontWeight: FontWeight.bold),
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

  Widget _buildMealRow(Map<String, dynamic> meal) {
    final name = meal['meal_name']?.toString() ??
        meal['name']?.toString() ??
        _tr('صنف غير معروف', 'Unknown item');
    final quantity = int.tryParse(meal['quantity']?.toString() ?? '1') ?? 1;
    final total = _parsePrice(meal['total'] ?? meal['price']);
    final discount = _parsePrice(meal['discount']);
    final tax = _parsePrice(meal['tax']);
    final isInvoiced = _isTruthy(meal['is_invoiced']);
    final invoiceId = meal['invoice_id'];
    final addons = meal['addons'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFFEE2E2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'x$quantity',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFEF4444),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                name,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1E293B),
                  decoration: TextDecoration.lineThrough,
                ),
              ),
            ),
            Text(
              '${total.toStringAsFixed(2)} ${ApiConstants.currency}',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Color(0xFFEF4444),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            const SizedBox(width: 42),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: isInvoiced
                    ? const Color(0xFFFEE2E2)
                    : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                isInvoiced
                    ? (invoiceId != null
                        ? _tr('مسترجع - فاتورة #$invoiceId',
                            'Refunded - Invoice #$invoiceId')
                        : _tr('مسترجع', 'Refunded'))
                    : _tr('ملغي قبل الفوترة', 'Cancelled before invoice'),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: isInvoiced
                      ? const Color(0xFFDC2626)
                      : const Color(0xFF64748B),
                ),
              ),
            ),
          ],
        ),
        if (discount > 0 || tax > 0) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 42),
            child: Text(
              [
                if (discount > 0)
                  '${_tr('خصم', 'Discount')}: ${discount.toStringAsFixed(2)}',
                if (tax > 0)
                  '${_tr('ضريبة', 'Tax')}: ${tax.toStringAsFixed(2)}',
              ].join(' | '),
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ),
        ],
        if (addons is List && addons.isNotEmpty) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 42),
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: addons.map((addon) {
                final text = addon is Map
                    ? [addon['attribute'], addon['option']]
                        .where((e) => e != null && e.toString().trim().isNotEmpty)
                        .join(' - ')
                    : addon.toString();
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '+ $text',
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFFD97706),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ],
    );
  }
}
