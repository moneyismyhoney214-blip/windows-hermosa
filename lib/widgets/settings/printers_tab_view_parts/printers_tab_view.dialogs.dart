// Auxiliary classes used by PrintersTabView — split for size.
// ignore_for_file: use_build_context_synchronously
part of '../printers_tab_view.dart';

class _AddPrinterDialog extends StatefulWidget {
  final Future<void> Function(DeviceConfig) onAdd;
  final List<DeviceConfig> existingDevices;
  final Future<BluetoothDevice?> Function() scanHelper;

  const _AddPrinterDialog({
    required this.onAdd,
    required this.existingDevices,
    required this.scanHelper,
  });

  @override
  State<_AddPrinterDialog> createState() => _AddPrinterDialogState();
}

class _AddPrinterDialogState extends State<_AddPrinterDialog> {
  final _formKey = GlobalKey<FormState>();
  String _name = '';
  String _ip = '';
  String _port = '9100';
  final String _model = 'default';
  final int _copies = 1;
  int _paperWidthMm = 58;
  bool _saving = false;
  PrinterConnectionType _connectionType = PrinterConnectionType.wifi;
  String _bluetoothAddress = '';
  // null = auto-detect by name (default), otherwise explicit
  PrinterRole? _role;

  static final TextInputFormatter _macFormatter = _MacAddressFormatter();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _scanForBluetoothDevices() async {
    final selected = await widget.scanHelper();
    if (selected != null && mounted) {
      setState(() {
        _nameController.text = selected.name ?? 'Bluetooth Printer';
        _addressController.text = selected.address;
        _name = _nameController.text;
        _bluetoothAddress = _addressController.text;
      });
    }
  }

  String _t(String key, {Map<String, dynamic>? args}) {
    return translationService.t(key, args: args);
  }

  String? _findDuplicate() {
    if (_connectionType == PrinterConnectionType.wifi) {
      final ip = _ip.trim().toLowerCase();
      final port = _port.trim().isEmpty ? '9100' : _port.trim();
      for (final d in widget.existingDevices) {
        if (d.connectionType != PrinterConnectionType.wifi) continue;
        if (d.ip.trim().toLowerCase() == ip && d.port.trim() == port) {
          return d.name;
        }
      }
    } else {
      final mac = _bluetoothAddress.trim().toUpperCase();
      if (mac.isEmpty) return null;
      for (final d in widget.existingDevices) {
        if (d.connectionType != PrinterConnectionType.bluetooth) continue;
        if ((d.bluetoothAddress?.trim().toUpperCase() ?? '') == mac) {
          return d.name;
        }
      }
    }
    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();
    if (_connectionType == PrinterConnectionType.bluetooth &&
        _bluetoothAddress.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 3),
          content: Text('يرجى إدخال عنوان MAC لطابعة البلوتوث'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Duplicate detection
    final duplicate = _findDuplicate();
    if (duplicate != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'هذه الطابعة مضافة مسبقاً باسم "$duplicate". لا يمكن إضافة نفس الطابعة مرتين.',
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }

    final resolvedBluetoothAddress = _bluetoothAddress.trim();
    final resolvedBluetoothName = _name;
    final newId = DateTime.now().millisecondsSinceEpoch.toString();
    setState(() => _saving = true);
    try {
      await widget.onAdd(
        DeviceConfig(
          id: newId,
          name: _name,
          ip: _connectionType == PrinterConnectionType.bluetooth ? '' : _ip,
          port: _port,
          type: 'printer',
          model: _model,
          connectionType: _connectionType,
          bluetoothAddress: resolvedBluetoothAddress.isEmpty
              ? null
              : resolvedBluetoothAddress,
          bluetoothName:
              resolvedBluetoothName.isEmpty ? null : resolvedBluetoothName,
          copies: _copies <= 0 ? 1 : _copies,
          paperWidthMm: normalizePaperWidthMm(_paperWidthMm),
        ),
      );
      // Save the chosen role immediately so it's applied from the start
      if (_role != null) {
        final registry = getIt<PrinterRoleRegistry>();
        await registry.initialize();
        await registry.setRole(newId, _role!);
        // Role wasn't set when `onAdd` fired the first broadcast; fire
        // again so waiters see the final role, not the inferred one.
        _notifyPrinterConfigChanged();
      }
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_t('add_printer_title')),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('WiFi'),
                        selected: _connectionType == PrinterConnectionType.wifi,
                        onSelected: (value) {
                          if (!value) return;
                          setState(() {
                            _connectionType = PrinterConnectionType.wifi;
                          });
                        },
                        selectedColor: const Color(0xFFF58220),
                        backgroundColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: const BorderSide(
                              color: Color(0xFFF58220), width: 1.5),
                        ),
                        showCheckmark: false,
                        labelStyle: TextStyle(
                          color: _connectionType == PrinterConnectionType.wifi
                              ? Colors.white
                              : const Color(0xFFF58220),
                          fontWeight: FontWeight.w600,
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                      ),
                      // BT printer support is Android-only — see
                      // BluetoothPrintBridge.kt. Hide the chip on iOS so
                      // the user can't add a printer that would never
                      // print.
                      if (Platform.isAndroid)
                        ChoiceChip(
                          label: const Text('بلوتوث'),
                          selected:
                              _connectionType == PrinterConnectionType.bluetooth,
                          onSelected: (value) {
                            if (!value) return;
                            setState(() {
                              _connectionType = PrinterConnectionType.bluetooth;
                            });
                          },
                          selectedColor: const Color(0xFFF58220),
                          backgroundColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: const BorderSide(
                                color: Color(0xFFF58220), width: 1.5),
                          ),
                          showCheckmark: false,
                          labelStyle: TextStyle(
                            color: _connectionType ==
                                    PrinterConnectionType.bluetooth
                                ? Colors.white
                                : const Color(0xFFF58220),
                            fontWeight: FontWeight.w600,
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // ── Printer Role ──
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'Printer Role',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _RoleCard(
                        label: ApiConstants.branchModule == 'salons'
                            ? 'طابعة الأدوار'
                            : 'Kitchen / KDS',
                        subtitle: ApiConstants.branchModule == 'salons'
                            ? 'تطبع تذاكر الأدوار للموظفات'
                            : 'Prints kitchen tickets',
                        icon: ApiConstants.branchModule == 'salons'
                            ? LucideIcons.scissors
                            : LucideIcons.utensils,
                        selected: _role == PrinterRole.kds,
                        onTap: () => setState(
                          () => _role =
                              _role == PrinterRole.kds ? null : PrinterRole.kds,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _RoleCard(
                        label: 'Cashier',
                        subtitle: 'Prints customer invoices',
                        icon: LucideIcons.receipt,
                        selected: _role == PrinterRole.cashierReceipt,
                        onTap: () => setState(
                          () => _role = _role == PrinterRole.cashierReceipt
                              ? null
                              : PrinterRole.cashierReceipt,
                        ),
                      ),
                    ),
                  ],
                ),
                if (_role == null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'No role selected — will be auto-detected from name',
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    ),
                  ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(labelText: _t('printer_name')),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? _t('required') : null,
                  onSaved: (v) => _name = v ?? '',
                  onChanged: (v) => _name = v,
                ),
                if (_connectionType == PrinterConnectionType.wifi)
                  TextFormField(
                    decoration: InputDecoration(labelText: _t('ip_label')),
                    validator: (v) =>
                        (v == null || v.isEmpty) ? _t('required') : null,
                    onSaved: (v) => _ip = v ?? '',
                  ),
                if (_connectionType == PrinterConnectionType.bluetooth) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _addressController,
                          decoration: const InputDecoration(
                            labelText: 'عنوان MAC للبلوتوث',
                            hintText: '00:00:00:00:00:00',
                          ),
                          style: const TextStyle(fontFamily: 'monospace'),
                          inputFormatters: [_macFormatter],
                          validator: (v) =>
                              (v == null || v.trim().isEmpty) ? _t('required') : null,
                          onSaved: (v) => _bluetoothAddress = v ?? '',
                          onChanged: (v) => _bluetoothAddress = v,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        onPressed: _scanForBluetoothDevices,
                        icon: const Icon(LucideIcons.search, size: 20),
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xFFF58220),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        tooltip: 'بحث عن طابعات قريبة',
                      ),
                    ],
                  ),
                ],
                TextFormField(
                  initialValue: _port,
                  decoration: InputDecoration(labelText: _t('port_label')),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? _t('required') : null,
                  onSaved: (v) => _port = v ?? '9100',
                ),
                DropdownButtonFormField<int>(
                  initialValue: _paperWidthMm,
                  decoration:
                      InputDecoration(labelText: _t('paper_size_label')),
                  items: const [
                    DropdownMenuItem(value: 58, child: Text('58 mm')),
                    DropdownMenuItem(value: 80, child: Text('80 mm')),
                    DropdownMenuItem(value: 88, child: Text('88 mm')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _paperWidthMm = normalizePaperWidthMm(value);
                    });
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: Text(_t('cancel')),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_t('save')),
        ),
      ],
    );
  }
}

class _RoleCard extends StatelessWidget {
  final String label;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _RoleCard({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFFF7ED) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? const Color(0xFFF58220) : const Color(0xFFE2E8F0),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color:
                  selected ? const Color(0xFFF58220) : const Color(0xFF94A3B8),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: selected
                          ? const Color(0xFFF58220)
                          : const Color(0xFF1E293B),
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MacAddressFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final raw =
        newValue.text.toUpperCase().replaceAll(RegExp(r'[^0-9A-F]'), '');
    final buffer = StringBuffer();
    for (var i = 0; i < raw.length; i++) {
      if (i > 0 && i % 2 == 0) buffer.write(':');
      buffer.write(raw[i]);
    }
    final formatted = buffer.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
