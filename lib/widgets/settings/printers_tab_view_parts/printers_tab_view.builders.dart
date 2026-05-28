// Private widget builders for _PrintersTabViewState — split for size.
// ignore_for_file: use_build_context_synchronously
part of '../printers_tab_view.dart';

extension _PrintersTabViewBuilders on _PrintersTabViewState {
  Widget _buildHeaderSection(List<DeviceConfig> printers) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 900;

          final titleBlock = Row(
            children: [
              Container(
                width: compact ? 36 : 42,
                height: compact ? 36 : 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3E8),
                  borderRadius: BorderRadius.circular(compact ? 8 : 10),
                ),
                child: Icon(
                  LucideIcons.printer,
                  color: const Color(0xFFF58220),
                  size: compact ? 18 : 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _t('printers_management'),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: compact ? 16 : 18,
                    color: context.appText,
                  ),
                ),
              ),
            ],
          );

          final actions = Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _busyId == 'scan_all'
                    ? null
                    : () => unawaited(_runBulkHealthCheck(printers)),
                icon: _busyId == 'scan_all'
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(LucideIcons.refreshCw, size: compact ? 14 : 15),
                label: Text(_t('full_scan')),
                style: OutlinedButton.styleFrom(
                  padding: compact
                      ? const EdgeInsets.symmetric(horizontal: 12, vertical: 8)
                      : null,
                  foregroundColor: const Color(0xFFF58220),
                  side: const BorderSide(color: Color(0xFFF58220)),
                ),
              ),
              ElevatedButton.icon(
                onPressed: _showAddPrinterDialog,
                icon: Icon(LucideIcons.plus, size: compact ? 14 : 16),
                label: Text(_t('add_printer')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF58220),
                  foregroundColor: Colors.white,
                  padding: compact
                      ? const EdgeInsets.symmetric(horizontal: 12, vertical: 8)
                      : null,
                ),
              ),
            ],
          );

          if (compact && constraints.maxWidth < 520) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                titleBlock,
                const SizedBox(height: 12),
                actions,
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: titleBlock),
              const SizedBox(width: 12),
              actions,
            ],
          );
        },
      ),
    );
  }


  String _connectionLabel(DeviceConfig device) {
    if (device.connectionType == PrinterConnectionType.bluetooth) {
      final name = device.bluetoothName?.trim().isNotEmpty == true
          ? device.bluetoothName!.trim()
          : 'Bluetooth';
      final address = device.bluetoothAddress ?? '-';
      return '$name • $address';
    }
    return '${device.ip}:${device.port}';
  }

  Future<void> _confirmDeleteDevice(DeviceConfig device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(_t('delete_printer_title')),
        content: Text('${_t('delete_printer_confirm')} "${device.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_t('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(_t('delete')),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.onRemoveDevice(device.id);
    }
  }

  Widget _buildPrinterCard(DeviceConfig device, {required bool compact}) {
    final role = _roleRegistry.resolveRole(device);
    final isOnline = _effectiveOnline(device);
    final paperWidth = _normalizePaperWidthMm(device.paperWidthMm);
    final testBusy = _busyId == 'test_${device.id}';
    final printBusy = _busyId == 'print_${device.id}';
    final isCashierRole = role == PrinterRole.cashierReceipt || role == PrinterRole.general;
    final roleLabel = _roleLabel(role);
    final roleColor = isCashierRole ? const Color(0xFF2563EB) : const Color(0xFFF58220);
    final isKitchenRole = !isCashierRole;

    return Container(
      decoration: BoxDecoration(
        color: context.appCardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ═══ Row 1: Name + Status + Settings ═══
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: Row(
              children: [
                // Status dot
                Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(
                    color: isOnline ? const Color(0xFF16A34A) : const Color(0xFFD1D5DB),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                // Printer name
                Expanded(
                  child: Text(device.name,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF111827)),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Settings gear
                PopupMenuButton<String>(
                  tooltip: 'إعدادات',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  style: IconButton.styleFrom(padding: const EdgeInsets.all(4)),
                  icon: const Icon(LucideIcons.settings2, size: 15, color: Color(0xFF9CA3AF)),
                  onSelected: (action) {
                    switch (action) {
                      case 'role_cashier': unawaited(_updatePrinterRole(device, PrinterRole.cashierReceipt)); return;
                      case 'role_kitchen': unawaited(_updatePrinterRole(device, PrinterRole.kitchen)); return;
                      case 'paper58': unawaited(_updatePrinterPaperWidth(device, 58)); return;
                      case 'paper80': unawaited(_updatePrinterPaperWidth(device, 80)); return;
                      case 'paper88': unawaited(_updatePrinterPaperWidth(device, 88)); return;
                    }
                  },
                  itemBuilder: (_) {
                    return [
                      PopupMenuItem(value: 'role_cashier', child: Text('كاشير${isCashierRole ? ' ✓' : ''}')),
                      PopupMenuItem(
                        value: 'role_kitchen',
                        child: Text(
                            '${ApiConstants.branchModule == 'salons' ? 'أدوار' : 'مطبخ'}${isKitchenRole ? ' ✓' : ''}'),
                      ),
                      const PopupMenuDivider(),
                      PopupMenuItem(value: 'paper58', child: Text('58mm${paperWidth == 58 ? ' ✓' : ''}')),
                      PopupMenuItem(value: 'paper80', child: Text('80mm${paperWidth == 80 ? ' ✓' : ''}')),
                      PopupMenuItem(value: 'paper88', child: Text('88mm${paperWidth == 88 ? ' ✓' : ''}')),
                    ];
                  },
                ),
              ],
            ),
          ),

          // ═══ Row 2: Badges (role + paper + connection) ═══
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: Row(
              children: [
                // Role badge
                _badge(roleLabel, roleColor),
                const SizedBox(width: 6),
                // Paper badge
                _badge('${paperWidth}mm', const Color(0xFF6B7280)),
                const SizedBox(width: 6),
                // Connection type badge
                _badge(
                  device.connectionType == PrinterConnectionType.bluetooth ? 'BT' : 'WiFi',
                  device.connectionType == PrinterConnectionType.bluetooth
                      ? const Color(0xFF7C3AED) : const Color(0xFF0EA5E9),
                ),
              ],
            ),
          ),

          // ═══ Row 3: IP/Address ═══
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: Row(
              children: [
                Text(_connectionLabel(device),
                    style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF), fontFamily: 'monospace')),
              ],
            ),
          ),

          // ═══ Divider ═══
          Divider(height: 0, thickness: 1, color: context.appBorder),

          // ═══ Actions Row ═══
          SizedBox(
            height: 38,
            child: Row(
              children: [
                // Connect / Disconnect
                Expanded(
                  child: InkWell(
                    onTap: testBusy ? null : () {
                      if (isOnline) { _disconnectPrinter(device); } else { _testConnection(device); }
                    },
                    child: Center(
                      child: testBusy
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(isOnline ? 'قطع' : 'اتصال',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                                color: isOnline ? const Color(0xFF16A34A) : const Color(0xFFF58220))),
                    ),
                  ),
                ),
                _vDivider(),
                // Test print
                Expanded(
                  child: InkWell(
                    onTap: printBusy ? null : () => _testPrint(device),
                    child: Center(
                      child: printBusy
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('تجربة', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF6B7280))),
                    ),
                  ),
                ),
                // Sections (kitchen only)
                if (isKitchenRole) ...[
                  _vDivider(),
                  Expanded(
                    child: InkWell(
                      onTap: () => _showCategoryAssignmentsDialog(device),
                      child: const Center(
                        child: Text('أقسام', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF6B7280))),
                      ),
                    ),
                  ),
                ],
                _vDivider(),
                // Edit
                Expanded(
                  child: InkWell(
                    onTap: () => _showEditPrinterDialog(device),
                    child: Center(
                      child: Text(translationService.t('edit'),
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF2563EB))),
                    ),
                  ),
                ),
                _vDivider(),
                // Delete
                Expanded(
                  child: InkWell(
                    onTap: () => _confirmDeleteDevice(device),
                    child: const Center(
                      child: Text('حذف', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFEF4444))),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _badge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
    );
  }

  Widget _vDivider() {
    return Container(width: 1, height: 20, color: context.appBorder);
  }

  // Keep old reference for code that reads first icon button

  Widget _buildStatChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(
          color: color.withValues(alpha: 0.95),
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }

}
