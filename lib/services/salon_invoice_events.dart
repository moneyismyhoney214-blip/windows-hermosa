import 'dart:async';

class SalonInvoiceCreatedEvent {
  SalonInvoiceCreatedEvent({
    this.invoiceId,
    this.invoiceNumber,
    this.bookingId,
    this.orderNumber,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String? invoiceId;
  final String? invoiceNumber;
  final String? bookingId;
  final String? orderNumber;
  final DateTime createdAt;
}

/// Salon-only event bus that lets `main_screen.payment.dart` notify the
/// invoices and orders screens the moment a new invoice is created.
///
/// Two delivery modes — both are needed because `OrdersScreen` and
/// `InvoicesScreen` aren't mounted while the user is on the home tab
/// creating the invoice; they only mount after navigation.
///
///   1. Broadcast stream — for screens that ARE mounted when the event fires.
///   2. In-memory recent buffer — for screens that mount AFTER the event
///      fires. They drain `recentEvents()` in `initState` and apply the
///      same logic the live stream listener would have.
///
/// The buffer auto-prunes events older than [retention] on every read so
/// it can't grow unbounded across a long session.
class SalonInvoiceEvents {
  final StreamController<SalonInvoiceCreatedEvent> _controller =
      StreamController<SalonInvoiceCreatedEvent>.broadcast();
  final List<SalonInvoiceCreatedEvent> _recent = [];

  static const Duration retention = Duration(seconds: 90);
  static const int _maxBuffered = 50;

  Stream<SalonInvoiceCreatedEvent> get stream => _controller.stream;

  /// Events fired within the last [retention] window. Safe to call from
  /// `initState` — screens use this to pick up events fired before they
  /// were mounted.
  List<SalonInvoiceCreatedEvent> recentEvents() {
    final cutoff = DateTime.now().subtract(retention);
    _recent.removeWhere((e) => e.createdAt.isBefore(cutoff));
    return List.unmodifiable(_recent);
  }

  void emitCreated({
    String? invoiceId,
    String? invoiceNumber,
    String? bookingId,
    String? orderNumber,
  }) {
    final event = SalonInvoiceCreatedEvent(
      invoiceId: invoiceId,
      invoiceNumber: invoiceNumber,
      bookingId: bookingId,
      orderNumber: orderNumber,
    );
    _recent.add(event);
    if (_recent.length > _maxBuffered) {
      _recent.removeRange(0, _recent.length - _maxBuffered);
    }
    if (!_controller.isClosed) {
      _controller.add(event);
    }
  }
}
