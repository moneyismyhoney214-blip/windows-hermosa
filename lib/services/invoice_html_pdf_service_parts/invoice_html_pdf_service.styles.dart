// _buildStyleSheet — embedded CSS for the invoice HTML.
// Split out of invoice_html_pdf_service.dart for size; remains in the same library via `part of`.
part of '../invoice_html_pdf_service.dart';

extension InvoiceHtmlPdfServiceStyles on InvoiceHtmlPdfService {
  String _buildStyleSheet(int paperWidthMm) {
    final widthMm = _normalizePaperWidthMm(paperWidthMm);
    final widthCss = paperWidthCss(widthMm);

    return '''
@page {
  size: $widthCss auto;
  margin: 2mm;
}
* {
  box-sizing: border-box;
}
body {
  margin: 0;
  padding: 8px 0;
  background: #e5e7eb;
  color: #111827;
  font-family: 'Tajawal', Arial, Tahoma, sans-serif;
  font-size: 14px;
  line-height: 1.4;
  -webkit-print-color-adjust: exact;
  print-color-adjust: exact;
}
p {
  margin: 2px 0;
}

/* ========== Layout utilities (Tailwind-compatible) ========== */
.hidden {
  display: flex !important;
  justify-content: center;
}
.flex {
  display: flex;
}
.justify-center {
  justify-content: center;
}
.justify-between {
  justify-content: space-between;
}
.items-center {
  align-items: center;
}
.text-left {
  text-align: left;
}
.text-right {
  text-align: right;
}
.text-center {
  text-align: center;
}
.font-bold {
  font-weight: 700;
}
.force-ltr {
  direction: ltr;
  text-align: left;
}
.whitespace-nowrap {
  white-space: nowrap;
}

/* ========== Spacing utilities ========== */
.mt-2 { margin-top: 8px; }
.mb-4 { margin-bottom: 16px; }
.my-2 { margin-top: 8px; margin-bottom: 8px; }
.px-2 { padding-right: 8px; padding-left: 8px; }
.px-4 { padding-right: 16px; padding-left: 16px; }
.py-1 { padding-top: 4px; padding-bottom: 4px; }
.pb-2 { padding-bottom: 8px; }

/* ========== Sizing utilities ========== */
.w-full { width: 100%; }
.w-24 { width: 96px; }
.h-24 { height: 96px; }
.w-1\\/3 { width: 33.333%; }
.w-7\\/12 { width: 58.333%; }
.object-contain { object-fit: contain; }

/* ========== Border utilities ========== */
.border { border: 1px solid; }
.border-2 { border: 2px solid #000; }
.border-black { border-color: #000; }
.border-gray-300 { border-color: #d1d5db; }
.border-collapse { border-collapse: collapse; }

/* ========== Background utilities ========== */
.bg-gray-50 { background-color: #f9fafb; }

/* ========== Typography utilities ========== */
.text-xs { font-size: 12px; }
.text-sm { font-size: 14px; }
.text-lg { font-size: 18px; }

/* ========== Receipt container ========== */
.bill {
  width: var(--receipt-width, $widthCss);
}
.bill-container {
  width: var(--receipt-width, $widthCss);
  max-width: calc(100vw - 12px);
  background: #fff;
  padding: 8px;
  box-sizing: border-box;
}
.size-5cm {
  --receipt-width: $widthCss;
}
.size-8cm {
  --receipt-width: 80mm;
}
.size-9cm {
  --receipt-width: 88mm;
}

/* ========== Seller info / header ========== */
.seller-info {
  text-align: center;
}
.logo-container {
  margin-bottom: 12px;
}
.logo-container img,
footer img {
  max-width: 96px;
  max-height: 96px;
  object-fit: contain;
}
.info {
  margin-bottom: 8px;
}
.title {
  margin: 0;
  font-size: 18px;
  font-weight: 700;
}
.mobile {
  direction: ltr;
}
.info-bottom {
  margin-bottom: 8px;
}
.info-bottom-item {
  margin-bottom: 6px;
  border-bottom: 1px dashed #d1d5db;
  padding-bottom: 4px;
}

/* ========== Invoice title (فاتورة ضريبية مبسطة) ========== */
.invoice-title {
  text-align: center;
  border-bottom: 1px dashed #9ca3af;
  border-top: 1px dashed #9ca3af;
  padding: 6px 0;
  margin: 10px 0;
  font-weight: 700;
}

/* ========== Client info ========== */
.client-info {
  margin-bottom: 8px;
}
.client-info-item {
  margin-bottom: 6px;
  border-bottom: 1px dashed #d1d5db;
  padding-bottom: 4px;
}

/* ========== Items table ========== */
.invoice-items table,
.car-info-table,
.addons-table {
  width: 100%;
  border-collapse: collapse;
}
.invoice-items th,
.invoice-items td,
.car-info-table th,
.car-info-table td,
.addons-table td,
.addons-table th {
  border: 1px solid #d1d5db;
  padding: 4px;
  vertical-align: top;
}
.addon-size {
  font-size: 11px;
}
.addon-item {
  font-size: 11px;
}

/* ========== Invoice details (totals) ========== */
.invoice-details {
  margin-bottom: 8px;
}
.invoice-details-item {
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
  border-bottom: 1px dashed #e5e7eb;
  padding: 6px 0;
}
.invoice-item-title {
  width: 52%;
}
.currency-area {
  margin-left: 4px;
  font-size: 11px;
  color: #6b7280;
}
.price {
  font-weight: 700;
}

/* ========== Footer ========== */
footer {
  text-align: center;
}
footer .invoice-details-item {
  display: block;
  text-align: center;
}

/* ==========================================================
   Scoped overrides from PrintOrdertokitchen.vue
   These scale font sizes UP for thermal-printer readability.
   ========================================================== */
.seller-info .info p,
.seller-info .info-bottom .info-bottom-item p {
  font-size: 18px !important;
  line-height: 1.5 !important;
}
.seller-info .border-2 {
  font-size: 20px !important;
  font-weight: bold !important;
}
.client-info .client-info-item p {
  font-size: 18px !important;
  line-height: 1.4 !important;
}
.invoice-items table thead th {
  font-size: 20px !important;
  font-weight: bold !important;
  padding: 6px !important;
}
.invoice-items table tbody td p {
  font-size: 18px !important;
  line-height: 1.4 !important;
}
.addons-table td {
  font-size: 16px !important;
  padding: 4px !important;
}
.addon-item {
  font-size: 16px !important;
}
.invoice-title p {
  font-size: 22px !important;
  font-weight: bold !important;
}
.invoice-details-item p,
.invoice-details-item .price {
  font-size: 18px !important;
}
.invoice-details-item .currency-area p {
  font-size: 14px !important;
}
.invoice-item-title p {
  font-size: 18px !important;
}
footer p {
  font-size: 16px !important;
}

/* ========== Print media ========== */
@media print {
  @page {
    size: $widthCss auto;
    margin: 2mm;
  }
  body {
    background: #fff;
    padding: 0;
    margin: 0;
  }
  .hidden {
    justify-content: flex-start;
  }
  .bill-container {
    width: $widthCss !important;
    max-width: $widthCss !important;
    box-shadow: none;
    margin: 0;
    padding: 0;
  }
}
''';
  }
}
