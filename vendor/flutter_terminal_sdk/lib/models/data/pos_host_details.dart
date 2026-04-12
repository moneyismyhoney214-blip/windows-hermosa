import 'detail_item.dart';

class PosHostDetails {
  final DetailItem credit;
  final DetailItem debit;
  final DetailItem total;

  PosHostDetails({
    required this.credit,
    required this.debit,
    required this.total,
  });

  factory PosHostDetails.fromJson(Map<String, dynamic> json) {
    return PosHostDetails(
      credit: DetailItem.fromJson(json['credit'] as Map<String, dynamic>),
      debit: DetailItem.fromJson(json['debit'] as Map<String, dynamic>),
      total: DetailItem.fromJson(json['total'] as Map<String, dynamic>),
    );
  }

}
