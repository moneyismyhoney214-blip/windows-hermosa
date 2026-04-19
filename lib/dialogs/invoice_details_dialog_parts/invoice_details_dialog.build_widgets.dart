// ignore_for_file: invalid_use_of_protected_member, unused_element, unused_element_parameter, dead_code, dead_null_aware_expression, unnecessary_cast
part of '../invoice_details_dialog.dart';

extension InvoiceDetailsDialogBuildWidgets on _InvoiceDetailsDialogState {
  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(LucideIcons.alertCircle, size: 48, color: Colors.red),
          const SizedBox(height: 16),
          Text('حدث خطأ: $_error', style: const TextStyle(color: Colors.red)),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loadInvoiceDetails,
            child: const Text('إعادة المحاولة'),
          ),
        ],
      ),
    );
  }

  Widget _buildInvoiceContent(NumberFormat formatter) {
    if (_invoiceDetails == null) {
      return Center(child: Text(translationService.t('no_data')));
    }

    final payload = _asMap(_invoiceDetails!['data']) ?? _invoiceDetails!;
    final data = _asMap(payload['invoice']) ?? payload;
    
    final receiptData = _mapToOrderReceiptData(payload, data);

    // Read local printer language settings (device-scoped, user-configurable).
    final String pri = printerLanguageSettings.primary;
    final String sec = printerLanguageSettings.secondary;
    final bool allow = printerLanguageSettings.allowSecondary;

    return Container(
      color: context.appSurfaceAlt, // خلفية رمادية فاتحة لبروز "الورقة"
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 450),
            decoration: BoxDecoration(
              // Keep the receipt "paper" white even in dark mode so
              // InvoicePrintWidget (designed for paper printing) stays legible.
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: context.isDark ? 0.4 : 0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                // Ribbon or Indicator for Refunded state
                if (_isFullyRefundedFromDetails())
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: const BoxDecoration(
                      color: Color(0xFFEF4444),
                      borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
                    ),
                    child: const Text(
                      'مسترجع بالكامل - FULLY REFUNDED',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  )
                else if (_hasPartialRefundFromDetails())
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: const BoxDecoration(
                      color: Color(0xFFF59E0B),
                      borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
                    ),
                    child: const Text(
                      'استرجاع جزئي - PARTIAL REFUND',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                
                InvoicePrintWidget(
                  data: receiptData,
                  paperWidthMm: 80,
                  primaryLang: pri,
                  secondaryLang: sec,
                  allowSecondary: allow,
                ),
                
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<ReceiptPayment> _resolvePaymentsList(Map<String, dynamic> data, Map<String, dynamic> payload) {
    final paysRaw = data['pays'] ?? payload['pays'];
    final pays = paysRaw is List ? paysRaw : const [];
    final payments = <ReceiptPayment>[];
    for (final pay in pays) {
      final map = _asMap(pay);
      if (map == null) continue;
      final method = (map['pay_method'] ?? map['method'] ?? map['name'])
          ?.toString()
          .trim()
          .toLowerCase();
      final numericAmount = _parsePrice(map['amount'] ?? map['value'] ?? map['paid'] ?? map['total']);
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
        case 'بطاقة':
        case 'مدى':
        case 'فيزا':
        case 'ماستر':
        case 'بينيفت':
          label = 'بطاقة';
          break;
        case 'stc':
        case 'stc_pay':
        case 'اس تي سي':
          label = 'STC Pay';
          break;
        case 'bank_transfer':
        case 'bank':
        case 'تحويل بنكي':
          label = 'تحويل بنكي';
          break;
        case 'wallet':
        case 'المحفظة':
          label = 'محفظة';
          break;
        case 'cheque':
        case 'check':
        case 'شيك':
          label = 'شيك';
          break;
        case 'petty_cash':
        case 'بيتي كاش':
          label = 'بيتي كاش';
          break;
        case 'pay_later':
        case 'postpaid':
        case 'deferred':
        case 'الدفع بالآجل':
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
        case 'ماي فاتورة':
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

  OrderReceiptData _mapToOrderReceiptData(
      Map<String, dynamic> payload, Map<String, dynamic> data) {
    final items = _extractItems(data, payload);
    
    final receiptItems = items.map((item) {
      final meal = _asMap(item['meal']) ?? const <String, dynamic>{};

      // Backend attaches `addons_translations` alongside `addons`, shaped
      // `[{attribute: {ar, en}, option: {ar, en}, price}]`. Walk both lists
      // in lockstep so each ReceiptAddon carries its per-language name and
      // the cashier invoice can print it in the chosen language.
      final addonsList = item['addons'] as List? ?? const [];
      final addonsTranslations = item['addons_translations'] as List? ?? const [];
      final receiptAddons = <ReceiptAddon>[];
      for (var i = 0; i < addonsList.length; i++) {
        final addonMap = _asMap(addonsList[i])!;
        final translation = i < addonsTranslations.length
            ? _asMap(addonsTranslations[i])
            : null;
        final optionMap = translation != null ? _asMap(translation['option']) : null;

        final localized = <String, String>{};
        if (optionMap != null) {
          for (final entry in optionMap.entries) {
            final v = entry.value?.toString().trim() ?? '';
            if (v.isEmpty) continue;
            localized[entry.key.toString().trim().toLowerCase()] = v;
          }
        }

        final nameAr = localized['ar']?.isNotEmpty == true
            ? localized['ar']!
            : (addonMap['name_ar']?.toString() ??
                addonMap['name']?.toString() ??
                '');
        final nameEn = localized['en']?.isNotEmpty == true
            ? localized['en']!
            : (addonMap['name_en']?.toString() ?? '');

        receiptAddons.add(ReceiptAddon(
          nameAr: nameAr,
          nameEn: nameEn,
          price: _parsePrice(addonMap['price']),
          localizedNames: localized,
        ));
      }

      return ReceiptItem(
        nameAr: item['meal_name']?.toString() ?? item['name']?.toString() ?? meal['name']?.toString() ?? '',
        nameEn: item['meal_name_en']?.toString() ?? meal['name_en']?.toString() ?? '',
        quantity: _parsePrice(item['quantity']),
        unitPrice: _parsePrice(item['unit_price'] ?? item['price']),
        total: _parsePrice(item['total'] ?? item['amount']),
        addons: receiptAddons,
        discountAmount: _parsePrice(item['discount_amount'] ?? item['discount']),
        discountPercentage: _parsePrice(item['discount_percentage']),
        discountName: item['discount_name']?.toString(),
      );
    }).toList();

    final issueDateTime = data['date']?.toString() ??
        data['created_at']?.toString() ??
        payload['date']?.toString() ??
        payload['created_at']?.toString() ??
        '';

    return OrderReceiptData(
      invoiceNumber: (data['invoice_number']?.toString() ?? widget.invoiceId).replaceAll('#', '').trim(),
      issueDateTime: issueDateTime,
      sellerNameAr: _extractSellerName(data, payload) ?? 'هيرموسا',
      sellerNameEn: _extractSellerNameEn(data, payload) ?? 'Hermosa',
      vatNumber: _extractVatNumber(data, payload) ?? '',
      branchName: data['branch_name']?.toString() ?? payload['branch_name']?.toString() ?? '',
      items: receiptItems,
      totalExclVat: _parsePrice(data['total'] ?? payload['total']),
      vatAmount: _parsePrice(data['tax'] ?? data['vat'] ?? payload['tax']),
      totalInclVat: _parsePrice(data['grand_total'] ?? data['final_total'] ?? payload['grand_total']),
      paymentMethod: _resolvePaymentMethodLabel(data, payload),
      payments: _resolvePaymentsList(data, payload),
      qrCodeBase64: data['zatca_qr']?.toString() ?? payload['zatca_qr']?.toString() ?? '',
      zatcaQrImage: data['zatca_qr_image']?.toString() ?? payload['zatca_qr_image']?.toString(),
      sellerLogo: _extractLogoUrl(data, payload),
      branchAddress: _extractBranchAddress(data, payload),
      branchMobile: _extractBranchMobile(data, payload),
      cashierName: data['cashier_name']?.toString() ?? payload['cashier_name']?.toString(),
      orderType: data['order_type']?.toString() ?? payload['order_type']?.toString(),
      orderNumber: data['order_number']?.toString() ?? payload['order_number']?.toString() ?? data['booking_id']?.toString(),
      clientName: _extractCustomerName(data, payload),
      clientPhone: _extractCustomerPhone(data, payload),
      tableNumber: _extractTableNumber(data, payload),
      carNumber: data['car_number']?.toString() ?? payload['car_number']?.toString() ?? _asMap(data['type_extra'])?['car_number']?.toString() ?? '',
      commercialRegisterNumber: _extractCommercialRegister(data, payload),
      orderDiscountAmount: _parsePrice(data['discount'] ?? data['discount_amount'] ?? payload['discount'] ?? payload['discount_amount']),
      orderDiscountPercentage: _parsePrice(data['discount_percentage'] ?? payload['discount_percentage']),
      orderDiscountName: (data['discount_name'] ?? data['discount_code'] ?? payload['discount_name'] ?? payload['discount_code'])?.toString(),
    );
  }

  String? _extractCustomerName(Map<String, dynamic> data, Map<String, dynamic> payload) {
    final nodes = [data, payload];
    for (final node in nodes) {
      final direct = node['customer_name']?.toString().trim() ?? 
                    node['client_name']?.toString().trim() ??
                    node['client']?.toString().trim();
      if (direct != null && direct.isNotEmpty && direct != 'null') return direct;
      
      final customer = _asMap(node['customer']) ?? _asMap(node['client']);
      if (customer != null) {
        final name = customer['name']?.toString().trim();
        if (name != null && name.isNotEmpty) return name;
      }
    }
    return null;
  }

  String? _extractCustomerPhone(Map<String, dynamic> data, Map<String, dynamic> payload) {
    final nodes = [data, payload];
    for (final node in nodes) {
      final direct = node['customer_phone']?.toString().trim() ?? 
                    node['client_phone']?.toString().trim() ??
                    node['phone']?.toString().trim();
      if (direct != null && direct.isNotEmpty && direct != 'null') return direct;

      final customer = _asMap(node['customer']) ?? _asMap(node['client']);
      if (customer != null) {
        final phone = customer['phone']?.toString().trim() ?? 
                     customer['mobile']?.toString().trim() ??
                     customer['phone_number']?.toString().trim();
        if (phone != null && phone.isNotEmpty) return phone;
      }
    }
    return null;
  }

  String? _extractSellerName(Map<String, dynamic> data, Map<String, dynamic> payload) {
    final nodes = [data, payload];
    for (final node in nodes) {
      final branch = _asMap(node['branch']);
      final seller = _asMap(node['seller']) ?? _asMap(branch?['seller']);
      
      final candidates = [
        node['seller_name'],
        node['name'],
        branch?['seller_name'],
        branch?['name'],
        seller?['seller_name'],
        seller?['name'],
      ];
      
      for (final c in candidates) {
        final val = c?.toString().trim();
        if (val != null && val.isNotEmpty && val.toLowerCase() != 'null') return val;
      }
    }
    return null;
  }

  String? _extractSellerNameEn(Map<String, dynamic> data, Map<String, dynamic> payload) {
    final nodes = [data, payload];
    for (final node in nodes) {
      final branch = _asMap(node['branch']);
      final seller = _asMap(node['seller']) ?? _asMap(branch?['seller']);
      
      final candidates = [
        node['seller_name_en'],
        node['name_en'],
        branch?['seller_name_en'],
        branch?['name_en'],
        seller?['seller_name_en'],
        seller?['name_en'],
      ];
      
      for (final c in candidates) {
        final val = c?.toString().trim();
        if (val != null && val.isNotEmpty && val.toLowerCase() != 'null') return val;
      }
    }
    return null;
  }

  String? _extractVatNumber(Map<String, dynamic> data, Map<String, dynamic> payload) {
    final nodes = [data, payload];
    for (final node in nodes) {
      final branch = _asMap(node['branch']);
      final seller = _asMap(node['seller']) ?? _asMap(branch?['seller']);
      
      final candidates = [
        node['vat_number'],
        node['tax_number'],
        branch?['vat_number'],
        branch?['tax_number'],
        seller?['vat_number'],
        seller?['tax_number'],
      ];
      
      for (final c in candidates) {
        final val = c?.toString().trim();
        if (val != null && val.isNotEmpty && val.toLowerCase() != 'null') return val;
      }
    }
    return null;
  }

  String? _extractLogoUrl(Map<String, dynamic> data, Map<String, dynamic> payload) {
    final nodes = [data, payload];
    for (final node in nodes) {
      final branch = _asMap(node['branch']);
      final seller = _asMap(node['seller']) ?? _asMap(branch?['seller']);
      
      final candidates = [
        node['seller_logo'],
        node['logo'],
        branch?['logo'],
        seller?['logo'],
      ];
      
      for (final c in candidates) {
        final val = c?.toString().trim();
        if (val != null && val.isNotEmpty && val.toLowerCase() != 'null') return val;
      }
    }
    return null;
  }

  String? _extractBranchAddress(Map<String, dynamic> data, Map<String, dynamic> payload) {
    final nodes = [data, payload];
    for (final node in nodes) {
      final branch = _asMap(node['branch']);
      final seller = _asMap(node['seller']) ?? _asMap(branch?['seller']);
      
      final candidates = [
        node['branch_address'],
        node['address'],
        branch?['address'],
        branch?['location'],
        seller?['address'],
        seller?['seller_address'],
      ];
      
      for (final c in candidates) {
        final val = c?.toString().trim();
        if (val != null && val.isNotEmpty && val.toLowerCase() != 'null') return val;
      }
    }
    return null;
  }

  String? _extractBranchMobile(Map<String, dynamic> data, Map<String, dynamic> payload) {
    final nodes = [data, payload];
    for (final node in nodes) {
      final branch = _asMap(node['branch']);
      final seller = _asMap(node['seller']) ?? _asMap(branch?['seller']);
      
      final candidates = [
        node['branch_phone'],
        node['branch_mobile'],
        node['phone'],
        node['mobile'],
        branch?['mobile'],
        branch?['phone'],
        branch?['telephone'],
        branch?['mobile_number'],
        seller?['mobile'],
        seller?['phone'],
        seller?['telephone'],
      ];
      
      for (final c in candidates) {
        final val = c?.toString().trim();
        if (val != null && val.isNotEmpty && val.toLowerCase() != 'null') return val;
      }
    }
    return null;
  }

  String? _extractCommercialRegister(Map<String, dynamic> data, Map<String, dynamic> payload) {
    final nodes = [data, payload];
    for (final node in nodes) {
      final branch = _asMap(node['branch']);
      final seller = _asMap(node['seller']) ?? _asMap(branch?['seller']);
      
      final candidates = [
        node['commercial_register'],
        node['commercial_register_number'],
        node['commercial_number'],
        node['cr_number'],
        node['seller_commercial_register'],
        branch?['commercial_register'],
        branch?['commercial_register_number'],
        branch?['commercial_number'],
        branch?['cr_number'],
        seller?['commercial_register'],
        seller?['commercial_register_number'],
        seller?['commercial_number'],
        seller?['cr_number'],
      ];
      
      for (final c in candidates) {
        final val = c?.toString().trim();
        if (val != null && val.isNotEmpty && val.toLowerCase() != 'null') return val;
      }
    }
    return null;
  }

  String? _extractTableNumber(Map<String, dynamic> data, Map<String, dynamic> payload) {
    final nodes = [data, payload];
    for (final node in nodes) {
      final table = node['table_name']?.toString().trim() ?? 
                   node['table_number']?.toString().trim() ??
                   node['table']?.toString().trim();
      if (table != null && table.isNotEmpty && table != 'null') return table;

      final extra = _asMap(node['type_extra']);
      if (extra != null) {
        final t = extra['table_name']?.toString().trim();
        if (t != null && t.isNotEmpty) return t;
      }
      
      final tableObj = _asMap(node['table']);
      if (tableObj != null) {
        final name = tableObj['name']?.toString().trim() ?? tableObj['number']?.toString().trim();
        if (name != null && name.isNotEmpty) return name;
      }
    }
    return null;
  }


}
