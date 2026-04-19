// ignore_for_file: invalid_use_of_protected_member, unused_element, unused_element_parameter, dead_code, dead_null_aware_expression
part of '../orders_screen.dart';

extension OrdersScreenUtils on _OrdersScreenState {
  dynamic _extractListResponse(dynamic response) {
    if (response is List) return response;
    if (response is! Map) return [];

    if (response['data'] is List) return response['data'];
    final data = response['data'];
    if (data is Map) {
      if (data['data'] is List) return data['data'];
      if (data['items'] is List) return data['items'];
    }
    if (response['items'] is List) return response['items'];
    return [];
  }

  double _parseNum(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    final cleaned = value
        .toString()
        .replaceAll(',', '')
        .replaceAll(RegExp(r'[^0-9.\-]'), '')
        .trim();
    return double.tryParse(cleaned) ?? 0.0;
  }

  int get _rawResponsesTrackedCount =>
      _bookingsRawResponse.length +
      _orderDetailsRawResponse.length +
      _orderInvoiceRawResponse.length +
      _updateStatusRawResponse.length +
      _updateDataRawResponse.length +
      _singleWhatsAppRawResponse.length +
      _multiWhatsAppRawResponse.length;

  Widget _buildEmptyView(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.inbox, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            translationService.t('no_data'),
            style: TextStyle(
                color: Colors.grey[400],
                fontSize: 18,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: TextStyle(color: Colors.grey[500], fontSize: 14),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh),
            label: Text(translationService.t('refresh')),
          ),
        ],
      ),
    );
  }
}
