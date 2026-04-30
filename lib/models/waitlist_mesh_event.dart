import 'waitlist_entry.dart';

/// Which waitlist mutation the receiver should apply.
///
/// One wire type carries all of these so the `network_message` enum
/// doesn't have to grow per mutation — the `kind` field discriminates
/// at the router level.
enum WaitlistMeshKind {
  /// A brand-new party was queued. Payload: full [WaitlistEntry].
  added,

  /// An existing party's details changed (name fix, party size,
  /// channel flip, notes). Payload: full [WaitlistEntry]; match by id.
  updated,

  /// The host removed the party. Payload: [entryId] only; no full
  /// entry sent because the sender may have already cleared it.
  removed,

  /// Party was notified (table assignment + message sent). Payload:
  /// the updated [WaitlistEntry] reflecting the new
  /// `notified` status + `assignedTable*` fields. Having the whole
  /// entry simplifies late joiners — they don't need a prior `added`.
  notified,

  /// Party sat down at the assigned table. Payload: updated entry.
  seated,

  /// Party left / was manually cancelled. Payload: updated entry.
  cancelled,
}

/// One waitlist delta carried over the LAN mesh.
class WaitlistMeshEvent {
  final WaitlistMeshKind kind;

  /// Populated for every kind except [WaitlistMeshKind.removed].
  final WaitlistEntry? entry;

  /// Populated for [WaitlistMeshKind.removed]. Always equals
  /// `entry.id` when `entry` is non-null — handlers can use either.
  final String entryId;

  /// Wall-clock stamp of the sender's decision. Receivers use it as
  /// a last-write-wins tiebreaker if two devices race on the same
  /// entry.
  final DateTime sentAt;

  WaitlistMeshEvent({
    required this.kind,
    required this.entryId,
    this.entry,
    DateTime? sentAt,
  }) : sentAt = sentAt ?? DateTime.now();

  factory WaitlistMeshEvent.added(WaitlistEntry entry) =>
      WaitlistMeshEvent(
        kind: WaitlistMeshKind.added,
        entryId: entry.id,
        entry: entry,
      );

  factory WaitlistMeshEvent.updated(WaitlistEntry entry) =>
      WaitlistMeshEvent(
        kind: WaitlistMeshKind.updated,
        entryId: entry.id,
        entry: entry,
      );

  factory WaitlistMeshEvent.removed(String entryId) => WaitlistMeshEvent(
        kind: WaitlistMeshKind.removed,
        entryId: entryId,
      );

  factory WaitlistMeshEvent.notified(WaitlistEntry entry) =>
      WaitlistMeshEvent(
        kind: WaitlistMeshKind.notified,
        entryId: entry.id,
        entry: entry,
      );

  factory WaitlistMeshEvent.seated(WaitlistEntry entry) =>
      WaitlistMeshEvent(
        kind: WaitlistMeshKind.seated,
        entryId: entry.id,
        entry: entry,
      );

  factory WaitlistMeshEvent.cancelled(WaitlistEntry entry) =>
      WaitlistMeshEvent(
        kind: WaitlistMeshKind.cancelled,
        entryId: entry.id,
        entry: entry,
      );

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'entry_id': entryId,
        if (entry != null) 'entry': entry!.toJson(),
        'sent_at': sentAt.toIso8601String(),
      };

  factory WaitlistMeshEvent.fromJson(Map<String, dynamic> json) {
    final rawEntry = json['entry'];
    return WaitlistMeshEvent(
      kind: _kindFrom(json['kind']),
      entryId: (json['entry_id'] ?? '').toString(),
      entry: rawEntry is Map<String, dynamic>
          ? WaitlistEntry.fromJson(rawEntry)
          : null,
      sentAt:
          DateTime.tryParse(json['sent_at']?.toString() ?? '') ??
              DateTime.now(),
    );
  }

  static WaitlistMeshKind _kindFrom(Object? raw) {
    final value = raw?.toString();
    return WaitlistMeshKind.values.firstWhere(
      (k) => k.name == value,
      orElse: () => WaitlistMeshKind.updated,
    );
  }
}

/// Full-queue snapshot pushed to a newly-joined peer so it starts
/// with the same list the rest of the LAN already has.
class WaitlistMeshSnapshot {
  final List<WaitlistEntry> entries;
  final DateTime sentAt;

  WaitlistMeshSnapshot({
    required this.entries,
    DateTime? sentAt,
  }) : sentAt = sentAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'entries': entries.map((e) => e.toJson()).toList(),
        'sent_at': sentAt.toIso8601String(),
      };

  factory WaitlistMeshSnapshot.fromJson(Map<String, dynamic> json) {
    final raw = json['entries'];
    final list = raw is List
        ? raw
            .whereType<Map<String, dynamic>>()
            .map(WaitlistEntry.fromJson)
            .toList()
        : <WaitlistEntry>[];
    return WaitlistMeshSnapshot(
      entries: list,
      sentAt:
          DateTime.tryParse(json['sent_at']?.toString() ?? '') ??
              DateTime.now(),
    );
  }
}

/// Envelope mirroring `WaiterTableEventEnvelope` so UI consumers can
/// tell self-echoes from genuine remote deltas and skip their own
/// broadcasts.
class WaitlistMeshEventEnvelope {
  final WaitlistMeshEvent event;
  final bool fromSelf;

  const WaitlistMeshEventEnvelope({
    required this.event,
    required this.fromSelf,
  });
}
