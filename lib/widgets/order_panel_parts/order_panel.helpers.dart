// ignore_for_file: invalid_use_of_protected_member, unused_element, unused_element_parameter, dead_code, dead_null_aware_expression, unnecessary_cast
part of '../order_panel.dart';

extension OrderPanelHelpers on _OrderPanelState {
  bool get _useArabicUi {
    final code = translationService.currentLanguageCode.trim().toLowerCase();
    return code.startsWith('ar') || code.startsWith('ur');
  }

  String _tr(String ar, String en) {
    return _useArabicUi ? ar : en;
  }

  String _canonicalOrderTypeValue(String value) {
    final normalized = value.trim().toLowerCase();
    switch (normalized) {
      case 'pickup':
      case 'takeaway':
      case 'take_away':
      case 'restaurant_takeaway':
      case 'restaurant_take_away':
      case 'restaurant_pickup':
        return 'restaurant_pickup';
      case 'dine_in':
      case 'dinein':
      case 'internal':
      case 'inside':
      case 'table':
      case 'restaurant_table':
      case 'restaurant_internal':
        return 'restaurant_internal';
      case 'delivery':
      case 'home_delivery':
      case 'restaurant_home_delivery':
      case 'restaurant_delivery':
        return 'restaurant_delivery';
      case 'parking':
      case 'restaurant_parking':
      case 'drive_through':
      case 'drive-through':
      case 'cars':
      case 'car':
        return 'cars';
      case 'service':
      case 'services':
      case 'restaurant_services':
        return 'services';
      default:
        return normalized;
    }
  }

  String _orderTypeLabel(Map<String, dynamic> option) {
    final fallback = option['label']?.toString() ?? '';
    switch (_canonicalOrderTypeValue(option['value']?.toString() ?? '')) {
      case 'restaurant_pickup':
        return _tr('سفري', 'Pickup');
      case 'restaurant_internal':
        return _tr('داخل المطعم', 'Dine In');
      case 'restaurant_delivery':
        return _tr('توصيل', 'Delivery');
      case 'cars':
        return _tr('سيارة', 'Car');
      case 'services':
        return _tr('محلي', 'Local');
      default:
        return fallback;
    }
  }

  bool get _isCarOrderType {
    final selected = _canonicalOrderTypeValue(widget.selectedOrderType);
    if (selected == 'cars') {
      return true;
    }

    final matched = widget.typeOptions.cast<Map<String, dynamic>?>().firstWhere(
          (t) => t?['value']?.toString() == widget.selectedOrderType,
          orElse: () => null,
        );
    final label = matched?['label']?.toString().toLowerCase() ?? '';
    return label.contains('سيار') || label.contains('car');
  }

}
