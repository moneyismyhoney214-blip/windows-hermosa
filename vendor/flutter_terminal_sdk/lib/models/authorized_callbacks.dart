import 'callbacks.dart';
import 'card_reader_callbacks.dart';

class AuthorizedCallbacks {
  final CardReaderCallbacks? cardReaderCallbacks;
  final StringCallback? onSendTransactionFailure;
  final AuthorizedResponseCallback? onSendAuthorizedCompleted;

  AuthorizedCallbacks({
    this.cardReaderCallbacks,
    this.onSendTransactionFailure,
    this.onSendAuthorizedCompleted,
  });
}