import '../models/receipt_data.dart';

class ReceiptPrintJob {
  final String invoiceId;
  final OrderReceiptData receiptData;
  final DateTime createdAt;

  const ReceiptPrintJob({
    required this.invoiceId,
    required this.receiptData,
    required this.createdAt,
  });
}

class KitchenPrintJob {
  final String orderNumber;
  final String orderType;
  final List<Map<String, dynamic>> items;
  final String? note;
  final String? invoiceNumber;
  final Map<String, dynamic>? templateMeta;
  final DateTime createdAt;

  const KitchenPrintJob({
    required this.orderNumber,
    required this.orderType,
    required this.items,
    this.note,
    this.invoiceNumber,
    this.templateMeta,
    required this.createdAt,
  });
}

class PrintJobHistoryService {
  final Map<String, ReceiptPrintJob> _receiptJobsByInvoiceId =
      <String, ReceiptPrintJob>{};
  final Map<String, KitchenPrintJob> _kitchenJobsByInvoiceNumber =
      <String, KitchenPrintJob>{};

  ReceiptPrintJob? getReceiptJob(String invoiceId) {
    return _receiptJobsByInvoiceId[invoiceId.trim()];
  }

  KitchenPrintJob? getKitchenJobForInvoice(String invoiceNumber) {
    return _kitchenJobsByInvoiceNumber[invoiceNumber.trim()];
  }

  void storeReceiptJob({
    required String? invoiceId,
    required OrderReceiptData receiptData,
  }) {
    final normalized = invoiceId?.trim();
    if (normalized == null || normalized.isEmpty) return;
    _receiptJobsByInvoiceId[normalized] = ReceiptPrintJob(
      invoiceId: normalized,
      receiptData: receiptData,
      createdAt: DateTime.now(),
    );
  }

  void storeKitchenJob({
    required String orderNumber,
    required String orderType,
    required List<Map<String, dynamic>> items,
    String? note,
    String? invoiceNumber,
    Map<String, dynamic>? templateMeta,
    DateTime? createdAt,
  }) {
    final job = KitchenPrintJob(
      orderNumber: orderNumber,
      orderType: orderType,
      items: items.map((item) => Map<String, dynamic>.from(item)).toList(),
      note: note,
      invoiceNumber: invoiceNumber,
      templateMeta: templateMeta == null
          ? null
          : Map<String, dynamic>.from(templateMeta),
      createdAt: createdAt ?? DateTime.now(),
    );

    final normalizedInvoice = invoiceNumber?.trim();
    if (normalizedInvoice != null && normalizedInvoice.isNotEmpty) {
      _kitchenJobsByInvoiceNumber[normalizedInvoice] = job;
    }
  }

  void clear() {
    _receiptJobsByInvoiceId.clear();
    _kitchenJobsByInvoiceNumber.clear();
  }
}
