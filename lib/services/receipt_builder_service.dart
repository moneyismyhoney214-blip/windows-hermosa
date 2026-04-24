import '../models/receipt_data.dart';
import 'printer_language_settings_service.dart';

/// Shared receipt-building logic used by both the cashier (main screen)
/// and the waiter module. Previously the cashier's
/// `_buildOrderReceiptData` (mixin method on `_MainScreenState`) held
/// the only canonical implementation, and the waiter dispatcher kept a
/// hand-maintained copy — drift between the two showed up as mismatched
/// printed receipts (missing QR, wrong seller name, different payment
/// label format, etc.).
///
/// By extracting the logic here, any change to how a receipt is built
/// now applies to both entry points without duplication. The service is
/// intentionally stateless — every input that was previously an
/// instance field on `_MainScreenState` is now an explicit parameter.
///
/// The caller-side caches (`cache.sellerInfo`, `cache.branchMap`, etc.)
/// preserve the cashier's behaviour of reusing the most recent
/// successful invoice payload when a subsequent print call arrives
/// with a payload that's missing header data.
class ReceiptBuilderService {
  ReceiptBuilderService._();

  // ---------------------------------------------------------------------------
  // Tax helpers (mirror of main_screen.tax.dart)
  // ---------------------------------------------------------------------------

  static double subtotalFromTaxInclusiveTotal(
    double total, {
    required bool isTaxEnabled,
    required double taxRate,
  }) {
    if (!isTaxEnabled || taxRate <= 0 || total <= 0) return total;
    return total / (1.0 + taxRate);
  }

  static double taxFromTaxInclusiveTotal(
    double total, {
    required bool isTaxEnabled,
    required double taxRate,
  }) {
    if (!isTaxEnabled || taxRate <= 0 || total <= 0) return 0.0;
    final subtotal = subtotalFromTaxInclusiveTotal(total,
        isTaxEnabled: isTaxEnabled, taxRate: taxRate);
    return total - subtotal;
  }

  // ---------------------------------------------------------------------------
  // Order-type helpers (mirror of main_screen.cart.dart)
  // ---------------------------------------------------------------------------

  static String normalizeOrderTypeValue(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty || normalized == 'null') {
      return 'restaurant_pickup';
    }
    switch (normalized) {
      case 'pickup':
      case 'takeaway':
      case 'take_away':
      case 'restaurant_takeaway':
      case 'restaurant_take_away':
        return 'restaurant_pickup';
      case 'dine_in':
      case 'dinein':
      case 'internal':
      case 'inside':
      case 'restaurant_table':
      case 'table':
        return 'restaurant_internal';
      case 'delivery':
      case 'home_delivery':
      case 'restaurant_home_delivery':
        return 'restaurant_delivery';
      case 'restaurant_parking':
      case 'parking':
      case 'drive_through':
      case 'drive-through':
      case 'cars':
      case 'car':
        return 'restaurant_parking';
      case 'services':
      case 'service':
      case 'restaurant_services':
        return 'services';
      default:
        return normalized;
    }
  }

  /// When the active menu list is a known delivery provider, returns a
  /// canonical order-type code (`hungerstation_delivery`, `talabat_pickup`,
  /// etc.). Returns null if no provider matches — callers should fall
  /// through to `normalizeOrderTypeValue` with their raw type string.
  static String? resolveDeliveryProviderTypeCode({
    required bool isMenuListActive,
    required String activeMenuListName,
    required String menuListPriceType,
  }) {
    if (!isMenuListActive) return null;
    final rawName = activeMenuListName.trim();
    if (rawName.isEmpty) return null;
    final lower = rawName.toLowerCase();
    final suffix = menuListPriceType == 'pickup' ? 'pickup' : 'delivery';
    String? base;
    if (lower.contains('hunger') ||
        rawName.contains('هنقر') ||
        rawName.contains('هنجر')) {
      base = 'hungerstation';
    } else if (lower.contains('talabat') || rawName.contains('طلبات')) {
      base = 'talabat';
    } else if (lower.contains('jahez') ||
        lower.contains('gahez') ||
        rawName.contains('جاهز')) {
      base = 'jahez';
    }
    return base == null ? null : '${base}_$suffix';
  }

  // ---------------------------------------------------------------------------
  // Payment-method helpers
  // ---------------------------------------------------------------------------

  static String normalizePayMethod(String? method) {
    final rawInput = (method ?? '').trim();
    if (rawInput.isEmpty) return 'cash';
    final raw = rawInput.toLowerCase();
    final compact = raw.replaceAll(RegExp(r'[\s_\-]+'), '');

    if (raw.contains('آجل') || raw.contains('اجل') || raw.contains('بالآجل')) {
      return 'pay_later';
    }
    if (raw.contains('بيتي') ||
        raw.contains('بيتي كاش') ||
        raw.contains('بيتيكاش')) {
      return 'petty_cash';
    }
    if (raw.contains('تابي')) return 'tabby';
    if (raw.contains('تمارا')) return 'tamara';
    if (raw.contains('كيتا')) return 'keeta';
    if (raw.contains('ماي فاتورة') ||
        raw.contains('ماي_فاتورة') ||
        raw.contains('مايفاتورة')) {
      return 'my_fatoorah';
    }
    if (raw.contains('جاهز')) return 'jahez';
    if (raw.contains('طلبات')) return 'talabat';
    if (raw.contains('هنقر') || raw.contains('هنجر')) return 'hunger_station';
    if (raw.contains('تحويل')) return 'bank_transfer';
    if (raw.contains('محفظة')) return 'wallet';
    if (raw.contains('شيك')) return 'cheque';
    if (raw.contains('بينيفت') || raw.contains('بنفت')) return 'benefit';
    if (raw.contains('اس تي سي') ||
        raw.contains('stc') ||
        raw.contains('اس_تي_سي')) {
      return 'stc';
    }
    if (raw.contains('مدى')) return 'mada';
    if (raw.contains('بطاقة') ||
        raw.contains('فيزا') ||
        raw.contains('ماستر')) {
      return 'card';
    }
    if (raw.contains('نقد')) return 'cash';

    switch (compact) {
      case 'cash':
      case 'cashpayment':
        return 'cash';
      case 'pettycash':
      case 'petty_cash':
        return 'petty_cash';
      case 'paylater':
      case 'pay_later':
      case 'postpaid':
      case 'deferred':
        return 'pay_later';
      case 'card':
      case 'creditcard':
      case 'debitcard':
        return 'card';
      case 'mada':
        return 'mada';
      case 'visa':
      case 'mastercard':
        return 'visa';
      case 'benefit':
      case 'benefitpay':
      case 'benefit_pay':
        return 'benefit';
      case 'stc':
      case 'stcpay':
      case 'stc_pay':
        return 'stc';
      case 'bank':
      case 'banktransfer':
      case 'bank_transfer':
      case 'transfer':
        return 'bank_transfer';
      case 'wallet':
      case 'ewallet':
      case 'electronicwallet':
        return 'wallet';
      case 'cheque':
      case 'check':
        return 'cheque';
      case 'tabby':
      case 'taby':
        return 'tabby';
      case 'tamara':
        return 'tamara';
      case 'keeta':
      case 'kita':
        return 'keeta';
      case 'myfatoorah':
      case 'my_fatoorah':
      case 'myfatora':
      case 'myfatoora':
      case 'my_fatoora':
        return 'my_fatoorah';
      case 'jahez':
      case 'gahez':
        return 'jahez';
      case 'talabat':
        return 'talabat';
      case 'hungerstation':
      case 'hunger_station':
      case 'hunger':
        return 'hunger_station';
      default:
        return 'cash';
    }
  }

  static String payMethodArabicLabel(String method) {
    switch (method) {
      case 'cash':
        return 'نقدي';
      case 'card':
        return 'بطاقة';
      case 'mada':
        return 'مدى';
      case 'visa':
        return 'فيزا';
      case 'stc':
        return 'STC Pay';
      case 'bank_transfer':
        return 'تحويل بنكي';
      case 'wallet':
        return 'محفظة';
      case 'cheque':
        return 'شيك';
      case 'benefit':
        return 'Benefit Pay';
      case 'tabby':
        return 'Tabby';
      case 'tamara':
        return 'Tamara';
      case 'keeta':
        return 'Keeta';
      case 'my_fatoorah':
        return 'ماي فاتورة';
      case 'jahez':
        return 'جاهز';
      case 'talabat':
        return 'طلبات';
      case 'hunger_station':
        return 'هنقر ستيشن';
      case 'petty_cash':
        return 'بيتي كاش';
      case 'pay_later':
        return 'دفع لاحق';
      default:
        return method.isNotEmpty ? method : 'دفع';
    }
  }

  /// Renders the single-line "paymentMethod" string shown under the
  /// totals block on the printed receipt. Split payments become
  /// "نقدي (10.00) - بطاقة (5.00)"; single payments drop the amount.
  static String buildPaymentMethodLabel({
    required String type,
    required List<Map<String, dynamic>> pays,
  }) {
    if (type != 'payment') return 'دفع لاحق';
    if (pays.isEmpty) return 'دفع';

    if (pays.length > 1) {
      final parts = pays.map((pay) {
        final normalized = normalizePayMethod(pay['pay_method']?.toString());
        final label = payMethodArabicLabel(normalized);
        final amount = pay['amount'];
        if (amount != null) {
          final amountStr = (amount is num)
              ? amount.toStringAsFixed(2)
              : (double.tryParse(amount.toString()) ?? 0)
                  .toStringAsFixed(2);
          return '$label ($amountStr)';
        }
        return label;
      }).toList();
      return parts.join(' - ');
    }

    final normalized =
        normalizePayMethod(pays.first['pay_method']?.toString());
    return payMethodArabicLabel(normalized);
  }

  // ---------------------------------------------------------------------------
  // Main receipt data builder
  // ---------------------------------------------------------------------------

  /// Pure-function port of the cashier's `_buildOrderReceiptData`.
  ///
  /// All state that was previously an instance field on `_MainScreenState`
  /// is now an explicit parameter:
  ///   * `isTaxEnabled`, `taxRate` — were `_isTaxEnabled`, `_taxRate`
  ///   * `userNameFallback` — was `_userName`
  ///   * `cache` — holds the `_cachedSellerInfo` / `_cachedBranchMap` /
  ///     `_cachedSellerNameEn` / `_cachedBranchAddressEn` fields. The
  ///     cashier creates one instance tied to its session; the service
  ///     reads + writes it just like the mixin did.
  ///   * `authUser` / `branchReceiptCache` — waiter-specific fallbacks
  ///     (auth profile and BranchService snapshot). Cashier passes null.
  ///   * `activeMenuListName` / `menuListPriceType` / `isMenuListActive`
  ///     — delivery-provider detection inputs (cashier-only).
  static OrderReceiptData build({
    required String orderId,
    String? invoiceNumber,
    required List<Map<String, dynamic>> orderItems,
    required double orderTotal,
    required String orderType,
    required String type,
    required List<Map<String, dynamic>> pays,
    Map<String, dynamic>? invoicePayload,
    String carNumber = '',
    String? tableNumber,
    double? discountAmount,
    double? discountPercentage,
    String? discountName,
    String? dailyOrderNumber,
    required bool isTaxEnabled,
    required double taxRate,
    String? userNameFallback,
    ReceiptBuilderCache? cache,
    Map<String, dynamic>? authUser,
    Map<String, dynamic>? branchReceiptCache,
    String activeMenuListName = '',
    String menuListPriceType = '',
    bool isMenuListActive = false,
  }) {
    final subtotal = subtotalFromTaxInclusiveTotal(orderTotal,
        isTaxEnabled: isTaxEnabled, taxRate: taxRate);
    final vat = taxFromTaxInclusiveTotal(orderTotal,
        isTaxEnabled: isTaxEnabled, taxRate: taxRate);
    final branch = invoicePayload?['branch'];
    final seller = invoicePayload?['seller'];
    final invoice = invoicePayload?['invoice'];
    final branchMap = branch is Map ? _asStringKeyMap(branch) : null;
    final sellerMap = seller is Map ? _asStringKeyMap(seller) : null;
    final nestedSeller = branchMap?['seller'];
    final nestedSellerMap =
        nestedSeller is Map ? _asStringKeyMap(nestedSeller) : null;
    final originalSeller = branchMap?['original_seller'];
    final originalSellerMap =
        originalSeller is Map ? _asStringKeyMap(originalSeller) : null;
    final invoiceMap = invoice is Map ? _asStringKeyMap(invoice) : null;

    // Waiter-specific fallback layers — consulted only when the primary
    // payload (`invoicePayload`) is missing a field. The cashier path
    // passes `authUser=null` and `branchReceiptCache=null`, so these
    // branches drop out at runtime for the cashier.
    final userBranch = authUser == null ? null : _asStringKeyMap(authUser['branch']);
    final userSeller = authUser == null
        ? null
        : (_asStringKeyMap(authUser['seller']) ??
            _asStringKeyMap(userBranch?['seller']));
    final cachedReceiptBranch =
        branchReceiptCache == null ? null : _asStringKeyMap(branchReceiptCache['branch']);
    final cachedBranchLogoUrl =
        branchReceiptCache?['branch_logo_url']?.toString().trim();
    final cachedSellerNameEnFromCache =
        branchReceiptCache?['seller_name_en']?.toString().trim();
    final cachedProfileBranchName =
        branchReceiptCache?['profile_branch_name']?.toString().trim();

    // Unify primary branch map — payload first, then the BranchService
    // snapshot. Every nested-seller / tax / logo picker below reads
    // through this single reference, so a missing `branch` in the
    // payload transparently falls through to the cache without
    // changing the rest of the logic.
    final effectiveBranch = branchMap ?? cachedReceiptBranch;
    final effectiveNestedSeller = nestedSellerMap ??
        (effectiveBranch != null
            ? _asStringKeyMap(effectiveBranch['seller'])
            : null);
    final effectiveOriginalSeller = originalSellerMap ??
        (effectiveBranch != null
            ? _asStringKeyMap(effectiveBranch['original_seller'])
            : null);

    String? firstNonEmptyString(List<dynamic> values) {
      for (final value in values) {
        final text = value?.toString().trim();
        if (text != null && text.isNotEmpty && text.toLowerCase() != 'null') {
          return text;
        }
      }
      return null;
    }

    final receiptCache = cache;

    // Branch address: combine district + street when both exist
    // (matches the old paper-receipt layout "الحي، العنوان"); fall
    // back to whichever is available.
    final branchDistrict =
        (effectiveBranch?['district']?.toString() ?? '').trim();
    final branchStreet = (firstNonEmptyString([
              effectiveBranch?['address'],
              sellerMap?['address'],
              effectiveNestedSeller?['address'],
              invoiceMap?['branch_address'],
              invoicePayload?['address'],
              userBranch?['address'],
            ]) ??
            '')
        .trim();
    final branchAddressCombined = (branchDistrict.isNotEmpty &&
            branchStreet.isNotEmpty &&
            branchDistrict != branchStreet)
        ? '$branchDistrict، $branchStreet'
        : (branchStreet.isNotEmpty ? branchStreet : branchDistrict);
    final branchAddressEn = firstNonEmptyString([
      invoicePayload?['branch_address_en'],
      invoicePayload?['branch_district_en'],
    ]);
    final sellerNameEnMerged = firstNonEmptyString([
      invoicePayload?['seller_name_en'],
      cachedSellerNameEnFromCache,
    ]);
    final branchMobile = firstNonEmptyString([
      effectiveBranch?['mobile'],
      effectiveBranch?['phone'],
      sellerMap?['mobile'],
      sellerMap?['phone'],
      effectiveNestedSeller?['mobile'],
      effectiveNestedSeller?['phone'],
      invoiceMap?['branch_mobile'],
      invoicePayload?['mobile'],
      userBranch?['mobile'],
      userBranch?['phone'],
    ]);

    // Update caller-side session cache (cashier uses this to carry
    // seller / branch info across receipts; waiter supplies null).
    if (receiptCache != null) {
      if (effectiveNestedSeller != null && effectiveNestedSeller.isNotEmpty) {
        receiptCache.sellerInfo =
            Map<String, dynamic>.from(effectiveNestedSeller);
      } else if (effectiveOriginalSeller != null &&
          effectiveOriginalSeller.isNotEmpty) {
        receiptCache.sellerInfo =
            Map<String, dynamic>.from(effectiveOriginalSeller);
      }
      if (effectiveBranch != null && effectiveBranch.isNotEmpty) {
        receiptCache.branchMap = Map<String, dynamic>.from(effectiveBranch);
      }
      if (invoicePayload != null) {
        receiptCache.branchAddressEn ??=
            invoicePayload['branch_address_en']?.toString();
        receiptCache.sellerNameEn ??=
            invoicePayload['seller_name_en']?.toString();
      }
    }

    // Tax number — API nests it under `branch.seller.tax_number`.
    final taxNumber = firstNonEmptyString([
      effectiveNestedSeller?['tax_number'],
      effectiveOriginalSeller?['tax_number'],
      effectiveBranch?['tax_number'],
      sellerMap?['tax_number'],
      effectiveNestedSeller?['vat_number'],
      effectiveOriginalSeller?['vat_number'],
      effectiveBranch?['vat_number'],
      sellerMap?['vat_number'],
      invoiceMap?['tax_number'],
      invoiceMap?['vat_number'],
      invoicePayload?['tax_number'],
      invoicePayload?['vat_number'],
      receiptCache?.sellerInfo?['tax_number'],
      receiptCache?.sellerInfo?['vat_number'],
      userSeller?['tax_number'],
      userSeller?['vat_number'],
      userBranch?['tax_number'],
      userBranch?['vat_number'],
    ]);

    // Commercial register — same nested-first ordering.
    final commercialRegNumber = firstNonEmptyString([
      effectiveNestedSeller?['commercial_register_number'],
      effectiveNestedSeller?['commercial_register'],
      effectiveOriginalSeller?['commercial_register_number'],
      effectiveOriginalSeller?['commercial_register'],
      effectiveBranch?['commercial_register_number'],
      sellerMap?['commercial_register_number'],
      effectiveBranch?['commercial_register'],
      sellerMap?['commercial_register'],
      effectiveBranch?['commercial_number'],
      sellerMap?['commercial_number'],
      effectiveNestedSeller?['cr_number'],
      effectiveOriginalSeller?['cr_number'],
      effectiveBranch?['cr_number'],
      sellerMap?['cr_number'],
      invoiceMap?['commercial_register_number'],
      invoiceMap?['commercial_register'],
      invoiceMap?['commercial_number'],
      invoiceMap?['cr_number'],
      invoicePayload?['commercial_register_number'],
      invoicePayload?['commercial_register'],
      invoicePayload?['commercial_number'],
      invoicePayload?['cr_number'],
      receiptCache?.sellerInfo?['commercial_register_number'],
      receiptCache?.sellerInfo?['commercial_register'],
      receiptCache?.sellerInfo?['commercial_number'],
      receiptCache?.sellerInfo?['cr_number'],
      userSeller?['commercial_register_number'],
      userSeller?['commercial_register'],
      userSeller?['cr_number'],
      userBranch?['commercial_register_number'],
      userBranch?['commercial_register'],
    ]);

    // Base64 QR + ZATCA image URL. The backend serves the base64 QR
    // under `data.qr_image` (root of the unwrapped payload) and a
    // separate image URL under `zatca_qr_image`.
    final qrValue = (invoiceMap?['qr_image'] ??
            invoiceMap?['zatca_qr_image'] ??
            invoicePayload?['qr_image'])
        ?.toString();
    final zatcaQrImageUrl =
        (invoiceMap?['zatca_qr_image'] ?? invoicePayload?['zatca_qr_image'])
            ?.toString();

    // Seller logo — priority: branch.seller.logo > branch.original_seller.logo
    // > BranchService cache (/seller/branches) > plain seller.logo.
    // Relative `/storage/...` paths get the portal base prepended.
    String? logoUrl;
    if (effectiveBranch != null) {
      final branchSeller = effectiveBranch['seller'];
      final branchOriginalSeller = effectiveBranch['original_seller'];
      if (branchSeller is Map && branchSeller['logo'] != null) {
        final logo = branchSeller['logo'].toString();
        logoUrl = logo.startsWith('/')
            ? 'https://portal.hermosaapp.com$logo'
            : logo;
      } else if (branchOriginalSeller is Map &&
          branchOriginalSeller['logo'] != null) {
        final logo = branchOriginalSeller['logo'].toString();
        logoUrl = logo.startsWith('/')
            ? 'https://portal.hermosaapp.com$logo'
            : logo;
      }
    }
    if (logoUrl == null || logoUrl.isEmpty) {
      if (cachedBranchLogoUrl != null && cachedBranchLogoUrl.isNotEmpty) {
        logoUrl = cachedBranchLogoUrl;
      } else {
        logoUrl = firstNonEmptyString([
          sellerMap?['logo'],
          userSeller?['logo'],
        ]);
      }
    }

    final invoiceDateTime = (invoiceMap?['ISO8601'] ??
            invoiceMap?['date'] ??
            invoicePayload?['created_at'])
        ?.toString();

    // Cashier name (for the "الكاشير: X" row). Stays separate from
    // the brand/seller name shown in the big header text.
    final invoiceCashier = invoiceMap?['cashier'];
    final invoiceCashierMap =
        invoiceCashier is Map ? _asStringKeyMap(invoiceCashier) : null;
    final cashierName = (invoiceCashierMap != null
                ? (invoiceCashierMap['fullname'] ??
                    invoiceCashierMap['name'])
                : null) ??
            invoiceMap?['cashier_name'] ??
            invoicePayload?['cashier_name'] ??
            invoicePayload?['user_name'];
    final cashierNameStr = cashierName?.toString();

    // Branch display name (for the header under the brand).
    final branchName = (effectiveBranch?['seller_name'] ??
            invoicePayload?['table_name'])
        ?.toString();

    // Brand / seller-name-en resolution. The backend stores
    // `branch.seller_name` as "عربي | English"; splitting it yields
    // per-language names. We fall through to the enriched merged
    // English payload and finally `userNameFallback` (the cashier's
    // account name) only as a last resort.
    String resolvedSellerNameEn;
    if (sellerNameEnMerged != null && sellerNameEnMerged.isNotEmpty) {
      resolvedSellerNameEn = sellerNameEnMerged;
    } else if (branchName != null && branchName.contains('|')) {
      resolvedSellerNameEn = branchName.split('|').last.trim();
    } else if (cashierNameStr != null && cashierNameStr.contains('|')) {
      resolvedSellerNameEn = cashierNameStr.split('|').last.trim();
    } else {
      resolvedSellerNameEn = branchName ??
          cashierNameStr ??
          cachedProfileBranchName ??
          userNameFallback ??
          '';
    }

    String resolvedSellerNameAr;
    if (branchName != null && branchName.contains('|')) {
      resolvedSellerNameAr = branchName.split('|').first.trim();
    } else if (cashierNameStr != null && cashierNameStr.contains('|')) {
      resolvedSellerNameAr = cashierNameStr.split('|').first.trim();
    } else {
      resolvedSellerNameAr = branchName ??
          cachedProfileBranchName ??
          cashierNameStr ??
          userNameFallback ??
          '';
    }

    // Delivery-provider suffix — the cashier extracts "(هنقرستيشن)"
    // from the raw orderType string and preserves it alongside the
    // normalized base type.
    String menuListSuffix = '';
    String baseOrderType = orderType;
    final parenIdx = orderType.indexOf('(');
    if (parenIdx > 0) {
      menuListSuffix = ' ${orderType.substring(parenIdx).trim()}';
      baseOrderType = orderType.substring(0, parenIdx).trim();
    }
    final baseLower = baseOrderType.toLowerCase();
    final isClientProviderCode = baseLower.startsWith('hungerstation_') ||
        baseLower.startsWith('hunger_station_') ||
        baseLower.startsWith('talabat_') ||
        baseLower.startsWith('jahez_') ||
        baseLower.startsWith('gahez_');
    final rawResolvedOrderType = isClientProviderCode
        ? baseOrderType
        : normalizeOrderTypeValue(
            firstNonEmptyString([
                  invoiceMap?['type'],
                  invoiceMap?['booking_type'],
                  invoiceMap?['order_type'],
                  invoicePayload?['type'],
                  invoicePayload?['booking_type'],
                  invoicePayload?['order_type'],
                  baseOrderType,
                ]) ??
                baseOrderType,
          );
    final resolvedOrderType = menuListSuffix.isNotEmpty
        ? '$rawResolvedOrderType$menuListSuffix'
        : rawResolvedOrderType;

    // Daily order number — prefer callerArg, then invoice / booking /
    // order sub-nodes from the payload, then the invoice number.
    final bookingNode = invoicePayload?['booking'];
    final orderNode = invoicePayload?['order'];
    final bookingNodeMap =
        bookingNode is Map ? _asStringKeyMap(bookingNode) : null;
    final orderNodeMap = orderNode is Map ? _asStringKeyMap(orderNode) : null;
    final resolvedDailyOrderNumber = (dailyOrderNumber != null &&
            dailyOrderNumber.isNotEmpty)
        ? dailyOrderNumber
        : firstNonEmptyString([
            invoiceMap?['daily_order_number'],
            invoiceMap?['order_number'],
            bookingNodeMap?['daily_order_number'],
            bookingNodeMap?['order_number'],
            orderNodeMap?['daily_order_number'],
            orderNodeMap?['order_number'],
            invoicePayload?['daily_order_number'],
            invoicePayload?['order_number'],
          ]);

    final resolvedInvoiceNumber = firstNonEmptyString([
          invoiceNumber,
          invoiceMap?['invoice_number'],
          invoicePayload?['invoice_number'],
        ]) ??
        '';

    final resolvedBranchAddressEn = branchAddressEn ??
        (branchAddressCombined.isEmpty ? null : branchAddressCombined);

    // Unused outside cashier for now (no call site relies on a
    // provider suffix being applied when there's no orderType paren),
    // but kept available via the public helper for future callers.
    // ignore: unused_local_variable
    final _providerHint = resolveDeliveryProviderTypeCode(
      isMenuListActive: isMenuListActive,
      activeMenuListName: activeMenuListName,
      menuListPriceType: menuListPriceType,
    );

    // ------------------------------------------------------------------
    // Items + addons — merge per-language names from the API's parallel
    // items list and resolve primary/secondary based on the device's
    // printer language settings.
    // ------------------------------------------------------------------
    final apiItems = invoiceMap?['items'] ?? invoicePayload?['items'];
    final apiItemsList = apiItems is List ? apiItems : const [];
    final invoicePri = printerLanguageSettings.primary;
    final invoiceSec = printerLanguageSettings.secondary;

    final receiptItems = orderItems.asMap().entries.map((entry) {
      final idx = entry.key;
      final item = entry.value;
      final cartName = item['name']?.toString() ?? '';
      final localizedNames = item['localizedNames'];
      final namesMap = localizedNames is Map
          ? Map<String, String>.from(
              localizedNames.map((k, v) =>
                  MapEntry(k.toString(), v?.toString() ?? '')))
          : <String, String>{};

      String arName = item['nameAr']?.toString() ?? cartName;
      String enName = item['nameEn']?.toString() ?? '';

      if (idx < apiItemsList.length) {
        final apiItem = apiItemsList[idx];
        final apiName =
            (apiItem is Map ? apiItem['item_name']?.toString() : null) ?? '';
        if (apiName.contains(' - ')) {
          arName = apiName.split(' - ').first.trim();
          enName = apiName.split(' - ').last.trim();
        } else if (apiName.isNotEmpty) {
          arName = apiName;
        }
      }

      if (enName.isEmpty && cartName.contains(' - ')) {
        arName = cartName.split(' - ').first.trim();
        enName = cartName.split(' - ').last.trim();
      }

      if (!namesMap.containsKey('ar') || namesMap['ar']!.isEmpty) {
        if (arName.isNotEmpty) namesMap['ar'] = arName;
      }
      if (!namesMap.containsKey('en') || namesMap['en']!.isEmpty) {
        if (enName.isNotEmpty) namesMap['en'] = enName;
      }

      String resolveName(String langCode) {
        if (namesMap.containsKey(langCode) && namesMap[langCode]!.isNotEmpty) {
          return namesMap[langCode]!;
        }
        if (enName.isNotEmpty) return enName;
        return arName.isNotEmpty ? arName : cartName;
      }

      final primaryName = resolveName(invoicePri);
      final secondaryName = resolveName(invoiceSec);

      final rawQty = (item['quantity'] as num?)?.toDouble() ?? 0;
      final rawUnitPrice = (item['unitPrice'] as num?)?.toDouble() ?? 0;
      final rawTotal = (item['total'] as num?)?.toDouble() ?? 0;
      final multiplier = isTaxEnabled ? (1.0 + taxRate) : 1.0;

      final rawExtras = item['extras'];
      final addons = <ReceiptAddon>[];
      if (rawExtras is List) {
        for (final e in rawExtras) {
          if (e is Map) {
            final name = e['name']?.toString() ?? '';
            if (name.isEmpty) continue;
            final price = (e['price'] is num)
                ? (e['price'] as num).toDouble()
                : double.tryParse(e['price']?.toString() ?? '') ?? 0.0;

            final translations = e['translations'];
            final optionMap =
                (translations is Map) ? translations['option'] : null;
            final localized = <String, String>{};
            if (optionMap is Map) {
              for (final optEntry in optionMap.entries) {
                final v = optEntry.value?.toString().trim() ?? '';
                if (v.isEmpty) continue;
                localized[optEntry.key.toString().trim().toLowerCase()] = v;
              }
            }

            addons.add(ReceiptAddon(
              nameAr: localized['ar']?.isNotEmpty == true
                  ? localized['ar']!
                  : name,
              nameEn: localized['en']?.isNotEmpty == true
                  ? localized['en']!
                  : name,
              price: price,
              localizedNames: localized,
            ));
          }
        }
      }

      return ReceiptItem(
        nameAr: primaryName,
        nameEn: secondaryName.isNotEmpty ? secondaryName : primaryName,
        quantity: rawQty,
        unitPrice: rawUnitPrice * multiplier,
        total: rawTotal * multiplier,
        addons: addons.isNotEmpty ? addons : null,
      );
    }).toList();

    final receiptPayments = _parsePaymentsList(pays);

    return OrderReceiptData(
      invoiceNumber: resolvedInvoiceNumber,
      issueDateTime: invoiceDateTime ?? DateTime.now().toIso8601String(),
      sellerNameAr: resolvedSellerNameAr,
      sellerNameEn: resolvedSellerNameEn,
      vatNumber: taxNumber ?? '',
      branchName: branchName ?? '',
      carNumber: carNumber,
      tableNumber: tableNumber?.trim().isNotEmpty == true ? tableNumber : null,
      branchAddressEn: resolvedBranchAddressEn,
      items: receiptItems,
      totalExclVat: subtotal,
      vatAmount: vat,
      totalInclVat: orderTotal,
      paymentMethod: buildPaymentMethodLabel(type: type, pays: pays),
      payments: receiptPayments,
      qrCodeBase64: qrValue ?? '',
      sellerLogo: logoUrl,
      zatcaQrImage: zatcaQrImageUrl,
      branchAddress:
          branchAddressCombined.isEmpty ? null : branchAddressCombined,
      branchMobile: branchMobile,
      commercialRegisterNumber: commercialRegNumber,
      cashierName: cashierNameStr ?? userNameFallback,
      orderType: resolvedOrderType,
      orderNumber: resolvedDailyOrderNumber ?? orderId,
      orderDiscountAmount: discountAmount,
      orderDiscountPercentage: discountPercentage,
      orderDiscountName: discountName,
    );
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  static Map<String, dynamic>? _asStringKeyMap(Object? v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return v.map((k, val) => MapEntry(k.toString(), val));
    return null;
  }

  static List<ReceiptPayment> _parsePaymentsList(dynamic paysRaw) {
    final paysList = paysRaw is List ? paysRaw : const [];
    final parsedPayments = <ReceiptPayment>[];

    double parseNumLocal(dynamic value) {
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? 0.0;
      return 0.0;
    }

    for (final pay in paysList) {
      final map = pay is Map ? pay : null;
      if (map == null) continue;
      final method = (map['pay_method'] ?? map['method'] ?? map['name'])
          ?.toString()
          .trim()
          .toLowerCase();
      final numericAmount = parseNumLocal(
          map['amount'] ?? map['value'] ?? map['paid'] ?? map['total']);
      if (method == null || method.isEmpty) continue;
      final normalized = normalizePayMethod(method);
      parsedPayments.add(ReceiptPayment(
        methodLabel: payMethodArabicLabel(normalized),
        amount: numericAmount,
      ));
    }
    return parsedPayments;
  }
}

/// Mutable container for session-scoped seller/branch caches. The
/// cashier's main-screen state owns one instance; the receipt builder
/// reads it for fallbacks and writes back fresh values on each call.
/// Waiter callers pass null (they have a separate BranchService-backed
/// cache).
class ReceiptBuilderCache {
  Map<String, dynamic>? sellerInfo;
  Map<String, dynamic>? branchMap;
  String? branchAddressEn;
  String? sellerNameEn;
}
