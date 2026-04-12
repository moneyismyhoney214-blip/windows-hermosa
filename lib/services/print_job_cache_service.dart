import '../models/receipt_data.dart';

class CachedReceiptJob {
  final OrderReceiptData receiptData;
  final String? invoiceId;
  final DateTime createdAt;

  const CachedReceiptJob({
    required this.receiptData,
    this.invoiceId,
    required this.createdAt,
  });
}

class PrintJobCacheService {
  CachedReceiptJob? _lastReceiptJob;

  CachedReceiptJob? get lastReceiptJob => _lastReceiptJob;

  bool get hasReceiptJob => _lastReceiptJob != null;

  void cacheReceiptJob({
    required OrderReceiptData receiptData,
    String? invoiceId,
  }) {
    _lastReceiptJob = CachedReceiptJob(
      receiptData: receiptData,
      invoiceId: invoiceId,
      createdAt: DateTime.now(),
    );
  }
}

final PrintJobCacheService printJobCacheService = PrintJobCacheService();
