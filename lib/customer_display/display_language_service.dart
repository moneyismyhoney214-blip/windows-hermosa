class DisplayLanguageService {
  static const Set<String> _supportedLanguages = <String>{
    'ar',
    'en',
    'es',
    'hi',
    'ur',
    'tr',
  };

  static String normalizeLanguageCode(String? languageCode) {
    final normalized = languageCode?.trim().toLowerCase() ?? '';
    if (_supportedLanguages.contains(normalized)) {
      return normalized;
    }
    return 'en';
  }

  static bool isRtl(String? languageCode) {
    final code = normalizeLanguageCode(languageCode);
    return code == 'ar' || code == 'ur';
  }

  static String t(
    String key, {
    String? languageCode,
    Map<String, dynamic>? args,
  }) {
    final code = normalizeLanguageCode(languageCode);
    final translations = _effectiveTranslations(code);
    final text = translations[key] ?? key;
    if (args == null || args.isEmpty) {
      return text;
    }
    var result = text;
    args.forEach((argKey, value) {
      result = result.replaceAll('{$argKey}', value.toString());
    });
    return result;
  }

  static Map<String, String> _effectiveTranslations(String code) {
    // Priority: Selected Code > English > Arabic
    if (code == 'ar') {
      return Map<String, String>.from(_ar);
    }
    if (code == 'en') {
      return <String, String>{..._ar, ..._en};
    }
    // For other languages (tr, es, etc.), layer them: AR < EN < Target
    return <String, String>{..._ar, ..._en, ..._mapByLanguage(code)};
  }

  static Map<String, String> _mapByLanguage(String code) {
    switch (code) {
      case 'es':
        return _es;
      case 'hi':
        return _hi;
      case 'ur':
        return _ur;
      case 'tr':
        return _tr;
      case 'en':
        return _en;
      case 'ar':
      default:
        return _ar;
    }
  }

  static const Map<String, String> _ar = <String, String>{
    // Connection Screen
    'conn_ready_title': 'جاهز للاتصال',
    'conn_mode_auto': 'الوضع يتحدد تلقائياً من تطبيق الكاشير',
    'conn_network_error': 'تعذر اكتشاف عنوان الشبكة',
    'conn_retry': 'إعادة المحاولة',
    'conn_connected': 'متصل ({count} كاشير)',
    'conn_waiting': 'في انتظار اتصال الكاشير...',
    'conn_show_qr': 'عرض QR للربط السريع',
    'conn_web_note': 'على المتصفح: أدخل IP يدويًا في الكاشير.',
    
    // CDS Screen
    'cds_tab_order': 'الطلب',
    'cds_tab_inventory': 'المخزون',
    'cds_search_meal': 'بحث عن وجبة...',
    'cds_all_categories': 'كل الفئات',
    'cds_no_meals': 'لا توجد وجبات',
    'cds_meal_unavailable': 'الوجبة "{name}" نفذت حالياً',
    'cds_meal_available': 'الوجبة "{name}" متاحة',
    'cds_status_unavailable': 'الحالة: نفذت',
    'cds_status_available': 'الحالة: متاح',
    'cds_welcome_title': 'أهلاً بك في متجرنا',
    'cds_welcome_waiting': '..بانتظار تسجيل طلبك الجديد',
    'cds_current_order_title': 'تفاصيل\nطلبك الحالي',
    'cds_current_order_subtitle':
        'يمكنك مراجعة المنتجات والأسعار من القائمة الجانبية.',
    'cds_cart_list': 'قائمة المشتريات',
    'cds_order_no': '{order}',
    'cds_promo': 'الترويج: {code}',
    'cds_discount': 'الخصم: -{amount}',
    'cds_before_discount': 'قبل الخصم: {amount}',
    'cds_after_discount': 'بعد الخصم: {amount}',
    'cds_subtotal': 'المجموع الفرعي',
    'cds_tax': 'الضريبة ({rate}%)',
    'cds_total_final': 'الإجمالي النهائي',
    'cds_cash_float': 'الرصيد النقدي',
    'cds_opening': 'الافتتاح: {amount}',
    'cds_transactions': 'المعاملات: {amount}',
    'cds_current': 'الحالي: {amount}',
    'currency_default': 'ر.س',
    'currency_suffix': '{value} {currency}',
    'conn_reconnecting': 'جارٍ إعادة الاتصال...',
    'conn_reconnect_in': 'إعادة المحاولة خلال {seconds} ث',

    // NearPay Payment Screen
    'nearpay_payment': 'دفع NearPay',
    'warning_title': 'تحذير',
    'confirm_cancel_payment': 'هل أنت متأكد من إلغاء عملية الدفع؟',
    'no': 'لا',
    'yes': 'نعم',
  };

  static const Map<String, String> _en = <String, String>{
    // Connection Screen
    'conn_ready_title': 'Ready to Connect',
    'conn_mode_auto': 'Mode is automatically set from cashier app',
    'conn_network_error': 'Unable to detect network address',
    'conn_retry': 'Retry',
    'conn_connected': 'Connected ({count} cashier)',
    'conn_waiting': 'Waiting for cashier connection...',
    'conn_reconnecting': 'Reconnecting...',
    'conn_reconnect_in': 'Retrying in {seconds}s',
    'conn_show_qr': 'Show QR for quick link',
    'conn_web_note': 'On browser: Enter IP manually in cashier.',
    
    // CDS Screen
    'cds_tab_order': 'Order',
    'cds_tab_inventory': 'Inventory',
    'cds_search_meal': 'Search meal...',
    'cds_all_categories': 'All categories',
    'cds_no_meals': 'No meals found',
    'cds_meal_unavailable': 'Meal "{name}" is unavailable now',
    'cds_meal_available': 'Meal "{name}" is available',
    'cds_status_unavailable': 'Status: Unavailable',
    'cds_status_available': 'Status: Available',
    'cds_welcome_title': 'Welcome to our store',
    'cds_welcome_waiting': 'Waiting for your new order..',
    'cds_current_order_title': 'Current\nOrder Details',
    'cds_current_order_subtitle':
        'You can review products and prices from the side panel.',
    'cds_cart_list': 'Shopping cart',
    'cds_order_no': 'Order {order}',
    'cds_promo': 'Promo: {code}',
    'cds_discount': 'Discount: -{amount}',
    'cds_before_discount': 'Before discount: {amount}',
    'cds_after_discount': 'After discount: {amount}',
    'cds_subtotal': 'Subtotal',
    'cds_tax': 'Tax ({rate}%)',
    'cds_total_final': 'Final total',
    'cds_cash_float': 'Cash Float',
    'cds_opening': 'Opening: {amount}',
    'cds_transactions': 'Transactions: {amount}',
    'cds_current': 'Current: {amount}',
    'currency_default': 'SAR',
    'currency_suffix': '{value} {currency}',

    // NearPay Payment Screen
    'nearpay_payment': 'NearPay Payment',
    'warning_title': 'Warning',
    'confirm_cancel_payment': 'Are you sure you want to cancel the payment?',
    'no': 'No',
    'yes': 'Yes',
  };

  static const Map<String, String> _es = <String, String>{
    // Connection Screen
    'conn_ready_title': 'Listo para conectar',
    'conn_mode_auto': 'El modo se establece automáticamente desde la caja',
    'conn_network_error': 'No se pudo detectar la dirección de red',
    'conn_retry': 'Reintentar',
    'conn_connected': 'Conectado ({count} caja)',
    'conn_waiting': 'Esperando conexión de caja...',
    'conn_show_qr': 'Mostrar QR para enlace rápido',
    'conn_web_note': 'En navegador: Ingrese IP manualmente en caja.',
    
    // CDS Screen
    'cds_tab_order': 'Pedido',
    'cds_tab_inventory': 'Inventario',
    'cds_search_meal': 'Buscar comida...',
    'cds_all_categories': 'Todas las categorías',
    'cds_no_meals': 'No hay comidas',
    'cds_meal_unavailable': 'La comida "{name}" no está disponible',
    'cds_meal_available': 'La comida "{name}" está disponible',
    'cds_status_unavailable': 'Estado: No disponible',
    'cds_status_available': 'Estado: Disponible',
    'cds_welcome_title': 'Bienvenido a nuestra tienda',
    'cds_welcome_waiting': 'Esperando tu nuevo pedido..',
    'cds_current_order_title': 'Detalles\ndel pedido actual',
    'cds_current_order_subtitle':
        'Puedes revisar productos y precios desde el panel lateral.',
    'cds_cart_list': 'Carrito',
    'cds_order_no': 'Pedido {order}',
    'cds_promo': 'Cupón: {code}',
    'cds_discount': 'Descuento: -{amount}',
    'cds_before_discount': 'Antes del descuento: {amount}',
    'cds_after_discount': 'Después del descuento: {amount}',
    'cds_subtotal': 'Subtotal',
    'cds_tax': 'Impuesto ({rate}%)',
    'cds_total_final': 'Total final',
    'cds_cash_float': 'Caja inicial',
    'cds_opening': 'Apertura: {amount}',
    'cds_transactions': 'Movimientos: {amount}',
    'cds_current': 'Actual: {amount}',
    'currency_default': 'SAR',
    'currency_suffix': '{value} {currency}',

    // NearPay Payment Screen
    'nearpay_payment': 'Pago NearPay',
    'warning_title': 'Advertencia',
    'confirm_cancel_payment': '¿Estás seguro de cancelar el pago?',
    'no': 'No',
    'yes': 'Sí',
  };

  static const Map<String, String> _hi = <String, String>{
    // Connection Screen
    'conn_ready_title': 'कनेक्ट करने के लिए तैयार',
    'conn_mode_auto': 'मोड कैशियर ऐप से स्वचालित रूप से सेट होता है',
    'conn_network_error': 'नेटवर्क पता पता लगाने में असमर्थ',
    'conn_retry': 'पुनः प्रयास करें',
    'conn_connected': 'कनेक्टेड ({count} कैशियर)',
    'conn_waiting': 'कैशियर कनेक्शन की प्रतीक्षा में...',
    'conn_show_qr': 'त्वरित लिंक के लिए QR दिखाएं',
    'conn_web_note': 'ब्राउज़र पर: कैशियर में IP मैन्युअल रूप से दर्ज करें।',
    
    // CDS Screen
    'cds_tab_order': 'ऑर्डर',
    'cds_tab_inventory': 'इन्वेंटरी',
    'cds_search_meal': 'भोजन खोजें...',
    'cds_all_categories': 'सभी श्रेणियाँ',
    'cds_no_meals': 'कोई भोजन नहीं',
    'cds_meal_unavailable': '"{name}" उपलब्ध नहीं है',
    'cds_meal_available': '"{name}" उपलब्ध है',
    'cds_status_unavailable': 'स्थिति: उपलब्ध नहीं',
    'cds_status_available': 'स्थिति: उपलब्ध',
    'cds_welcome_title': 'हमारे स्टोर में आपका स्वागत है',
    'cds_welcome_waiting': 'आपके नए ऑर्डर की प्रतीक्षा है..',
    'cds_current_order_title': 'आपके मौजूदा\nऑर्डर का विवरण',
    'cds_current_order_subtitle':
        'आप साइड पैनल से उत्पाद और कीमतें देख सकते हैं।',
    'cds_cart_list': 'कार्ट सूची',
    'cds_order_no': 'ऑर्डर {order}',
    'cds_promo': 'कूपन: {code}',
    'cds_discount': 'छूट: -{amount}',
    'cds_before_discount': 'छूट से पहले: {amount}',
    'cds_after_discount': 'छूट के बाद: {amount}',
    'cds_subtotal': 'उप-योग',
    'cds_tax': 'कर ({rate}%)',
    'cds_total_final': 'अंतिम कुल',
    'cds_cash_float': 'कैश फ्लोट',
    'cds_opening': 'ओपनिंग: {amount}',
    'cds_transactions': 'लेनदेन: {amount}',
    'cds_current': 'वर्तमान: {amount}',
    'currency_default': 'SAR',
    'currency_suffix': '{value} {currency}',

    // NearPay Payment Screen
    'nearpay_payment': 'NearPay भुगतान',
    'warning_title': 'चेतावनी',
    'confirm_cancel_payment': 'क्या आप भुगतान रद्द करना चाहते हैं?',
    'no': 'नहीं',
    'yes': 'हाँ',
  };

  static const Map<String, String> _ur = <String, String>{
    // Connection Screen
    'conn_ready_title': 'منسلک ہونے کے لیے تیار',
    'conn_mode_auto': 'موڈ کیشیئر ایپ سے خودکار طور پر سیٹ ہوتا ہے',
    'conn_network_error': 'نیٹ ورک ایڈریس کا پتہ لگانے میں ناکام',
    'conn_retry': 'دوبارہ کوشش کریں',
    'conn_connected': 'منسلک ({count} کیشیئر)',
    'conn_waiting': 'کیشیئر کنیکشن کا انتظار ہے...',
    'conn_show_qr': 'فوری لنک کے لیے QR دکھائیں',
    'conn_web_note': 'براؤزر پر: کیشیئر میں IP دستی طور پر درج کریں۔',
    
    // CDS Screen
    'cds_tab_order': 'آرڈر',
    'cds_tab_inventory': 'اسٹاک',
    'cds_search_meal': 'کھانا تلاش کریں...',
    'cds_all_categories': 'تمام زمرے',
    'cds_no_meals': 'کوئی آئٹم نہیں',
    'cds_meal_unavailable': '"{name}" دستیاب نہیں ہے',
    'cds_meal_available': '"{name}" دستیاب ہے',
    'cds_status_unavailable': 'حالت: دستیاب نہیں',
    'cds_status_available': 'حالت: دستیاب',
    'cds_welcome_title': 'ہماری دکان میں خوش آمدید',
    'cds_welcome_waiting': 'آپ کے نئے آرڈر کا انتظار ہے..',
    'cds_current_order_title': 'آپ کے موجودہ\nآرڈر کی تفصیل',
    'cds_current_order_subtitle':
        'آپ سائیڈ پینل سے اشیاء اور قیمتیں دیکھ سکتے ہیں۔',
    'cds_cart_list': 'خریداری فہرست',
    'cds_order_no': 'آرڈر {order}',
    'cds_promo': 'کوپن: {code}',
    'cds_discount': 'رعایت: -{amount}',
    'cds_before_discount': 'رعایت سے پہلے: {amount}',
    'cds_after_discount': 'رعایت کے بعد: {amount}',
    'cds_subtotal': 'جزوی کل',
    'cds_tax': 'ٹیکس ({rate}%)',
    'cds_total_final': 'حتمی کل',
    'cds_cash_float': 'کیش فلوٹ',
    'cds_opening': 'اوپننگ: {amount}',
    'cds_transactions': 'ٹرانزیکشنز: {amount}',
    'cds_current': 'موجودہ: {amount}',
    'currency_default': 'SAR',
    'currency_suffix': '{value} {currency}',

    // NearPay Payment Screen
    'nearpay_payment': 'NearPay ادائیگی',
    'warning_title': 'انتباہ',
    'confirm_cancel_payment': 'کیا آپ واقعی ادائیگی منسوخ کرنا چاہتے ہیں؟',
    'no': 'نہیں',
    'yes': 'ہاں',
  };

  static const Map<String, String> _tr = <String, String>{
    // Connection Screen
    'conn_ready_title': 'Bağlanmaya hazır',
    'conn_mode_auto': 'Mod kasa uygulamasından otomatik olarak ayarlanır',
    'conn_network_error': 'Ağ adresi tespit edilemedi',
    'conn_retry': 'Tekrar dene',
    'conn_connected': 'Bağlı ({count} kasa)',
    'conn_waiting': 'Kasa bağlantısı bekleniyor...',
    'conn_show_qr': 'Hızlı bağlantı için QR göster',
    'conn_web_note': 'Tarayıcıda: Kasaya IP\'yi manuel olarak girin.',
    
    // CDS Screen
    'cds_tab_order': 'Siparis',
    'cds_tab_inventory': 'Stok',
    'cds_search_meal': 'Yemek ara...',
    'cds_all_categories': 'Tum kategoriler',
    'cds_no_meals': 'Yemek yok',
    'cds_meal_unavailable': '"{name}" su an tukendi',
    'cds_meal_available': '"{name}" su an mevcut',
    'cds_status_unavailable': 'Durum: Tukenmis',
    'cds_status_available': 'Durum: Mevcut',
    'cds_welcome_title': 'Magazamiza hos geldiniz',
    'cds_welcome_waiting': 'Yeni siparisiniz bekleniyor..',
    'cds_current_order_title': 'Mevcut\nSiparis Detayi',
    'cds_current_order_subtitle':
        'Urunleri ve fiyatlari yan panelden inceleyebilirsiniz.',
    'cds_cart_list': 'Alisveris listesi',
    'cds_order_no': 'Siparis {order}',
    'cds_promo': 'Kupon: {code}',
    'cds_discount': 'Indirim: -{amount}',
    'cds_before_discount': 'Indirim oncesi: {amount}',
    'cds_after_discount': 'Indirim sonrasi: {amount}',
    'cds_subtotal': 'Ara toplam',
    'cds_tax': 'Vergi (%{rate})',
    'cds_total_final': 'Genel toplam',
    'cds_cash_float': 'Nakit kasasi',
    'cds_opening': 'Acilis: {amount}',
    'cds_transactions': 'Hareketler: {amount}',
    'cds_current': 'Guncel: {amount}',
    'currency_default': 'SAR',
    'currency_suffix': '{value} {currency}',

    // NearPay Payment Screen
    'nearpay_payment': 'NearPay Odeme',
    'warning_title': 'Uyari',
    'confirm_cancel_payment': 'Odemeyi iptal etmek istediginizden emin misiniz?',
    'no': 'Hayir',
    'yes': 'Evet',
  };
}
