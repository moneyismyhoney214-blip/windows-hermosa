import 'dart:convert';

class OtpResponse {

  final String? message;

  OtpResponse({this.message});

  factory OtpResponse.fromJson(Map<String, dynamic> json) {
    return OtpResponse(message: json['message']);
  }

  String toJson() => json.encode({"message": message});
}