import 'package:json_annotation/json_annotation.dart';

part 'location.g.dart';

@JsonSerializable()
class Country {
  final int id;
  final String name;
  @JsonKey(name: 'name_ar')
  final String? nameAr;
  final String? code;

  Country({
    required this.id,
    required this.name,
    this.nameAr,
    this.code,
  });

  factory Country.fromJson(Map<String, dynamic> json) => _$CountryFromJson(json);
  Map<String, dynamic> toJson() => _$CountryToJson(this);

  String get displayName => nameAr ?? name;
}

@JsonSerializable()
class City {
  final int id;
  final String name;
  @JsonKey(name: 'name_ar')
  final String? nameAr;
  @JsonKey(name: 'country_id')
  final int countryId;

  City({
    required this.id,
    required this.name,
    this.nameAr,
    required this.countryId,
  });

  factory City.fromJson(Map<String, dynamic> json) => _$CityFromJson(json);
  Map<String, dynamic> toJson() => _$CityToJson(this);

  String get displayName => nameAr ?? name;
}
