import 'language_content.dart';

class TransactionType {
  String? id;
  LanguageContent? name;

  TransactionType({required this.id, required this.name});

  factory TransactionType.fromJson(Map<String, dynamic> json) {
    return TransactionType(
      id: json['id'],
      name: LanguageContent.fromJson(json['name']),
    );
  }


  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name?.toJson(),
    };
  }

}
