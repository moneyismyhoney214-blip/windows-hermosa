// ignore_for_file: invalid_use_of_protected_member, unused_element, unused_element_parameter, dead_code, dead_null_aware_expression, unnecessary_cast, library_private_types_in_public_api
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
        hintText: translationService.t('search_invoice_or_order'),
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
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: context.appText,
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
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: context.appText,
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
            translationService.t('invoices_load_failed'),
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
            label: Text(translationService.t('retry')),
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
          translationService.t('no_invoices_found'),
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
                            translationService.t('total'),
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
                      label: Text(translationService.t('view_details_btn')),
                      style: TextButton.styleFrom(
                        foregroundColor: context.isDark
                            ? const Color(0xFF60A5FA)
                            : const Color(0xFF2563EB),
                      ),
                    ),
                    SendInvoiceWhatsAppButton(
                      invoiceId: invoice.id.toString(),
                      customerPhone: _extractCustomerPhoneFromInvoice(invoice),
                      customerName: invoice.customerName,
                      invoiceNumber: invoice.invoiceNumber.isNotEmpty
                          ? invoice.invoiceNumber
                          : invoice.id.toString(),
                      minimumSize: const Size(0, 36),
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
                              translationService.t('fully_refunded'),
                              style: const TextStyle(
                                color: Color(0xFFDC2626),
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    PopupMenuButton<String>(
                      tooltip: translationService.t('more_label'),
                      icon: isRefunding
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(LucideIcons.moreVertical,
                              size: 20, color: context.appText),
                      onSelected: (value) {
                        if (value == 'refund') {
                          _showInvoiceRefundOptions(invoice);
                        } else if (value == 'refunds_list') {
                          _showRefundedMealsForInvoice(invoice);
                        } else if (value == 'update_date') {
                          _updateInvoiceDate(invoice);
                        }
                      },
                      itemBuilder: (context) => [
                        if (canRefund)
                          PopupMenuItem<String>(
                            value: 'refund',
                            enabled: !isRefunding,
                            child: Row(
                              children: [
                                const Icon(LucideIcons.refreshCw,
                                    size: 16, color: Color(0xFFEF4444)),
                                const SizedBox(width: 8),
                                Text(
                                  hasPartialRefund
                                      ? translationService.t('refund_more')
                                      : translationService.t('refund'),
                                  style: const TextStyle(
                                      color: Color(0xFFEF4444),
                                      fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                        PopupMenuItem<String>(
                          value: 'refunds_list',
                          child: Row(
                            children: [
                              const Icon(LucideIcons.list,
                                  size: 16, color: Color(0xFFB45309)),
                              const SizedBox(width: 8),
                              Text(
                                translationService.t('refunds_label'),
                                style: const TextStyle(
                                    color: Color(0xFFB45309),
                                    fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                        PopupMenuItem<String>(
                          value: 'update_date',
                          child: Row(
                            children: [
                              const Icon(LucideIcons.calendarClock,
                                  size: 16, color: Color(0xFF0EA5E9)),
                              const SizedBox(width: 8),
                              Text(
                                translationService.t('update_date_label'),
                                style: const TextStyle(
                                    color: Color(0xFF0EA5E9),
                                    fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ],
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
