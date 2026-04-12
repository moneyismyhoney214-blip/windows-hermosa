
import '../errors/errors.dart';
import '../flutter_terminal_sdk.dart';
import 'data/terminal_merchant.dart';
import 'terminal_response.dart';

class TerminalConnectionModel {
  final String? name;
  final String tid;
  final String uuid;
  final bool busy;
  final String mode;
  final bool isLocked;
  final bool hasProfile;
  final String userUUID;
  final String? client;
  final TerminalMerchant? merchant;

  TerminalConnectionModel({
    this.name,
    required this.tid,
    required this.uuid,
    required this.busy,
    required this.mode,
    required this.isLocked,
    required this.hasProfile,
    required this.userUUID,
    this.client,
    this.merchant,
  });

  factory TerminalConnectionModel.fromJson(Map<String, dynamic> json) {
    return TerminalConnectionModel(
      name: json['name'] as String?,
      tid: json['tid'] as String,
      uuid: json['uuid'] as String,
      busy: json['busy'] as bool? ?? false,
      mode: json['mode'] as String,
      isLocked: json['isLocked'] as bool? ?? false,
      hasProfile: json['hasProfile'] as bool? ?? false,
      userUUID: json['userUUID'] as String,
      client: json['client'],
      merchant: json['merchant'] != null
          ? TerminalMerchant.fromJson(json['merchant'] as Map<String, dynamic>)
          : null,
    );
  }

  /// connectTerminal
  Future<TerminalModel> connect(FlutterTerminalSdk sdk) async {
    if (userUUID.isEmpty) {
      throw NearpayException('User UUID is missing');
    }
    if (tid.isEmpty) {
      throw NearpayException('Terminal TID is missing');
    }

    return sdk.connectTerminal(
        tid: tid, userUUID: userUUID, terminalUUID: uuid);
  }
}
