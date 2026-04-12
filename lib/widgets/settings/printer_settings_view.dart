import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../models.dart';
import '../../services/display_app_service.dart';
import '../../services/printer_service.dart';
import '../../locator.dart';
import 'bluetooth_device_picker.dart';

class PrinterSettingsView extends StatefulWidget {
  final List<DeviceConfig> devices;
  final Future<void> Function(DeviceConfig) onAddDevice;
  final Future<void> Function(String) onRemoveDevice;
  final bool embedded;

  const PrinterSettingsView({
    super.key,
    required this.devices,
    required this.onAddDevice,
    required this.onRemoveDevice,
    this.embedded = false,
  });

  @override
  State<PrinterSettingsView> createState() => _PrinterSettingsViewState();
}

class _PrinterSettingsViewState extends State<PrinterSettingsView> {
  String? _testingId;
  final PrinterService _printerService = getIt<PrinterService>();
  final DisplayAppService _displayService = getIt<DisplayAppService>();

  @override
  void initState() {
    super.initState();
  }

  Future<void> _handleTestConnection(DeviceConfig device) async {
    setState(() => _testingId = device.id);

    try {
      final normalizedType = device.type.trim().toLowerCase();
      final isDisplayDevice = _isDisplayType(normalizedType);

      bool isConnected;
      if (isDisplayDevice) {
        final parsedPort = int.tryParse(device.port) ?? 8080;
        final targetMode = _displayModeForDevice(device);
        await _displayService.connectWithMode(
          device.ip,
          port: parsedPort,
          mode: targetMode,
        );
        isConnected = _displayService.isConnected;
      } else {
        // Printer-only TCP probe
        isConnected = await _printerService.testConnection(device);
      }

      if (mounted) {
        // Update the device status locally
        setState(() {
          device.isOnline = isConnected;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isConnected ? 'تم الاتصال بنجاح' : 'فشل الاتصال'),
            backgroundColor: isConnected ? Colors.green : Colors.red,
            behavior: SnackBarBehavior.floating,
            width: 300,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        // Ensure status is false on error
        setState(() {
          device.isOnline = false;
        });

        String errorMessage = 'خطأ: $e';
        if (e.toString().contains('Connection refused') ||
            e.toString().contains('SocketException')) {
          errorMessage =
              'فشل الاتصال: تأكد من عنوان IP. (127.0.0.1 يعمل فقط على الجهاز نفسه، للهاتف استخدم IP الشبكة مثل 192.168.1.x)';
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMessage),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
              width: 400, // Slightly wider for longer message
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() => _testingId = null);
      }
    }
  }

  bool _isDisplayType(String type) {
    final normalized = type.trim().toLowerCase();
    return normalized == 'kds' ||
        normalized == 'kitchen_screen' ||
        normalized == 'order_viewer' ||
        normalized == 'cds' ||
        normalized == 'customer_display';
  }

  bool _isPrinterType(String type) {
    return type.trim().toLowerCase() == 'printer';
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

  DisplayMode _displayModeForDevice(DeviceConfig device) {
    final type = device.type.trim().toLowerCase();
    if (device.id.startsWith('kitchen:')) {
      final isExplicitCds = type == 'cds' || type == 'customer_display';
      return isExplicitCds ? DisplayMode.cds : DisplayMode.kds;
    }
    if (type == 'order_viewer' || type == 'cds' || type == 'customer_display') {
      return DisplayMode.cds;
    }
    return DisplayMode.kds;
  }

  bool _isDisplayDevice(DeviceConfig device) {
    return _isDisplayType(device.type) || device.id.startsWith('kitchen:');
  }

  void _showAddPrinterDialog() {
    showDialog(
      context: context,
      builder: (context) => _AddDeviceDialog(
        onAdd: widget.onAddDevice,
        title: 'إضافة طابعة',
      ),
    );
  }

  void _showAddDisplayDialog() {
    showDialog(
      context: context,
      builder: (context) => _AddDisplayDialog(
        onAdd: widget.onAddDevice,
      ),
    );
  }

  IconData _getDeviceIcon(String type) {
    switch (type) {
      case 'kitchen_screen':
        return LucideIcons.monitor;
      case 'kds':
        return LucideIcons.utensils;
      case 'order_viewer':
        return LucideIcons.smartphone;
      case 'notification':
        return LucideIcons.bell;
      case 'payment':
        return LucideIcons.creditCard;
      case 'sub_cashier':
        return LucideIcons.userSquare;
      default:
        return LucideIcons.printer;
    }
  }

  @override
  Widget build(BuildContext context) {
    final printers = widget.devices
        .where((d) => _isPrinterType(d.type) && !_isDisplayDevice(d))
        .toList(growable: false);
    final displayDevices =
        widget.devices.where(_isDisplayDevice).toList(growable: false);

    Widget buildDevicesGrid(List<DeviceConfig> devices) => GridView.builder(
          shrinkWrap: widget.embedded,
          physics: widget.embedded
              ? const NeverScrollableScrollPhysics()
              : const AlwaysScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 350,
            childAspectRatio: 1.05,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
          ),
          itemCount: devices.length,
          itemBuilder: (context, index) {
            final device = devices[index];
            final isDisplayDevice = _isDisplayType(device.type);
            final isOrangeType = isDisplayDevice;

            return Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 8,
                      offset: const Offset(0, 2)),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: isOrangeType
                                      ? const Color(0xFFFFF7ED)
                                      : const Color(0xFFEFF6FF),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  _getDeviceIcon(device.type),
                                  color: isOrangeType
                                      ? Colors.orange
                                      : Colors.blue,
                                  size: 24,
                                ),
                              ),
                              Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: device.isOnline
                                      ? Colors.green
                                      : Colors.red,
                                  shape: BoxShape.circle,
                                  border:
                                      Border.all(color: Colors.white, width: 2),
                                  boxShadow: [
                                    BoxShadow(
                                      color: (device.isOnline
                                              ? Colors.green
                                              : Colors.red)
                                          .withValues(alpha: 0.4),
                                      blurRadius: 4,
                                    )
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const Spacer(),
                          Text(
                            device.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                                color: Color(0xFF1E293B)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Flexible(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    _connectionLabel(device),
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 12,
                                      color: Color(0xFF64748B),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  device.model,
                                  style: const TextStyle(
                                      color: Color(0xFF94A3B8),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    decoration: const BoxDecoration(
                      color: Color(0xFFF8FAFC),
                      border: Border(top: BorderSide(color: Color(0xFFF1F5F9))),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextButton.icon(
                            onPressed: _testingId == device.id
                                ? null
                                : () => _handleTestConnection(device),
                            icon: _testingId == device.id
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2))
                                : const Icon(LucideIcons.wifi, size: 16),
                            label: const Text('فحص'),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              foregroundColor: const Color(0xFF475569),
                            ),
                          ),
                        ),
                        Container(
                            width: 1,
                            height: 24,
                            color: const Color(0xFFE2E8F0)),
                        if (_isPrinterType(device.type)) ...[
                          Expanded(
                            child: TextButton.icon(
                              onPressed: _testingId == device.id
                                  ? null
                                  : () async {
                                      setState(() =>
                                          _testingId = 'print_${device.id}');
                                      try {
                                        await _printerService
                                            .printTicket(device, isTest: true);
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            const SnackBar(
                                                content: Text(
                                                    'تم إرسال أمر الطباعة التجريبية'),
                                                backgroundColor: Colors.green),
                                          );
                                        }
                                      } catch (e) {
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                                content:
                                                    Text('فشل الطباعة: $e'),
                                                backgroundColor: Colors.red),
                                          );
                                        }
                                      } finally {
                                        if (mounted) {
                                          setState(() => _testingId = null);
                                        }
                                      }
                                    },
                              icon: _testingId == 'print_${device.id}'
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2))
                                  : const Icon(LucideIcons.printer, size: 16),
                              label: const Text('تجربة'),
                              style: TextButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                foregroundColor: Colors.blue,
                              ),
                            ),
                          ),
                          Container(
                              width: 1,
                              height: 24,
                              color: const Color(0xFFE2E8F0)),
                        ],
                        Expanded(
                          child: TextButton.icon(
                            onPressed: () async {
                              try {
                                await widget.onRemoveDevice(device.id);
                              } catch (e) {
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('فشل حذف الجهاز: $e'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            },
                            icon: const Icon(LucideIcons.trash2, size: 16),
                            label: const Text('حذف'),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              foregroundColor: Colors.red[400],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );

    Widget buildSection({
      required String title,
      required String subtitle,
      required IconData icon,
      required Color iconColor,
      required Color iconBackground,
      required Color bannerColor,
      required Color bannerBorder,
      required VoidCallback onAdd,
      required String addLabel,
      required List<DeviceConfig> sectionDevices,
      List<Widget> extraActions = const [],
    }) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: bannerColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: bannerBorder),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: iconBackground,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: iconColor, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Color(0xFF1E293B),
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                ...extraActions,
                if (extraActions.isNotEmpty) const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(LucideIcons.plus, size: 18),
                  label: Text(addLabel),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF58220),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 1,
                  ),
                ),
              ],
            ),
          ),
          if (sectionDevices.isEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 28),
              padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: const Text(
                'لا توجد أجهزة في هذا القسم',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          else ...[
            if (widget.embedded)
              buildDevicesGrid(sectionDevices)
            else
              SizedBox(
                height: 280,
                child: buildDevicesGrid(sectionDevices),
              ),
            const SizedBox(height: 28),
          ],
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.all(24),
      color: const Color(0xFFF8FAFC),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'إدارة الأجهزة',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 16),
          if (widget.embedded)
            SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  buildSection(
                    title: 'الطابعات',
                    subtitle: 'أجهزة الطباعة الخاصة بالفواتير والمطبخ',
                    icon: LucideIcons.printer,
                    iconColor: Colors.blue,
                    iconBackground: const Color(0xFFEFF6FF),
                    bannerColor: const Color(0xFFF8FAFC),
                    bannerBorder: const Color(0xFFE2E8F0),
                    onAdd: _showAddPrinterDialog,
                    addLabel: 'إضافة طابعة',
                    sectionDevices: printers,
                    extraActions: const [],
                  ),
                  buildSection(
                    title: 'شاشات CDS / KDS',
                    subtitle: 'أجهزة عرض الطلبات والعملاء منفصلة عن الطابعات',
                    icon: LucideIcons.monitor,
                    iconColor: const Color(0xFFF58220),
                    iconBackground: const Color(0xFFFFF7ED),
                    bannerColor: const Color(0xFFFFF7ED),
                    bannerBorder: const Color(0xFFFED7AA),
                    onAdd: _showAddDisplayDialog,
                    addLabel: 'إضافة شاشة',
                    sectionDevices: displayDevices,
                  ),
                ],
              ),
            )
          else
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    buildSection(
                      title: 'الطابعات',
                      subtitle: 'أجهزة الطباعة الخاصة بالفواتير والمطبخ',
                      icon: LucideIcons.printer,
                      iconColor: Colors.blue,
                      iconBackground: const Color(0xFFEFF6FF),
                      bannerColor: const Color(0xFFF8FAFC),
                      bannerBorder: const Color(0xFFE2E8F0),
                      onAdd: _showAddPrinterDialog,
                      addLabel: 'إضافة طابعة',
                      sectionDevices: printers,
                    ),
                    buildSection(
                      title: 'شاشات CDS / KDS',
                      subtitle: 'أجهزة عرض الطلبات والعملاء منفصلة عن الطابعات',
                      icon: LucideIcons.monitor,
                      iconColor: const Color(0xFFF58220),
                      iconBackground: const Color(0xFFFFF7ED),
                      bannerColor: const Color(0xFFFFF7ED),
                      bannerBorder: const Color(0xFFFED7AA),
                      onAdd: _showAddDisplayDialog,
                      addLabel: 'إضافة شاشة',
                      sectionDevices: displayDevices,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

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
        const SnackBar(
          content: Text('تم إرسال طباعة تجريبية بلوتوث'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذر الاتصال — تأكد أن الطابعة في وضع الإقران'),
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
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: const BoxDecoration(
                color: Color(0xFFF8FAFC),
                border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('رجوع'),
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
                        : const Text('حفظ',
                            style: TextStyle(fontWeight: FontWeight.bold)),
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
                              ChoiceChip(
                                label: const Text('بلوتوث'),
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
                            [
                              'default',
                              'TM_T20',
                              'TM_T88',
                              'star',
                              'espon',
                              'Sunmi_V2'
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
                                      color: const Color(0xFFF8FAFC),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                          color: const Color(0xFFE2E8F0)),
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

class _AddDisplayDialog extends StatefulWidget {
  final Future<void> Function(DeviceConfig) onAdd;

  const _AddDisplayDialog({required this.onAdd});

  @override
  State<_AddDisplayDialog> createState() => _AddDisplayDialogState();
}

class _AddDisplayDialogState extends State<_AddDisplayDialog> {
  final _formKey = GlobalKey<FormState>();
  String _name = '';
  String _ip = '';
  String _port = '8080';
  DisplayMode _selectedMode = DisplayMode.cds;
  bool _submitting = false;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();
    setState(() => _submitting = true);
    try {
      final isCds = _selectedMode == DisplayMode.cds;
      await widget.onAdd(DeviceConfig(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: _name.trim(),
        ip: _ip,
        port: _port,
        type: isCds ? 'customer_display' : 'kds',
        model: 'display',
        isOnline: false,
        copies: 1,
      ));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('فشل إضافة الشاشة: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 460,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: const BoxDecoration(
                color: Color(0xFFFFF7ED),
                border: Border(bottom: BorderSide(color: Color(0xFFFED7AA))),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('رجوع'),
                  ),
                  const Text(
                    'إضافة شاشة عرض',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  TextButton(
                    onPressed: _submitting ? null : _submit,
                    child: _submitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text(
                            'حفظ',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                  ),
                ],
              ),
            ),
            SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _modeCard(
                            label: 'CDS',
                            subtitle: 'شاشة العملاء',
                            icon: LucideIcons.monitor,
                            selected: _selectedMode == DisplayMode.cds,
                            onTap: () {
                              setState(() => _selectedMode = DisplayMode.cds);
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _modeCard(
                            label: 'KDS',
                            subtitle: 'شاشة المطبخ',
                            icon: LucideIcons.utensils,
                            selected: _selectedMode == DisplayMode.kds,
                            onTap: () {
                              setState(() => _selectedMode = DisplayMode.kds);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _buildTextField('الاسم', (val) => _name = val ?? ''),
                    const Divider(height: 1),
                    _buildTextField('عنوان الايبي', (val) => _ip = val!,
                        hint: '192.168.1.xxx', isLtr: true),
                    const Divider(height: 1),
                    _buildTextField('المنفذ', (val) => _port = val!,
                        hint: '8080', isLtr: true, isNumber: true),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _modeCard({
    required String label,
    required String subtitle,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFFF7ED) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? const Color(0xFFF58220) : const Color(0xFFE2E8F0),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: selected ? const Color(0xFFF58220) : Colors.grey),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: selected ? const Color(0xFFF58220) : Colors.black87,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
          ],
        ),
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
              validator: (val) => val == null || val.isEmpty ? 'مطلوب' : null,
              textAlign: TextAlign.left,
              textDirection: isLtr ? TextDirection.ltr : TextDirection.rtl,
              keyboardType:
                  isNumber ? TextInputType.number : TextInputType.text,
              decoration: InputDecoration(
                hintText: hint,
                hintTextDirection: TextDirection.ltr,
                hintStyle: const TextStyle(
                    color: Color(0xFF94A3B8), fontWeight: FontWeight.normal),
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                isDense: true,
              ),
              style: const TextStyle(
                  fontWeight: FontWeight.bold, color: Colors.black),
            ),
          ),
        ],
      ),
    );
  }
}
