import 'package:json_annotation/json_annotation.dart';

part 'customer.g.dart';

@JsonSerializable()
class Customer {
  final int id;
  final String name;
  final String? email;
  final String? mobile;
  @JsonKey(name: 'country_id')
  final int? countryId;
  @JsonKey(name: 'city_id')
  final int? cityId;
  final String? birthdate;
  final String? type;
  @JsonKey(name: 'tax_number')
  final String? taxNumber;
  @JsonKey(name: 'commercial_register')
  final String? commercialRegister;
  @JsonKey(name: 'zatca_postal_number')
  final String? zatcaPostalNumber;
  @JsonKey(name: 'zatca_street_name')
  final String? zatcaStreetName;
  @JsonKey(name: 'zatca_building_number')
  final String? zatcaBuildingNumber;
  @JsonKey(name: 'zatca_plot_identification')
  final String? zatcaPlotIdentification;
  @JsonKey(name: 'zatca_city_sub_division')
  final String? zatcaCitySubDivision;
  final String? avatar;

  Customer({
    required this.id,
    required this.name,
    this.email,
    this.mobile,
    this.countryId,
    this.cityId,
    this.birthdate,
    this.type,
    this.taxNumber,
    this.commercialRegister,
    this.zatcaPostalNumber,
    this.zatcaStreetName,
    this.zatcaBuildingNumber,
    this.zatcaPlotIdentification,
    this.zatcaCitySubDivision,
    this.avatar,
  });

  factory Customer.fromJson(Map<String, dynamic> json) => _$CustomerFromJson(json);
  Map<String, dynamic> toJson() => _$CustomerToJson(this);
}
