import 'callbacks.dart';
import 'card_reader_callbacks.dart';


class RefundVoidCallbacks {
  final CardReaderCallbacks? cardReaderCallbacks;
  final StringCallback? onRefundVoidFailure;
  final RefundVoidResponseCallback? onRefundVoidCompleted;

  RefundVoidCallbacks({
    this.cardReaderCallbacks,
    this.onRefundVoidFailure,
    this.onRefundVoidCompleted,
  });
}