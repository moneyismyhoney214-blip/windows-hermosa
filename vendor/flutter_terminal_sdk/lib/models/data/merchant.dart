import 'dto/language_content.dart';

class Merchant {
  final String? id;
  final LanguageContent? name;
  final LanguageContent? address;
  final String? categoryCode;

  const Merchant({
    required this.id,
    required this.name,
    required this.address,
    required this.categoryCode,
  });

  factory Merchant.fromJson(Map<String, dynamic> json) {
    return Merchant(
      id: json['id'] as String?,
      name: LanguageContent.fromJson(json['name'] as Map<String, dynamic>),
      address: LanguageContent.fromJson(json['address'] as Map<String, dynamic>),
      categoryCode: json['categoryCode'] as String?,
    );
  }



  Merchant copyWith({
    String? id,
    LanguageContent? name,
    LanguageContent? address,
    String? categoryCode,
  }) {
    return Merchant(
      id: id ?? this.id,
      name: name ?? this.name,
      address: address ?? this.address,
      categoryCode: categoryCode ?? this.categoryCode,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name?.toJson(),
      'address': address?.toJson(),
      'category_code': categoryCode ?? "",
      'categoryCode': categoryCode ?? "",
    };
  }

  @override
  String toString() =>
      'Merchant(id: $id, name: $name, address: $address, categoryCode: $categoryCode)';
}
