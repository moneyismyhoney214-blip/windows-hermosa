import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_printer/flutter_bluetooth_printer.dart';
import 'package:permission_handler/permission_handler.dart';

class BluetoothSelection {
  final String name;
  final String address;

  const BluetoothSelection({
    required this.name,
    required this.address,
  });
}

class BluetoothDevicePicker {
  static Future<BluetoothSelection?> show(BuildContext context) async {
    // On Linux, print_bluetooth_thermal and flutter_bluetooth_serial are
    // Android-only. Skip all BT API checks and go straight to manual entry.
    if (!Platform.isAndroid && !Platform.isIOS) {
      if (!context.mounted) return null;
      return _showManualEntryDialog(context);
    }

    final hasPermission = await _ensureBluetoothPermissions(context);
    if (!context.mounted) return null;
    if (!hasPermission) return null;

    return showModalBottomSheet<BluetoothSelection>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return StreamBuilder<dynamic>(
              stream: FlutterBluetoothPrinter.discovery,
              builder: (context, snapshot) {
                final dynamic state = snapshot.data;
                final List<BluetoothDevice> discovered = [];
                if (state != null) {
                  try {
                    discovered.addAll(state.devices as Iterable<BluetoothDevice>);
                  } catch (_) {}
                }
                final bool isScanning = state?.isDiscovering ?? false;

                return SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'اختر طابعة بلوتوث',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('إغلاق'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (discovered.isEmpty && !isScanning)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 20),
                            child: Text(
                              'لا توجد أجهزة مكتشفة حالياً.',
                              style: TextStyle(color: Color(0xFF64748B)),
                            ),
                          ),
                        if (isScanning && discovered.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 20),
                            child: Center(child: CircularProgressIndicator()),
                          ),
                        if (discovered.isNotEmpty) ...[
                          const Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'الأجهزة المكتشفة',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF475569),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Flexible(
                            child: ListView.builder(
                              shrinkWrap: true,
                              itemCount: discovered.length,
                              itemBuilder: (context, index) {
                                final device = discovered[index];
                                return ListTile(
                                  leading: const Icon(Icons.bluetooth),
                                  title: Text(device.name ?? 'طابعة بلوتوث'),
                                  subtitle: Text(device.address),
                                  onTap: () => Navigator.pop(
                                    context,
                                    BluetoothSelection(
                                      name: device.name ?? 'BT Printer',
                                      address: device.address,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                        const Divider(height: 24),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final manual = await _showManualEntryDialog(
                                sheetContext,
                              );
                              if (manual != null && sheetContext.mounted) {
                                Navigator.pop(sheetContext, manual);
                              }
                            },
                            icon: const Icon(Icons.edit),
                            label: const Text('إدخال يدوي للعنوان'),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  static Future<BluetoothSelection?> _showManualEntryDialog(
    BuildContext context,
  ) async {
    final nameController = TextEditingController();
    final macController = TextEditingController();
    BluetoothSelection? result;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('إدخال MAC يدوي'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'اسم الطابعة (اختياري)',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: macController,
                decoration: const InputDecoration(
                  labelText: 'Bluetooth MAC Address',
                  hintText: '00:11:22:33:44:55',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () {
                final mac = macController.text.trim();
                if (mac.isEmpty) return;
                final name = nameController.text.trim();
                result = BluetoothSelection(
                  name: name.isNotEmpty ? name : 'BT Printer',
                  address: mac,
                );
                Navigator.pop(dialogContext);
              },
              child: const Text('حفظ'),
            ),
          ],
        );
      },
    );

    return result;
  }

  static Future<bool> _ensureBluetoothPermissions(
    BuildContext context,
  ) async {
    final statuses = await [
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.location,
    ].request();

    final ok = statuses.values.every((status) => status.isGranted);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('صلاحيات البلوتوث مطلوبة لاستخدام الطابعة'),
          backgroundColor: Colors.red,
        ),
      );
    }
    return ok;
  }
}
