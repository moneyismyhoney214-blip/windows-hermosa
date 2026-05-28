// Parsing / utility helpers — split from invoice_html_pdf_service.dart for size.
part of '../invoice_html_pdf_service.dart';

extension InvoiceHtmlPdfServiceHelpers on InvoiceHtmlPdfService {
  String _resolveOrderTypeLabel(String type, String primaryLang) {
    final normalized = type.trim().toLowerCase();
    final pri = primaryLang.trim().toLowerCase();
    String pick({required String ar, required String en, String? hi, String? ur, String? es, String? tr}) {
      switch (pri) {
        case 'en': return en;
        case 'hi': return hi ?? en;
        case 'ur': return ur ?? en;
        case 'es': return es ?? en;
        case 'tr': return tr ?? en;
        default: return ar;
      }
    }
    switch (normalized == 'services' ? 'restaurant_services' : normalized) {
      case 'restaurant_services':
      case 'service':
        return pick(ar: 'محلي', en: 'Local', hi: 'स्थानीय', ur: 'مقامی', es: 'Local', tr: 'Yerel');
      case 'restaurant_internal':
      case 'restaurant_table':
      case 'table':
        return pick(ar: 'داخل المطعم', en: 'Dine In', hi: 'डाइन इन', ur: 'اندرونی', es: 'Comer Aquí', tr: 'İçeride');
      case 'restaurant_delivery':
      case 'delivery':
      case 'home_delivery':
        return pick(ar: 'توصيل', en: 'Delivery', hi: 'डिलीवरी', ur: 'ڈیلیوری', es: 'Entrega', tr: 'Teslimat');
      case 'restaurant_pickup':
      case 'pickup':
      case 'takeaway':
        return pick(ar: 'استلام من الفرع', en: 'Pickup', hi: 'पिकअप', ur: 'پک اپ', es: 'Recogida', tr: 'Teslim Alma');
      case 'restaurant_parking':
      case 'cars':
      case 'car':
        return pick(ar: 'سيارة', en: 'Drive-through', hi: 'ड्राइव-थ्रू', ur: 'ڈرائیو تھرو', es: 'Auto-servicio', tr: 'Araç Servisi');
      case 'hungerstation_delivery':
      case 'hunger_station_delivery':
        return pick(ar: 'هنقر ستيشن (توصيل)', en: 'HungerStation (Delivery)', hi: 'हंगरस्टेशन (डिलीवरी)', ur: 'ہنگر سٹیشن (ڈیلیوری)', es: 'HungerStation (Entrega)', tr: 'HungerStation (Teslimat)');
      case 'hungerstation_pickup':
      case 'hunger_station_pickup':
        return pick(ar: 'هنقر ستيشن (استلام)', en: 'HungerStation (Pickup)', hi: 'हंगरस्टेशन (पिकअप)', ur: 'ہنگر سٹیشن (پک اپ)', es: 'HungerStation (Recogida)', tr: 'HungerStation (Teslim Alma)');
      case 'talabat_delivery':
        return pick(ar: 'طلبات (توصيل)', en: 'Talabat (Delivery)', hi: 'तलबात (डिलीवरी)', ur: 'طلبات (ڈیلیوری)', es: 'Talabat (Entrega)', tr: 'Talabat (Teslimat)');
      case 'talabat_pickup':
        return pick(ar: 'طلبات (استلام)', en: 'Talabat (Pickup)', hi: 'तलबात (पिकअप)', ur: 'طلبات (پک اپ)', es: 'Talabat (Recogida)', tr: 'Talabat (Teslim Alma)');
      case 'jahez_delivery':
      case 'gahez_delivery':
        return pick(ar: 'جاهز (توصيل)', en: 'Jahez (Delivery)', hi: 'जाहेज़ (डिलीवरी)', ur: 'جاہز (ڈیلیوری)', es: 'Jahez (Entrega)', tr: 'Jahez (Teslimat)');
      case 'jahez_pickup':
      case 'gahez_pickup':
        return pick(ar: 'جاهز (استلام)', en: 'Jahez (Pickup)', hi: 'जाहेज़ (पिकअप)', ur: 'جاہز (پک اپ)', es: 'Jahez (Recogida)', tr: 'Jahez (Teslim Alma)');
      default:
        return normalized.isEmpty ? '' : normalized;
    }
  }

  /// Resolves the invoice title into `(text, textAlt)` — `text` is the
  /// localized primary-language title, `textAlt` is the universally
  /// recognizable Arabic subtitle kept on every receipt for regulatory
  /// consistency.
  ///
  /// Every kind now resolves across all six supported languages
  /// (ar/en/es/tr/hi/ur) through a single lookup table so adding a new
  /// language or invoice kind stays a one-line change instead of another
  /// copy-pasted `switch` arm.
  _InvoiceTitle _resolveTitle(String kind, String primaryLanguage) {
    final primary = primaryLanguage.trim().toLowerCase();

    String pickTitle({
      required String ar,
      required String en,
      String? hi,
      String? ur,
      String? tr,
      String? es,
    }) {
      switch (primary) {
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

    switch (kind) {
      case 'simplified':
      case 'simplified_b2b':
        return _InvoiceTitle(
          text: pickTitle(
            ar: 'فاتورة ضريبية مبسطة',
            en: 'Simplified Tax Invoice',
            hi: kind == 'simplified' ? 'सरलीकृत कर इनवॉइस' : 'सरल कर इनवॉइस',
            ur: 'سادہ ٹیکس انوائس',
            tr: 'Basitleştirilmiş Vergi Faturası',
            es: 'Factura Fiscal Simplificada',
          ),
          textAlt: primary == 'ar'
              ? 'Simplified Tax Invoice'
              : 'فاتورة ضريبية مبسطة',
        );

      case 'refundSalesInvoice':
        return _InvoiceTitle(
          text: pickTitle(
            ar: 'إشعار دائن',
            en: 'Credit Note',
            hi: 'क्रेडिट नोट',
            ur: 'کریڈٹ نوٹ',
            tr: 'Alacak Dekontu',
            es: 'Nota de Crédito',
          ),
          textAlt: primary == 'ar' ? 'Credit Note' : 'إشعار دائن',
        );

      case 'debitNote':
      case 'debitNote_b2b':
        return _InvoiceTitle(
          text: pickTitle(
            ar: 'إشعار مدين',
            en: 'Debit Note',
            hi: 'डेबिट नोट',
            ur: 'ڈیبٹ نوٹ',
            tr: 'Borç Dekontu',
            es: 'Nota de Débito',
          ),
          textAlt: primary == 'ar' ? 'Debit Note' : 'إشعار مدين',
        );

      case 'deposit':
        return _InvoiceTitle(
          text: pickTitle(
            ar: 'فاتورة العربون',
            en: 'Deposit Invoice',
            hi: 'जमा चालान',
            ur: 'ڈپازٹ انوائس',
            tr: 'Depozito Faturası',
            es: 'Factura de Depósito',
          ),
          textAlt: primary == 'ar' ? 'Deposit Invoice' : 'فاتورة العربون',
        );

      case 'depositRefund':
        return _InvoiceTitle(
          text: pickTitle(
            ar: 'إشعار دائن - عربون',
            en: 'Deposit Credit Note',
            hi: 'जमा क्रेडिट नोट',
            ur: 'ڈپازٹ کریڈٹ نوٹ',
            tr: 'Depozito Alacak Dekontu',
            es: 'Nota de Crédito - Depósito',
          ),
          textAlt: primary == 'ar'
              ? 'Deposit Credit Note'
              : 'إشعار دائن - عربون',
        );

      case 'usedProducts':
        return _InvoiceTitle(
          text: pickTitle(
            ar: 'فاتورة استخدام منتجات',
            en: 'Used Products Invoice',
            hi: 'उपयोग किए गए उत्पाद इनवॉइस',
            ur: 'استعمال شدہ مصنوعات انوائس',
            tr: 'Kullanılmış Ürünler Faturası',
            es: 'Factura de Productos Usados',
          ),
          textAlt: primary == 'ar'
              ? 'Used Products Invoice'
              : 'فاتورة استخدام منتجات',
        );

      case 'sessions':
        return _InvoiceTitle(
          text: pickTitle(
            ar: 'حجوزات الجلسات',
            en: 'Sessions Bookings',
            hi: 'सत्र बुकिंग',
            ur: 'سیشن بکنگ',
            tr: 'Oturum Rezervasyonları',
            es: 'Reservas de Sesiones',
          ),
          textAlt: primary == 'ar'
              ? 'Sessions Bookings'
              : 'حجوزات الجلسات',
        );

      default:
        return _InvoiceTitle(
          text: pickTitle(
            ar: 'فاتورة ضريبية مبسطة',
            en: 'Simplified Tax Invoice',
            hi: 'सरलीकृत कर इनवॉइस',
            ur: 'سادہ ٹیکس انوائس',
            tr: 'Basitleştirilmiş Vergi Faturası',
            es: 'Factura Fiscal Simplificada',
          ),
          textAlt: primary == 'ar'
              ? 'Simplified Tax Invoice'
              : 'الفاتورة الضريبية المبسطة',
        );
    }
  }

  String _resolveKind({
    required String? forcedKind,
    required Map<String, dynamic> envelope,
    required Map<String, dynamic> invoice,
  }) {
    const allowed = <String>{
      'simplified',
      'debitNote',
      'simplified_b2b',
      'debitNote_b2b',
      'refundSalesInvoice',
      'deposit',
      'depositRefund',
      'usedProducts',
      'sessions',
    };

    final candidate = _firstNonEmptyString([
      forcedKind,
      _pick(invoice, const ['kind', 'invoice_kind']),
      _pick(envelope, const ['kind', 'invoice_kind']),
    ]);

    if (candidate != null && allowed.contains(candidate)) {
      return candidate;
    }

    final hasOriginalInvoice = _firstNonEmptyString([
          _pick(invoice, const ['original_invoice_number']),
        ]) !=
        null;

    if (hasOriginalInvoice) {
      return 'refundSalesInvoice';
    }

    return 'simplified';
  }

  bool _isValidAttribute(String key, List<String> fields) {
    if (key == 'addons') return false;
    return fields.contains(key);
  }

  bool _isRestaurant(_PrintInvoiceModel model) {
    final module = model.module.trim().toLowerCase();
    final type = model.type.trim().toLowerCase();

    if (module.contains('restaurant')) return true;
    if (type.contains('restaurant')) return true;
    return false;
  }

  bool _isCarCare(_PrintInvoiceModel model) {
    if (model.carInfo.isEmpty) return false;
    final module = model.module.trim().toLowerCase();
    if (module.contains('car')) return true;
    final envelopeCarInfo = _asMap(_pick(model.envelope, const ['car_info']));
    if (envelopeCarInfo.isNotEmpty) return true;
    final invoiceCarInfo = _asMap(_pick(model.invoice, const ['car_info']));
    return invoiceCarInfo.isNotEmpty;
  }

  List<Map<String, dynamic>> _extractItems(Map<String, dynamic> invoice) {
    final candidates = [
      invoice['items'],
      invoice['sales_meals'],
      invoice['booking_products'],
      invoice['products'],
      invoice['meals'],
    ];

    for (final candidate in candidates) {
      final items = _asMapList(candidate);
      if (items.isNotEmpty) {
        return items;
      }
    }

    return const [];
  }

  List<String> _extractFields(
    Map<String, dynamic> invoice,
    List<Map<String, dynamic>> items,
  ) {
    final raw = invoice['fields'];
    if (raw is List) {
      final seen = <String>{};
      final result = <String>[];
      for (final field in raw) {
        final key = field.toString().trim();
        if (key.isEmpty || seen.contains(key)) continue;
        seen.add(key);
        result.add(key);
      }
      if (result.isNotEmpty) {
        return result;
      }
    }

    final derived = <String>[];
    final seen = <String>{};
    for (final item in items) {
      for (final key in item.keys) {
        final k = key.toString().trim();
        if (k.isEmpty || seen.contains(k)) continue;
        seen.add(k);
        derived.add(k);
      }
    }

    if (derived.isNotEmpty) {
      return derived;
    }

    return const ['item_name', 'quantity', 'total'];
  }

  String _resolvePaymentMethods(Map<String, dynamic> invoice) {
    final methods = invoice['payment_methods'];

    if (methods is String && methods.trim().isNotEmpty) {
      return methods.trim();
    }

    if (methods is List) {
      final labels = methods
          .map((entry) {
            final map = _asMap(entry);
            return _firstNonEmptyString([
                  _pick(map, const ['name_ar', 'name', 'pay_method', 'method']),
                ]) ??
                '';
          })
          .where((label) => label.isNotEmpty)
          .toList();
      if (labels.isNotEmpty) {
        return labels.join(' - ');
      }
    }

    final pays = invoice['pays'];
    if (pays is List && pays.length > 1) {
      // Split payment: show each method with its amount
      final parts = <String>[];
      for (final entry in pays) {
        final map = _asMap(entry);
        final label = _firstNonEmptyString([
              _pick(map, const ['name_ar', 'name', 'pay_method', 'method']),
            ]) ??
            '';
        if (label.isEmpty) continue;
        final amount = map['amount'];
        if (amount != null) {
          final amountStr = (amount is num)
              ? amount.toStringAsFixed(ApiConstants.digitsNumber)
              : (double.tryParse(amount.toString()) ?? 0).toStringAsFixed(ApiConstants.digitsNumber);
          parts.add('$label ($amountStr)');
        } else {
          parts.add(label);
        }
      }
      if (parts.isNotEmpty) {
        return parts.join(' - ');
      }
    } else if (pays is List && pays.isNotEmpty) {
      // Single payment method
      final map = _asMap(pays.first);
      final label = _firstNonEmptyString([
            _pick(map, const ['name_ar', 'name', 'pay_method', 'method']),
          ]) ??
          '';
      if (label.isNotEmpty) return label;
    }

    return '';
  }

  /// Resolve the SECONDARY label based on invoice language settings.
  String _altLabel(
    _InvoiceLanguage language, {
    String ar = '',
    required String en,
    String? hi,
    String? ur,
    String? tr,
    String? es,
  }) {
    return language.secLabel(
        ar: ar, en: en, hi: hi, ur: ur, tr: tr, es: es);
  }

  /// Resolve the PRIMARY label based on invoice language settings.
  String _mainLbl(
    _InvoiceLanguage language, {
    required String ar,
    required String en,
    String? hi,
    String? ur,
    String? tr,
    String? es,
  }) {
    return language.mainLabel(
        ar: ar, en: en, hi: hi, ur: ur, tr: tr, es: es);
  }

  String? _normalizeLanguageCode(String? raw) {
    if (raw == null) return null;
    final normalized = raw.trim().toLowerCase();
    if (normalized.isEmpty) return null;

    switch (normalized) {
      case 'ar':
      case 'en':
      case 'hi':
      case 'ur':
      case 'tr':
      case 'es':
        return normalized;
      default:
        return null;
    }
  }

  double _calculatePriceBeforeTax({
    required Map<String, dynamic> invoice,
    required List<Map<String, dynamic>> items,
  }) {
    if (items.isEmpty) {
      return _toDouble(_pick(invoice, const ['price']));
    }

    final firstItem = items.first;
    if (!firstItem.containsKey('total')) {
      return _toDouble(_pick(invoice, const ['price']));
    }

    var total = 0.0;
    for (final item in items) {
      total += _toDouble(_pick(item, const ['price', 'total']));
    }

    return double.parse(total.toStringAsFixed(ApiConstants.digitsNumber));
  }

  bool _truthy(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) return value.trim().isNotEmpty;
    if (value is List) return value.isNotEmpty;
    if (value is Map) return value.isNotEmpty;
    return true;
  }

  String _displayValue(dynamic value) {
    if (value == null) return '';
    if (value is String) return value;
    if (value is num) {
      if (value % 1 == 0) {
        return value.toStringAsFixed(0);
      }
      return value.toStringAsFixed(ApiConstants.digitsNumber);
    }
    return value.toString();
  }

  /// Pick the string for [languageCode] out of a language-keyed translation
  /// map (e.g. `{ar: "...", en: "..."}`). Falls back through English →
  /// Arabic → any non-empty value → `_displayValue` so the caller always
  /// receives a sensible string even when the requested language is missing.
  String _localizedValue(dynamic value, String languageCode) {
    if (value is Map) {
      final code = languageCode.trim().toLowerCase();
      final direct = value[code]?.toString().trim();
      if (direct != null && direct.isNotEmpty) return direct;
      final en = value['en']?.toString().trim();
      if (en != null && en.isNotEmpty) return en;
      final ar = value['ar']?.toString().trim();
      if (ar != null && ar.isNotEmpty) return ar;
      for (final v in value.values) {
        final text = v?.toString().trim();
        if (text != null && text.isNotEmpty) return text;
      }
      return '';
    }
    return _displayValue(value);
  }

  String _extractDate(String rawValue) {
    final trimmed = rawValue.trim();
    if (trimmed.isEmpty) return '';

    final parsed = DateTime.tryParse(trimmed);
    if (parsed != null) {
      return DateFormat('yyyy-MM-dd').format(parsed);
    }

    if (trimmed.contains(' ')) {
      return trimmed.split(' ').first;
    }
    if (trimmed.contains('T')) {
      return trimmed.split('T').first;
    }

    return trimmed;
  }

  String _extractTime(String rawValue) {
    final trimmed = rawValue.trim();
    if (trimmed.isEmpty) return '';

    final parsed = DateTime.tryParse(trimmed);
    if (parsed != null) {
      return DateFormat('HH:mm:ss').format(parsed);
    }

    if (trimmed.contains(' ')) {
      return trimmed.split(' ').last;
    }
    if (trimmed.contains('T')) {
      return trimmed.split('T').last;
    }

    return '';
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return Map<String, dynamic>.from(value);
    }
    if (value is Map) {
      return value.map((key, val) => MapEntry(key.toString(), val));
    }
    return <String, dynamic>{};
  }

  List<Map<String, dynamic>> _asMapList(dynamic value) {
    if (value is! List) return const [];
    return value
        .map((entry) => _asMap(entry))
        .where((entry) => entry.isNotEmpty)
        .toList();
  }

  /// Locate an item's addon list across the same key variants probed by
  /// [extractReceiptAddonsFromItem]. The HTML preview previously read only
  /// `item['addons']`, so payloads that nested the list under
  /// `meal_addons` / `extras` / `meal.addons` rendered the meal without its
  /// addons even though the printer (which uses the extractor) showed them.
  List<Map<String, dynamic>> _extractItemAddonsForRender(
    Map<String, dynamic> item,
  ) {
    List<dynamic>? probe(List<String> keys) {
      for (final source in <Map<String, dynamic>>[item, _asMap(item['meal'])]) {
        if (source.isEmpty) continue;
        for (final key in keys) {
          final value = source[key];
          if (value is List && value.isNotEmpty) return value;
        }
      }
      return null;
    }

    final raw = probe(const [
      'addons',
      'meal_addons',
      'extras',
      'selected_addons',
      'addon_options',
    ]);
    if (raw == null) return const [];

    final translations = probe(const [
      'addons_translations',
      'meal_addons_translations',
      'extras_translations',
    ]);

    final result = <Map<String, dynamic>>[];
    for (var i = 0; i < raw.length; i++) {
      final entry = raw[i];
      if (entry is Map) {
        final m = _asMap(entry);
        if (translations != null && i < translations.length) {
          final t = _asMap(translations[i]);
          if (t.isNotEmpty) {
            m.putIfAbsent('attribute', () => t['attribute'] ?? t);
            m.putIfAbsent('option', () => t['option'] ?? t);
          }
        }
        if (m.isNotEmpty) result.add(m);
      } else if (entry is String) {
        final display = entry.trim();
        if (display.isEmpty) continue;
        // Saved-invoice endpoint sometimes returns addons as plain strings
        // ("Cooking type - Medium"). Synthesize the map shape the renderer
        // expects so the addon still surfaces in the preview.
        result.add(<String, dynamic>{
          'attribute': display,
          'option': '',
          'total': '',
        });
      }
    }
    return result;
  }

  dynamic _pick(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value != null) return value;
    }
    return null;
  }

  dynamic _pickPath(Map<String, dynamic> map, String path) {
    dynamic current = map;
    for (final segment in path.split('.')) {
      if (current is Map && current.containsKey(segment)) {
        current = current[segment];
      } else {
        return null;
      }
    }
    return current;
  }

  String? _firstNonEmptyString(List<dynamic> values) {
    for (final value in values) {
      final text = value?.toString().trim();
      if (text != null && text.isNotEmpty && text.toLowerCase() != 'null') {
        return text;
      }
    }
    return null;
  }

  String? _firstNonEmptyNonZeroString(List<dynamic> values) {
    for (final value in values) {
      final text = value?.toString().trim();
      if (text == null || text.isEmpty || text.toLowerCase() == 'null') {
        continue;
      }

      final normalized = text.startsWith('#') ? text.substring(1) : text;
      final parsed = int.tryParse(normalized);
      if (parsed != null && parsed == 0) {
        continue;
      }

      return text;
    }
    return null;
  }

  double _toDouble(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    final text = value.toString().trim();
    if (text.isEmpty) return 0;
    return double.tryParse(text.replaceAll(',', '.')) ?? 0;
  }

  int _normalizePaperWidthMm(dynamic value) {
    return normalizePaperWidthMm(value);
  }

  String _escapeHtml(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
  }
}
