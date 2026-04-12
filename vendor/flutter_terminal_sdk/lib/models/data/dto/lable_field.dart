
class LabelField<T> {
  final T value;

  LabelField({required this.value});

  factory LabelField.fromJson(Map<String, dynamic> json) {
    return LabelField(
      value: json['value'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'value': value,
    };
  }
}