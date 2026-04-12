import 'package:hermosa_pos/utils/paper_width_utils.dart';

import '../models/receipt_data.dart';
import '../services/api/api_constants.dart';

/// قالب HTML للفاتورة الضريبية
/// يستخدم لطباعة الفاتورة عبر WebView أو الطابعة
class InvoiceHtmlTemplate {
  /// إنشاء HTML للفاتورة مع البيانات الديناميكية
  static String generateInvoiceHtml({
    required OrderReceiptData data,
    String? orderType,
    String? tableNumber,
    String? carNumber,
    String? dailyOrderNumber,
    String? carBrand,
    String? carModel,
    String? carPlateNumber,
    String? carYear,
    String? clientName,
    String? clientPhone,
    String? clientTaxNumber,
    String? commercialRegisterNumber,
    String? returnPolicy,
    int paperWidthMm = 80,
  }) {
    final widthCss = paperWidthCss(paperWidthMm);
    // تحويل نوع الطلب للعربية
    String orderTypeAr = _getOrderTypeArabic(orderType ?? '');
    final hasLogo = data.sellerLogo != null && data.sellerLogo!.isNotEmpty;
    final resolvedDailyOrderNumber =
        (dailyOrderNumber != null && dailyOrderNumber.trim().isNotEmpty)
            ? dailyOrderNumber.trim()
            : (data.orderNumber != null && data.orderNumber!.trim().isNotEmpty)
                ? data.orderNumber!.trim()
                : null;
    final resolvedInvoiceNumber = data.invoiceNumber.replaceAll('#', '').trim();

    // بناء قائمة الأصناف
    String itemsHtml = '';
    for (var item in data.items) {
      String addonsHtml = '';
      if (item.addons != null && item.addons!.isNotEmpty) {
        for (var addon in item.addons!) {
          addonsHtml +=
              '<div class="flex justify-between text-[9px] pl-2" style="font-size: 10px; color: #000000;"><span>${addon.nameAr}</span><span>${addon.price.toStringAsFixed(2)}</span></div>';
        }
      }

      itemsHtml += '''
        <tr>
          <td class="py-1 pr-1">
            <div class="w-full">
              <div class="flex justify-between">
                <p class="font-bold">${item.nameAr}</p>
                <p>${item.unitPrice.toStringAsFixed(2)}</p>
              </div>
              $addonsHtml
            </div>
          </td>
          <td class="text-center py-1 align-top">${item.quantity}</td>
          <td class="text-left py-1 align-top font-mono">${item.total.toStringAsFixed(2)}</td>
        </tr>
      ''';
    }

    // بناء معلومات السيارة إذا كانت موجودة
    String carInfoHtml = '';
    if (carBrand != null ||
        carModel != null ||
        carPlateNumber != null ||
        carYear != null) {
      carInfoHtml = '''
        <div class="mt-2 mb-4">
          <table class="car-info-table w-full border-collapse border border-gray-300 text-xs">
            <thead>
              <tr>
                <th colspan="2" class="border border-gray-300 px-2 py-1 bg-gray-50 text-center font-bold text-sm">
                  معلومات السيارة <br>
                  <span style="font-size: 10px; font-weight: bold;">Car Information</span>
                </th>
              </tr>
            </thead>
            <tbody>
              ${carBrand != null ? '<tr><td class="border border-gray-300 px-2 py-1 font-bold w-1/3 text-sm">الماركة <br><span style="font-size: 10px; font-weight: bold; color: #000000;">Brand</span></td><td class="border border-gray-300 px-2 py-1 text-sm font-bold">$carBrand</td></tr>' : ''}
              ${carModel != null ? '<tr><td class="border border-gray-300 px-2 py-1 font-bold text-sm">الموديل <br><span style="font-size: 10px; font-weight: bold; color: #000000;">Model</span></td><td class="border border-gray-300 px-2 py-1 text-sm font-bold">$carModel</td></tr>' : ''}
              ${carPlateNumber != null ? '<tr><td class="border border-gray-300 px-2 py-1 font-bold text-sm">رقم اللوحة <br><span style="font-size: 10px; font-weight: bold; color: #000000;">Plate Number</span></td><td class="border border-gray-300 px-2 py-1 text-sm font-bold">$carPlateNumber</td></tr>' : ''}
              ${carYear != null ? '<tr><td class="border border-gray-300 px-2 py-1 font-bold text-sm">السنة <br><span style="font-size: 10px; font-weight: bold; color: #000000;">Year</span></td><td class="border border-gray-300 px-2 py-1 text-sm font-bold">$carYear</td></tr>' : ''}
            </tbody>
          </table>
        </div>
      ''';
    }

    // بناء معلومات العميل
    String clientInfoHtml = '';
    if (clientName != null || clientPhone != null || clientTaxNumber != null) {
      clientInfoHtml = '''
        <div class="client-info">
          ${clientName != null ? '<div class="client-info-item"><div class="flex-row"><span class="font-bold">اسم العميل</span><span class="value">$clientName</span></div><span class="label-en">Client Name</span></div>' : ''}
          ${clientPhone != null ? '<div class="client-info-item"><div class="flex-row"><span class="font-bold">جوال العميل</span><span class="value force-ltr">$clientPhone</span></div><span class="label-en">Client Phone</span></div>' : ''}
          ${clientTaxNumber != null ? '<div class="client-info-item"><div class="flex-row"><span class="font-bold">الرقم الضريبي</span><span class="value">$clientTaxNumber</span></div><span class="label-en">Tax number</span></div>' : ''}
        </div>
      ''';
    }

    // حساب الخصم
    double discountAmount =
        data.totalExclVat - (data.totalInclVat - data.vatAmount);
    double totalAfterDiscount = data.totalExclVat - discountAmount;

    return '''
<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
  <meta charset="UTF-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
  <title>فاتورة ضريبية مبسطة</title>
  <link href="https://fonts.googleapis.com/css2?family=Tajawal:wght@400;500;700&display=swap" rel="stylesheet">
  <style>
    @page {size: $widthCss auto;margin: 2mm;}
    * {box-sizing: border-box;}
    body {margin: 0;padding: 8px 0;background: #e5e7eb;color: #111827;font-family: 'Tajawal', Arial, Tahoma, sans-serif;font-size: 14px;line-height: 1.4;-webkit-print-color-adjust: exact;print-color-adjust: exact;font-weight: bold;}
    p {margin: 2px 0;}
    .flex { display: flex; }
    .justify-center { justify-content: center; }
    .justify-between { justify-content: space-between; }
    .items-center { align-items: center; }
    .text-left { text-align: left; }
    .text-right { text-align: right; }
    .text-center { text-align: center; }
    .font-bold { font-weight: 700; }
    .force-ltr { direction: ltr; text-align: left; }
    .whitespace-nowrap { white-space: nowrap; }
    .mt-2 { margin-top: 8px; }
    .mb-4 { margin-bottom: 16px; }
    .my-2 { margin-top: 8px; margin-bottom: 8px; }
    .px-2 { padding-right: 8px; padding-left: 8px; }
    .px-4 { padding-right: 16px; padding-left: 16px; }
    .py-1 { padding-top: 4px; padding-bottom: 4px; }
    .pb-2 { padding-bottom: 8px; }
    .w-full { width: 100%; }
    .w-24 { width: 96px; }
    .h-24 { height: 96px; }
    .w-1\/3 { width: 33.333%; }
    .w-7\/12 { width: 58.333%; }
    .object-contain { object-fit: contain; }
    .border { border: 1px solid; }
    .border-2 { border: 2px solid #000; }
    .border-black { border-color: #000; }
    .border-gray-300 { border-color: #d1d5db; }
    .border-collapse { border-collapse: collapse; }
    .bg-gray-50 { background-color: #f9fafb; }
    .text-xs { font-size: 12px; }
    .text-sm { font-size: 14px; }
    .text-lg { font-size: 18px; }
    .wrapper {display: flex;justify-content: center;}
    .bill-container {width: $widthCss;max-width: calc(100vw - 12px);background: #fff;padding: 8px;box-sizing: border-box;box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1);}
    .seller-info { text-align: center; }
    .logo-container { margin-bottom: 12px; }
    .logo-container img, footer img {max-width: 96px;max-height: 96px;object-fit: contain;}
    .logo-placeholder { width: 110px; height: 110px; border: 2px dashed #111827; display:flex; align-items:center; justify-content:center; font-size:12px; font-weight:700; color:#111827; }
    .info { margin-bottom: 8px; }
    .title { margin: 0; font-size: 18px; font-weight: 700; }
    .mobile { direction: ltr; }
    .info-bottom { margin-bottom: 8px; }
    .info-bottom-item {margin-bottom: 6px;border-bottom: 1px dashed #d1d5db;padding-bottom: 4px;text-align: right;display: flex;flex-direction: column;}
    .info-bottom-item .label-en {font-size: 10px;color: #000000;margin-top: -2px;font-weight: bold;}
    .info-bottom-item .value {font-weight: bold;}
    .info-bottom-item .flex-row {display: flex;justify-content: space-between;align-items: baseline;}
    .invoice-title {text-align: center;border-bottom: 1px dashed #9ca3af;border-top: 1px dashed #9ca3af;padding: 6px 0;margin: 10px 0;font-weight: 700;background-color: #f9fafb;}
    .client-info { margin-bottom: 8px; text-align: right; }
    .client-info-item {margin-bottom: 6px;border-bottom: 1px dashed #d1d5db;padding-bottom: 4px;}
    .client-info-item .flex-row {display: flex;justify-content: space-between;align-items: baseline;}
    .client-info-item .label-en {font-size: 10px;color: #000000;font-weight: bold;}
    .invoice-items table, .car-info-table, .addons-table {width: 100%;border-collapse: collapse;}
    .invoice-items th, .invoice-items td, .car-info-table th, .car-info-table td, .addons-table td, .addons-table th {border-bottom: 1px dashed #d1d5db;padding: 4px;vertical-align: top;}
    .invoice-items th {border-bottom: 1px solid #000;border-top: 1px solid #000;}
    .addon-size { font-size: 11px; }
    .addon-item { font-size: 11px; font-weight: bold; }
    .invoice-details { margin-bottom: 8px; border-top: 1px solid #000; padding-top: 8px; }
    .invoice-details-item {display: flex;justify-content: space-between;align-items: flex-start;border-bottom: 1px dashed #e5e7eb;padding: 6px 0;}
    .invoice-item-title { width: 52%; text-align: right; }
    .invoice-item-title .label-en { font-size: 10px; color: #000000; font-weight: bold; }
    .currency-area { margin-left: 4px; font-size: 11px; color: #000000; font-weight: bold; }
    .price { font-weight: 700; font-family: monospace; font-size: 14px; }
    footer { text-align: center; margin-top: 16px; }
    footer .invoice-details-item { display: block; text-align: center; }
    @media print {
      @page { size: $widthCss auto; margin: 0; }
      body { background: #fff; padding: 0; margin: 0; }
      .wrapper { justify-content: flex-start; }
      .bill-container { width: $widthCss !important; max-width: $widthCss !important; box-shadow: none; margin: 0; padding: 0; }
      .print-btn { display: none; }
    }
    .print-btn {display: block;width: 200px;margin: 20px auto;padding: 10px;background-color: #2563eb;color: white;text-align: center;border-radius: 8px;text-decoration: none;font-weight: bold;cursor: pointer;border: none;}
    .print-btn:hover { background-color: #1d4ed8; }
  </style>
</head>
<body>
  <button class="print-btn" onclick="window.print()">طباعة الفاتورة (Print)</button>
  <div class="wrapper">
    <div class="bill-container">
      <header>
        <div class="seller-info">
          <div class="info">
            ${hasLogo ? '<div class="logo-container flex justify-center mb-2"><img src="${data.sellerLogo}" alt="Logo" class="w-24 h-24 object-contain"/></div>' : '<div class="logo-container flex justify-center mb-2"><div class="logo-placeholder">مكان الشعار</div></div>'}
            ${data.sellerNameAr.isNotEmpty ? '<p class="title font-bold">${data.sellerNameAr}</p>' : ''}
            ${data.sellerNameEn.isNotEmpty ? '<p>${data.sellerNameEn}</p>' : ''}
            ${data.branchAddress != null && data.branchAddress!.isNotEmpty ? '<p>${data.branchAddress}</p>' : ''}
            ${data.branchMobile != null && data.branchMobile!.isNotEmpty ? '<p class="mobile">${data.branchMobile}</p>' : ''}
          </div>
          <div class="info-bottom">
            ${resolvedDailyOrderNumber != null ? '<div class="flex justify-center my-2"><div class="border border-black px-3 py-1.5 text-center"><div class="text-base font-bold">$resolvedDailyOrderNumber</div></div></div>' : ''}
            ${resolvedInvoiceNumber.isNotEmpty ? '<div class="flex justify-center my-2"><div class="border border-black px-3 py-1.5 text-center"><div class="text-base font-bold">$resolvedInvoiceNumber</div></div></div>' : ''}
            <div class="info-bottom-item">
              <div class="flex-row">
                <span>الكاشير</span>
                <span class="value">${data.sellerNameAr}</span>
              </div>
              <span class="label-en">Cashier</span>
            </div>
            <div class="info-bottom-item">
              <div class="flex-row">
                <span>الرقم الضريبي</span>
                <span class="value">${data.vatNumber}</span>
              </div>
              <span class="label-en">Tax Number</span>
            </div>
            ${commercialRegisterNumber != null ? '<div class="info-bottom-item"><div class="flex-row"><span>رقم السجل التجاري</span><span class="value">$commercialRegisterNumber</span></div><span class="label-en">Commercial Register Number</span></div>' : ''}
            ${data.issueDate != null ? '<div class="info-bottom-item"><div class="flex-row"><span>التاريخ</span><span class="value">${data.issueDate}</span></div><span class="label-en">Date</span></div>' : ''}
            ${data.issueTime != null ? '<div class="info-bottom-item"><div class="flex-row"><span>الوقت</span><span class="value force-ltr">${data.issueTime}</span></div><span class="label-en">Time</span></div>' : ''}
            ${resolvedDailyOrderNumber != null ? '<div class="info-bottom-item"><div class="flex-row"><span>رقم الطلب</span><span class="value force-ltr">$resolvedDailyOrderNumber</span></div><span class="label-en">Order Number</span></div>' : ''}
            ${orderType != null ? '<div class="info-bottom-item"><div class="flex-row"><span>نوع الطلب</span><span class="value">$orderTypeAr</span></div><span class="label-en">Order Type</span></div>' : ''}
            ${tableNumber != null ? '<div class="info-bottom-item"><div class="flex-row"><span>رقم الطاوله</span><span class="value">$tableNumber</span></div><span class="label-en">Table number</span></div>' : ''}
            ${carNumber != null ? '<div class="info-bottom-item"><div class="flex-row"><span>رقم السياره</span><span class="value">$carNumber</span></div><span class="label-en">Car number</span></div>' : ''}
          </div>
        </div>
      </header>
      <section>
        <div class="invoice-title" style="padding: 4px 0; font-size: 13px;">
          <p style="margin: 0;">فاتورة ضريبية مبسطة - Simplified Tax Invoice</p>
        </div>
        $clientInfoHtml
        $carInfoHtml
        <div class="invoice-items">
          <table>
            <thead>
              <tr>
                <th class="text-right font-bold">الصنف<br><span style="font-size: 10px; font-weight: bold;">Item</span></th>
                <th class="text-center font-bold">الكمية<br><span style="font-size: 10px; font-weight: bold;">Qty</span></th>
                <th class="text-left font-bold">الاجمالي<br><span style="font-size: 10px; font-weight: bold;">Total</span></th>
              </tr>
            </thead>
            <tbody>
              $itemsHtml
            </tbody>
          </table>
        </div>
        <div class="invoice-details">
          <div class="invoice-details-item">
            <div class="invoice-item-title">
              <p>الاجمالي قبل الضريبة</p>
              <p class="label-en">Total Before Tax</p>
            </div>
            <div class="flex items-center text-left">
              <p class="price">${data.totalExclVat.toStringAsFixed(2)}</p>
              <div class="currency-area">
                <p>${ApiConstants.currency}</p>
              </div>
            </div>
          </div>
          ${discountAmount > 0 ? '<div class="invoice-details-item"><div class="invoice-item-title"><p>قيمة الخصم</p><p class="label-en">Discount Amount</p></div><div class="flex items-center text-left"><p class="price">${discountAmount.toStringAsFixed(2)}</p><div class="currency-area"><p>${ApiConstants.currency}</p></div></div></div>' : ''}
          ${discountAmount > 0 ? '<div class="invoice-details-item"><div class="invoice-item-title"><p>الاجمالي بعد الخصم</p><p class="label-en">Total After Discount</p></div><div class="flex items-center text-left"><p class="price">${totalAfterDiscount.toStringAsFixed(2)}</p><div class="currency-area"><p>${ApiConstants.currency}</p></div></div></div>' : ''}
          <div class="invoice-details-item">
            <div class="invoice-item-title">
              <p>قيمة الضريبة</p>
              <p class="label-en">Tax Amount</p>
            </div>
            <div class="flex items-center text-left">
              <p class="price">${data.vatAmount.toStringAsFixed(2)}</p>
              <div class="currency-area">
                <p>${ApiConstants.currency}</p>
              </div>
            </div>
          </div>
          <div class="invoice-details-item" style="border-top: 1px solid #000; margin-top: 4px; padding-top: 8px;">
            <div class="invoice-item-title">
              <p class="font-bold" style="font-size: 16px;">الاجمالي بعد الضريبة</p>
              <p class="label-en">Total After Tax</p>
            </div>
            <div class="flex items-center text-left">
              <p class="price" style="font-size: 18px;">${data.totalInclVat.toStringAsFixed(2)}</p>
              <div class="currency-area">
                <p>${ApiConstants.currency}</p>
              </div>
            </div>
          </div>
          ${data.paymentMethod.isNotEmpty ? '<div class="invoice-details-item" style="border-bottom: none;"><div class="invoice-item-title"><p>طرق الدفع</p><p class="label-en">Payment Methods</p></div><div class="text-left w-7/12"><p class="price" style="font-size: 12px;">${data.paymentMethod}</p></div></div>' : ''}
        </div>
      </section>
      <footer>
        ${data.qrCodeBase64.isNotEmpty ? '<div class="flex justify-center mb-4"><img src="https://api.qrserver.com/v1/create-qr-code/?size=150x150&data=${Uri.encodeComponent(data.qrCodeBase64)}" alt="QR Code"/></div>' : ''}
        ${returnPolicy != null && returnPolicy.isNotEmpty ? '<div style="font-size: 10px; border-bottom: 1px dashed #d1d5db; padding-bottom: 8px; margin-bottom: 8px;"><p class="font-bold" style="margin-bottom: 4px;">سياسة الاسترجاع والاستبدال</p><div style="white-space: pre-wrap;">$returnPolicy</div></div>' : ''}
        <div style="font-size: 10px; margin-top: 12px;">
          <p class="font-bold">شكرا لثقتكم بنا</p>
          <p style="font-size: 10px; color: #000000;">Thank you for trusting us</p>
          <p class="font-bold mt-2">برنامج هيرموسا المحاسبي المتكامل</p>
          <p style="font-size: 10px; color: #000000;">Integrated Accounting Program Hermosa</p>
        </div>
      </footer>
    </div>
  </div>
</body>
</html>
    ''';
  }

  /// تحويل نوع الطلب للعربية
  static String _getOrderTypeArabic(String type) {
    switch (type) {
      case 'restaurant_internal':
        return 'طلب داخلي';
      case 'restaurant_pickup':
      case 'restaurant_takeaway':
        return 'طلب خارجي';
      case 'restaurant_delivery':
        return 'توصيل';
      case 'restaurant_parking':
        return 'سيارات';
      default:
        return type;
    }
  }
}
