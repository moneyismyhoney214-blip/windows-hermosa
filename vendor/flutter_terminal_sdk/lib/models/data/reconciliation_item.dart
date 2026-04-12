import 'label_value.dart';
import 'dto/language_content.dart';

class ReconciliationItem {
  final String id;
  final String date;
  final String time;
  final String startDate;
  final String startTime;
  final LabelValue<bool> isBalanced;
  final String total;
  final LanguageContent currency;

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
      id: json['id'] as String,
      date: json['date'] as String,
      time: json['time'] as String,
      startDate: json['startDate'] as String,
      startTime: json['startTime'] as String,
      isBalanced: LabelValue<bool>.fromJson(json['isBalanced'] as Map<String, dynamic>),
      total: json['total'] as String,
      currency: LanguageContent.fromJson(json['currency'] as Map<String, dynamic>),
    );
  }

}
