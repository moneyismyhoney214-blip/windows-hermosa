// ignore_for_file: invalid_use_of_protected_member, unused_element, unused_element_parameter, dead_code, dead_null_aware_expression
part of '../main_screen.dart';

extension MainScreenSettings on _MainScreenState {
  Future<void> _loadCashierSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getBool(_requireCustomerSelectionKey);
      final cdsEnabled = prefs.getBool(_cdsEnabledKey) ?? true;
      final kdsEnabled = prefs.getBool(_kdsEnabledKey) ?? true;
      final autoPrintCashier = prefs.getBool(_autoPrintCashierKey) ?? true;
      final autoPrintCustomer = prefs.getBool(_autoPrintCustomerKey) ?? true;
      final autoPrintCustomerSecondCopy =
          prefs.getBool(_autoPrintCustomerSecondCopyKey) ?? false;
      final printKitchenInvoices =
          prefs.getBool(_printKitchenInvoicesKey) ?? true;
      final allowPrintWithKds = prefs.getBool(_allowPrintWithKdsKey) ?? false;
      final mealIconScale = prefs.getDouble(_mealIconScaleKey) ?? 1.0;
      final sidebarIconScale = prefs.getDouble(_sidebarIconScaleKey) ?? 1.0;
      final categoryLayoutVertical = prefs.getBool(_categoryLayoutVerticalKey) ?? false;
      final normalizedSidebarIconScale =
          sidebarIconScale.clamp(0.85, 1.4).toDouble();
      final opening = prefs.getDouble(_cashFloatOpeningBalanceKey) ?? 0.0;
      final transactions =
          prefs.getDouble(_cashFloatTransactionsTotalKey) ?? 0.0;
      if (mounted) {
        setState(() {
          if (value != null) {
            _requireCustomerSelection = value;
          }
          _isCdsEnabled = cdsEnabled;
          _isKdsEnabled = kdsEnabled;
          _autoPrintCashier = autoPrintCashier;
          _autoPrintCustomer = autoPrintCustomer;
          _autoPrintCustomerSecondCopy = autoPrintCustomerSecondCopy;
          _printKitchenInvoices = printKitchenInvoices;
          _allowPrintWithKds = allowPrintWithKds;
          _mealIconScale = mealIconScale;
          _sidebarIconScale = normalizedSidebarIconScale;
          _categoryLayoutVertical = categoryLayoutVertical;
          _cashOpeningBalance = opening;
          _cashTransactionsTotal = transactions;
        });
      }

      if (_isKdsEnabled) {
        unawaited(_mealAvailabilityService.initialize());
      }

      _displayAppService.setCashFloatSnapshot(
        _buildCashFloatSnapshot(),
        sync: false,
      );
    } catch (e) {
      print('⚠️ Failed to load cashier settings: $e');
    }
  }

  Future<void> _persistCashFloat() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_cashFloatOpeningBalanceKey, _cashOpeningBalance);
      await prefs.setDouble(
        _cashFloatTransactionsTotalKey,
        _cashTransactionsTotal,
      );
    } catch (e) {
      print('⚠️ Failed to persist cash float: $e');
    }
  }

  Map<String, dynamic> _buildCashFloatSnapshot() {
    final currentBalance = _cashOpeningBalance + _cashTransactionsTotal;
    return {
      'opening_balance': _cashOpeningBalance,
      'transactions_total': _cashTransactionsTotal,
      'current_balance': currentBalance,
      'currency': ApiConstants.currency,
      'updated_at': DateTime.now().toIso8601String(),
    };
  }

  Future<void> _recordCashTransaction(
    List<Map<String, dynamic>> pays,
  ) async {
    if (pays.isEmpty) return;
    double cashIn = 0.0;
    for (final pay in pays) {
      final method = _normalizePayMethod(pay['pay_method']?.toString());
      if (method != 'cash') continue;
      final amount = (pay['amount'] as num?)?.toDouble() ??
          double.tryParse(pay['amount']?.toString() ?? '') ??
          0.0;
      if (amount > 0) {
        cashIn += amount;
      }
    }
    if (cashIn <= 0) return;

    setState(() {
      _cashTransactionsTotal = double.parse(
        (_cashTransactionsTotal + cashIn).toStringAsFixed(2),
      );
    });
    await _persistCashFloat();
    _displayAppService.setCashFloatSnapshot(_buildCashFloatSnapshot());
  }

  Future<void> _setRequireCustomerSelection(bool value) async {
    setState(() {
      _requireCustomerSelection = value;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_requireCustomerSelectionKey, value);
    } catch (e) {
      print('⚠️ Failed to save cashier settings: $e');
    }
  }

  bool _isDisplayModeEnabled(DisplayMode mode) {
    return mode == DisplayMode.cds ? _isCdsEnabled : _isKdsEnabled;
  }

  Future<void> _setCdsEnabled(bool value) async {
    setState(() {
      _isCdsEnabled = value;
      _lastMainCartFingerprint = null;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_cdsEnabledKey, value);
    } catch (e) {
      print('⚠️ Failed to save CDS setting: $e');
    }

    if (!value) {
      _displayAppService.clearPaymentDisplay();
      if (_displayAppService.isConnected &&
          _displayAppService.currentMode == DisplayMode.cds) {
        if (_isKdsEnabled) {
          _displayAppService.setMode(DisplayMode.kds);
        } else {
          _displayAppService.disconnect();
        }
      }
    }
  }

  Future<void> _setKdsEnabled(bool value) async {
    setState(() {
      _isKdsEnabled = value;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kdsEnabledKey, value);
    } catch (e) {
      print('⚠️ Failed to save KDS setting: $e');
    }

    if (value) {
      unawaited(_mealAvailabilityService.initialize());
      return;
    }

    unawaited(_mealAvailabilityService.disposeService());

    if (_displayAppService.isConnected &&
        _displayAppService.currentMode == DisplayMode.kds) {
      if (_isCdsEnabled) {
        _displayAppService.setMode(DisplayMode.cds);
      } else {
        _displayAppService.disconnect();
      }
    }
  }

  Future<void> _setAllowPrintWithKds(bool value) async {
    setState(() {
      _allowPrintWithKds = value;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_allowPrintWithKdsKey, value);
    } catch (e) {
      print('⚠️ Failed to save print-with-kds setting: $e');
    }
  }

  Future<void> _setAutoPrintCashier(bool value) async {
    setState(() {
      _autoPrintCashier = value;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_autoPrintCashierKey, value);
    } catch (e) {
      print('⚠️ Failed to save auto-print cashier setting: $e');
    }
  }

  Future<void> _setAutoPrintCustomer(bool value) async {
    setState(() {
      _autoPrintCustomer = value;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_autoPrintCustomerKey, value);
    } catch (e) {
      print('⚠️ Failed to save auto-print customer setting: $e');
    }
  }

  Future<void> _setAutoPrintCustomerSecondCopy(bool value) async {
    setState(() {
      _autoPrintCustomerSecondCopy = value;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_autoPrintCustomerSecondCopyKey, value);
    } catch (e) {
      print('⚠️ Failed to save auto-print customer second copy setting: $e');
    }
  }

  Future<void> _setPrintKitchenInvoices(bool value) async {
    setState(() {
      _printKitchenInvoices = value;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_printKitchenInvoicesKey, value);
    } catch (e) {
      print('⚠️ Failed to save print kitchen setting: $e');
    }
  }

  Future<void> _setMealIconScale(double value) async {
    final clamped = value.clamp(0.85, 1.4).toDouble();
    setState(() {
      _mealIconScale = clamped;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_mealIconScaleKey, clamped);
    } catch (e) {
      print('⚠️ Failed to save meal icon scale setting: $e');
    }
  }

  Future<void> _setSidebarIconScale(double value) async {
    final clamped = value.clamp(0.85, 1.4).toDouble();
    setState(() {
      _sidebarIconScale = clamped;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_sidebarIconScaleKey, clamped);
    } catch (e) {
      print('⚠️ Failed to save sidebar icon scale setting: $e');
    }
  }

  Future<void> _setCategoryLayoutVertical(bool value) async {
    setState(() {
      _categoryLayoutVertical = value;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_categoryLayoutVerticalKey, value);
    } catch (e) {
      print('⚠️ Failed to save category layout setting: $e');
    }
  }
}
