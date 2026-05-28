import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../locator.dart';
import '../../models.dart';
import '../../services/api/api_constants.dart';
import '../../services/app_themes.dart';
import '../../services/display_app_service.dart';
import '../../services/language_service.dart';
import '../../services/printer_service.dart';
import 'bluetooth_device_picker.dart';

part 'printer_settings_view_parts/printer_settings_view.add_device.dart';
part 'printer_settings_view_parts/printer_settings_view.add_display.dart';

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
            duration: const Duration(seconds: 3),
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
              duration: const Duration(seconds: 3),
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
                color: context.appCardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: context.appBorder),
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
                                    color: context.appBg,
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
                    decoration: BoxDecoration(
                      color: context.appBg,
                      border: Border(top: BorderSide(color: context.appSurfaceAlt)),
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
                            label: Text(translationService.t('test')),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              foregroundColor: const Color(0xFF475569),
                            ),
                          ),
                        ),
                        Container(
                            width: 1,
                            height: 24,
                            color: context.appBorder),
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
                                            SnackBar(
                                                duration: const Duration(seconds: 3),
                                                content: Text(translationService.t('test_print_sent')),
                                                backgroundColor: Colors.green),
                                          );
                                        }
                                      } catch (e) {
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                                duration: const Duration(seconds: 3),
                                                content: Text(
                                                  translationService.t(
                                                    'print_failed_with_reason',
                                                    args: {'reason': '$e'},
                                                  ),
                                                ),
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
                              label: Text(translationService.t('try_label')),
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
                              color: context.appBorder),
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
                                    duration: const Duration(seconds: 3),
                                    content: Text(
                                      translationService.t(
                                        'device_remove_failed',
                                        args: {'reason': '$e'},
                                      ),
                                    ),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            },
                            icon: const Icon(LucideIcons.trash2, size: 16),
                            label: Text(translationService.t('delete')),
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
                color: context.appCardBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: context.appBorder),
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
      color: context.appBg,
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
                    subtitle: ApiConstants.branchModule == 'salons'
                        ? 'أجهزة الطباعة الخاصة بالفواتير والأدوار'
                        : 'أجهزة الطباعة الخاصة بالفواتير والمطبخ',
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
                    title: ApiConstants.branchModule == 'salons'
                        ? 'شاشات CDS / SDS'
                        : 'شاشات CDS / KDS',
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
                      subtitle: ApiConstants.branchModule == 'salons'
                          ? 'أجهزة الطباعة الخاصة بالفواتير والأدوار'
                          : 'أجهزة الطباعة الخاصة بالفواتير والمطبخ',
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
                      title: ApiConstants.branchModule == 'salons'
                        ? 'شاشات CDS / SDS'
                        : 'شاشات CDS / KDS',
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
