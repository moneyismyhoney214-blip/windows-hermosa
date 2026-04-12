import 'language_content.dart';

class CardScheme {
  final LanguageContent name;
  final String id;

  CardScheme({
    required this.name,
    required this.id,
  });

  factory CardScheme.fromJson(Map<String, dynamic> json) {
    return CardScheme(
      name: LanguageContent.fromJson(json['name']),
      id: json['id'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name.toJson(),
      'id': id,
    };
  }

}