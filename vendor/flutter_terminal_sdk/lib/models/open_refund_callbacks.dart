import 'callbacks.dart';
import 'card_reader_callbacks.dart';

class OpenRefundCallbacks {
  final CardReaderCallbacks? cardReaderCallbacks;
  final StringCallback? onSendTransactionFailure;
  final TransactionRefundCallback? onTransactionOpenRefundCompleted;

  OpenRefundCallbacks({
    this.cardReaderCallbacks,
    this.onSendTransactionFailure,
    this.onTransactionOpenRefundCompleted,
  });
}
