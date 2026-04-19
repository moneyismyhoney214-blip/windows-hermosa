// ignore_for_file: invalid_use_of_protected_member, unused_element, unused_element_parameter, dead_code, dead_null_aware_expression, unnecessary_cast
part of '../invoices_screen.dart';

extension InvoicesScreenPaymentResolvers on _InvoicesScreenState {
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

      String label = 'نقدي';
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
              branchMap?['seller_name_en'],
              sellerMap?['name_en'],
              branchMap?['name_en'],
              invoiceMap['seller_name_en'],
              payload['seller_name_en'],
              branchMap?['seller_name'],
              sellerMap?['name'],
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
      orderDiscountAmount: _parseNum(
        invoiceMap['discount'] ??
            invoiceMap['discount_amount'] ??
            payload['discount'] ??
            payload['discount_amount'],
      ),
      orderDiscountPercentage: _parseNum(
        invoiceMap['discount_percentage'] ?? payload['discount_percentage'],
      ),
      orderDiscountName: _firstNonEmptyText([
        invoiceMap['discount_name'],
        invoiceMap['discount_code'],
        payload['discount_name'],
        payload['discount_code'],
      ]),
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
}
