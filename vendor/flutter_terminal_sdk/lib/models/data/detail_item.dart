import 'dto/language_content.dart';

class DetailItem {
  final LanguageContent label;
  final String total;
  final num count;

  DetailItem({
    required this.label,
    required this.total,
    required this.count,
  });

  factory DetailItem.fromJson(Map<String, dynamic> json) {
    return DetailItem(
      label: LanguageContent.fromJson(json['label'] as Map<String, dynamic>),
      total: json['total'] as String,
      count: json['count'] as num,
    );
  }

}
