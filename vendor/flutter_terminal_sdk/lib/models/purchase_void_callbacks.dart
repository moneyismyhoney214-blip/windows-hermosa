import 'callbacks.dart';
import 'card_reader_callbacks.dart';

class PurchaseVoidCallbacks {
  final CardReaderCallbacks? cardReaderCallbacks;
  final StringCallback? onSendPurchaseVoidFailure;
  final PurchaseVoidResponseCallback? onSendPurchaseVoidCompleted;

  PurchaseVoidCallbacks({
    this.cardReaderCallbacks,
    this.onSendPurchaseVoidFailure,
    this.onSendPurchaseVoidCompleted,
  });
}