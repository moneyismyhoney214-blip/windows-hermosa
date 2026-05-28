// _AddDeviceDialog + state — split from printer_settings_view.dart for size.
part of '../printer_settings_view.dart';

class _AddDeviceDialog extends StatefulWidget {
  final Future<void> Function(DeviceConfig) onAdd;
  final String title;
  const _AddDeviceDialog({
    required this.onAdd,
    required this.title,
  });

  @override
  State<_AddDeviceDialog> createState() => _AddDeviceDialogState();
}

class _AddDeviceDialogState extends State<_AddDeviceDialog> {
  final _formKey = GlobalKey<FormState>();
  String _name = '';
  String _ip = '';
  String _port = '9100';
  String _model = 'TM_T20';
  int _copies = 1;
  bool _submitting = false;
  PrinterConnectionType _connectionType = PrinterConnectionType.wifi;
  BluetoothSelection? _selectedBluetooth;
  bool _testingBluetooth = false;

  Future<void> _submit() async {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();
      if (_connectionType == PrinterConnectionType.bluetooth &&
          _selectedBluetooth == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            duration: Duration(seconds: 3),
            content: Text('يرجى اختيار طابعة بلوتوث أولاً'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      setState(() => _submitting = true);
      try {
        await widget.onAdd(DeviceConfig(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          name: _name,
          ip: _connectionType == PrinterConnectionType.bluetooth ? '' : _ip,
          port: _port,
          type: 'printer',
          model: _model,
          connectionType: _connectionType,
          bluetoothAddress: _selectedBluetooth?.address,
          bluetoothName: _selectedBluetooth?.name,
          isOnline: false,
          copies: _copies <= 0 ? 1 : _copies,
        ));
        if (mounted) Navigator.pop(context);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 3),
            content: Text('فشل إضافة الجهاز: $e'),
            backgroundColor: Colors.red,
          ),
        );
      } finally {
        if (mounted) {
          setState(() => _submitting = false);
        }
      }
    }
  }

  Future<void> _pickBluetoothPrinter() async {
    final selection = await BluetoothDevicePicker.show(context);
    if (!mounted || selection == null) return;
    setState(() {
      _selectedBluetooth = selection;
      if (_name.trim().isEmpty) {
        _name = selection.name;
      }
      _testingBluetooth = true;
    });

    try {
      final printerService = getIt<PrinterService>();
      final device = DeviceConfig(
        id: 'printer:bt_preview',
        name: _name.isEmpty ? selection.name : _name,
        ip: '',
        port: _port,
        type: 'printer',
        model: _model,
        connectionType: PrinterConnectionType.bluetooth,
        bluetoothAddress: selection.address,
        bluetoothName: selection.name,
        copies: 1,
      );
      await printerService.printTicket(device, isTest: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 3),
          content: Text(translationService.t('bt_test_print_sent')),
          backgroundColor: Colors.green,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 3),
          content: Text(translationService.t('bt_connect_failed_check_pair')),
          backgroundColor: Colors.orange,
        ),
      );
    } finally {
      if (mounted) setState(() => _testingBluetooth = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 450,
        padding: const EdgeInsets.all(0),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: context.appCardBg,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: context.appSurfaceAlt,
                border: Border(bottom: BorderSide(color: context.appBorder)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(translationService.t('back')),
                  ),
                  Text(widget.title,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                  TextButton(
                    onPressed: _submitting ? null : _submit,
                    child: _submitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(translationService.t('save'),
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),

            // Form
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Wrap(
                            spacing: 8,
                            children: [
                              ChoiceChip(
                                label: const Text('WiFi'),
                                selected: _connectionType ==
                                    PrinterConnectionType.wifi,
                                onSelected: (value) {
                                  if (!value) return;
                                  setState(() {
                                    _connectionType =
                                        PrinterConnectionType.wifi;
                                  });
                                },
                              ),
                              // Bluetooth printing depends on a Kotlin
                              // bridge (BluetoothPrintBridge.kt) and
                              // Sunmi/Centerm-specific drivers; neither
                              // exists on iOS, so hide the chip there.
                              if (Platform.isAndroid)
                                ChoiceChip(
                                  label: Text(translationService.t('bluetooth')),
                                  selected: _connectionType ==
                                      PrinterConnectionType.bluetooth,
                                  onSelected: (value) {
                                    if (!value) return;
                                    setState(() {
                                      _connectionType =
                                          PrinterConnectionType.bluetooth;
                                    });
                                  },
                                ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        _buildDropdown(
                            'الموديل',
                            _model,
                            Platform.isAndroid
                                ? const [
                                    'default',
                                    'TM_T20',
                                    'TM_T88',
                                    'star',
                                    'espon',
                                    'Sunmi_V2'
                                  ]
                                : const [
                                    'default',
                                    'TM_T20',
                                    'TM_T88',
                                    'star',
                                    'espon',
                                  ],
                            (val) => setState(() => _model = val!)),
                        const Divider(height: 1),
                        _buildTextField('الاسم', (val) => _name = val!),
                        const Divider(height: 1),
                        if (_connectionType == PrinterConnectionType.wifi)
                          _buildTextField('عنوان الايبي', (val) => _ip = val!,
                              hint: '192.168.1.xxx', isLtr: true)
                        else
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: _testingBluetooth
                                      ? null
                                      : _pickBluetoothPrinter,
                                  icon: _testingBluetooth
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2),
                                        )
                                      : const Icon(Icons.bluetooth_searching),
                                  label: const Text('مسح عن الطابعات'),
                                ),
                                if (_selectedBluetooth != null)
                                  Container(
                                    width: double.infinity,
                                    margin: const EdgeInsets.only(top: 8),
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: context.appBg,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                          color: context.appBorder),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _selectedBluetooth!.name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          _selectedBluetooth!.address,
                                          style: const TextStyle(
                                            color: Color(0xFF64748B),
                                            fontFamily: 'monospace',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        if (_connectionType == PrinterConnectionType.wifi) ...[
                          const Divider(height: 1),
                          _buildTextField('المنفذ', (val) => _port = val!,
                              hint: '9100', isLtr: true),
                        ],
                        const Divider(height: 1),
                        _buildTextField('عدد النسخ',
                            (val) => _copies = int.tryParse(val!) ?? 1,
                            hint: '1', isNumber: true),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDropdown(String label, String value, List<String> items,
      ValueChanged<String?> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(
                  color: Color(0xFF64748B), fontWeight: FontWeight.w500)),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              items: items
                  .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                  .toList(),
              onChanged: onChanged,
              style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                  fontSize: 14),
              icon: const Icon(LucideIcons.chevronDown, size: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(String label, FormFieldSetter<String> onSaved,
      {String? hint, bool isLtr = false, bool isNumber = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(label,
                style: const TextStyle(
                    color: Color(0xFF64748B), fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: TextFormField(
              onSaved: onSaved,
              validator: (val) =>
                  val == null || val.trim().isEmpty ? 'مطلوب' : null,
              textAlign: TextAlign.left,
              textDirection: isLtr ? TextDirection.ltr : TextDirection.rtl,
              keyboardType:
                  isNumber ? TextInputType.number : TextInputType.text,
              decoration: InputDecoration(
                hintText: hint,
                hintTextDirection: TextDirection.ltr,
                hintStyle: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontWeight: FontWeight.normal), // Gray hint
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                isDense: true,
              ),
              style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.black), // Black input text
            ),
          ),
        ],
      ),
    );
  }
}
