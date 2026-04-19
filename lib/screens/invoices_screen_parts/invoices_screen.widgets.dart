// ignore_for_file: invalid_use_of_protected_member, unused_element, unused_element_parameter, dead_code, dead_null_aware_expression, unnecessary_cast
part of '../invoices_screen.dart';

extension InvoicesScreenWidgets on _InvoicesScreenState {
  Widget _buildHeader() {
    final width = MediaQuery.sizeOf(context).width;
    final isCompact = width < 900;
    final searchWidth = (width * 0.25).clamp(180.0, 280.0).toDouble();

    final searchField = TextField(
      controller: _searchController,
      onChanged: (value) => setState(() => _searchQuery = value.trim()),
      onSubmitted: (_) => _loadInvoices(reset: true),
      decoration: InputDecoration(
        hintText: _tr(
          'بحث برقم الفاتورة أو رقم الطلب',
          'Search by invoice or order number',
        ),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        prefixIcon: const Icon(Icons.search, size: 18),
        suffixIcon: _searchController.text.isNotEmpty
            ? IconButton(
                onPressed: () {
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                  _loadInvoices(reset: true);
                },
                icon: const Icon(Icons.clear, size: 18),
              )
            : null,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );

    final headerContent = isCompact
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
                      translationService.t('invoices'),
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
                    onPressed: () => _loadInvoices(reset: true),
                    icon: const Icon(Icons.refresh),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
              const Spacer(),
              Text(
                translationService.t('invoices'),
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
                onPressed: () => _loadInvoices(reset: true),
                icon: const Icon(Icons.refresh),
              ),
            ],
          );

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 12 : 16,
        vertical: 12,
      ),
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
      child: headerContent,
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.alertCircle, size: 40, color: Colors.red.shade400),
          const SizedBox(height: 8),
          Text(
            _tr('تعذر تحميل الفواتير', 'Unable to load invoices'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          if (_error != null) ...[
            const SizedBox(height: 6),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: () => _loadInvoices(reset: true),
            icon: const Icon(Icons.refresh),
            label: Text(_tr('إعادة المحاولة', 'Retry')),
          ),
        ],
      ),
    );
  }

  Widget _buildInvoicesList() {
    final query = _searchQuery.trim();
    final displayItems = query.isEmpty
        ? _invoices
        : _invoices.where((item) => _invoiceMatchesSearch(item, query)).toList();

    if (displayItems.isEmpty) {
      return Center(
        child: Text(
          _tr('لا توجد فواتير', 'No invoices found'),
          style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadInvoices(reset: true),
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        itemCount: displayItems.length + (_hasMore ? 1 : 0),
        // PERF: keys + RepaintBoundary isolate each invoice card so a single
        // row update never repaints every other card in the list.
        itemBuilder: (context, index) {
          if (index >= displayItems.length) {
            return const Padding(
              key: ValueKey('invoices_loader'),
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: CircularProgressIndicator(),
              ),
            );
          }

          final invoice = displayItems[index];
          final statusLabel = invoice.statusDisplay.trim();
          final showStatusBadge =
              statusLabel.isNotEmpty && statusLabel.toLowerCase() != 'null';
          final statusColor = _statusColor(statusLabel);
          final isFullyRefunded = _isInvoiceFullyRefunded(invoice);
          final hasPartialRefund = _hasPartialRefund(invoice);
          final isRefunding = _refundingInvoiceIds.contains(invoice.id);
          final isPaid = _isInvoicePaid(invoice);
          final canRefund = (isPaid || hasPartialRefund) && !isFullyRefunded;
          final orderId = _resolveOrderIdFromInvoice(invoice);
          final rawOrderStatus = (invoice.raw['order_status']?.toString() ??
                  invoice.raw['status']?.toString() ??
                  '')
              .trim();
          final isCancelled =
              _normalizeStatusToApiValue(rawOrderStatus) == 8 ||
                  rawOrderStatus == 'ملغي' ||
                  rawOrderStatus.toLowerCase() == 'cancelled' ||
                  rawOrderStatus.toLowerCase() == 'canceled';
          final canOrderActions = invoice.id > 0 && !isCancelled;
          final totalValue = invoice.grandTotal > 0
              ? invoice.grandTotal
              : (invoice.total > 0 ? invoice.total : invoice.paid);

          return RepaintBoundary(
            key: ValueKey('invoice_${invoice.id}'),
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
                      child: _buildInvoiceHeaderIds(invoice),
                    ),
                    if (showStatusBadge)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          invoice.statusDisplay,
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
                  _formatInvoiceDate(invoice),
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                if (invoice.customerName != null &&
                    invoice.customerName!.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(LucideIcons.user, size: 16, color: Colors.grey[500]),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          invoice.customerName!.trim(),
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
                            '${_amountFormatter.format(totalValue)} ${ApiConstants.currency}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFF58220),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: () => _showBookingDetailsForInvoice(invoice),
                      icon: const Icon(LucideIcons.fileText, size: 16),
                      label: Text(_tr('عرض التفاصيل', 'View details')),
                      style: TextButton.styleFrom(
                        foregroundColor: context.isDark
                            ? const Color(0xFF60A5FA)
                            : const Color(0xFF2563EB),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _openInvoicePreview(invoice),
                      icon: const Icon(LucideIcons.eye, size: 16),
                      label: Text(_tr('معاينة الفاتورة', 'Invoice preview')),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF0EA5E9),
                        side: const BorderSide(color: Color(0xFF0EA5E9)),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: canOrderActions && !_isSendingWhatsApp
                          ? () async {
                              final resolvedOrderId =
                                  orderId ?? await _resolveOrderIdForInvoiceAsync(invoice);
                              if (resolvedOrderId == null || resolvedOrderId <= 0) {
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(_tr(
                                      'تعذر تحديد رقم الطلب لهذه الفاتورة',
                                      'Unable to resolve order for this invoice',
                                    )),
                                  ),
                                );
                                return;
                              }
                              await _sendWhatsAppForOrder(
                                orderId: resolvedOrderId,
                                orderLabel: _formatInvoiceNumber(invoice),
                              );
                            }
                          : null,
                      icon: const Icon(LucideIcons.messageCircle, size: 16),
                      label: Text(_tr('واتساب', 'WhatsApp')),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF16A34A),
                        side: const BorderSide(color: Color(0xFF16A34A)),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: canOrderActions
                          ? () async {
                              final resolvedOrderId =
                                  orderId ?? await _resolveOrderIdForInvoiceAsync(invoice);
                              if (resolvedOrderId == null || resolvedOrderId <= 0) {
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(_tr(
                                      'تعذر تحديد رقم الطلب لهذه الفاتورة',
                                      'Unable to resolve order for this invoice',
                                    )),
                                  ),
                                );
                                return;
                              }
                              await _showUpdateStatusDialogForOrder(
                                orderId: resolvedOrderId,
                                orderLabel: _formatInvoiceNumber(invoice),
                                currentStatus:
                                    invoice.raw['order_status']?.toString() ??
                                        invoice.raw['status']?.toString() ??
                                        '1',
                              );
                            }
                          : null,
                      icon: const Icon(LucideIcons.edit, size: 16),
                      label: Text(_tr('تغيير الحالة', 'Change status')),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF0EA5E9),
                        side: const BorderSide(color: Color(0xFF0EA5E9)),
                      ),
                    ),
                    if (canRefund)
                      OutlinedButton.icon(
                        onPressed: isRefunding
                            ? null
                            : () => _showInvoiceRefundOptions(invoice),
                        icon: isRefunding
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(LucideIcons.refreshCw, size: 16),
                        label: Text(
                          hasPartialRefund
                              ? _tr('استرجاع إضافي', 'Refund More')
                              : _tr('استرجاع', 'Refund'),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFEF4444),
                          side: const BorderSide(color: Color(0xFFEF4444)),
                        ),
                      ),
                    if (isFullyRefunded)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEE2E2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(LucideIcons.checkCircle,
                                size: 14, color: Color(0xFFDC2626)),
                            const SizedBox(width: 4),
                            Text(
                              _tr('مسترجع بالكامل', 'Fully Refunded'),
                              style: const TextStyle(
                                color: Color(0xFFDC2626),
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    OutlinedButton.icon(
                      onPressed: () => _showRefundedMealsForInvoice(invoice),
                      icon: const Icon(LucideIcons.list, size: 16),
                      label: Text(_tr('المرتجعات', 'Refunds')),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFB45309),
                        side: const BorderSide(color: Color(0xFFB45309)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          );
        },
      ),
    );
  }
}
