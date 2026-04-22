import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../locator.dart';
import '../../models.dart';
import '../../services/api/device_service.dart';
import '../../services/api/product_service.dart';
import '../../services/app_themes.dart';
import '../../services/category_printer_route_registry.dart';
import '../../services/kitchen_printer_route_registry.dart';
import '../../services/print_orchestrator_service.dart';
import '../../services/printer_role_registry.dart';
import '../../widgets/printer_language_settings_view.dart';
import '../../widgets/settings/display_devices_tab_view.dart';
import '../../widgets/settings/printer_settings_view.dart';
import '../../widgets/settings/printers_tab_view.dart';
import '../services/waiter_device_prefs.dart';
import '../widgets/waiter_print_behavior_view.dart';

/// Waiter-module hub for every device / print / KDS / CDS setting.
///
/// We don't duplicate the printing stack — this is a thin shell that
/// hosts the shared views from `lib/widgets/settings/` in a tabbed
/// scaffold and owns the device fetch / add / remove lifecycle so the
/// waiter sees identical behavior to the cashier's settings.
///
/// Tab layout (mirror of the cashier's Devices + Printing sub-tabs):
///   1. الطابعات   — role binding, category routing
///   2. الإعدادات  — per-device edit, test connection, remove
///   3. الشاشات    — KDS / CDS display device management (reconnect,
///                    mode switch, add/remove)
///   4. السلوك     — device-level toggles for printing + displays
///                    (CDS/KDS enable, auto-print flags, etc.)
///   5. اللغة      — printer primary / secondary language
class WaiterPrinterSettingsScreen extends StatefulWidget {
  const WaiterPrinterSettingsScreen({super.key});

  @override
  State<WaiterPrinterSettingsScreen> createState() =>
      _WaiterPrinterSettingsScreenState();
}

class _WaiterPrinterSettingsScreenState
    extends State<WaiterPrinterSettingsScreen> {
  final DeviceService _deviceService = getIt<DeviceService>();
  final ProductService _productService = getIt<ProductService>();

  final List<DeviceConfig> _devices = [];
  final List<CategoryModel> _categories = [];
  bool _loading = true;
  Object? _error;

  /// Surfaced on the Displays tab so KDS/CDS rows can hide modes the
  /// waiter has disabled from the Behavior tab. Kept in sync via
  /// [_reloadPrefs] on every tab mount.
  bool _cdsEnabled = true;
  bool _kdsEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadAll();
    _reloadPrefs();
  }

  Future<void> _reloadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _cdsEnabled =
          prefs.getBool(WaiterDevicePrefKeys.cdsEnabled) ?? true;
      _kdsEnabled =
          prefs.getBool(WaiterDevicePrefKeys.kdsEnabled) ?? true;
    });
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Match the cashier's bootstrap: cached devices first for
      // instant UI, then refresh from network.
      List<DeviceConfig> devices = <DeviceConfig>[];
      try {
        final cached = await _deviceService.getCachedDevices();
        if (cached.isNotEmpty) devices = cached;
      } catch (_) {}
      try {
        devices = await _deviceService.getDevices();
      } catch (e) {
        if (devices.isEmpty) rethrow;
        // Network fail but cache available — still useful.
        debugPrint('⚠️ Waiter printers refresh (using cache): $e');
      }

      List<CategoryModel> categories = const <CategoryModel>[];
      try {
        categories = await _productService.getCategories();
      } catch (e) {
        debugPrint('⚠️ Waiter categories fetch failed: $e');
      }

      if (!mounted) return;
      setState(() {
        _devices
          ..clear()
          ..addAll(devices);
        _categories
          ..clear()
          ..addAll(categories);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  /// Mirrors the cashier's _addDevice. Waiter doesn't need the
  /// DisplayAppService connect-on-add side effect (CDS/KDS pairing is
  /// pushed by the cashier); it's safe to omit here.
  Future<void> _addDevice(DeviceConfig device) async {
    final created = await _deviceService.createDevice(device);
    if (!mounted) return;
    setState(() => _devices.add(created));
  }

  /// Mirrors the cashier's _removeDevice including the registry
  /// cleanup so the waiter device doesn't carry stale role/routing
  /// bindings for a deleted printer.
  Future<void> _removeDevice(String id) async {
    await _deviceService.deleteDevice(id);
    try {
      getIt<PrinterRoleRegistry>().clearRole(id);
    } catch (_) {}
    try {
      getIt<CategoryPrinterRouteRegistry>().clearPrinterAssignments(id);
    } catch (_) {}
    try {
      getIt<KitchenPrinterRouteRegistry>().clearPrinterAssignments(id);
    } catch (_) {}
    try {
      getIt<PrintOrchestratorService>().updatePrinterStatus(id, false);
    } catch (_) {}
    if (!mounted) return;
    setState(() => _devices.removeWhere((d) => d.id == id));
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        backgroundColor: context.appBg,
        appBar: AppBar(
          backgroundColor: context.appHeaderBg,
          foregroundColor: context.appText,
          elevation: 0,
          title: const Text('إعدادات الأجهزة'),
          actions: [
            IconButton(
              tooltip: 'تحديث',
              onPressed: _loading
                  ? null
                  : () {
                      _loadAll();
                      _reloadPrefs();
                    },
              icon: const Icon(LucideIcons.rotateCcw),
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            labelColor: context.appPrimary,
            unselectedLabelColor: context.appTextMuted,
            indicatorColor: context.appPrimary,
            tabs: const [
              Tab(
                icon: Icon(LucideIcons.printer, size: 18),
                text: 'الطابعات',
              ),
              Tab(
                icon: Icon(LucideIcons.settings, size: 18),
                text: 'الإعدادات',
              ),
              Tab(
                icon: Icon(LucideIcons.monitor, size: 18),
                text: 'الشاشات',
              ),
              Tab(
                icon: Icon(LucideIcons.slidersHorizontal, size: 18),
                text: 'السلوك',
              ),
              Tab(
                icon: Icon(LucideIcons.languages, size: 18),
                text: 'اللغة',
              ),
            ],
          ),
        ),
        body: _loading
            ? Center(child: CircularProgressIndicator(color: context.appPrimary))
            : _error != null
                ? _ErrorView(error: _error!, onRetry: _loadAll)
                : TabBarView(
                    children: [
                      // 1. Printers — role binding, category routing.
                      PrintersTabView(
                        devices: _devices,
                        categories: _categories,
                        onAddDevice: _addDevice,
                        onRemoveDevice: _removeDevice,
                      ),
                      // 2. Per-device settings — test connection, edit,
                      //    remove.
                      PrinterSettingsView(
                        devices: _devices,
                        onAddDevice: _addDevice,
                        onRemoveDevice: _removeDevice,
                      ),
                      // 3. KDS / CDS displays — pair, reconnect, remove.
                      //    Shares the same widget the cashier's settings
                      //    uses, fed the live cds/kds flags so rows that
                      //    belong to a disabled mode are hidden.
                      DisplayDevicesTabView(
                        devices: _devices,
                        onAddDevice: _addDevice,
                        onRemoveDevice: _removeDevice,
                        cdsEnabled: _cdsEnabled,
                        kdsEnabled: _kdsEnabled,
                      ),
                      // 4. Device-level behaviour toggles. Writes to the
                      //    same SharedPreferences slots the cashier reads
                      //    on next startup so both modules stay in sync.
                      const WaiterPrintBehaviorView(),
                      // 5. Primary / secondary printer language toggles.
                      const PrinterLanguageSettingsView(),
                    ],
                  ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;
  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.alertCircle,
                size: 42, color: context.appDanger),
            const SizedBox(height: 8),
            Text(
              'تعذّر تحميل الإعدادات',
              style: TextStyle(color: context.appText),
            ),
            const SizedBox(height: 4),
            Text(
              '$error',
              style: TextStyle(color: context.appTextMuted, fontSize: 12),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(LucideIcons.rotateCcw),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    );
  }
}
