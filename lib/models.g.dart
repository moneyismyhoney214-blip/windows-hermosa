// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Extra _$ExtraFromJson(Map<String, dynamic> json) => Extra(
      id: json['id'] as String,
      name: json['name'] as String,
      price: (json['price'] as num).toDouble(),
    );

Map<String, dynamic> _$ExtraToJson(Extra instance) => <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'price': instance.price,
    };

Product _$ProductFromJson(Map<String, dynamic> json) => Product(
      id: json['id'] as String,
      name: json['name'] as String,
      nameAr: json['nameAr'] as String? ?? '',
      nameEn: json['nameEn'] as String? ?? '',
      price: (json['unit_price'] as num).toDouble(),
      category: json['category_name'] as String,
      categoryId: json['category_id'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      image: json['image'] as String?,
      extras: (json['extras'] as List<dynamic>?)
              ?.map((e) => Extra.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );

Map<String, dynamic> _$ProductToJson(Product instance) => <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'nameAr': instance.nameAr,
      'nameEn': instance.nameEn,
      'unit_price': instance.price,
      'category_name': instance.category,
      'category_id': instance.categoryId,
      'is_active': instance.isActive,
      'image': instance.image,
      'extras': instance.extras,
    };

CartItem _$CartItemFromJson(Map<String, dynamic> json) => CartItem(
      cartId: json['cartId'] as String,
      product: Product.fromJson(json['product'] as Map<String, dynamic>),
      quantity: (json['quantity'] as num?)?.toDouble() ?? 1.0,
      selectedExtras: (json['selectedExtras'] as List<dynamic>?)
              ?.map((e) => Extra.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      discount: (json['discount'] as num?)?.toDouble() ?? 0.0,
      discountType:
          $enumDecodeNullable(_$DiscountTypeEnumMap, json['discountType']) ??
              DiscountType.amount,
      isFree: json['isFree'] as bool? ?? false,
      notes: json['notes'] as String? ?? '',
    );

Map<String, dynamic> _$CartItemToJson(CartItem instance) => <String, dynamic>{
      'cartId': instance.cartId,
      'product': instance.product,
      'quantity': instance.quantity,
      'selectedExtras': instance.selectedExtras,
      'discount': instance.discount,
      'discountType': _$DiscountTypeEnumMap[instance.discountType]!,
      'isFree': instance.isFree,
      'notes': instance.notes,
    };

const _$DiscountTypeEnumMap = {
  DiscountType.amount: 'amount',
  DiscountType.percentage: 'percentage',
};

CategoryModel _$CategoryModelFromJson(Map<String, dynamic> json) =>
    CategoryModel(
      id: json['id'] as String,
      name: json['name'] as String,
      type: json['type'] as String?,
      parentId: json['parent_id'] as String?,
      imageUrl: json['icon'] as String?,
    );

Map<String, dynamic> _$CategoryModelToJson(CategoryModel instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'type': instance.type,
      'parent_id': instance.parentId,
      'icon': instance.imageUrl,
    };

DeviceConfig _$DeviceConfigFromJson(Map<String, dynamic> json) => DeviceConfig(
      id: json['id'] as String,
      name: json['name'] as String,
      ip: json['ip'] as String,
      port: json['port'] as String? ?? '9100',
      type: json['type'] as String,
      model: json['model'] as String,
      connectionType: $enumDecodeNullable(
              _$PrinterConnectionTypeEnumMap, json['connectionType']) ??
          PrinterConnectionType.wifi,
      bluetoothAddress: json['bluetoothAddress'] as String?,
      bluetoothName: json['bluetoothName'] as String?,
      isOnline: json['isOnline'] as bool? ?? false,
      copies: (json['copies'] as num?)?.toInt() ?? 1,
      paperWidthMm: (json['paperWidthMm'] as num?)?.toInt() ?? 58,
    );

Map<String, dynamic> _$DeviceConfigToJson(DeviceConfig instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'ip': instance.ip,
      'port': instance.port,
      'type': instance.type,
      'model': instance.model,
      'connectionType':
          _$PrinterConnectionTypeEnumMap[instance.connectionType]!,
      'bluetoothAddress': instance.bluetoothAddress,
      'bluetoothName': instance.bluetoothName,
      'isOnline': instance.isOnline,
      'copies': instance.copies,
      'paperWidthMm': instance.paperWidthMm,
    };

const _$PrinterConnectionTypeEnumMap = {
  PrinterConnectionType.wifi: 'wifi',
  PrinterConnectionType.bluetooth: 'bluetooth',
};

TableItem _$TableItemFromJson(Map<String, dynamic> json) => TableItem(
      id: json['id'] as String,
      number: json['name'] as String,
      floorId: json['floor_id'] as String? ?? 'f1',
      seats: (json['seats'] as num?)?.toInt() ?? 4,
      status: $enumDecodeNullable(_$TableStatusEnumMap, json['status']) ??
          TableStatus.available,
      occupiedMinutes: (json['occupied_minutes'] as num?)?.toInt() ?? 0,
      waiterName: json['waiter_name'] as String?,
      isPaid: json['isPaid'] as bool? ?? false,
      qrImage: json['qr_image'] as String?,
      isActive: json['is_active'] as bool? ?? true,
    );

Map<String, dynamic> _$TableItemToJson(TableItem instance) => <String, dynamic>{
      'id': instance.id,
      'name': instance.number,
      'floor_id': instance.floorId,
      'seats': instance.seats,
      'status': _$TableStatusEnumMap[instance.status]!,
      'occupied_minutes': instance.occupiedMinutes,
      'waiter_name': instance.waiterName,
      'isPaid': instance.isPaid,
      'qr_image': instance.qrImage,
      'is_active': instance.isActive,
    };

const _$TableStatusEnumMap = {
  TableStatus.available: 'available',
  TableStatus.occupied: 'occupied',
  TableStatus.printed: 'printed',
};

PromoCode _$PromoCodeFromJson(Map<String, dynamic> json) => PromoCode(
      id: json['id'] as String,
      code: json['code'] as String,
      discount: (json['discount'] as num).toDouble(),
      type: $enumDecode(_$DiscountTypeEnumMap, json['discount_type']),
      maxDiscount: (json['maxDiscount'] as num?)?.toDouble(),
      maxDiscountDisplay: json['maxDiscountDisplay'] as String?,
      minPay: (json['minPay'] as num?)?.toDouble(),
      minPayDisplay: json['minPayDisplay'] as String?,
      durationFrom: json['durationFrom'] as String?,
      durationTo: json['durationTo'] as String?,
      maxUse: (json['maxUse'] as num?)?.toInt(),
      isActive: json['isActive'] as bool? ?? true,
    );

Map<String, dynamic> _$PromoCodeToJson(PromoCode instance) => <String, dynamic>{
      'id': instance.id,
      'code': instance.code,
      'discount': instance.discount,
      'discount_type': _$DiscountTypeEnumMap[instance.type]!,
      'maxDiscount': instance.maxDiscount,
      'maxDiscountDisplay': instance.maxDiscountDisplay,
      'minPay': instance.minPay,
      'minPayDisplay': instance.minPayDisplay,
      'durationFrom': instance.durationFrom,
      'durationTo': instance.durationTo,
      'maxUse': instance.maxUse,
      'isActive': instance.isActive,
    };
