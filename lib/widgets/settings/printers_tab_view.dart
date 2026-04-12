import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hermosa_pos/utils/paper_width_utils.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../locator.dart';
import '../../models.dart';
import '../../services/api/device_service.dart';
import '../../services/api/filter_service.dart';
import '../../services/category_printer_route_registry.dart';
import '../../services/language_service.dart';
import '../../services/print_orchestrator_service.dart';
import '../../services/printer_role_registry.dart';
import '../../services/printer_service.dart';
import 'package:flutter_bluetooth_printer/flutter_bluetooth_printer.dart';
import 'package:permission_handler/permission_handler.dart';

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
      print('⚠️ Failed loading categories for printer routing: $e');
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
      print('⚠️ Failed syncing category routes from backend: $e');
    }
  }

  String _roleLabel(PrinterRole role) {
    if (role == PrinterRole.cashierReceipt || role == PrinterRole.general) {
      return 'كاشير';
    }
    return 'مطبخ';
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
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
    print('🔧 _updatePrinterRole called: "${device.name}" id=${device.id} → ${role.storageValue}');
    await _roleRegistry.setRole(device.id, role);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
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
                        title: const Text('مسح كل الأقسام؟'),
                        content: const Text('سيتم إزالة جميع الأقسام من هذه الطابعة. هل أنت متأكد؟'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            style: TextButton.styleFrom(foregroundColor: Colors.red),
                            child: const Text('مسح الكل'),
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
      final printers = widget.devices.where(_isPrinter).toList(growable: false);

      final updates = <String, Set<String>>{
        printer.id: selectedSet,
      };

      for (final other in printers) {
        if (other.id == printer.id) continue;
        final existing =
            _categoryRouteRegistry.categoryIdsForPrinter(other.id).toSet();
        final filtered = existing.difference(selectedSet);
        if (filtered.length != existing.length) {
          updates[other.id] = filtered;
        }
      }

      // Save locally only (no API)
      for (final entry in updates.entries) {
        await _categoryRouteRegistry.setCategoryAssignmentsForPrinter(
          entry.key,
          entry.value,
        );
      }

      if (!mounted) return;
      setState(() {});
      final assignedCount =
          _categoryRouteRegistry.assignedCategoryCountForPrinter(printer.id);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
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
        title: const Text('نتائج الفحص الشامل'),
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
                        ? const Text('✓ متصل',
                            style: TextStyle(color: Color(0xFF16A34A)))
                        : const Text('✗ فشل الاتصال',
                            style: TextStyle(color: Color(0xFFDC2626))),
                  ),
                )
                .toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
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
                      items: const [
                        DropdownMenuItem(value: 'cashier', child: Text('كاشير')),
                        DropdownMenuItem(value: 'kitchen', child: Text('مطبخ')),
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
                    color: const Color(0xFF1E293B),
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
        color: Colors.white,
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
                      PopupMenuItem(value: 'role_kitchen', child: Text('مطبخ${isKitchenRole ? ' ✓' : ''}')),
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
          const Divider(height: 0, thickness: 1, color: Color(0xFFF3F4F6)),

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
    return Container(width: 1, height: 20, color: const Color(0xFFF3F4F6));
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
          color: const Color(0xFFF8F8F8),
          child: Column(
            children: [
              _buildHeaderSection(printers),
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildStatChip(
                      _t('kds_printers_count'),
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
                                  color: Colors.white,
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
  String _model = 'default';
  int _copies = 1;
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
                        backgroundColor: const Color(0xFFFDF2E9),
                        labelStyle: TextStyle(
                          color: _connectionType == PrinterConnectionType.wifi
                              ? Colors.white
                              : const Color(0xFF9A3412),
                          fontWeight: FontWeight.w600,
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                      ),
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
                        backgroundColor: const Color(0xFFFDF2E9),
                        labelStyle: TextStyle(
                          color:
                              _connectionType == PrinterConnectionType.bluetooth
                                  ? Colors.white
                                  : const Color(0xFF9A3412),
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
                        label: 'Kitchen / KDS',
                        subtitle: 'Prints kitchen tickets',
                        icon: LucideIcons.utensils,
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
