import 'package:uuid/uuid.dart';

/// Lifecycle of a single customer on the waitlist.
///
///  * [waiting] — freshly added, no table yet.
///  * [notified] — a table was assigned AND the notification went out.
///  * [seated]   — guest arrived and the waiter/cashier opened the table.
///  * [cancelled] — walked away / removed manually.
enum WaitlistStatus { waiting, notified, seated, cancelled }

/// One party queued for a table. Lives entirely on-device (SharedPreferences)
/// — every mutation goes through [WaitlistService] so persistence stays in
/// one place.
class WaitlistEntry {
  /// Stable local id. Kept as a string so we can upgrade to server ids
  /// later without breaking UI that stores `entry.id` in state.
  final String id;

  /// Customer's display name as typed by the host. Required, trimmed.
  final String customerName;

  /// E.164-like phone number with the country code, **without** the
  /// leading `+`. e.g. `966501234567`. Stored normalized so the
  /// messaging layer never has to re-parse it.
  final String phoneNumber;

  /// How many guests are in the party. Drives table-fit suggestions
  /// later. Defaults to 1 so the UI never shows "0 guests".
  final int partySize;

  /// Free-form host note ("prefers window", "birthday", ...).
  final String? notes;

  /// Backend customer id this party is linked to. Set when the party is
  /// added via the waitlist dialog (which now creates — or picks — a real
  /// customer record), so the booking opened on the assigned table carries
  /// the same `customer_id` and the order shows up against that customer
  /// on the backend instead of an anonymous walk-in.
  final String? customerId;

  /// See [WaitlistStatus].
  final WaitlistStatus status;

  /// When the party joined the queue. The sheet uses this to render the
  /// "waited N min" live label.
  final DateTime createdAt;

  /// When the notification actually landed (or — for wa.me fallback —
  /// when the host pressed "send"). Null until [markNotified].
  final DateTime? notifiedAt;

  /// Which table they were sent to. Kept so we can paint a "waiting
  /// for: NAME" pill on the matching table card.
  final String? assignedTableId;
  final String? assignedTableNumber;

  WaitlistEntry({
    String? id,
    required this.customerName,
    required this.phoneNumber,
    this.partySize = 1,
    this.notes,
    this.customerId,
    this.status = WaitlistStatus.waiting,
    DateTime? createdAt,
    this.notifiedAt,
    this.assignedTableId,
    this.assignedTableNumber,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();

  /// Minutes the party has been waiting right now. UI reads this from
  /// a ticking timer so the label updates without rebuilding the list.
  int minutesWaiting({DateTime? now}) {
    final ref = now ?? DateTime.now();
    final since = status == WaitlistStatus.notified && notifiedAt != null
        ? notifiedAt!
        : createdAt;
    final diff = ref.difference(since);
    return diff.inMinutes < 0 ? 0 : diff.inMinutes;
  }

  bool get isActive =>
      status == WaitlistStatus.waiting || status == WaitlistStatus.notified;

  WaitlistEntry copyWith({
    String? customerName,
    String? phoneNumber,
    int? partySize,
    String? notes,
    bool clearNotes = false,
    String? customerId,
    WaitlistStatus? status,
    DateTime? notifiedAt,
    bool clearNotifiedAt = false,
    String? assignedTableId,
    String? assignedTableNumber,
    bool clearAssignedTable = false,
  }) {
    return WaitlistEntry(
      id: id,
      customerName: customerName ?? this.customerName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      partySize: partySize ?? this.partySize,
      notes: clearNotes ? null : (notes ?? this.notes),
      customerId: customerId ?? this.customerId,
      status: status ?? this.status,
      createdAt: createdAt,
      notifiedAt: clearNotifiedAt ? null : (notifiedAt ?? this.notifiedAt),
      assignedTableId: clearAssignedTable
          ? null
          : (assignedTableId ?? this.assignedTableId),
      assignedTableNumber: clearAssignedTable
          ? null
          : (assignedTableNumber ?? this.assignedTableNumber),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'customerName': customerName,
        'phoneNumber': phoneNumber,
        'partySize': partySize,
        if (notes != null) 'notes': notes,
        if (customerId != null) 'customerId': customerId,
        'status': status.name,
        'createdAt': createdAt.toIso8601String(),
        if (notifiedAt != null) 'notifiedAt': notifiedAt!.toIso8601String(),
        if (assignedTableId != null) 'assignedTableId': assignedTableId,
        if (assignedTableNumber != null)
          'assignedTableNumber': assignedTableNumber,
      };

  factory WaitlistEntry.fromJson(Map<String, dynamic> json) {
    return WaitlistEntry(
      id: json['id'] as String?,
      customerName: (json['customerName'] as String?)?.trim() ?? '',
      phoneNumber: (json['phoneNumber'] as String?)?.trim() ?? '',
      partySize: (json['partySize'] as num?)?.toInt() ?? 1,
      notes: (json['notes'] as String?)?.trim(),
      customerId: json['customerId']?.toString(),
      status: _statusFrom(json['status']),
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
              DateTime.now(),
      notifiedAt: json['notifiedAt'] is String
          ? DateTime.tryParse(json['notifiedAt'] as String)
          : null,
      assignedTableId: json['assignedTableId'] as String?,
      assignedTableNumber: json['assignedTableNumber'] as String?,
    );
  }

  static WaitlistStatus _statusFrom(Object? raw) {
    final value = raw?.toString();
    return WaitlistStatus.values.firstWhere(
      (s) => s.name == value,
      orElse: () => WaitlistStatus.waiting,
    );
  }
}
