import 'callbacks.dart';

class CardReaderCallbacks {
  final VoidCallback? onReadingStarted;
  final VoidCallback? onReaderWaiting;
  final VoidCallback? onReaderReading;
  final VoidCallback? onReaderRetry;
  final VoidCallback? onPinEntering;
  final VoidCallback? onReaderFinished;
  final VoidCallback? onReaderClosed;
  final VoidCallback? onReaderDisplayed;
  final VoidCallback? onReaderDismissed;
  final StringCallback? onReaderError;
  final VoidCallback? onCardReadSuccess;
  final StringCallback? onCardReadFailure;

  CardReaderCallbacks({
    this.onReadingStarted,
    this.onReaderDismissed,
    this.onReaderWaiting,
    this.onReaderReading,
    this.onReaderRetry,
    this.onPinEntering,
    this.onReaderFinished,
    this.onReaderError,
    this.onCardReadSuccess,
    this.onCardReadFailure,
    this.onReaderClosed,
    this.onReaderDisplayed,
  });
}
