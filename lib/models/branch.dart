/// Branch model representing user branches
class Branch {
  final int id;
  final String name;
  final String district;
  final bool whatsappStatus;
  final int countDays;
  final int countryId;
  final String module;
  final int cityId;
  final bool isValid;
  final bool isBio;
  final String? sn;
  final String? deviceId;
  final String? evaluationLink;
  final String? taxNumber;
  final TaxObject taxObject;
  final bool printersSettings;
  final List<SubscriptionFeature> subscription;

  Branch({
    required this.id,
    required this.name,
    required this.district,
    required this.whatsappStatus,
    required this.countDays,
    required this.countryId,
    required this.module,
    required this.cityId,
    required this.isValid,
    required this.isBio,
    this.sn,
    this.deviceId,
    this.evaluationLink,
    this.taxNumber,
    required this.taxObject,
    required this.printersSettings,
    required this.subscription,
  });

  factory Branch.fromJson(Map<String, dynamic> json) {
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

    return Branch(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      district: json['district'] ?? '',
      whatsappStatus: toBool(json['whatsapp_status']),
      countDays: json['count_days'] ?? 0,
      countryId: json['country_id'] ?? 0,
      module: json['module'] ?? '',
      cityId: json['city_id'] ?? 0,
      isValid: toBool(json['is_valid']),
      isBio: toBool(json['is_bio']),
      sn: json['sn'],
      deviceId: json['device_id'],
      evaluationLink: json['evaluation_link'],
      taxNumber: json['tax_number'],
      taxObject: TaxObject.fromJson(json['taxObject'] ?? {}),
      printersSettings: toBool(json['printers_settings']),
      subscription: (json['subscription'] as List?)
              ?.map((e) => SubscriptionFeature.fromJson(e))
              .toList() ??
          [],
    );
  }
}

class TaxObject {
  final bool hasTax;
  final int taxPercentage;
  final int digitsNumber;
  final String currency;
  final String today;

  TaxObject({
    required this.hasTax,
    required this.taxPercentage,
    required this.digitsNumber,
    required this.currency,
    required this.today,
  });

  factory TaxObject.fromJson(Map<String, dynamic> json) {
    bool toBool(dynamic value, {bool fallback = false}) {
      if (value == null) return fallback;
      if (value is bool) return value;
      if (value is num) return value != 0;
      if (value is String) {
        final v = value.trim().toLowerCase();
        if (['1', 'true', 'yes', 'on', 'active'].contains(v)) return true;
        if (['0', 'false', 'no', 'off', 'inactive'].contains(v)) return false;
      }
      return fallback;
    }

    return TaxObject(
      hasTax: toBool(json['has_tax']),
      taxPercentage: json['tax_percentage'] ?? 0,
      digitsNumber: json['digits_number'] ?? 2,
      currency: json['currency'] ?? 'SAR',
      today: json['today'] ?? '',
    );
  }
}

class SubscriptionFeature {
  final int id;
  final String name;
  final String type;
  final String createdAt;
  final String updatedAt;
  final Pivot pivot;

  SubscriptionFeature({
    required this.id,
    required this.name,
    required this.type,
    required this.createdAt,
    required this.updatedAt,
    required this.pivot,
  });

  factory SubscriptionFeature.fromJson(Map<String, dynamic> json) {
    return SubscriptionFeature(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      type: json['type'] ?? '',
      createdAt: json['created_at'] ?? '',
      updatedAt: json['updated_at'] ?? '',
      pivot: Pivot.fromJson(json['pivot'] ?? {}),
    );
  }
}

class Pivot {
  final int planId;
  final int featureId;
  final String value;

  Pivot({
    required this.planId,
    required this.featureId,
    required this.value,
  });

  factory Pivot.fromJson(Map<String, dynamic> json) {
    return Pivot(
      planId: json['plan_id'] ?? 0,
      featureId: json['feature_id'] ?? 0,
      value: json['value']?.toString() ?? '',
    );
  }
}

/// Branches response model
class BranchesResponse {
  final List<Branch> data;
  final int status;
  final String? maintenance;
  final String? today;
  final String? message;

  BranchesResponse({
    required this.data,
    required this.status,
    this.maintenance,
    this.today,
    this.message,
  });

  factory BranchesResponse.fromJson(Map<String, dynamic> json) {
    return BranchesResponse(
      data: (json['data'] as List?)?.map((e) => Branch.fromJson(e)).toList() ??
          [],
      status: json['status'] ?? 200,
      maintenance: json['maintenance'],
      today: json['today'],
      message: json['message'],
    );
  }
}
