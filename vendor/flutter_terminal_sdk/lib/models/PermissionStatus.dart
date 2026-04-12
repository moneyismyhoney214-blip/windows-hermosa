// TODO: needs behavioral review - vendor file name kept for SDK compatibility.
// ignore_for_file: file_names
class PermissionStatus {
  final String? permission;
  final bool? isGranted;

  PermissionStatus({this.permission, this.isGranted});

  factory PermissionStatus.fromJson(dynamic json) {
    return PermissionStatus(
      permission: json['permission'],
      isGranted: json['isGranted'],
    );
  }
}
