// terminal_merchant.dart
import 'dto/LocalizationField.dart';

class TerminalMerchant {
  final String id;
  final LocalizationField name;
  final String? createdAt;

  const TerminalMerchant({
    required this.id,
    required this.name,
    this.createdAt,
  });

  /// JSON factory (deserialization)
  factory TerminalMerchant.fromJson(Map<String, dynamic> json) {
    return TerminalMerchant(
      id: json['id'] as String,
      name: LocalizationField.fromJson(json['name'] as Map<String, dynamic>),
      createdAt: json['createdAt'] as String?,
    );
  }

  /// copyWith for convenient updates
  TerminalMerchant copyWith({
    String? id,
    LocalizationField? name,
    String? createdAt,
  }) {
    return TerminalMerchant(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  String toString() =>
      'TerminalMerchant(id: $id, name: $name, createdAt: $createdAt)';
}
