import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../locator.dart';
import '../../services/app_themes.dart';
import '../../services/display_app_service.dart';
import '../../services/kds_meal_availability_service.dart';
import '../../services/language_service.dart';
import '../services/waiter_device_prefs.dart';

/// Waiter-facing mirror of the device-behaviour toggles that live in the
/// cashier's CashierSettingsView. We reuse the same SharedPreferences
/// keys (via [WaiterDevicePrefKeys]) so a flip here is picked up by the
/// cashier on next read, and vice versa.
///
/// Side effects matter — when KDS is toggled off we tear down the
/// `KdsMealAvailabilityService`; when CDS is toggled off we drop the
/// display connection if it's currently in CDS mode. This mirrors the
/// cashier's `_setCdsEnabled` / `_setKdsEnabled` so we don't leave
/// stale subsystems running after a waiter flips a switch.
class WaiterPrintBehaviorView extends StatefulWidget {
  const WaiterPrintBehaviorView({super.key});

  @override
  State<WaiterPrintBehaviorView> createState() =>
      _WaiterPrintBehaviorViewState();
}

class _WaiterPrintBehaviorViewState extends State<WaiterPrintBehaviorView> {
  final DisplayAppService _displayService = getIt<DisplayAppService>();
  final KdsMealAvailabilityService _kdsService =
      getIt<KdsMealAvailabilityService>();

  WaiterDevicePrefs? _prefs;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final snapshot = await WaiterDevicePrefs.load();
    if (!mounted) return;
    setState(() => _prefs = snapshot);
  }

  Future<void> _persist(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  String _t(String key) => translationService.t(key);

  Future<void> _setCds(bool value) async {
    final current = _prefs;
    if (current == null) return;
    setState(() => _prefs = current.copyWith(cdsEnabled: value));
    await _persist(WaiterDevicePrefKeys.cdsEnabled, value);
    // Mirror the cashier's _setCdsEnabled teardown: if we just turned
    // CDS off and the display pipe is currently in CDS mode, either
    // switch it to KDS (if that's enabled) or disconnect entirely.
    if (!value) {
      _displayService.clearPaymentDisplay();
      if (_displayService.isConnected &&
          _displayService.currentMode == DisplayMode.cds) {
        if (_prefs?.kdsEnabled == true) {
          _displayService.setMode(DisplayMode.kds);
        } else {
          _displayService.disconnect();
        }
      }
    }
  }

  Future<void> _setKds(bool value) async {
    final current = _prefs;
    if (current == null) return;
    setState(() => _prefs = current.copyWith(kdsEnabled: value));
    await _persist(WaiterDevicePrefKeys.kdsEnabled, value);
    if (value) {
      unawaited(_kdsService.initialize());
      return;
    }
    unawaited(_kdsService.disposeService());
    if (_displayService.isConnected &&
        _displayService.currentMode == DisplayMode.kds) {
      if (_prefs?.cdsEnabled == true) {
        _displayService.setMode(DisplayMode.cds);
      } else {
        _displayService.disconnect();
      }
    }
  }

  Future<void> _setBool({
    required String key,
    required bool value,
    required WaiterDevicePrefs Function(WaiterDevicePrefs) update,
  }) async {
    final current = _prefs;
    if (current == null) return;
    setState(() => _prefs = update(current));
    await _persist(key, value);
  }

  @override
  Widget build(BuildContext context) {
    final p = _prefs;
    if (p == null) {
      return Center(
        child: CircularProgressIndicator(color: context.appPrimary),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionHeader(context, _t('settings_section_devices')),
          _card(context, [
            _row(
              context,
              title: _t('enable_cds'),
              description: _t('enable_cds_hint'),
              value: p.cdsEnabled,
              onChanged: _setCds,
            ),
            _divider(context),
            _row(
              context,
              title: _t('enable_kds'),
              description: _t('enable_kds_hint'),
              value: p.kdsEnabled,
              onChanged: _setKds,
            ),
          ]),
          const SizedBox(height: 20),
          _sectionHeader(context, _t('settings_section_printing')),
          _card(context, [
            _row(
              context,
              title: _t('auto_print_cashier'),
              description: _t('auto_print_cashier_hint'),
              value: p.autoPrintCashier,
              onChanged: (v) => _setBool(
                key: WaiterDevicePrefKeys.autoPrintCashier,
                value: v,
                update: (prefs) => prefs.copyWith(autoPrintCashier: v),
              ),
            ),
            _divider(context),
            _row(
              context,
              title: _t('auto_print_customer'),
              description: _t('auto_print_customer_hint'),
              value: p.autoPrintCustomer,
              onChanged: (v) => _setBool(
                key: WaiterDevicePrefKeys.autoPrintCustomer,
                value: v,
                update: (prefs) => prefs.copyWith(autoPrintCustomer: v),
              ),
            ),
            _divider(context),
            _row(
              context,
              title: _t('auto_print_customer_second_copy'),
              description: _t('auto_print_customer_second_copy_hint'),
              value: p.autoPrintCustomerSecondCopy,
              onChanged: (v) => _setBool(
                key: WaiterDevicePrefKeys.autoPrintCustomerSecondCopy,
                value: v,
                update: (prefs) =>
                    prefs.copyWith(autoPrintCustomerSecondCopy: v),
              ),
            ),
            _divider(context),
            _row(
              context,
              title: _t('print_kitchen_invoices'),
              description: _t('print_kitchen_invoices_hint'),
              value: p.printKitchenInvoices,
              onChanged: (v) => _setBool(
                key: WaiterDevicePrefKeys.printKitchenInvoices,
                value: v,
                update: (prefs) => prefs.copyWith(printKitchenInvoices: v),
              ),
            ),
            _divider(context),
            _row(
              context,
              title: _t('allow_print_with_kds'),
              description: _t('allow_print_with_kds_hint'),
              value: p.allowPrintWithKds,
              onChanged: (v) => _setBool(
                key: WaiterDevicePrefKeys.allowPrintWithKds,
                value: v,
                update: (prefs) => prefs.copyWith(allowPrintWithKds: v),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4, right: 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: context.appTextMuted,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }

  Widget _card(BuildContext context, List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.appBorder),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(children: children),
    );
  }

  Widget _divider(BuildContext context) =>
      Divider(height: 1, color: context.appDivider);

  Widget _row(
    BuildContext context, {
    required String title,
    required String description,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: context.appText,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
                    color: context.appTextMuted,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: context.appPrimary,
          ),
        ],
      ),
    );
  }
}
