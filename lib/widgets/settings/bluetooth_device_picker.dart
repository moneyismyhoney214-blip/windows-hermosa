// ignore_for_file: avoid_dynamic_calls
//
// JSON wire-boundary / message-dispatch layer — dynamic accesses here are
// known and accepted pending the typed-model refactor planned in
// audit_2026_05_19.md (split models.dart, introduce concrete DTOs).
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_printer/flutter_bluetooth_printer.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../services/bluetooth_print_channel.dart';
import '../../services/language_service.dart';
import '../../services/logger_service.dart';

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
    // On Linux/desktop, print_bluetooth_thermal and flutter_bluetooth_serial
    // are unavailable. On iOS, the cashier's BT print bridge is implemented
    // only in Kotlin (BluetoothPrintBridge.kt) — there is no CoreBluetooth
    // counterpart, so a discovered printer would never actually print.
    // Skip BT discovery in both cases and offer manual entry only, so the
    // address can still be saved for use over Wi-Fi/network bridges.
    if (!Platform.isAndroid) {
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
                  } catch (e) {
                    Log.d('BluetoothDevicePicker', 'discovery snapshot parse failed (non-fatal): $e');
                  }
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
                                  onTap: () async {
                                    final selection = BluetoothSelection(
                                      name: device.name ?? 'BT Printer',
                                      address: device.address,
                                    );
                                    final paired = await _ensurePairedBeforeReturn(
                                      sheetContext,
                                      selection,
                                    );
                                    if (!paired) return;
                                    if (!sheetContext.mounted) return;
                                    Navigator.pop(sheetContext, selection);
                                  },
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
          title: Text(translationService.t('bt_manual_mac_title')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: translationService.t('bt_printer_name_optional'),
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
              child: Text(translationService.t('cancel')),
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
              child: Text(translationService.t('save')),
            ),
          ],
        );
      },
    );

    return result;
  }

  /// Pairs the device with the OS if it isn't already, surfacing the system
  /// PIN dialog. Required for thermal printers that ship with a PIN — the
  /// RFCOMM connect at print time only works on bonded devices.
  static Future<bool> _ensurePairedBeforeReturn(
    BuildContext context,
    BluetoothSelection selection,
  ) async {
    final alreadyBonded =
        await BluetoothPrintChannel.isBonded(selection.address);
    if (alreadyBonded) return true;

    if (!context.mounted) return false;
    // Visual cue that pairing is in flight — bondDevice() blocks up to 30s
    // waiting on ACTION_BOND_STATE_CHANGED, and we don't want the cashier
    // tapping again while the system dialog is still up.
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 16),
            Expanded(
              child: Text(translationService.t('bt_pairing_in_progress')),
            ),
          ],
        ),
      ),
    ));

    bool ok = false;
    try {
      ok = await BluetoothPrintChannel.bondDevice(selection.address);
    } catch (e) {
      Log.d('catch', 'non-fatal: $e');
      ok = false;
    }

    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }

    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 3),
          content: Text(translationService.t('bt_pairing_failed')),
          backgroundColor: Colors.red,
        ),
      );
    }
    return ok;
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
        SnackBar(
          duration: const Duration(seconds: 3),
          content: Text(translationService.t('bt_permission_required')),
          backgroundColor: Colors.red,
        ),
      );
    }
    return ok;
  }
}
