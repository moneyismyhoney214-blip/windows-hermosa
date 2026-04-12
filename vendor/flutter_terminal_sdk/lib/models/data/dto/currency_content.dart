class CurrencyContent {
  final String? english;
  final String? turkish;
  final String? arabic;

  CurrencyContent({
    required this.english,
    required this.turkish,
    required this.arabic,
  });

  factory CurrencyContent.fromJson(dynamic json) {
    return CurrencyContent(
      english: json['english'] ?? '',
      turkish: json['turkish'] ?? '',
      arabic: json['arabic'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'english': english,
      'turkish': turkish,
      'arabic': arabic,
    };
  }
}
