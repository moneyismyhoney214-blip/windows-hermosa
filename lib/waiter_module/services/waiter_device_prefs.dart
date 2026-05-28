import 'package:shared_preferences/shared_preferences.dart';

/// Device-level preference keys that the cashier's [MainScreen] writes
/// and reads to control printing + display behaviour. They're mirrored
/// here so the waiter module's settings UI writes to the same slots —
/// both modules run on the same device and must agree on what's
/// printed, what's sent to KDS, and whether the CDS is enabled.
///
/// **Keep these strings byte-for-byte identical to the `const String`
/// declarations at the top of `lib/screens/main_screen.dart`.** There's
/// no single source of truth because `main_screen.dart`'s constants are
/// file-private; duplicating them here is the lowest-risk way to let
/// the waiter share the same settings without reaching into the
/// cashier screen's internals.
class WaiterDevicePrefKeys {
  WaiterDevicePrefKeys._();

  static const String cdsEnabled = 'cashier_cds_enabled_v1';
  static const String kdsEnabled = 'cashier_kds_enabled_v1';
  static const String autoPrintCashier = 'cashier_auto_print_cashier_v1';
  static const String autoPrintCustomer = 'cashier_auto_print_customer_v1';
  static const String autoPrintCustomerSecondCopy =
      'cashier_auto_print_customer_second_copy_v1';
  static const String printKitchenInvoices =
      'cashier_print_kitchen_invoices_v1';
  static const String allowPrintWithKds = 'cashier_allow_print_with_kds_v1';

  /// Waiter-only toggle (NOT mirrored from the cashier): when on, every
  /// table must be linked to a customer before the waiter can send an
  /// order to the kitchen or take payment. Mirrors the restaurant's
  /// `cashier_require_customer_selection` behaviour but kept independent
  /// so the merchant can enforce it on the waiter floor without changing
  /// the cashier register's own setting.
  static const String requireCustomerSelection =
      'waiter_require_customer_selection_v1';
}

/// Snapshot of every device-scope toggle the waiter settings UI cares
/// about. Loaded once on screen mount so the UI renders instantly
/// instead of showing a spinner per switch.
class WaiterDevicePrefs {
  const WaiterDevicePrefs({
    required this.cdsEnabled,
    required this.kdsEnabled,
    required this.autoPrintCashier,
    required this.autoPrintCustomer,
    required this.autoPrintCustomerSecondCopy,
    required this.printKitchenInvoices,
    required this.allowPrintWithKds,
    required this.requireCustomerSelection,
  });

  final bool cdsEnabled;
  final bool kdsEnabled;
  final bool autoPrintCashier;
  final bool autoPrintCustomer;
  final bool autoPrintCustomerSecondCopy;
  final bool printKitchenInvoices;
  final bool allowPrintWithKds;
  final bool requireCustomerSelection;

  /// Defaults match `_loadCashierSettings` in main_screen.settings.dart
  /// — if either module ever disagrees on the default, first-run
  /// behaviour diverges between cashier and waiter.
  static Future<WaiterDevicePrefs> load() async {
    final prefs = await SharedPreferences.getInstance();
    return WaiterDevicePrefs(
      cdsEnabled: prefs.getBool(WaiterDevicePrefKeys.cdsEnabled) ?? true,
      kdsEnabled: prefs.getBool(WaiterDevicePrefKeys.kdsEnabled) ?? true,
      autoPrintCashier:
          prefs.getBool(WaiterDevicePrefKeys.autoPrintCashier) ?? true,
      autoPrintCustomer:
          prefs.getBool(WaiterDevicePrefKeys.autoPrintCustomer) ?? true,
      autoPrintCustomerSecondCopy:
          prefs.getBool(WaiterDevicePrefKeys.autoPrintCustomerSecondCopy) ??
              false,
      printKitchenInvoices:
          prefs.getBool(WaiterDevicePrefKeys.printKitchenInvoices) ?? true,
      allowPrintWithKds:
          prefs.getBool(WaiterDevicePrefKeys.allowPrintWithKds) ?? false,
      requireCustomerSelection:
          prefs.getBool(WaiterDevicePrefKeys.requireCustomerSelection) ??
              false,
    );
  }

  /// Quick single-key read for callsites (e.g. the order screen) that
  /// only need the "require customer" flag and don't want to load the
  /// whole snapshot.
  static Future<bool> isRequireCustomerSelectionEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(WaiterDevicePrefKeys.requireCustomerSelection) ??
        false;
  }

  /// Persist the "require customer" flag.
  static Future<void> setRequireCustomerSelection(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(WaiterDevicePrefKeys.requireCustomerSelection, value);
  }

  WaiterDevicePrefs copyWith({
    bool? cdsEnabled,
    bool? kdsEnabled,
    bool? autoPrintCashier,
    bool? autoPrintCustomer,
    bool? autoPrintCustomerSecondCopy,
    bool? printKitchenInvoices,
    bool? allowPrintWithKds,
    bool? requireCustomerSelection,
  }) {
    return WaiterDevicePrefs(
      cdsEnabled: cdsEnabled ?? this.cdsEnabled,
      kdsEnabled: kdsEnabled ?? this.kdsEnabled,
      autoPrintCashier: autoPrintCashier ?? this.autoPrintCashier,
      autoPrintCustomer: autoPrintCustomer ?? this.autoPrintCustomer,
      autoPrintCustomerSecondCopy:
          autoPrintCustomerSecondCopy ?? this.autoPrintCustomerSecondCopy,
      printKitchenInvoices:
          printKitchenInvoices ?? this.printKitchenInvoices,
      allowPrintWithKds: allowPrintWithKds ?? this.allowPrintWithKds,
      requireCustomerSelection:
          requireCustomerSelection ?? this.requireCustomerSelection,
    );
  }
}
