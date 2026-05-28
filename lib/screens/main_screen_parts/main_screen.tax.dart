// ignore_for_file: invalid_use_of_protected_member, unused_element, unused_element_parameter, dead_code, dead_null_aware_expression, library_private_types_in_public_api
part of '../main_screen.dart';

extension MainScreenTax on _MainScreenState {
  Future<void> _loadTaxConfiguration({BranchService? branchService}) async {
    final service = branchService ?? getIt<BranchService>();
    double? resolvedRate;
    bool? resolvedHasTax;

    // Authoritative source: the dedicated `/seller/filters/branches/{id}/getTax`
    // endpoint. On success it also updates `ApiConstants` so other tax
    // consumers see fresh values without re-reading branch settings.
    try {
      await service.refreshTaxConfig();
      resolvedRate = ApiConstants.taxRate;
      resolvedHasTax = ApiConstants.hasTax;
    } catch (e) {
      Log.w('tax', 'getTax endpoint failed', error: e);
    }

    // Secondary source: branch settings cache (multi-endpoint racer).
    if (resolvedRate == null || resolvedHasTax == null) {
      try {
        final settings = await service.getBranchSettings();
        if (settings.isNotEmpty) {
          resolvedRate ??= _findTaxRateInPayload(settings);
          resolvedHasTax ??= _findHasTaxInPayload(settings);
        }
      } catch (e) {
        Log.w('tax', 'branch settings failed', error: e);
      }
    }

    // Tertiary source: scanning the branches list for a `taxObject`.
    if (resolvedRate == null || resolvedHasTax == null) {
      try {
        final branches = await getIt<AuthService>().getBranchesRaw();
        Map<String, dynamic>? currentBranch;
        for (final branch in branches) {
          final branchId = int.tryParse(branch['id']?.toString() ?? '') ??
              int.tryParse(branch['branch_id']?.toString() ?? '') ??
              0;
          if (branchId == ApiConstants.branchId) {
            currentBranch = branch;
            break;
          }
        }
        currentBranch ??= branches.isNotEmpty ? branches.first : null;
        if (currentBranch != null) {
          resolvedRate ??= _findTaxRateInPayload(currentBranch);
          resolvedHasTax ??= _findHasTaxInPayload(currentBranch);
        }
      } catch (e) {
        Log.w('tax', 'branches scan failed', error: e);
      }
    }

    final hasTax = resolvedHasTax ?? ApiConstants.hasTax;
    final taxRate = hasTax
        ? (resolvedRate ?? ApiConstants.taxRate).clamp(0.0, 1.0).toDouble()
        : 0.0;
    if (!mounted) return;
    if ((_taxRate - taxRate).abs() > 0.000001 || _isTaxEnabled != hasTax) {
      setState(() {
        _taxRate = taxRate;
        _isTaxEnabled = hasTax;
      });
      _syncDisplayCartFromMain();
    }
  }

  /// Snapshot of the current branch tax config as a pure calculator.
  /// Recomputed each call so it reflects whatever `_loadTaxConfiguration`
  /// last wrote into `_isTaxEnabled` + `_taxRate`. Kept private so the
  /// rest of the screen can keep referencing the existing local helpers;
  /// new code outside this file should construct its own
  /// [OrderTotalsCalculator] from `ApiConstants`.
  OrderTotalsCalculator get _totalsCalculator => OrderTotalsCalculator(
        isTaxEnabled: _isTaxEnabled,
        taxRate: _taxRate,
      );

  double _taxAmountFromSubtotal(double subtotal) =>
      _totalsCalculator.taxAmountFromSubtotal(subtotal);

  double _subtotalFromTaxInclusiveTotal(double total) =>
      _totalsCalculator.subtotalFromTaxInclusiveTotal(total);

  double _taxFromTaxInclusiveTotal(double total) =>
      _totalsCalculator.taxFromTaxInclusiveTotal(total);
}
