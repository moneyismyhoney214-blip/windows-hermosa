// payment_text.dart

class PaymentText {
  final String? localizedPaymentText;
  final String? englishPaymentText;

  const PaymentText({
    required this.localizedPaymentText,
    required this.englishPaymentText,
  });

  factory PaymentText.fromJson(Map<String, dynamic> json) {
    return PaymentText(
      localizedPaymentText: json['localizedPaymentText'],
      englishPaymentText: json['englishPaymentText'],
    );
  }

  PaymentText copyWith({
    String? localizedPaymentText,
    String? englishPaymentText,
  }) {
    return PaymentText(
      localizedPaymentText: localizedPaymentText ?? this.localizedPaymentText,
      englishPaymentText: englishPaymentText ?? this.englishPaymentText,
    );
  }

  @override
  String toString() =>
      'PaymentText(localizedPaymentText: $localizedPaymentText, '
      'englishPaymentText: $englishPaymentText)';
}
