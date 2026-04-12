// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'customer.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Customer _$CustomerFromJson(Map<String, dynamic> json) => Customer(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String,
      email: json['email'] as String?,
      mobile: json['mobile'] as String?,
      countryId: (json['country_id'] as num?)?.toInt(),
      cityId: (json['city_id'] as num?)?.toInt(),
      birthdate: json['birthdate'] as String?,
      type: json['type'] as String?,
      taxNumber: json['tax_number'] as String?,
      commercialRegister: json['commercial_register'] as String?,
      zatcaPostalNumber: json['zatca_postal_number'] as String?,
      zatcaStreetName: json['zatca_street_name'] as String?,
      zatcaBuildingNumber: json['zatca_building_number'] as String?,
      zatcaPlotIdentification: json['zatca_plot_identification'] as String?,
      zatcaCitySubDivision: json['zatca_city_sub_division'] as String?,
      avatar: json['avatar'] as String?,
    );

Map<String, dynamic> _$CustomerToJson(Customer instance) => <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'email': instance.email,
      'mobile': instance.mobile,
      'country_id': instance.countryId,
      'city_id': instance.cityId,
      'birthdate': instance.birthdate,
      'type': instance.type,
      'tax_number': instance.taxNumber,
      'commercial_register': instance.commercialRegister,
      'zatca_postal_number': instance.zatcaPostalNumber,
      'zatca_street_name': instance.zatcaStreetName,
      'zatca_building_number': instance.zatcaBuildingNumber,
      'zatca_plot_identification': instance.zatcaPlotIdentification,
      'zatca_city_sub_division': instance.zatcaCitySubDivision,
      'avatar': instance.avatar,
    };
