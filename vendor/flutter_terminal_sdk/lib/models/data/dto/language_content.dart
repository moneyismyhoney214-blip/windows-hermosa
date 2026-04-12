class LanguageContent {
  final String? arabic;
  final String? english;
  final String? turkish;

  LanguageContent({
    required this.arabic,
    required this.english,
    required this.turkish,
  });

  factory LanguageContent.fromJson(dynamic json) {
    return LanguageContent(
      arabic: json['arabic'] ?? '',
      english: json['english'] ?? '',
      turkish: json['turkish'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'arabic': arabic,
      'english': english,
      'turkish': turkish,
    };
  }

}
