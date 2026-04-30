/// Profile data model representing user profile information from API
class ProfileData {
  final int id;
  final int countryId;
  final int cityId;
  final FullName fullname;
  final String? avatar;
  final String? birthdate;
  final String email;
  final String? mobile;
  final String? ip;
  final bool isVerified;
  final String? namiPort;
  final String? namiWithIp;
  final List<dynamic>? parents;
  final List<dynamic> pays;
  final String? port;
  final bool portStatus;
  final bool portStatusNami;
  final String role;
  final String roleDisplay;
  final String serialBaudRate;
  final String? serialPort;
  final String today;

  ProfileData({
    required this.id,
    required this.countryId,
    required this.cityId,
    required this.fullname,
    this.avatar,
    this.birthdate,
    required this.email,
    this.mobile,
    this.ip,
    required this.isVerified,
    this.namiPort,
    this.namiWithIp,
    this.parents,
    required this.pays,
    this.port,
    required this.portStatus,
    required this.portStatusNami,
    required this.role,
    required this.roleDisplay,
    required this.serialBaudRate,
    this.serialPort,
    required this.today,
  });

  factory ProfileData.fromJson(Map<String, dynamic> json) {
    int toInt(dynamic value, {int fallback = 0}) {
      if (value == null) return fallback;
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value) ?? fallback;
      return fallback;
    }

    String toStr(dynamic value, {String fallback = ''}) {
      if (value == null) return fallback;
      if (value is String) return value;
      if (value is num || value is bool) return value.toString();
      if (value is Map) {
        dynamic firstValue;
        if (value.values.isNotEmpty) {
          firstValue = value.values.first;
        }
        final candidate = value['ar'] ??
            value['en'] ??
            value['name'] ??
            value['value'] ??
            firstValue;
        return candidate?.toString() ?? fallback;
      }
      return fallback;
    }

    String? toNullableStr(dynamic value) {
      if (value == null) return null;
      final s = toStr(value, fallback: '');
      return s.isEmpty ? null : s;
    }

    FullName parseFullName(dynamic value) {
      if (value is Map<String, dynamic>) {
        return FullName.fromJson(value);
      }
      if (value is Map) {
        return FullName.fromJson(
            value.map((k, v) => MapEntry(k.toString(), v)));
      }
      final text = toStr(value, fallback: '');
      return FullName(ar: text, en: text);
    }

    bool toBool(dynamic value, {bool fallback = false}) {
      if (value == null) return fallback;
      if (value is bool) return value;
      if (value is num) return value != 0;
      if (value is String) {
        final v = value.trim().toLowerCase();
        if (['1', 'true', 'yes', 'on', 'active'].contains(v)) return true;
        if (['0', 'false', 'no', 'off', 'inactive'].contains(v)) return false;
        return fallback;
      }
      if (value is Map) {
        final candidate = value['value'] ??
            value['status'] ??
            value['is_active'] ??
            value['active'];
        return toBool(candidate, fallback: fallback);
      }
      return fallback;
    }

    return ProfileData(
      id: toInt(json['id']),
      countryId: toInt(json['country_id']),
      cityId: toInt(json['city_id']),
      fullname: parseFullName(json['fullname']),
      avatar: toNullableStr(json['avatar']),
      birthdate: toNullableStr(json['birthdate']),
      email: toStr(json['email']),
      mobile: toNullableStr(json['mobile']),
      ip: toNullableStr(json['ip']),
      isVerified: toBool(json['is_verified']),
      namiPort: toNullableStr(json['nami_port']),
      namiWithIp: toNullableStr(json['nami_with_ip']),
      parents:
          json['parents'] is List ? json['parents'] as List<dynamic> : null,
      pays: json['pays'] is List ? json['pays'] as List<dynamic> : const [],
      port: toNullableStr(json['port']),
      portStatus: toBool(json['port_status']),
      portStatusNami: toBool(json['port_status_nami']),
      role: toStr(json['role']),
      roleDisplay: toStr(json['role_display']),
      serialBaudRate: toStr(json['serial_baud_rate'], fallback: '0'),
      serialPort: toNullableStr(json['serial_port']),
      today: toStr(json['today']),
    );
  }

  String getAvatarUrl() {
    if (avatar == null || avatar!.isEmpty) return '';
    return 'https://portal.hermosaapp.com$avatar';
  }
}

class FullName {
  final String ar;
  final String en;

  FullName({
    required this.ar,
    required this.en,
  });

  factory FullName.fromJson(Map<String, dynamic> json) {
    String toStr(dynamic value) {
      if (value == null) return '';
      if (value is String) return value;
      if (value is num || value is bool) return value.toString();
      return '';
    }

    return FullName(
      ar: toStr(json['ar']),
      en: toStr(json['en']),
    );
  }
}
