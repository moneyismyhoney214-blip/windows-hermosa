// ignore_for_file: invalid_use_of_protected_member
//
// setState is protected on State<T>; extension methods aren't inferred as "within the subclass".
part of '../table_management_screen.dart';

// Widget builders extracted from _TableManagementScreenState (pure file split).

extension _TableManagementScreenBuilders on _TableManagementScreenState {
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
              color: Colors.red.shade700,
            ),
          ),
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(color: Colors.grey.shade600)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _loadTables,
            icon: const Icon(LucideIcons.refreshCw),
            label: Text(translationService.t('retry')),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.layers, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(translationService.t('no_data'),
              style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildTableGrid(List<TableItem> tables) {
    // Responsive grid — the prior free-positioned canvas hid tiles off-screen on resize.
    return LayoutBuilder(builder: (_, constraints) {
      final w = constraints.maxWidth;
      final double maxExtent = w < 430
          ? 120
          : w < 900
              ? 140
              : 170;
      return GridView.builder(
        padding: const EdgeInsets.all(8),
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: maxExtent,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          childAspectRatio: 1.0,
        ),
        itemCount: tables.length,
        itemBuilder: (context, index) {
          final table = tables[index];
          final isDeactivated = _deactivatedTables[table.id] ?? false;

          final pickup = _pickupByTable[table.id];
          final hasMeshOwner =
              _waiter.tableRegistry.ownerIdFor(table.id) != null;
          final waitlistHold = waitlistService.entryForTable(table.id);
          final waiterEnabled = ApiConstants.haveWaiters;
          final bookingId = _bookingIdForTable(table.id);
          final hasManageableOrder =
              bookingId != null && bookingId.trim().isNotEmpty;
          return _NormalTableCard(
            key: ValueKey('table_${table.id}'),
            table: table,
            isDeactivated: isDeactivated,
            compact: true,
            width: double.infinity,
            height: double.infinity,
            onTap: isDeactivated ? null : () => _handleTableTap(table),
            activePickup: pickup,
            onRequestPickup: (isDeactivated || !waiterEnabled)
                ? null
                : () => _requestPickup(table),
            onCancelPickup: (isDeactivated || !waiterEnabled)
                ? null
                : () => _cancelPickup(table),
            onMigrate: (isDeactivated || !waiterEnabled)
                ? null
                : () => _migrateTable(table),
            onReleaseTable: (isDeactivated || !hasMeshOwner || !waiterEnabled)
                ? null
                : () => _forceReleaseTable(table),
            onOrderDetails: (isDeactivated || !hasManageableOrder)
                ? null
                : () => _showTableOrderDetails(table, bookingId),
            onEditOrder: (isDeactivated || !hasManageableOrder || table.isPaid)
                ? null
                : () => _editTableOrder(table, bookingId),
            onRefundOrder: (isDeactivated || !hasManageableOrder)
                ? null
                : () => _refundTableBooking(table, bookingId),
            onCancelBooking:
                (isDeactivated || !hasManageableOrder || table.isPaid)
                    ? null
                    : () => _cancelTableBooking(table, bookingId),
            isTakingOrder: _takingOrderTables.contains(table.id),
            guestCount: _waiter.tableRegistry.guestCountFor(table.id),
            holdingForName: waitlistHold?.customerName,
          );
        },
      );
    });
  }

  // Tables for the active section (defaults to first so the screen is never blank).
  List<TableItem> _tablesForSelectedSection() {
    final sections = _groupBySection(_tables);
    if (sections.isEmpty) return const [];
    _selectedSectionKey ??= sections.first.key;
    final active = sections.firstWhere(
      (s) => s.key == _selectedSectionKey,
      orElse: () => sections.first,
    );
    _selectedSectionKey = active.key;
    return active.tables;
  }

  Widget _buildSectionTabBar() {
    final sections = _groupBySection(_tables);
    if (sections.length <= 1) return const SizedBox.shrink();
    final activeKey = _selectedSectionKey ?? sections.first.key;
    return Container(
      decoration: BoxDecoration(
        color: context.appCardBg,
        border: Border(
          top: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 56,
          child: Row(
            children: [
              for (final section in sections)
                Expanded(
                  child: InkWell(
                    onTap: () =>
                        setState(() => _selectedSectionKey = section.key),
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(
                            color: section.key == activeKey
                                ? const Color(0xFFF58220)
                                : Colors.transparent,
                            width: 3,
                          ),
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        section.title,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: section.key == activeKey
                              ? const Color(0xFFF58220)
                              : context.appText,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // Groups tables by category_name; "General" bucket is always present (empty-safe landing).
  List<_RestaurantTableSection> _groupBySection(List<TableItem> tables) {
    const generalKey = '__none__';
    final generalTitle = translationService.t('uncategorized_section');
    final order = <String>[generalKey];
    final byKey = <String, _RestaurantTableSection>{
      generalKey: _RestaurantTableSection(
        key: generalKey,
        title: generalTitle,
        tables: [],
      ),
    };
    for (final t in tables) {
      final raw = t.categoryName?.trim();
      final isGeneral = raw == null || raw.isEmpty;
      final key = isGeneral ? generalKey : raw;
      final title = isGeneral ? generalTitle : raw;
      final bucket = byKey.putIfAbsent(key, () {
        order.add(key);
        return _RestaurantTableSection(
            key: key, title: title, tables: []);
      });
      bucket.tables.add(t);
    }
    return [for (final k in order) byKey[k]!];
  }
}
