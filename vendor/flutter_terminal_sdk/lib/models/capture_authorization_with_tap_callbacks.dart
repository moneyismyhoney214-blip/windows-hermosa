import 'callbacks.dart';
import 'card_reader_callbacks.dart';

class CaptureAuthorizationWithTapCallbacks {
  final CardReaderCallbacks? cardReaderCallbacks;
  final StringCallback? onSendTransactionFailure;
  final AuthorizedResponseWithTapCallback? onAuthorizedResponseWithTapCompleted;

  CaptureAuthorizationWithTapCallbacks({
    this.cardReaderCallbacks,
    this.onSendTransactionFailure,
    this.onAuthorizedResponseWithTapCompleted,
  });
}