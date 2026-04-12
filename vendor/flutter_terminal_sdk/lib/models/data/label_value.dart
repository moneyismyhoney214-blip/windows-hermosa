import 'dto/language_content.dart';

class LabelValue<T> {
  final LanguageContent label;
  final T value;

  LabelValue({
    required this.label,
    required this.value,
  });

  factory LabelValue.fromJson(Map<String, dynamic> json) {
    return LabelValue(
      label: LanguageContent.fromJson(json['label'] as Map<String, dynamic>),
      value: json['value'] as T,  // Ensure T is of the correct type
    );
  }

}
