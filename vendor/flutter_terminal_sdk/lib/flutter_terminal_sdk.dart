// lib/flutter_terminal_sdk.dart

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'errors/errors.dart';
import 'models/PermissionStatus.dart';
import 'models/data/ui_dock_position.dart';
import 'models/nearpay_user_response.dart';
import 'models/send_otp_response.dart';
import 'models/terminal_connection_response.dart';
import 'models/terminal_response.dart';
import 'models/terminal_sdk_initialization_listener.dart';

/// Enumerations for environment/country
enum Environment { sandbox, production, internal }

enum Country { sa, tr, usa }

enum SupportSecondDisplay { enable, disable, initial }

class FlutterTerminalSdk {
  static final FlutterTerminalSdk _instance = FlutterTerminalSdk._internal();
  late TerminalSDKInitializationListener initializationListener;

  factory FlutterTerminalSdk() {
    return _instance;
  }

  FlutterTerminalSdk._internal()
      : _channel = const MethodChannel('nearpay_plugin') {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    debugPrint(
      "Flutter::: _handleMethodCall called with method: ${call.method}",
    );
    switch (call.method) {
      case 'onSdkInitializationFailed':
        final args = Map<String, dynamic>.from(call.arguments);
        final error = args['error'] as String?;
        initializationListener
            .onInitializationFailure!(error ?? "Unknown error");
        break;
      case 'onSdkInitialized':
        initializationListener.onInitializationSuccess!();
        break;
    }
  }

  final MethodChannel _channel;

  bool _initialized = false;

  bool get isInitialized => _initialized;

  Future<Map<String, dynamic>> _callAndReturnMapResponse(
    String methodName,
    dynamic data,
  ) async {
    if (!_initialized) {
      throw NearpayException("Cannot call $methodName before initialization");
    }
    final tempResponse = await _channel.invokeMethod(methodName, data);
    return jsonDecode(jsonEncode(tempResponse));
  }

  /// Initialize the SDK
  Future<void> initialize({
    required Environment environment,
    required int googleCloudProjectNumber,
    required String huaweiSafetyDetectApiKey,
    required Country country,
    UiDockPosition? uiDockPosition,
    UiDockPosition? secondDisplayDockPosition,
    SupportSecondDisplay? supportSecondDisplay,
    TerminalSDKInitializationListener? initializationListener,
  }) async {
    if (initializationListener != null) {
      setInitializationListener(initializationListener);
    }
    final environmentString =
        environment.name; // "sandbox" or "production" or "internal"
    final countryString = country.name; // "sa", "tr", or "usa"
    final uiDockPositionString = uiDockPosition?.name; // "sa", "tr", or "usa"
    final secondDisplayDockPositionString =
        secondDisplayDockPosition?.name; // "sa", "tr", or "usa"
    final supportSecondDisplayString = supportSecondDisplay?.name; // "enabled", "disabled", "auto"

    try {
      await _channel.invokeMethod('initialize', {
        'environment': environmentString,
        'googleCloudProjectNumber': googleCloudProjectNumber,
        'huaweiSafetyDetectApiKey': huaweiSafetyDetectApiKey,
        'country': countryString,
        'uiDockPosition': uiDockPositionString,
        'secondDisplayDockPosition': secondDisplayDockPositionString,
        'supportSecondDisplay': supportSecondDisplayString,
      });
      _initialized = true;
    } catch (e) {
      if (kDebugMode) {
        print("Flutter::: Error initializing Nearpay Terminal SDK: $e");
      }
      _initialized = false;
      throw NearpayException("Failed to initialize Nearpay Terminal SDK: $e");
    }
  }

  void setInitializationListener(TerminalSDKInitializationListener listener) {
    initializationListener = listener;
  }

  //checkRequiredPermissions
  Future<List<PermissionStatus>> checkRequiredPermissions() async {
    try {
      final response = await _channel.invokeMethod('checkRequiredPermissions');
      if (response["status"] == "success") {
        final data = response["data"];
        if (kDebugMode) {
          print("data $data");
        }
        return response["data"]
            .map<PermissionStatus>(
                (permission) => PermissionStatus.fromJson(permission))
            .toList();
      } else {
        final errorMsg = response["message"] ?? "Failed to send mobile OTP";
        throw NearpayException(errorMsg);
      }
    } catch (e) {
      throw NearpayException("Failed to check required permissions: $e");
    }
  }

  //check nfc
  Future<bool> isNfcEnabled() async {
    try {
      final response = await _channel.invokeMethod('isNfcEnabled');
      return response["data"];
    } catch (e) {
      throw NearpayException("Failed to get NFC status: $e");
    }
  }

  //check wifi
  Future<bool> isWifiEnabled() async {
    try {
      final response = await _channel.invokeMethod('isWifiEnabled');
      return response["data"];
    } catch (e) {
      throw NearpayException("Failed to get Wifi status: $e");
    }
  }

  /// Send Mobile OTP
  Future<OtpResponse> sendMobileOtp(String mobileNumber) async {
    final response = await _callAndReturnMapResponse(
      'sendMobileOtp',
      {"mobileNumber": mobileNumber},
    );

    if (response["status"] == "success") {
      final data = response["data"];
      return OtpResponse.fromJson(Map<String, dynamic>.from(data));
    } else {
      final errorMsg = response["message"] ?? "Failed to send mobile OTP";
      throw NearpayException(errorMsg);
    }
  }

  /// Send Email OTP
  Future<OtpResponse> sendEmailOtp(String email) async {
    final response = await _callAndReturnMapResponse(
      'sendEmailOtp',
      {"email": email.trim()},
    );

    if (response["status"] == "success") {
      final data = response["data"];
      return OtpResponse.fromJson(Map<String, dynamic>.from(data));
    } else {
      final errorMsg = response["message"] ?? "Failed to send email OTP";
      throw NearpayException(errorMsg);
    }
  }

  /// Verify Mobile OTP
  Future<NearpayUser> verifyMobileOtp({
    required String mobileNumber,
    required String code,
  }) async {
    final response = await _callAndReturnMapResponse(
      'verifyMobileOtp',
      {
        'mobileNumber': mobileNumber,
        'code': code,
        // 'deviceToken': deviceToken,
      },
    );

    if (response["status"] == "success") {
      final data = response["data"];
      return NearpayUser.fromJson(Map<String, dynamic>.from(data));
    } else {
      final errorMsg = response["message"] ?? "Failed to verify mobile OTP";
      throw NearpayException(errorMsg);
    }
  }

  /// Verify Email OTP
  Future<NearpayUser> verifyEmailOtp({
    required String email,
    required String code,
  }) async {
    final response = await _callAndReturnMapResponse(
      'verifyEmailOtp',
      {
        'email': email,
        'code': code,
      },
    );

    if (response["status"] == "success") {
      final data = response["data"];
      return NearpayUser.fromJson(Map<String, dynamic>.from(data));
    } else {
      final errorMsg = response["message"] ?? "Failed to verify email OTP";
      throw NearpayException(errorMsg);
    }
  }

  /// JWT Login - authenticate with a JWT token
  Future<TerminalModel> jwtLogin({
    required String jwt,
  }) async {
    final response = await _callAndReturnMapResponse(
      'jwtVerify',
      {
        'jwt': jwt,
      },
    );

    if (response["status"] == "success") {
      final data = response['data'];
      return TerminalModel.fromJson(Map<String, dynamic>.from(data));
    } else {
      final errorMsg = response["message"] ?? "Failed to JWT login";
      throw NearpayException(errorMsg);
    }
  }

  /// get User
  Future<NearpayUser> getUserByUUID({
    required String uuid,
  }) async {
    final response = await _callAndReturnMapResponse(
      'getUser',
      {
        'uuid': uuid,
      },
    );

    if (response["status"] == "success") {
      final data = response["data"];
      return NearpayUser.fromJson(Map<String, dynamic>.from(data));
    } else {
      final errorMsg = response["message"] ?? "Failed to get user";
      throw NearpayException(errorMsg);
    }
  }

  /// Documentation-compatible alias for getUserByUUID(uuid: ...).
  Future<NearpayUser> getUser({
    required String uuid,
  }) {
    return getUserByUUID(uuid: uuid);
  }

  /// get Users
  Future<List<NearpayUser>> getUsers() async {
    final response = await _callAndReturnMapResponse('getUsers', {});

    // Checking the status of the response
    if (response["status"] == "success") {
      final data = response["data"];

      // Ensure that data is a Map<String, dynamic> where each key is a user ID
      if (data is Map) {
        List<NearpayUser> userList = [];

        // Iterate through the map to create a list of NearpayUser objects
        data.forEach((key, value) {
          if (value is Map<String, dynamic>) {
            // Create a NearpayUser object from the map value (which should contain 'uuid' and 'name')
            userList
                .add(NearpayUser.fromJson(Map<String, dynamic>.from(value)));
          }
        });

        return userList;
      } else {
        throw NearpayException("Invalid data format");
      }
    } else {
      // Handle error if the response status is not "success"
      final errorMsg = response["message"] ?? "Failed to get users";
      throw NearpayException(errorMsg);
    }
  }

  /// logout
  Future<String> logout({
    String? uuid,
    String? userUUID,
  }) async {
    final resolvedUuid = uuid ?? userUUID;
    if (resolvedUuid == null || resolvedUuid.trim().isEmpty) {
      throw NearpayException("uuid is required");
    }
    final response = await _callAndReturnMapResponse(
      'logout',
      {
        'userUUID': resolvedUuid,
      },
    );

    if (response["status"] == "success") {
      return response["message"];
    } else {
      final errorMsg = response["message"] ?? "Failed to logout";
      throw NearpayException(errorMsg);
    }
  }

  /// get terminal
  Future<TerminalModel> getTerminal({
    String? terminalUUID,
    String? tid,
  }) async {
    final resolvedTerminalId = terminalUUID ?? tid;
    if (resolvedTerminalId == null || resolvedTerminalId.trim().isEmpty) {
      throw NearpayException("terminalUUID or tid is required");
    }
    final response = await _callAndReturnMapResponse(
      'getTerminal',
      {
        'terminalUUID': resolvedTerminalId,
      },
    );

    if (response["status"] == "success") {
      final data = response['data'] as Map<String, dynamic>;
      return TerminalModel.fromJson(data);
    } else {
      final errorMsg = response["message"] ?? "Failed to get user";
      throw NearpayException(errorMsg);
    }
  }

  /// getTerminalList
  Future<List<TerminalConnectionModel>> getTerminalList(
    String uuid, {
    int? page,
    int? pageSize,
    String? filter,
  }) async {
    final result = await _callAndReturnMapResponse(
      'getTerminalList',
      {
        'uuid': uuid,
        "page": page,
        "pageSize": pageSize,
        "filter": filter,
      },
    );
    final status = result['status'];
    if (status == 'success') {
      final data = result['data'] as Map<String, dynamic>;
      final terminals = data['terminals'] as List<dynamic>;
      return terminals.map((terminalJson) {
        return TerminalConnectionModel.fromJson(
          terminalJson as Map<String, dynamic>,
        );
      }).toList();
    } else {
      final message = result['message'] ?? 'Unknown error';
      throw NearpayException('Failed to retrieve terminals: $message');
    }
  }

  /// connectTerminal
  Future<TerminalModel> connectTerminal({
    required String tid,
    required String userUUID,
    required String terminalUUID,
  }) async {
    final response = await _callAndReturnMapResponse(
      'connectTerminal',
      {
        'tid': tid,
        'userUUID': userUUID,
        'terminalUUID': terminalUUID,
      },
    );

    final status = response['status'];
    if (status == 'success') {
      final data = response['data'] as Map<String, dynamic>;
      return TerminalModel.fromJson(data);
    } else {
      final message = response['message'] ?? 'Failed to connect to terminal';
      throw NearpayException(message);
    }
  }

// getPlatformVersion() {
//   return _channel.invokeMethod<String>('getPlatformVersion');
// }

  String getPlatformVersion() {
    return "42";
  }
}
