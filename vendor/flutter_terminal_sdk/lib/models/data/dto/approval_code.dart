import 'language_content.dart';

class ApprovalCode {
  final String value;
  final LanguageContent label;

  ApprovalCode({
    required this.value,
    required this.label,
  });

  factory ApprovalCode.fromJson(Map<String, dynamic> json) {
    return ApprovalCode(
      value: json['value'],
      label: LanguageContent.fromJson(json['label']),
    );
  }


  Map<String, dynamic> toJson() {
    return {
      'value': value,
      'label': label.toJson(),
    };
  }

}