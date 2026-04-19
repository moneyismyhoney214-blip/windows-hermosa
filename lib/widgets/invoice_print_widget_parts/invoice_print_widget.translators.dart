// ignore_for_file: unused_element, unused_element_parameter, dead_code
part of '../invoice_print_widget.dart';

extension InvoicePrintWidgetTranslators on InvoicePrintWidget {
  String _getOrderTypeArabic(String type) {
    final normalizedType = type.toLowerCase().trim();
    switch (normalizedType) {
      case 'restaurant_internal':
        return _ml(ar: 'طلب داخلي', en: 'Dine In', hi: 'डाइन इन', ur: 'اندرونی', es: 'Comer Aquí', tr: 'İçeride');
      case 'restaurant_pickup':
      case 'restaurant_takeaway':
        return _ml(ar: 'طلب خارجي', en: 'Takeaway', hi: 'टेकअवे', ur: 'ٹیک اوے', es: 'Para Llevar', tr: 'Paket');
      case 'restaurant_delivery':
        return _ml(ar: 'توصيل', en: 'Delivery', hi: 'डिलीवरी', ur: 'ڈیلیوری', es: 'Entrega', tr: 'Teslimat');
      case 'restaurant_parking':
      case 'cars':
      case 'car':
        return _ml(ar: 'سيارات', en: 'Drive-through', hi: 'ड्राइव-थ्रू', ur: 'ڈرائیو تھرو', es: 'Auto-servicio', tr: 'Araç Servisi');
      case 'services':
      case 'service':
        return _ml(ar: 'محلي', en: 'Local', hi: 'स्थानीय', ur: 'مقامی', es: 'Local', tr: 'Yerel');
      case 'talabat_delivery':
        return _ml(ar: 'طلبات (توصيل)', en: 'Talabat (Delivery)', hi: 'तलबात (डिलीवरी)', ur: 'طلبات (ڈیلیوری)', es: 'Talabat (Entrega)', tr: 'Talabat (Teslimat)');
      case 'talabat_pickup':
        return _ml(ar: 'طلبات (استلام)', en: 'Talabat (Pickup)', hi: 'तलबात (पिकअप)', ur: 'طلبات (پک اپ)', es: 'Talabat (Recogida)', tr: 'Talabat (Teslim Alma)');
      case 'hungerstation_delivery':
      case 'hunger_station_delivery':
        return _ml(ar: 'هنقر ستيشن (توصيل)', en: 'HungerStation (Delivery)', hi: 'हंगरस्टेशन (डिलीवरी)', ur: 'ہنگر سٹیشن (ڈیلیوری)', es: 'HungerStation (Entrega)', tr: 'HungerStation (Teslimat)');
      case 'hungerstation_pickup':
      case 'hunger_station_pickup':
        return _ml(ar: 'هنقر ستيشن (استلام)', en: 'HungerStation (Pickup)', hi: 'हंगरस्टेशन (पिकअप)', ur: 'ہنگر سٹیشن (پک اپ)', es: 'HungerStation (Recogida)', tr: 'HungerStation (Teslim Alma)');
      case 'jahez_delivery':
      case 'gahez_delivery':
        return _ml(ar: 'جاهز (توصيل)', en: 'Jahez (Delivery)', hi: 'जाहेज़ (डिलीवरी)', ur: 'جاہز (ڈیلیوری)', es: 'Jahez (Entrega)', tr: 'Jahez (Teslimat)');
      case 'jahez_pickup':
      case 'gahez_pickup':
        return _ml(ar: 'جاهز (استلام)', en: 'Jahez (Pickup)', hi: 'जाहेज़ (पिकअप)', ur: 'جاہز (پک اپ)', es: 'Jahez (Recogida)', tr: 'Jahez (Teslim Alma)');
      case 'payment':
        return _ml(ar: 'دفع نقدي', en: 'Cash Payment', hi: 'नकद भुगतान', ur: 'نقد ادائیگی', es: 'Pago en Efectivo', tr: 'Nakit Ödeme');
      case 'postpaid':
      case 'pay_later':
        return _ml(ar: 'دفع لاحقاً', en: 'Pay Later', hi: 'बाद में भुगतान', ur: 'بعد میں ادائیگی', es: 'Pagar Después', tr: 'Sonra Öde');
      default:
        // Handle compound types like "services (هنقر ستيشن توصيل)"
        if (type.contains('هنقر') || type.toLowerCase().contains('hunger')) {
          if (type.contains('توصيل') || type.toLowerCase().contains('delivery')) {
            return _ml(ar: 'هنقر ستيشن (توصيل)', en: 'HungerStation (Delivery)', hi: 'हंगरस्टेशन (डिलीवरी)', ur: 'ہنگر سٹیشن (ڈیلیوری)', es: 'HungerStation (Entrega)', tr: 'HungerStation (Teslimat)');
          }
          if (type.contains('استلام') || type.toLowerCase().contains('pickup')) {
            return _ml(ar: 'هنقر ستيشن (استلام)', en: 'HungerStation (Pickup)', hi: 'हंगरस्टेशन (पिكअप)', ur: 'ہنگر سٹیشن (پک اپ)', es: 'HungerStation (Recogida)', tr: 'HungerStation (Teslim Alma)');
          }
        }
        if (type.contains('طلبات') || type.toLowerCase().contains('talabat')) {
          if (type.contains('توصيل') || type.toLowerCase().contains('delivery')) {
            return _ml(ar: 'طلبات (توصيل)', en: 'Talabat (Delivery)', hi: 'तलबात (डिलीवरी)', ur: 'طلبات (ڈیلیوری)', es: 'Talabat (Entrega)', tr: 'Talabat (Teslimat)');
          }
          if (type.contains('استلام') || type.toLowerCase().contains('pickup')) {
            return _ml(ar: 'طلبات (استلام)', en: 'Talabat (Pickup)', hi: 'तलबात (पिकअप)', ur: 'طلبات (پک اپ)', es: 'Talabat (Recogida)', tr: 'Talabat (Teslim Alma)');
          }
        }
        if (type.contains('جاهز') || type.toLowerCase().contains('jahez') || type.toLowerCase().contains('gahez')) {
          if (type.contains('توصيل') || type.toLowerCase().contains('delivery')) {
            return _ml(ar: 'جاهز (توصيل)', en: 'Jahez (Delivery)', hi: 'जाहेज़ (डिलीवरी)', ur: 'جاہز (ڈیلیوری)', es: 'Jahez (Entrega)', tr: 'Jahez (Teslimat)');
          }
          if (type.contains('استلام') || type.toLowerCase().contains('pickup')) {
            return _ml(ar: 'جاهز (استلام)', en: 'Jahez (Pickup)', hi: 'जاहेज़ (पिकअप)', ur: 'جاہز (پک اپ)', es: 'Jahez (Recogida)', tr: 'Jahez (Teslim Alma)');
          }
        }
        return type;
    }
  }

  String _translateClientName(String name) {
    final normalized = name.trim().toLowerCase();
    if (normalized == 'عميل عام' || normalized == 'general customer' || normalized == 'walk-in' || normalized == 'walk in') {
      return _ml(ar: 'عميل عام', en: 'General Customer', hi: 'सामान्य ग्राहक', ur: 'عام گاہک', es: 'Cliente general', tr: 'Genel Müşteri');
    }
    return name;
  }

  /// Translate currency symbol based on invoice language.
  /// Arabic currencies stay as-is for Arabic, use ISO code for other languages.
  String _translateCurrency(String currency) {
    final trimmed = currency.trim();
    // Map common Arabic currency symbols to ISO codes
    const arabicToIso = {
      'ر.س': 'SAR',
      'ريال': 'SAR',
      'ر.ي': 'YER',
      'د.ك': 'KWD',
      'د.إ': 'AED',
      'ر.ع': 'OMR',
      'ر.ق': 'QAR',
      'د.ب': 'BHD',
      'ج.م': 'EGP',
      'د.ج': 'DZD',
      'د.ل': 'LYD',
      'د.ت': 'TND',
      'د.م': 'MAD',
      'ل.ل': 'LBP',
      'ل.س': 'SYP',
      'د.ع': 'IQD',
      'ج.س': 'SDG',
    };
    if (primaryLang == 'ar') return trimmed;
    return arabicToIso[trimmed] ?? trimmed;
  }

  /// Translate payment method name based on invoice language.
  String _translatePayMethod(String method) {
    final normalized = method.trim().toLowerCase();
    switch (normalized) {
      case 'cash':
      case 'نقدي':
      case 'نقد':
      case 'كاش':
      case 'دفع':
      case 'دفع نقدي':
        return _ml(ar: 'نقدي', en: 'Cash', hi: 'नकद', ur: 'نقد', es: 'Efectivo', tr: 'Nakit');
      case 'card':
      case 'بطاقة':
      case 'credit_card':
      case 'visa':
      case 'فيزا':
      case 'ماستر':
      case 'ماستر كارد':
        return _ml(ar: 'بطاقة', en: 'Card', hi: 'कार्ड', ur: 'کارڈ', es: 'Tarjeta', tr: 'Kart');
      case 'mada':
      case 'مدى':
        return _ml(ar: 'مدى', en: 'Mada', hi: 'मदा', ur: 'مدی', es: 'Mada', tr: 'Mada');
      case 'benefit':
      case 'benefit_pay':
      case 'benefit pay':
      case 'بينيفت':
      case 'بينيفت باي':
        return _ml(ar: 'بينيفت', en: 'Benefit Pay', hi: 'बेनिफिट पे', ur: 'بینیفٹ پے', es: 'Benefit Pay', tr: 'Benefit Pay');
      case 'stc':
      case 'stc_pay':
      case 'stc pay':
      case 'اس تي سي':
      case 'اس تي سي باي':
        return 'STC Pay';
      case 'bank_transfer':
      case 'bank':
      case 'bank transfer':
      case 'تحويل بنكي':
      case 'تحويل بنكى':
        return _ml(ar: 'تحويل بنكي', en: 'Bank Transfer', hi: 'बैंक ट्रांसफर', ur: 'بینک ٹرانسفر', es: 'Transferencia Bancaria', tr: 'Banka Transferi');
      case 'wallet':
      case 'محفظة':
      case 'المحفظة':
      case 'المحفظة الالكترونية':
      case 'المحفظة الإلكترونية':
        return _ml(ar: 'محفظة', en: 'Wallet', hi: 'वॉलेट', ur: 'والیٹ', es: 'Billetera', tr: 'Cüzdan');
      case 'cheque':
      case 'check':
      case 'شيك':
        return _ml(ar: 'شيك', en: 'Cheque', hi: 'चेक', ur: 'چیک', es: 'Cheque', tr: 'Çek');
      case 'petty_cash':
      case 'petty cash':
      case 'بيتي كاش':
        return _ml(ar: 'بيتي كاش', en: 'Petty Cash', hi: 'पेटी कैश', ur: 'پیٹی کیش', es: 'Caja Chica', tr: 'Küçük Kasa');
      case 'pay_later':
      case 'pay later':
      case 'postpaid':
      case 'deferred':
      case 'دفع لاحقاً':
      case 'الدفع بالآجل':
      case 'الدفع بالاجل':
        return _ml(ar: 'الدفع بالآجل', en: 'Pay Later', hi: 'बाद में भुगतान', ur: 'بعد میں ادائیگی', es: 'Pagar Después', tr: 'Sonra Öde');
      case 'tabby':
      case 'تابي':
        return 'Tabby';
      case 'tamara':
      case 'تمارا':
        return 'Tamara';
      case 'keeta':
      case 'كيتا':
        return 'Keeta';
      case 'my_fatoorah':
      case 'myfatoorah':
      case 'my fatoorah':
      case 'ماي فاتورة':
      case 'ماي فاتوره':
        return _ml(ar: 'ماي فاتورة', en: 'MyFatoorah', hi: 'माई फतूरा', ur: 'مائی فتوره', es: 'MyFatoorah', tr: 'MyFatoorah');
      case 'jahez':
      case 'جاهز':
        return _ml(ar: 'جاهز', en: 'Jahez', hi: 'जाहेज़', ur: 'جاہز', es: 'Jahez', tr: 'Jahez');
      case 'talabat':
      case 'طلبات':
        return _ml(ar: 'طلبات', en: 'Talabat', hi: 'तलबात', ur: 'طلبات', es: 'Talabat', tr: 'Talabat');
      default:
        return method;
    }
  }
}
