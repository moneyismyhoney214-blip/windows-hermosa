// ignore_for_file: unused_element, unused_element_parameter, dead_code
part of '../invoice_print_widget.dart';

extension InvoicePrintWidgetHtml on InvoicePrintWidget {
  String generateHtmlForPrint() {
    if (data == null) return "<html><body>Test / Kitchen Print</body></html>";
    return InvoiceHtmlTemplate.generateInvoiceHtml(
      data: data!,
      orderType: orderType,
      tableNumber: tableNumber,
      carNumber: carNumber,
      dailyOrderNumber: dailyOrderNumber,
      carBrand: carBrand,
      carModel: carModel,
      carPlateNumber: carPlateNumber,
      carYear: carYear,
      clientName: clientName,
      clientPhone: clientPhone,
      clientTaxNumber: clientTaxNumber,
      commercialRegisterNumber: commercialRegisterNumber,
      returnPolicy: returnPolicy,
      paperWidthMm: paperWidthMm,
      primaryLang: primaryLang,
      secondaryLang: secondaryLang,
      allowSecondary: allowSecondary,
    );
  }
}
