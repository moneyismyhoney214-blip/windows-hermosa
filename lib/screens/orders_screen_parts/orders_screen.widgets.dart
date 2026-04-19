// ignore_for_file: invalid_use_of_protected_member, unused_element, unused_element_parameter, dead_code, dead_null_aware_expression
part of '../orders_screen.dart';

extension OrdersScreenWidgets on _OrdersScreenState {
  Widget _buildHeader() {
    final width = MediaQuery.sizeOf(context).width;
    final isCompact = width < 900;
    final searchWidth = (width * 0.25).clamp(180.0, 280.0).toDouble();

    final searchField = TextField(
      controller: _searchController,
      onChanged: (_) {
        _syncSearchQueryFromInput(normalizeController: true);
        _searchDebounce?.cancel();
        _searchDebounce = Timer(const Duration(milliseconds: 400), () {
          if (mounted) {
            setState(() {});
            _loadData();
          }
        });
      },
      onSubmitted: (value) {
        _syncSearchQueryFromInput(normalizeController: true);
        _loadData();
      },
      decoration: InputDecoration(
        hintText: _tr(
          'بحث برقم الطلب (مثال: #258469)',
          'Search by order ID (e.g. #258469)',
        ),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        prefixIcon: const Icon(Icons.search, size: 18),
        suffixIcon: _searchController.text.isNotEmpty
            ? IconButton(
                onPressed: () {
                  _searchController.clear();
                  _searchQuery = '';
                  _loadData();
                },
                icon: const Icon(Icons.clear, size: 18),
              )
            : null,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );

    return Container(
      padding:
          EdgeInsets.symmetric(horizontal: isCompact ? 12 : 16, vertical: 12),
      decoration: BoxDecoration(
        color: context.appCardBg,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: isCompact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: widget.onBack,
                      icon: const Icon(LucideIcons.chevronRight, size: 24),
                      color: const Color(0xFFF58220),
                    ),
                    Expanded(
                      child: Text(
                        translationService.t('orders'),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _loadData,
                      icon: const Icon(Icons.refresh),
                      tooltip:
                          '${translationService.t('search')} ($_rawResponsesTrackedCount)',
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                searchField,
              ],
            )
          : Row(
              children: [
                TextButton.icon(
                  onPressed: widget.onBack,
                  icon: const Icon(LucideIcons.chevronRight, size: 28),
                  label: Text(
                    translationService.t('back'),
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFF58220),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                  ),
                ),
                const Spacer(),
                Text(
                  translationService.t('orders'),
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const Spacer(),
                SizedBox(width: searchWidth, child: searchField),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _loadData,
                  icon: const Icon(Icons.refresh),
                  tooltip:
                      '${translationService.t('search')} ($_rawResponsesTrackedCount)',
                ),
              ],
            ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.alertCircle, size: 64, color: Colors.red.shade300),
          const SizedBox(height: 16),
          Text(
            translationService.t('error'),
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.red.shade700),
          ),
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(color: Colors.grey.shade600)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _loadData,
            icon: const Icon(LucideIcons.refreshCw),
            label: Text(translationService.t('try_again')),
          ),
        ],
      ),
    );
  }

  Widget _buildBookingsList() {
    if (_bookings.isEmpty) {
      return _buildEmptyView(translationService.t('no_orders_today'));
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        controller: _bookingScrollController,
        padding: const EdgeInsets.all(16),
        itemCount: _bookings.length + (_hasMoreBookings ? 1 : 0),
        // PERF: item keys keep widget identity stable across list updates;
        // RepaintBoundary isolates each card so a rebuild of one card doesn't
        // repaint all the others.
        itemBuilder: (context, index) {
          if (index >= _bookings.length) {
            return const Padding(
              key: ValueKey('orders_loader'),
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: CircularProgressIndicator(),
              ),
            );
          }
          final booking = _bookings[index];
          return RepaintBoundary(
            key: ValueKey('booking_${booking.id}'),
            child: _buildCleanBookingCard(booking),
          );
        },
      ),
    );
  }

  Widget _buildCleanBookingCard(Booking booking) {
    final statusLabel = _resolveOrderStatusLabel(booking);
    final statusColor = _resolveOrderStatusColor(booking);
    final dateLabel = _formatBookingDate(booking);
    final canCreateInvoice = _canCreateInvoiceForBooking(booking);
    final canEditOrder = canCreateInvoice &&
        !isOrderLockedValue(booking.status) &&
        !isOrderLockedValue(booking.raw['status']);
    final isPaying = _payingBookingIds.contains(booking.id);

    return InkWell(
      onTap: () => _showBookingDetails(booking.id),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.appCardBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.appBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _bookingReference(booking),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: context.appText,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              dateLabel,
              style: TextStyle(color: Colors.grey.shade600),
            ),
            if (booking.customerName != null &&
                booking.customerName!.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(LucideIcons.user, size: 16, color: Colors.grey[500]),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      booking.customerName!.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                  ),
                ],
              ),
            ],
            if (booking.tableName != null &&
                booking.tableName!.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(LucideIcons.layoutGrid,
                      size: 16, color: Colors.grey[500]),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _tr('طاولة: ${booking.tableName}',
                          'Table: ${booking.tableName}'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                  ),
                ],
              ),
            ],
            const Divider(height: 24),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _tr('الإجمالي', 'Total'),
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_amountFormatter.format(_bookingGrandTotal(booking))} ${ApiConstants.currency}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFF58220),
                        ),
                      ),
                    ],
                  ),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: () => _showBookingDetails(booking.id),
                      icon: const Icon(LucideIcons.fileText, size: 16),
                      label: Text(_tr('عرض التفاصيل', 'View details')),
                      style: TextButton.styleFrom(
                        foregroundColor: context.isDark
                            ? const Color(0xFF60A5FA)
                            : const Color(0xFF2563EB),
                      ),
                    ),
                    if (canCreateInvoice)
                      OutlinedButton.icon(
                        onPressed: canEditOrder
                            ? () => _showEditOrderDialog(booking)
                            : null,
                        icon: const Icon(LucideIcons.edit3, size: 16),
                        label: Text(_tr('تعديل الطلب', 'Edit Order')),
                      ),
                  ],
                ),
              ],
            ),
            if (canCreateInvoice) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ElevatedButton.icon(
                    onPressed: isPaying
                        ? null
                        : () => _showCreateInvoiceDialog(booking),
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
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _cancelBooking(booking),
                    icon: const Icon(LucideIcons.xCircle, size: 16),
                    label: Text(_tr('إلغاء الحجز', 'Cancel Booking')),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFEF4444),
                      side: const BorderSide(color: Color(0xFFEF4444)),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _showBookingRefundDialog(booking),
                    icon: const Icon(LucideIcons.refreshCw, size: 16),
                    label: Text(_tr('استرجاع', 'Refund')),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFDC2626),
                      side: const BorderSide(color: Color(0xFFDC2626)),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
