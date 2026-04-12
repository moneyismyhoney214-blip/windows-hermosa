// TODO: needs behavioral review - vendor file name kept for SDK compatibility.
// ignore_for_file: file_names
class LocalizationField {
  final String? arabic;
  final String? english;

  const LocalizationField({
    required this.arabic,
    required this.english,
  });

  factory LocalizationField.fromJson(Map<String, dynamic> json) {
    return LocalizationField(
      arabic: json['arabic'] ,
      english: json['english'] ,
    );
  }

  LocalizationField copyWith({
    String? arabic,
    String? english,
  }) {
    return LocalizationField(
      arabic: arabic ?? this.arabic,
      english: english ?? this.english,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'arabic': arabic,
      'english': english,
    };
  }
  @override
  String toString() =>
      'LocalizationField(arabic: $arabic, english: $english)';
}
