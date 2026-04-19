// ignore_for_file: invalid_use_of_protected_member, unused_element, unused_element_parameter, dead_code, dead_null_aware_expression
part of '../main_screen.dart';

extension MainScreenTax on _MainScreenState {
  Future<void> _loadTaxConfiguration({BranchService? branchService}) async {
    final service = branchService ?? getIt<BranchService>();
    double? resolvedRate;
    bool? resolvedHasTax;

    try {
      final settings = await service.getBranchSettings();
      if (settings.isNotEmpty) {
        resolvedRate = _findTaxRateInPayload(settings);
        resolvedHasTax = _findHasTaxInPayload(settings);
      }
    } catch (e) {
      print('⚠️ Failed to read tax config from branch settings: $e');
    }

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
        print('⚠️ Failed to read tax config from branches: $e');
      }
    }

    final hasTax = resolvedHasTax ?? true;
    final taxRate =
        hasTax ? (resolvedRate ?? _taxRate).clamp(0.0, 1.0).toDouble() : 0.0;
    if (!mounted) return;
    if ((_taxRate - taxRate).abs() > 0.000001 || _isTaxEnabled != hasTax) {
      setState(() {
        _taxRate = taxRate;
        _isTaxEnabled = hasTax;
      });
      _syncDisplayCartFromMain();
    }
  }

  double _taxAmountFromSubtotal(double subtotal) {
    if (!_isTaxEnabled || _taxRate <= 0 || subtotal <= 0) return 0.0;
    return subtotal * _taxRate;
  }

  double _subtotalFromTaxInclusiveTotal(double total) {
    if (!_isTaxEnabled || _taxRate <= 0 || total <= 0) return total;
    return total / (1.0 + _taxRate);
  }

  double _taxFromTaxInclusiveTotal(double total) {
    if (!_isTaxEnabled || _taxRate <= 0 || total <= 0) return 0.0;
    final subtotal = _subtotalFromTaxInclusiveTotal(total);
    return total - subtotal;
  }
}
