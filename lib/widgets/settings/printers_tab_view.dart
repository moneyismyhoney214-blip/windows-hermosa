// `use_build_context_synchronously` is suppressed at file level — the
// dialog state-machines call showDialog after small awaited helpers; a
// dedicated pass is queued behind printer-settings refactor. Print
// calls have been migrated to Log so this file no longer needs an
// avoid_print suppression.
// ignore_for_file: use_build_context_synchronously

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bluetooth_printer/flutter_bluetooth_printer.dart';
import 'package:hermosa_pos/utils/paper_width_utils.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../locator.dart';
import '../../models.dart';
import '../../services/api/api_constants.dart';
import '../../services/api/device_service.dart';
import '../../services/api/filter_service.dart';
import '../../services/app_themes.dart';
import '../../services/cashier_mesh_bootstrap.dart';
import '../../services/category_printer_route_registry.dart';
import '../../services/language_service.dart';
import '../../services/logger_service.dart';
import '../../services/print_orchestrator_service.dart';
import '../../services/printer_role_registry.dart';
import '../../services/printer_service.dart';

part 'printers_tab_view_parts/printers_tab_view.builders.dart';
part 'printers_tab_view_parts/printers_tab_view.dialogs.dart';

/// Fire a kitchen-printer snapshot to every waiter on the LAN. Internally
/// debounced (250 ms) so a burst of printer edits produces a single
/// broadcast. Safe no-op if the cashier mesh hasn't started yet.
void _notifyPrinterConfigChanged() {
  try {
    final bootstrap = getIt<CashierMeshBootstrap>();
    if (!bootstrap.isStarted) return;
    unawaited(bootstrap.broadcastKitchenPrintersConfig());
  } catch (e) {
    Log.d('PrintersTabView', 'broadcast kitchen-printer config failed (non-fatal): $e');
  }
}

class PrintersTabView extends StatefulWidget {
  final List<DeviceConfig> devices;
  final List<CategoryModel> categories;
  final Future<void> Function(DeviceConfig) onAddDevice;
  final Future<void> Function(String) onRemoveDevice;

  const PrintersTabView({
    super.key,
    required this.devices,
    required this.categories,
    required this.onAddDevice,
    required this.onRemoveDevice,
  });

  @override
  State<PrintersTabView> createState() => _PrintersTabViewState();
}

class _PrintersTabViewState extends State<PrintersTabView> {
  final DeviceService _deviceService = getIt<DeviceService>();
  final PrinterService _printerService = getIt<PrinterService>();
  final FilterService _filterService = getIt<FilterService>();
  final PrinterRoleRegistry _roleRegistry = getIt<PrinterRoleRegistry>();
  final CategoryPrinterRouteRegistry _categoryRouteRegistry =
      getIt<CategoryPrinterRouteRegistry>();
  final PrintOrchestratorService _printOrchestrator =
      getIt<PrintOrchestratorService>();

  StreamSubscription<Map<String, bool>>? _statusSubscription;

  Map<String, bool> _livePrinterStatus = <String, bool>{};
  final List<CategoryModel> _fetchedCategories = <CategoryModel>[];
  String? _busyId;

  @override
  void initState() {
    super.initState();
    _initializeState();
    _bindOrchestratorStreams();
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PrintersTabView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldPrinterIds =
        oldWidget.devices.where(_isPrinter).map((d) => d.id).toSet();
    final newPrinterIds =
        widget.devices.where(_isPrinter).map((d) => d.id).toSet();

    if (oldPrinterIds.length != newPrinterIds.length ||
        !oldPrinterIds.containsAll(newPrinterIds)) {
      unawaited(_syncCategoryAssignmentsFromBackend());
    }
  }

  Future<void> _initializeState() async {
    await Future.wait<void>(<Future<void>>[
      _roleRegistry.initialize(),
      _categoryRouteRegistry.initialize(),
    ]);
    await _loadCategoriesFromApiIfNeeded();
    await _syncCategoryAssignmentsFromBackend();
    if (mounted) setState(() {});
    // Auto-check all printers on tab load
    unawaited(_autoCheckAllPrinters());
  }

  Future<void> _autoCheckAllPrinters() async {
    final printers = widget.devices.where(_isPrinter).toList();
    for (final device in printers) {
      if (!mounted) break;
      try {
        final ok = await _printerService.testConnection(device).timeout(
          const Duration(seconds: 3),
          onTimeout: () => false,
        );
        if (!mounted) return;
        setState(() {
          device.isOnline = ok;
          _livePrinterStatus[device.id] = ok;
        });
        _printOrchestrator.updatePrinterStatus(device.id, ok);
      } catch (_) {
        if (!mounted) return;
        setState(() {
          device.isOnline = false;
          _livePrinterStatus[device.id] = false;
        });
      }
    }
  }

  void _bindOrchestratorStreams() {
    _livePrinterStatus = <String, bool>{
      for (final d in widget.devices.where(_isPrinter))
        d.id: _printOrchestrator.isPrinterOnline(d.id),
    };

    _statusSubscription =
        _printOrchestrator.printerStatusStream.listen((event) {
      if (!mounted) return;
      setState(() {
        _livePrinterStatus = event;
      });
    });
  }

  bool _isPrinter(DeviceConfig d) {
    final type = d.type.trim().toLowerCase();
    return type == 'printer' && !d.id.startsWith('kitchen:');
  }

  bool _effectiveOnline(DeviceConfig device) {
    if (_livePrinterStatus.containsKey(device.id)) {
      return _livePrinterStatus[device.id] == true;
    }
    return device.isOnline;
  }

  String _t(String key, {Map<String, dynamic>? args}) {
    return translationService.t(key, args: args);
  }

  List<CategoryModel> _availableCategories() {
    final seenIds = <String>{};
    final filtered = <CategoryModel>[];
    final source = <CategoryModel>[
      ...widget.categories,
      ..._fetchedCategories,
    ];

    for (final category in source) {
      final id = category.id.trim();
      final name = category.name.trim();
      if (id.isEmpty || name.isEmpty) continue;

      final normalizedId = id.toLowerCase();
      final normalizedName = name.toLowerCase();
      final localizedAll = _t('all').trim().toLowerCase();

      if (normalizedId == 'all' || normalizedName == 'all') continue;
      if (normalizedName == 'الكل' || normalizedName == localizedAll) continue;
      if (!seenIds.add(normalizedId)) continue;
      filtered.add(category);
    }

    filtered
        .sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return filtered;
  }

  Future<void> _loadCategoriesFromApiIfNeeded() async {
    if (_availableCategories().isNotEmpty) return;
    if (_busyId == 'load_categories') return;

    if (mounted) setState(() => _busyId = 'load_categories');
    try {
      final response = await _filterService.getResourceCategories(
        scope: 'types',
        type: 'meals',
        all: true,
      );
      final rawData = response['data'];
      if (rawData is! List) return;

      final fetched = <CategoryModel>[];
      for (final item in rawData) {
        if (item is! Map) continue;
        final map = item.map((key, value) => MapEntry(key.toString(), value));
        final id = map['id']?.toString().trim() ?? '';
        final name = map['name']?.toString().trim() ?? '';
        if (id.isEmpty || name.isEmpty) continue;

        fetched.add(
          CategoryModel(
            id: id,
            name: name,
            type: map['type']?.toString(),
          ),
        );
      }

      if (fetched.isNotEmpty && mounted) {
        setState(() {
          _fetchedCategories
            ..clear()
            ..addAll(fetched);
        });
      }
    } catch (e) {
      Log.w('printer-tab', 'failed loading categories for routing', error: e);
    } finally {
      if (mounted && _busyId == 'load_categories') {
        setState(() => _busyId = null);
      }
    }
  }

  Future<void> _syncCategoryAssignmentsFromBackend() async {
    // No API sync needed — all local now
    try {
      await _categoryRouteRegistry.initialize();
    } catch (e) {
      Log.w('printer-tab', 'failed syncing category routes', error: e);
    }
  }

  String _roleLabel(PrinterRole role) {
    if (role == PrinterRole.cashierReceipt || role == PrinterRole.general) {
      return 'كاشير';
    }
    // Salon branches print per-service turn slips (تذكرة الدور), not kitchen
    // tickets — surface the role label accordingly. Restaurant wording is
    // unchanged.
    return ApiConstants.branchModule == 'salons' ? 'أدوار' : 'مطبخ';
  }

  int _normalizePaperWidthMm(dynamic value) {
    return normalizePaperWidthMm(value);
  }

  Future<void> _updatePrinterName(DeviceConfig device, String name) async {
    if (name.isEmpty || name == device.name) return;
    final previous = device.name;
    if (mounted) setState(() => device.name = name);
    try {
      await _deviceService.updateLocalDeviceConfig(device);
      _notifyPrinterConfigChanged();
    } catch (_) {
      if (mounted) setState(() => device.name = previous);
    }
  }

  Future<void> _updatePrinterIp(DeviceConfig device, String ip) async {
    if (ip == device.ip) return;
    final previous = device.ip;
    if (mounted) setState(() => device.ip = ip);
    try {
      await _deviceService.updateLocalDeviceConfig(device);
      _notifyPrinterConfigChanged();
    } catch (_) {
      if (mounted) setState(() => device.ip = previous);
    }
  }

  Future<void> _updatePrinterPaperWidth(
    DeviceConfig device,
    int paperWidthMm,
  ) async {
    final normalized = _normalizePaperWidthMm(paperWidthMm);
    if (device.paperWidthMm == normalized) return;

    final previous = device.paperWidthMm;
    if (mounted) {
      setState(() {
        device.paperWidthMm = normalized;
      });
    }

    try {
      await _deviceService.updateLocalDeviceConfig(device);
      _notifyPrinterConfigChanged();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 3),
          content: Text(
            _t(
              'paper_size_updated',
              args: {'name': device.name, 'size': normalized},
            ),
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        device.paperWidthMm = previous;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 3),
          content: Text(_t('printer_check_failed', args: {'error': e})),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _disconnectPrinter(DeviceConfig device) {
    setState(() {
      device.isOnline = false;
      _livePrinterStatus[device.id] = false;
    });
    _printOrchestrator.updatePrinterStatus(device.id, false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 3),
        content: Text('${device.name} - تم قطع الاتصال'),
        backgroundColor: Colors.orange,
      ),
    );
  }

  Future<BluetoothDevice?> _scanForBluetoothDevices() async {
    // 1. Request permissions using permission_handler
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();

    if (statuses[Permission.bluetoothScan] != PermissionStatus.granted ||
        statuses[Permission.bluetoothConnect] != PermissionStatus.granted) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 3),
          content: Text('يرجى منح صلاحيات البلوتوث للبحث عن الطابعات'),
          backgroundColor: Colors.red,
        ),
      );
      return null;
    }

    if (!mounted) return null;

    // 2. Use the built-in device selector from the package
    return await FlutterBluetoothPrinter.selectDevice(context);
  }

  Future<void> _testConnection(DeviceConfig device) async {
    setState(() => _busyId = 'test_${device.id}');
    try {
      final ok = await _printerService.testConnection(device);
      if (!mounted) return;
      setState(() {
        device.isOnline = ok;
        _livePrinterStatus[device.id] = ok;
      });
      _printOrchestrator.updatePrinterStatus(device.id, ok);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 3),
          content: Text(
            ok ? _t('printer_connected') : _t('printer_connection_failed'),
          ),
          backgroundColor: ok ? Colors.green : Colors.red,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 3),
          content: Text(_t('printer_check_failed', args: {'error': e})),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _testPrint(DeviceConfig device) async {
    setState(() => _busyId = 'print_${device.id}');
    try {
      await _printerService.printTicket(device, isTest: true);
      if (!mounted) return;
      setState(() => _livePrinterStatus[device.id] = true);
      _printOrchestrator.updatePrinterStatus(device.id, true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 3),
          content: Text(_t('printer_test_sent')),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _livePrinterStatus[device.id] = false);
      _printOrchestrator.updatePrinterStatus(device.id, false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 3),
          content: Text(_t('printer_print_failed', args: {'error': e})),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _updatePrinterRole(
    DeviceConfig device,
    PrinterRole role,
  ) async {
    Log.d('printer-tab',
        'updatePrinterRole ${device.name} (${device.id}) → ${role.storageValue}');
    await _roleRegistry.setRole(device.id, role);
    _notifyPrinterConfigChanged();
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 3),
        content: Text('${device.name} → ${_roleLabel(role)}'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _showCategoryAssignmentsDialog(DeviceConfig printer) async {
    await _loadCategoriesFromApiIfNeeded();
    if (!mounted) return;

    final categories = _availableCategories();
    if (categories.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 3),
          content: Text(_t('no_categories_available')),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final selected =
        _categoryRouteRegistry.categoryIdsForPrinter(printer.id).toSet();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final width = MediaQuery.sizeOf(dialogContext).width;
        final contentWidth = width < 460 ? width * 0.84 : 380.0;
        final contentHeight = MediaQuery.sizeOf(dialogContext).height * 0.52;

        return StatefulBuilder(
          builder: (context, setInnerState) {
            return AlertDialog(
              title: Text(
                _t(
                  'link_printer_to_categories',
                  args: {'printer': printer.name},
                ),
              ),
              content: SizedBox(
                width: contentWidth,
                height: contentHeight,
                child: ListView(
                  children: categories.map((category) {
                    final categoryId = category.id.trim();
                    final checked = selected.contains(categoryId);
                    return CheckboxListTile(
                      value: checked,
                      dense: true,
                      title: Text(category.name),
                      subtitle: Text(
                        _t('category_number', args: {'id': categoryId}),
                      ),
                      onChanged: (value) {
                        setInnerState(() {
                          if (value == true) {
                            selected.add(categoryId);
                          } else {
                            selected.remove(categoryId);
                          }
                        });
                      },
                    );
                  }).toList(growable: false),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(_t('cancel')),
                ),
                TextButton(
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text(_t('clear_all_categories_title')),
                        content: Text(_t('clear_all_categories_body')),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_t('cancel'))),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            style: TextButton.styleFrom(foregroundColor: Colors.red),
                            child: Text(_t('clear_all')),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true && context.mounted) {
                      selected.clear();
                      Navigator.of(context).pop(true);
                    }
                  },
                  child: Text(_t('clear_all')),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(_t('save')),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true) return;

    final busyToken = 'save_categories_${printer.id}';
    if (mounted) setState(() => _busyId = busyToken);
    try {
      final selectedSet = selected.where((id) => id.trim().isNotEmpty).toSet();

      // Multiple printers may share the same category (e.g. a "tea" category
      // routed to both the main kitchen and the drinks-bay printer). Only
      // update the printer the cashier is editing — don't strip overlapping
      // assignments from other printers.
      await _categoryRouteRegistry.setCategoryAssignmentsForPrinter(
        printer.id,
        selectedSet,
      );
      _notifyPrinterConfigChanged();

      if (!mounted) return;
      setState(() {});
      final assignedCount =
          _categoryRouteRegistry.assignedCategoryCountForPrinter(printer.id);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 3),
          content: Text(
            _t(
              'links_saved_for_categories',
              args: {'count': assignedCount, 'printer': printer.name},
            ),
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      await _syncCategoryAssignmentsFromBackend();
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 3),
          content: Text(_t('link_save_server_failed', args: {'error': e})),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted && _busyId == busyToken) {
        setState(() => _busyId = null);
      }
    }
  }

  Future<void> _runBulkHealthCheck(List<DeviceConfig> printers) async {
    if (printers.isEmpty) return;
    setState(() => _busyId = 'scan_all');

    var onlineCount = 0;
    final results = <DeviceConfig, bool>{};
    for (final printer in printers) {
      var ok = false;
      try {
        await _printerService.printTicket(printer, isTest: true);
        ok = true;
      } catch (_) {
        ok = false;
      }
      results[printer] = ok;
      printer.isOnline = ok;
      _livePrinterStatus[printer.id] = ok;
      _printOrchestrator.updatePrinterStatus(printer.id, ok);
      if (ok) onlineCount++;
      if (mounted) setState(() {});
    }

    if (!mounted) return;
    setState(() => _busyId = null);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_t('bulk_scan_results_title')),
        content: SizedBox(
          width: 320,
          child: ListView(
            shrinkWrap: true,
            children: results.entries
                .map(
                  (entry) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(entry.key.name),
                    subtitle: Text(_connectionLabel(entry.key)),
                    trailing: entry.value
                        ? Text('✓ ${_t('connected')}',
                            style: const TextStyle(color: Color(0xFF16A34A)))
                        : Text('✗ ${_t('connection_failed')}',
                            style: const TextStyle(color: Color(0xFFDC2626))),
                  ),
                )
                .toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_t('close')),
          ),
        ],
      ),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 3),
        content: Text(
          _t(
            'bulk_scan_finished',
            args: {'online': onlineCount, 'total': printers.length},
          ),
        ),
        backgroundColor: onlineCount > 0 ? Colors.green : Colors.orange,
      ),
    );
  }

  void _showEditPrinterDialog(DeviceConfig device) {
    final nameController = TextEditingController(text: device.name);
    final ipController = TextEditingController(text: device.ip);
    final addressController =
        TextEditingController(text: device.bluetoothAddress ?? '');
    final role = _roleRegistry.resolveRole(device);
    var selectedRole =
        role == PrinterRole.cashierReceipt || role == PrinterRole.general
            ? 'cashier'
            : 'kitchen';
    var selectedPaper = _normalizePaperWidthMm(device.paperWidthMm);
    final isBluetooth =
        device.connectionType == PrinterConnectionType.bluetooth;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(translationService.t('edit')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: translationService.t('name'),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 12),
                if (!isBluetooth)
                  TextField(
                    controller: ipController,
                    decoration: InputDecoration(
                      labelText: 'IP',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: addressController,
                          decoration: InputDecoration(
                            labelText: 'Bluetooth MAC',
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                          style: const TextStyle(fontFamily: 'monospace'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        onPressed: () async {
                          final selected = await _scanForBluetoothDevices();
                          if (selected != null) {
                            setDialogState(() {
                              nameController.text =
                                  selected.name ?? nameController.text;
                              addressController.text = selected.address;
                            });
                          }
                        },
                        icon: const Icon(LucideIcons.search, size: 20),
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xFFF58220),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: selectedRole,
                      decoration: InputDecoration(
                        labelText: translationService.t('role'),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        isDense: true,
                      ),
                      items: [
                        DropdownMenuItem(value: 'cashier', child: Text(_t('dropdown_role_cashier'))),
                        DropdownMenuItem(value: 'kitchen', child: Text(_t('dropdown_role_kitchen'))),
                      ],
                      onChanged: (v) => setDialogState(() => selectedRole = v ?? selectedRole),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: selectedPaper,
                      decoration: InputDecoration(
                        labelText: translationService.t('paper_width'),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        isDense: true,
                      ),
                      items: const [
                        DropdownMenuItem(value: 58, child: Text('58mm')),
                        DropdownMenuItem(value: 80, child: Text('80mm')),
                        DropdownMenuItem(value: 88, child: Text('88mm')),
                      ],
                      onChanged: (v) => setDialogState(() => selectedPaper = v ?? selectedPaper),
                    ),
                  ),
                ],
              ),
            ],
          ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(translationService.t('cancel')),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                final newRole = selectedRole == 'cashier'
                    ? PrinterRole.cashierReceipt
                    : PrinterRole.kitchen;
                if (nameController.text.trim() != device.name) {
                  await _updatePrinterName(device, nameController.text.trim());
                }
                if (newRole != role) {
                  await _updatePrinterRole(device, newRole);
                }
                if (selectedPaper !=
                    _normalizePaperWidthMm(device.paperWidthMm)) {
                  await _updatePrinterPaperWidth(device, selectedPaper);
                }
                if (isBluetooth) {
                  final newMac = addressController.text.trim();
                  if (newMac != device.bluetoothAddress) {
                    device.bluetoothAddress = newMac;
                    await _deviceService.updateLocalDeviceConfig(device);
                  }
                } else if (ipController.text.trim() != device.ip) {
                  await _updatePrinterIp(device, ipController.text.trim());
                }
                if (mounted) setState(() {});
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF58220),
                foregroundColor: Colors.white,
              ),
              child: Text(translationService.t('save')),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddPrinterDialog() {
    final printers = widget.devices.where(_isPrinter).toList(growable: false);
    showDialog(
      context: context,
      builder: (context) => _AddPrinterDialog(
        onAdd: widget.onAddDevice,
        existingDevices: printers,
        scanHelper: _scanForBluetoothDevices,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final printers = widget.devices.where(_isPrinter).toList(growable: false);
    final onlineCount = printers.where(_effectiveOnline).length;

    final kdsPrinterCount = printers
        .where((device) {
      final role = _roleRegistry.resolveRole(device);
      return role == PrinterRole.kds ||
          role == PrinterRole.kitchen ||
          role == PrinterRole.bar;
    }).length;

    final cdsPrinterCount = printers
        .where(
          (device) =>
              _roleRegistry.resolveRole(device) ==
              PrinterRole.cashierReceipt,
        )
        .length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 900;

        return Container(
          color: context.appBg,
          child: Column(
            children: [
              _buildHeaderSection(printers),
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.appCardBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.appBorder),
                ),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildStatChip(
                      ApiConstants.branchModule == 'salons'
                          ? 'طابعات الأدوار'
                          : _t('kds_printers_count'),
                      '$kdsPrinterCount',
                      const Color(0xFF7C3AED),
                    ),
                    _buildStatChip(
                      _t('cds_printers_count'),
                      '$cdsPrinterCount',
                      const Color(0xFF0EA5E9),
                    ),
                    _buildStatChip(
                      _t('connected_count'),
                      '$onlineCount',
                      Colors.green,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  children: [
                    if (printers.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 48),
                        child: Center(
                          child: Column(
                            children: [
                              Container(
                                width: 120,
                                height: 120,
                                decoration: BoxDecoration(
                                  color: context.appCardBg,
                                  borderRadius: BorderRadius.circular(24),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.05,
                                      ),
                                      blurRadius: 16,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  LucideIcons.printer,
                                  color: Color(0xFFF58220),
                                  size: 46,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _t('no_printers_added'),
                                style: const TextStyle(
                                  color: Color(0xFF475569),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 12),
                              ElevatedButton.icon(
                                onPressed: _showAddPrinterDialog,
                                icon: const Icon(LucideIcons.plus, size: 16),
                                label: Text(_t('add_printer')),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFF58220),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else if (compact)
                      ...printers.map(
                        (device) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _buildPrinterCard(device, compact: true),
                        ),
                      )
                    else
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 360,
                          childAspectRatio: 1.6,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                        itemCount: printers.length,
                        itemBuilder: (context, index) {
                          return _buildPrinterCard(
                            printers[index],
                            compact: false,
                          );
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
