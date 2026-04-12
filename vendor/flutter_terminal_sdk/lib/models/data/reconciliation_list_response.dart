
// Define the main response object
class ReconciliationListResponse {
  final List<ReconciliationItem> data;
  final Pagination pagination;

  ReconciliationListResponse({required this.data, required this.pagination});

  factory ReconciliationListResponse.fromJson(Map<String, dynamic> json) {
    var dataList = json['data'] as List;
    List<ReconciliationItem> transactionList =
        dataList.map((data) => ReconciliationItem.fromJson(data)).toList();
    return ReconciliationListResponse(
      data: transactionList,
      pagination: Pagination.fromJson(json['pagination']),
    );
  }
}

// Define the ReconciliationItem object
class ReconciliationItem {
  final String id;
  final String date;
  final String time;
  final String startDate;
  final String startTime;
  final LabelValue isBalanced;
  final String total;
  final Currency currency;

  ReconciliationItem({
    required this.id,
    required this.date,
    required this.time,
    required this.startDate,
    required this.startTime,
    required this.isBalanced,
    required this.total,
    required this.currency,
  });

  factory ReconciliationItem.fromJson(Map<String, dynamic> json) {
    return ReconciliationItem(
      id: json['id'] ?? '',
      date: json['date'] ?? '',
      time: json['time'] ?? '',
      startDate: json['startDate'] ?? '',
      startTime: json['startTime'] ?? '',
      isBalanced: LabelValue.fromJson(json['isBalanced']),
      total: json['total'] ?? '',
      currency: Currency.fromJson(json['currency']),
    );
  }
}

// Define the LabelValue object
class LabelValue {
  final LanguageContent label;
  final bool value;

  LabelValue({required this.label, required this.value});

  factory LabelValue.fromJson(Map<String, dynamic> json) {
    return LabelValue(
      label: LanguageContent.fromJson(json['label']),
      value: json['value'] ?? false,
    );
  }
}

// Define the LanguageContent object
class LanguageContent {
  final String arabic;
  final String english;
  final String? turkish;

  LanguageContent({
    required this.arabic,
    required this.english,
    this.turkish,
  });

  factory LanguageContent.fromJson(Map<String, dynamic> json) {
    return LanguageContent(
      arabic: json['arabic'] ?? '',
      english: json['english'] ?? '',
      turkish: json['turkish'],
    );
  }
}

// Define the Currency object
class Currency {
  final String? arabic;
  final String english;
  final String turkish;

  Currency({
    this.arabic,
    required this.english,
    required this.turkish,
  });

  factory Currency.fromJson(Map<String, dynamic> json) {
    return Currency(
      arabic: json['arabic'],
      english: json['english'] ?? '',
      turkish: json['turkish'] ?? '',
    );
  }
}

// Define the Pagination object
class Pagination {
  final double totalPages;
  final double currentPage;
  final double totalData;

  Pagination({
    required this.totalPages,
    required this.currentPage,
    required this.totalData,
  });

  factory Pagination.fromJson(Map<String, dynamic> json) {
    return Pagination(
      totalPages: json['total_pages'] ?? 0.0,
      currentPage: json['current_page'] ?? 0.0,
      totalData: json['total_data'] ?? 0.0,
    );
  }
}
