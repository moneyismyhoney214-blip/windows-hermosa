import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

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
import '../../widgets/settings/printers_tab_view.dart';

/// Waiter-module hub for per-device printer settings.
///
/// The waiter reuses the cashier's [PrintersTabView] widget so the two
/// modules share identical add/edit dialogs (IP, port, paper-width,
/// role). Keeping the widget shared means any tweak to the cashier's
/// printer form automatically reaches the waiter — the user expected
/// "waiter printer setup looks like the cashier" is literally true.
///
/// Tabs:
///   1. الإعدادات — printers list with full add/edit/test/remove
///   2. اللغة     — primary / secondary invoice language
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

  @override
  void initState() {
    super.initState();
    _loadAll();
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

      // PrintersTabView needs the category list so the owner can route
      // kitchen prints per category. Best-effort — a fetch failure
      // leaves the list empty, which the widget treats as "no routing
      // available" rather than crashing.
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
      length: 2,
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
              onPressed: _loading ? null : _loadAll,
              icon: const Icon(LucideIcons.rotateCcw),
            ),
          ],
          bottom: TabBar(
            labelColor: context.appPrimary,
            unselectedLabelColor: context.appTextMuted,
            indicatorColor: context.appPrimary,
            tabs: const [
              Tab(
                icon: Icon(LucideIcons.settings, size: 18),
                text: 'الإعدادات',
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
                      // 1. Printer management — identical to the
                      //    cashier's PrintersTabView. Add dialog shows
                      //    IP / port / paper-width / role; edit dialog
                      //    shows name / IP / paper-width / role. Test
                      //    connection, test print, and remove actions
                      //    all inherited.
                      PrintersTabView(
                        devices: _devices,
                        categories: _categories,
                        onAddDevice: _addDevice,
                        onRemoveDevice: _removeDevice,
                      ),
                      // 2. Primary / secondary printer language toggles.
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
