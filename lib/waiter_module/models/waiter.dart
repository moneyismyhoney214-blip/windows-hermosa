import 'package:flutter/foundation.dart';

/// What the waiter is currently doing.
/// Broadcast to other waiters and the cashier so they know who is free.
enum WaiterStatus {
  free,
  busy,
  onBreak,
  offline,
}

extension WaiterStatusX on WaiterStatus {
  String get wireValue {
    switch (this) {
      case WaiterStatus.free:
        return 'free';
      case WaiterStatus.busy:
        return 'busy';
      case WaiterStatus.onBreak:
        return 'on_break';
      case WaiterStatus.offline:
        return 'offline';
    }
  }

  static WaiterStatus fromWire(String? s) {
    switch (s) {
      case 'busy':
        return WaiterStatus.busy;
      case 'on_break':
        return WaiterStatus.onBreak;
      case 'offline':
        return WaiterStatus.offline;
      case 'free':
      default:
        return WaiterStatus.free;
    }
  }
}

/// A waiter identity advertised on the LAN.
/// `id` is stable per-device (UUID), `name` is the display name the user sees.
@immutable
class Waiter {
  /// Prefix for non-interactive listener peers (e.g. the cashier).
  /// Other waiters and cashier UIs filter these out of "call a waiter" lists.
  static const String viewerIdPrefix = 'viewer-';

  final String id;
  final String name;
  final String? avatarUrl;
  final String branchId;
  final WaiterStatus status;
  final String? host;
  final int? port;
  final DateTime? lastSeen;

  const Waiter({
    required this.id,
    required this.name,
    required this.branchId,
    this.avatarUrl,
    this.status = WaiterStatus.free,
    this.host,
    this.port,
    this.lastSeen,
  });

  bool get isViewer => id.startsWith(viewerIdPrefix);

  Waiter copyWith({
    String? id,
    String? name,
    String? avatarUrl,
    String? branchId,
    WaiterStatus? status,
    String? host,
    int? port,
    DateTime? lastSeen,
  }) {
    return Waiter(
      id: id ?? this.id,
      name: name ?? this.name,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      branchId: branchId ?? this.branchId,
      status: status ?? this.status,
      host: host ?? this.host,
      port: port ?? this.port,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'branch_id': branchId,
        if (avatarUrl != null) 'avatar_url': avatarUrl,
        'status': status.wireValue,
        if (host != null) 'host': host,
        if (port != null) 'port': port,
        if (lastSeen != null) 'last_seen': lastSeen!.toIso8601String(),
      };

  factory Waiter.fromJson(Map<String, dynamic> json) => Waiter(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        avatarUrl: json['avatar_url']?.toString(),
        branchId: json['branch_id']?.toString() ?? '',
        status: WaiterStatusX.fromWire(json['status']?.toString()),
        host: json['host']?.toString(),
        port: (json['port'] is int)
            ? json['port'] as int
            : int.tryParse(json['port']?.toString() ?? ''),
        lastSeen: DateTime.tryParse(json['last_seen']?.toString() ?? ''),
      );

  @override
  bool operator ==(Object other) => other is Waiter && other.id == id;
  @override
  int get hashCode => id.hashCode;
}
