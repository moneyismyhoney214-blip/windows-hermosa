import 'package:uuid/uuid.dart';

/// Cashier-initiated migration: the group seated at [oldTableId] moved to
/// [newTableId]. Kitchen tickets that were fired under the old table id
/// follow the party — a migration receipt is printed so the chef knows
/// the existing order now belongs to a different table number.
class TableMigrateEvent {
  final String requestId;
  final String oldTableId;
  final String oldTableNumber;
  final String newTableId;
  final String newTableNumber;

  /// Cashier (or whoever initiated this). Surface in the kitchen note so
  /// the chef has a point-of-contact.
  final String initiatedById;
  final String initiatedByName;

  final DateTime migratedAt;

  TableMigrateEvent({
    required this.oldTableId,
    required this.oldTableNumber,
    required this.newTableId,
    required this.newTableNumber,
    required this.initiatedById,
    required this.initiatedByName,
    String? requestId,
    DateTime? migratedAt,
  })  : requestId = requestId ?? const Uuid().v4(),
        migratedAt = migratedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => <String, dynamic>{
        'request_id': requestId,
        'old_table_id': oldTableId,
        'old_table_number': oldTableNumber,
        'new_table_id': newTableId,
        'new_table_number': newTableNumber,
        'initiated_by_id': initiatedById,
        'initiated_by_name': initiatedByName,
        'migrated_at': migratedAt.toIso8601String(),
      };

  factory TableMigrateEvent.fromJson(Map<String, dynamic> j) =>
      TableMigrateEvent(
        requestId: j['request_id']?.toString(),
        oldTableId: j['old_table_id']?.toString() ?? '',
        oldTableNumber: j['old_table_number']?.toString() ?? '',
        newTableId: j['new_table_id']?.toString() ?? '',
        newTableNumber: j['new_table_number']?.toString() ?? '',
        initiatedById: j['initiated_by_id']?.toString() ?? '',
        initiatedByName: j['initiated_by_name']?.toString() ?? '',
        migratedAt:
            DateTime.tryParse(j['migrated_at']?.toString() ?? ''),
      );
}
