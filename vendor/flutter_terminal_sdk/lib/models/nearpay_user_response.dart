

import '../errors/errors.dart';
import '../flutter_terminal_sdk.dart';
import 'terminal_connection_response.dart';

class NearpayUser {
  final String? name;
  final String? email;
  final String? mobile;
  final String? userUUID;

  NearpayUser({
    this.name,
    this.email,
    this.mobile,
    this.userUUID,
  });

  /// Convert from JSON.
  factory NearpayUser.fromJson(Map<String, dynamic> json) {
    return NearpayUser(
      name: json['name'] as String?,
      email: json['email'] as String?,
      mobile: json['mobile'] as String?,
      userUUID: json['userUUID'] as String?,
    );
  }

  /// Convert to JSON if needed for logging/debug.
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'email': email,
      'mobile': mobile,
      'userUUID': userUUID,
    };
  }

  /// getTerminalList
  Future<List<TerminalConnectionModel>> getTerminalList(
      FlutterTerminalSdk sdk,
      ) async {
    if (userUUID == null || userUUID!.isEmpty) {
      throw NearpayException(
        "Cannot fetch terminals: userUUID is null or empty",
      );
    }
    // Delegates to the SDK method, passing this user's UUID
    return sdk.getTerminalList(userUUID!);
  }
}
