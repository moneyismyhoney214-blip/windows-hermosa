// ignore_for_file: unused_element
part of '../orders_screen.dart';

/*
class _BookingCard extends StatelessWidget {
  final Booking booking;
  final bool isSelected;
  final bool isPaying;
  final ValueChanged<bool> onSelectionChanged;
  final VoidCallback? onViewInvoice;
  final VoidCallback? onCreateInvoice;
  final VoidCallback? onUpdateStatus;
  final VoidCallback? onSendWhatsApp;

  const _BookingCard({
    required this.booking,
    required this.isSelected,
    required this.isPaying,
    required this.onSelectionChanged,
    this.onViewInvoice,
    this.onCreateInvoice,
    this.onUpdateStatus,
    this.onSendWhatsApp,
  });

  String get _langCode =>
      translationService.currentLanguageCode.trim().toLowerCase();
  bool get _useArabicUi =>
      _langCode.startsWith('ar') || _langCode.startsWith('ur');
  String _tr(String ar, String nonArabic) => _useArabicUi ? ar : nonArabic;

  String _formatDisplayOrderNumber(Booking booking) {
    // IMPORTANT: Backend should provide daily_order_number in /bookings endpoint
    // Currently it returns null, so we fall back to booking_id
    // See: BACKEND_BOOKINGS_DAILY_ORDER_NUMBER_REQUEST.md
    final order = booking.orderNumber?.trim();
    if (order != null && order.isNotEmpty) {
      return order.startsWith('#') ? order : '#$order';
    }
    final orderId = booking.orderId;
    if (orderId != null && orderId > 0) {
      return '#$orderId';
    }
    // Fallback: Show booking_id (not ideal, but better than nothing)
    return '#${booking.id}';
  }

  bool _hasDistinctBookingReference(Booking booking) {
    final bookingRef = booking.bookingNumber?.trim();
    if (bookingRef == null || bookingRef.isEmpty) return false;

    final normalizedBooking =
        bookingRef.replaceAll(RegExp(r'[^0-9A-Za-z]'), '');
    final normalizedOrder =
        (booking.orderNumber ?? '').replaceAll(RegExp(r'[^0-9A-Za-z]'), '');

    return normalizedBooking.isNotEmpty &&
        normalizedBooking.toLowerCase() != normalizedOrder.toLowerCase();
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case '1':
      case 'pending':
      case 'confirmed':
        return const Color(0xFFF59E0B);
      case '2':
      case 'started':
        return const Color(0xFF3B82F6);
      case '3':
        return const Color(0xFF22C55E);
      case '4':
      case 'preparing':
      case 'processing':
        return const Color(0xFF3B82F6);
      case '5':
      case 'ready':
      case 'ready_for_delivery':
        return const Color(0xFF16A34A);
      case '6':
      case 'on_the_way':
      case 'out_for_delivery':
        return const Color(0xFF0EA5E9);
      case '7':
      case 'cooking':
      case 'in_kitchen':
      case 'finished':
      case 'done':
      case 'completed':
        return const Color(0xFF15803D);
      case '8':
      case 'cancelled':
      case 'canceled':
        return const Color(0xFFEF4444);
      default:
        return Colors.grey;
    }
  }

  String _resolvePreparationState(Booking booking) {
    Map<String, dynamic>? asStringMap(dynamic value) {
      if (value is Map<String, dynamic>) return value;
      if (value is Map) {
        return value.map((k, v) => MapEntry(k.toString(), v));
      }
      return null;
    }

    bool isTruthy(dynamic value) {
      if (value == null) return false;
      if (value is bool) return value;
      if (value is num) return value != 0;
      final normalized = value.toString().trim().toLowerCase();
      if (normalized.isEmpty || normalized == 'null') return false;
      return normalized == '1' ||
          normalized == 'true' ||
          normalized == 'yes' ||
          normalized == 'y' ||
          normalized == 'on' ||
          normalized == 'enabled' ||
          normalized == 'active' ||
          normalized == 'sent' ||
          normalized == 'queued';
    }

    int? parseInt(dynamic value) {
      if (value == null) return null;
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value.toString().trim());
    }

    List<Map<String, dynamic>> asMapList(dynamic value) {
      if (value is! List) return const <Map<String, dynamic>>[];
      return value
          .whereType<Map>()
          .map((row) => row.map((k, v) => MapEntry(k.toString(), v)))
          .toList();
    }

    bool matchesAny(String value, List<String> keywords) {
      for (final keyword in keywords) {
        if (value == keyword || value.contains(keyword)) {
          return true;
        }
      }
      return false;
    }

    String detectFrom(List<String> candidates) {
      for (final value in candidates) {
        if (matchesAny(value, [
          '3',
          '5',
          '6',
          'ready',
          'ready_for_delivery',
          'prepared',
          'served',
          'bumped',
          'all_bumped',
          'finished',
          'done',
          'completed',
          'تم التحضير',
          'تم التجهيز',
          'جاهز',
          'مكتمل',
        ])) {
          return 'prepared';
        }
      }

      for (final value in candidates) {
        if (matchesAny(value, [
          '2',
          'preparing',
          'processing',
          'confirmed',
          'cooking',
          'in_progress',
          'accepted',
          'queued',
          'sent_to_kitchen',
          'جاري التحضير',
          'قيد التحضير',
        ])) {
          return 'preparing';
        }
      }

      for (final value in candidates) {
        if (matchesAny(value, ['8', 'cancelled', 'canceled', 'ملغي'])) {
          return 'cancelled';
        }
      }

      for (final value in candidates) {
        if (matchesAny(value, ['1', 'new', 'pending', 'جديد'])) {
          return 'new';
        }
      }
      return '';
    }

    final orderNode = asStringMap(booking.raw['order']);
    final bookingNode = asStringMap(booking.raw['booking']);
    final orderPayloadNode = asStringMap(orderNode?['payload']);
    final bookingPayloadNode = asStringMap(bookingNode?['payload']);

    String inferFromItemProgress() {
      final itemBuckets = <Map<String, dynamic>>[
        ...asMapList(booking.raw['items']),
        ...asMapList(booking.raw['meals']),
        ...asMapList(booking.raw['card']),
        ...asMapList(booking.raw['sales_meals']),
        ...asMapList(booking.raw['booking_meals']),
        ...asMapList(orderNode?['items']),
        ...asMapList(orderNode?['meals']),
        ...asMapList(bookingNode?['items']),
        ...asMapList(bookingNode?['meals']),
      ];

      if (itemBuckets.isEmpty) return '';

      var bumpedCount = 0;
      var preparingCount = 0;

      for (final item in itemBuckets) {
        if (isTruthy(item['bumped']) ||
            isTruthy(item['is_bumped']) ||
            isTruthy(item['done']) ||
            isTruthy(item['prepared'])) {
          bumpedCount++;
          continue;
        }

        final itemStatus = (item['status'] ?? item['kitchen_status'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        if (itemStatus.isNotEmpty && detectFrom([itemStatus]) == 'prepared') {
          bumpedCount++;
          continue;
        }

        if (itemStatus.isNotEmpty && detectFrom([itemStatus]) == 'preparing') {
          preparingCount++;
        }
      }

      if (bumpedCount > 0 && bumpedCount >= itemBuckets.length) {
        return 'prepared';
      }
      if (bumpedCount > 0 || preparingCount > 0) {
        return 'preparing';
      }
      return '';
    }

    final kitchenSpecificCandidates = <String>[
      booking.raw['kitchen_status']?.toString() ?? '',
      booking.raw['preparation_status']?.toString() ?? '',
      booking.raw['kds_status']?.toString() ?? '',
      booking.raw['kitchen_state']?.toString() ?? '',
      booking.raw['kitchen_progress']?.toString() ?? '',
      booking.raw['kitchen_display_status']?.toString() ?? '',
      orderNode?['kitchen_status']?.toString() ?? '',
      orderNode?['preparation_status']?.toString() ?? '',
      orderNode?['kds_status']?.toString() ?? '',
      bookingNode?['kitchen_status']?.toString() ?? '',
      bookingNode?['preparation_status']?.toString() ?? '',
      bookingNode?['kds_status']?.toString() ?? '',
      orderPayloadNode?['kitchen_status']?.toString() ?? '',
      orderPayloadNode?['preparation_status']?.toString() ?? '',
      orderPayloadNode?['kds_status']?.toString() ?? '',
      bookingPayloadNode?['kitchen_status']?.toString() ?? '',
      bookingPayloadNode?['preparation_status']?.toString() ?? '',
      bookingPayloadNode?['kds_status']?.toString() ?? '',
    ]
        .map((value) => value.trim().toLowerCase())
        .where((value) => value.isNotEmpty)
        .toList();

    final kitchenState = detectFrom(kitchenSpecificCandidates);
    if (kitchenState.isNotEmpty) {
      return kitchenState;
    }

    final progressFromItems = inferFromItemProgress();
    if (progressFromItems.isNotEmpty) {
      return progressFromItems;
    }

    final totalItems = parseInt(
          booking.raw['items_count'] ??
              booking.raw['meals_count'] ??
              booking.raw['products_count'] ??
              orderNode?['items_count'] ??
              bookingNode?['items_count'],
        ) ??
        0;
    final bumpedItems = parseInt(
          booking.raw['bumped_items_count'] ??
              booking.raw['ready_items_count'] ??
              booking.raw['completed_items_count'] ??
              orderNode?['bumped_items_count'] ??
              bookingNode?['bumped_items_count'],
        ) ??
        0;
    if (totalItems > 0 && bumpedItems >= totalItems) {
      return 'prepared';
    }
    if (bumpedItems > 0) {
      return 'preparing';
    }

    final sentToKitchen = isTruthy(
      booking.raw['sent_to_kitchen'] ??
          booking.raw['kitchen_sent'] ??
          booking.raw['kds_sent'] ??
          booking.raw['sent_to_kds'] ??
          booking.raw['kitchen_receipt_generated'] ??
          orderNode?['sent_to_kitchen'] ??
          orderNode?['kitchen_sent'] ??
          orderNode?['kds_sent'] ??
          bookingNode?['sent_to_kitchen'] ??
          bookingNode?['kitchen_sent'] ??
          bookingNode?['kds_sent'],
    );
    final kdsEnabled = isTruthy(
      booking.raw['kds_enabled'] ??
          booking.raw['has_kds'] ??
          booking.raw['is_kds'] ??
          orderNode?['kds_enabled'] ??
          orderNode?['has_kds'] ??
          bookingNode?['kds_enabled'] ??
          bookingNode?['has_kds'],
    );
    if (sentToKitchen || kdsEnabled) {
      return 'preparing';
    }

    final genericCandidates = <String>[
      booking.raw['status_display']?.toString() ?? '',
      orderNode?['status_display']?.toString() ?? '',
      bookingNode?['status_display']?.toString() ?? '',
      booking.status,
    ]
        .map((value) => value.trim().toLowerCase())
        .where((value) => value.isNotEmpty)
        .toList();

    final genericState = detectFrom(genericCandidates);
    return genericState.isNotEmpty ? genericState : 'new';
  }

  Color _getPreparationStateColor(String preparationState) {
    switch (preparationState) {
      case 'prepared':
        return const Color(0xFF10B981);
      case 'preparing':
        return const Color(0xFF3B82F6);
      case 'cancelled':
        return const Color(0xFFEF4444);
      default:
        return const Color(0xFFF59E0B);
    }
  }

  IconData _getPreparationStateIcon(String preparationState) {
    switch (preparationState) {
      case 'prepared':
        return Icons.check_circle;
      case 'preparing':
        return Icons.restaurant;
      case 'cancelled':
        return Icons.cancel;
      default:
        return Icons.fiber_new;
    }
  }

  String _getPreparationStateLabel(String preparationState) {
    switch (preparationState) {
      case 'prepared':
        return translationService.t('booking_state_prepared');
      case 'preparing':
        return translationService.t('booking_state_preparing');
      case 'cancelled':
        return translationService.t('booking_state_cancelled');
      default:
        return translationService.t('booking_state_new');
    }
  }

  String _resolveStatusLabel(Booking booking) {
    final orderNode = booking.raw['order'] is Map
        ? (booking.raw['order'] as Map).map((k, v) => MapEntry(k.toString(), v))
        : null;
    final bookingNode = booking.raw['booking'] is Map
        ? (booking.raw['booking'] as Map)
            .map((k, v) => MapEntry(k.toString(), v))
        : null;
    final apiStatusCandidates = <String>[
      booking.raw['status_display']?.toString().trim() ?? '',
      orderNode?['status_display']?.toString().trim() ?? '',
      bookingNode?['status_display']?.toString().trim() ?? '',
    ].where((value) => value.isNotEmpty);
    if (apiStatusCandidates.isNotEmpty) {
      return apiStatusCandidates.first;
    }
    switch (booking.status.toLowerCase()) {
      case '1':
      case 'confirmed':
      case 'new':
      case 'pending':
        return _tr('حجز مؤكد', 'Confirmed');
      case '2':
      case 'started':
        return _tr('بدأ', 'Started');
      case '3':
        return _tr('انتهي', 'Ended');
      case '4':
      case 'preparing':
      case 'processing':
        return translationService.t('preparing_status');
      case '5':
      case 'ready':
      case 'ready_for_delivery':
        return _tr('جاهز للتوصيل', 'Ready for delivery');
      case '6':
      case 'on_the_way':
      case 'out_for_delivery':
        return translationService.t('on_the_way');
      case '7':
      case 'finished':
      case 'done':
      case 'completed':
        return translationService.t('completed_status');
      case '8':
      case 'cancelled':
      case 'canceled':
        return translationService.t('cancelled_status');
      default:
        return booking.status;
    }
  }

  String _effectiveStatusKey(Booking booking, String preparationState) {
    switch (preparationState) {
      case 'prepared':
        return 'ready';
      case 'preparing':
        return 'preparing';
      case 'cancelled':
        return 'cancelled';
      default:
        return booking.status.toLowerCase();
    }
  }

  String _effectiveStatusLabel(Booking booking, String preparationState) {
    switch (preparationState) {
      case 'prepared':
        return translationService.t('ready_status');
      case 'preparing':
        return translationService.t('preparing_status');
      case 'cancelled':
        return translationService.t('cancelled_status');
      default:
        return _resolveStatusLabel(booking);
    }
  }

  String _resolveTypeLabel(Booking booking) {
    final apiType = booking.raw['type_text']?.toString().trim();
    if (apiType != null && apiType.isNotEmpty) {
      return apiType;
    }
    switch (booking.type.toLowerCase()) {
      case 'restaurant_pickup':
        return translationService.t('pickup');
      case 'restaurant_internal':
      case 'restaurant_table':
        return translationService.t('dine_in');
      case 'restaurant_delivery':
        return translationService.t('delivery');
      case 'restaurant_parking':
      case 'cars':
      case 'car':
        return translationService.t('car');
      case 'services':
      case 'restaurant_services':
        return translationService.t('services_type');
      default:
        return booking.type;
    }
  }

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat('#,##0.00', _useArabicUi ? 'ar' : 'en');
    final preparationState = _resolvePreparationState(booking);
    final preparationColor = _getPreparationStateColor(preparationState);
    final preparationLabel = _getPreparationStateLabel(preparationState);
    final preparationIcon = _getPreparationStateIcon(preparationState);
    final effectiveStatusKey = _effectiveStatusKey(booking, preparationState);
    final effectiveStatusLabel =
        _effectiveStatusLabel(booking, preparationState);
    final isCompactCard = MediaQuery.sizeOf(context).width < 560;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: isSelected,
                  activeColor: const Color(0xFFF58220),
                  onChanged: (value) => onSelectionChanged(value ?? false),
                ),
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _getStatusColor(effectiveStatusKey)
                              .withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          effectiveStatusLabel,
                          style: TextStyle(
                            color: _getStatusColor(effectiveStatusKey),
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _resolveTypeLabel(booking),
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      // Show "Pay Later" badge when invoice can still be created.
                      if (onCreateInvoice != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFFF59E0B).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                LucideIcons.clock,
                                size: 12,
                                color: const Color(0xFFF59E0B),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _tr('دفع لاحقاً', 'Pay Later'),
                                style: const TextStyle(
                                  color: Color(0xFFF59E0B),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints:
                      BoxConstraints(maxWidth: isCompactCard ? 92 : 140),
                  child: Text(
                    _formatDisplayOrderNumber(booking),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (booking.tableName != null)
              Row(
                children: [
                  Icon(LucideIcons.layoutGrid,
                      size: 16, color: Colors.grey.shade500),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      _tr('طاولة: ${booking.tableName}',
                          'Table: ${booking.tableName}'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ),
                ],
              ),
            const Divider(height: 24),
            LayoutBuilder(
              builder: (context, constraints) {
                final stacked = constraints.maxWidth < 430;
                final totalSection = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _tr('الإجمالي', 'Total'),
                      style:
                          TextStyle(color: Colors.grey.shade500, fontSize: 12),
                    ),
                    Text(
                      '${formatter.format(booking.total)} ${ApiConstants.currency}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFF58220),
                      ),
                    ),
                  ],
                );
                final stateChip = Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: preparationColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(preparationIcon, color: preparationColor, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        preparationLabel,
                        style: TextStyle(
                          color: preparationColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                );

                if (!stacked) {
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [totalSection, stateChip],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    totalSection,
                    const SizedBox(height: 8),
                    Align(alignment: Alignment.centerRight, child: stateChip),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            // Calculate order types for button visibility
            // Show "Create Invoice" button only for:
            // 1. Pay Later orders (type = 'later' or 'postpaid' and not paid)
            Builder(
              builder: (context) {
                final bool isPayLaterOrder = onCreateInvoice != null;

                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (isPayLaterOrder)
                      ElevatedButton.icon(
                        onPressed: isPaying ? null : onCreateInvoice,
                        icon: isPaying
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.receipt, size: 16),
                        label: Text(
                          isPaying
                              ? _tr('جارٍ الإنشاء...', 'Creating...')
                              : _tr('إنشاء فاتورة', 'Create Invoice'),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              const Color(0xFF10B981), // Green for pay later
                          foregroundColor: Colors.white,
                        ),
                      ),
                    // Show "View Invoice" button for paid orders or orders with order_id
                    if (booking.isPaid || booking.orderId != null)
                      OutlinedButton.icon(
                        onPressed: onViewInvoice,
                        icon: const Icon(Icons.receipt_long, size: 16),
                        label: Text(_tr('الفاتورة', 'Invoice')),
                      ),
                    OutlinedButton.icon(
                      onPressed: onUpdateStatus,
                      icon: const Icon(Icons.sync_alt, size: 16),
                      label: Text(_tr('تحديث الحالة', 'Update Status')),
                    ),
                    OutlinedButton.icon(
                      onPressed: onSendWhatsApp,
                      icon: const Icon(LucideIcons.messageCircle, size: 16),
                      label: Text(translationService.t('whatsapp')),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF16A34A),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
*/
