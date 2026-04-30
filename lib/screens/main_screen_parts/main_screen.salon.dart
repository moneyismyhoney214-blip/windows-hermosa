// ignore_for_file: invalid_use_of_protected_member, unused_element, unused_element_parameter, dead_code, dead_null_aware_expression
part of '../main_screen.dart';

extension MainScreenSalon on _MainScreenState {
  Future<void> _loadSalonServices({int page = 1, String? categoryId}) async {
    try {
      final client = BaseClient();
      String endpoint =
          '${ApiConstants.bookingCreateMetadataEndpoint}?type=$_salonServiceType&page=$page&per_page=100';
      if (categoryId != null && categoryId != 'all') {
        endpoint += '&category_id=$categoryId';
      }
      final response = await client.get(endpoint);

      final List<Map<String, dynamic>> items = [];
      dynamic data;
      int lastPage = 1;
      int currentPage = page;

      if (response is Map<String, dynamic>) {
        data = response['data'] ?? response;
      } else {
        data = response;
      }

      // API returns: { data: { collection: { data: [...items...], current_page: 1, last_page: 58, total: 286, per_page: 5 } } }
      if (data is Map<String, dynamic>) {
        if (data.containsKey('collection') && data['collection'] is Map) {
          final collection = data['collection'] as Map;
          lastPage = (collection['last_page'] as num?)?.toInt() ?? 1;
          currentPage = (collection['current_page'] as num?)?.toInt() ?? page;
          data = collection['data'];
        } else if (data.containsKey('services') && data['services'] is List) {
          data = data['services'];
        } else if (data.containsKey('data') && data['data'] is List) {
          data = data['data'];
        }
      }

      if (data is List) {
        for (final item in data) {
          if (item is Map<String, dynamic>) {
            items.add(item);
          }
        }
      }

      if (mounted) {
        setState(() {
          _salonCurrentPage = currentPage;
          _salonLastPage = lastPage;

          if (_salonServiceType == 'packageServices') {
            // Package services mode
            if (page == 1) {
              _salonPackages = items;
            } else {
              _salonPackages.addAll(items);
            }
            _allProducts = _salonPackages
                .map((s) => Product(
                      id: (s['id'] ?? 0).toString(),
                      name: (s['name'] ?? '').toString(),
                      price: _parseSalonPrice(s['price']),
                      category: (s['category_name'] ?? '').toString(),
                      categoryId: (s['category_id'] ?? '').toString(),
                      isActive: true,
                      image: s['image']?.toString(),
                    ))
                .toList();
          } else {
            // Regular services mode
            if (page == 1) {
              _salonServices = items;
            } else {
              _salonServices.addAll(items);
            }
            _allProducts = _salonServices
                .map((s) => Product(
                      id: (s['id'] ?? 0).toString(),
                      name: (s['name'] ?? '').toString(),
                      price: _parseSalonPrice(s['price']),
                      category: (s['category_name'] ?? '').toString(),
                      categoryId: (s['category_id'] ?? '').toString(),
                      isActive: true,
                      image: s['image']?.toString(),
                    ))
                .toList();
          }
          _isLastPage = currentPage >= lastPage;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load salon services: $e');
    }
  }

  Future<void> _loadMoreSalonServices() async {
    if (_isLoadingMore || _isLastPage) return;
    if (_salonCurrentPage >= _salonLastPage) return;

    setState(() {
      _isLoadingMore = true;
    });

    try {
      await _loadSalonServices(
        page: _salonCurrentPage + 1,
        categoryId: _selectedCategory,
      );
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
        });
      }
    }
  }

  /// Fetches the branch/seller logo URL so salon product cards and the
  /// service selection dialog can use it as a placeholder when services
  /// don't have their own image.
  Future<void> _loadSalonBranchLogo() async {
    try {
      final branchId = ApiConstants.branchId;
      if (branchId <= 0) return;
      final branchService = getIt<BranchService>();

      String url = '';

      // 1. Try the cached receipt info first (populated at startup).
      final cached = branchService.cachedBranchReceiptInfo;
      if (cached != null) {
        url = _pickLogoFromBranch(cached['branch']);
      }

      // 2. Fall back to a direct API call.
      if (url.isEmpty) {
        url = await branchService.getBranchLogoUrl(branchId);
      }

      if (url.isEmpty) return;
      if (url.startsWith('/')) {
        url = 'https://portal.hermosaapp.com$url';
      }

      if (!mounted) return;
      setState(() => _salonBranchLogoUrl = url);
      debugPrint('🖼️ [SALON] branch logo resolved: $url');
    } catch (e) {
      debugPrint('⚠️ Failed to load salon branch logo: $e');
    }
  }

  String _pickLogoFromBranch(dynamic branch) {
    if (branch is! Map) return '';
    final candidates = <dynamic>[
      branch['logo'],
      branch['image'],
      (branch['seller'] is Map) ? branch['seller']['logo'] : null,
      (branch['original_seller'] is Map)
          ? branch['original_seller']['logo']
          : null,
    ];
    for (final c in candidates) {
      final val = c?.toString().trim();
      if (val != null && val.isNotEmpty && val.toLowerCase() != 'null') {
        return val;
      }
    }
    return '';
  }

  Future<void> _loadSalonEmployees() async {
    try {
      final salonService = getIt<SalonEmployeeService>();
      final response = await salonService.getEmployeeOptions();
      final data = response['data'];
      if (data is List) {
        final employees = <Map<String, dynamic>>[];
        for (final item in data) {
          if (item is Map<String, dynamic>) {
            employees.add({
              'id': item['value'],
              'name': (item['label'] ?? '').toString(),
              'is_active': item['is_active'] ?? true,
            });
          }
        }
        if (mounted) {
          setState(() => _salonEmployees = employees);
        }
        // Build service→employees mapping in background
        salonService.buildServiceEmployeeMap(employees).then((map) {
          if (mounted) {
            setState(() => _serviceEmployeeMap = map);
          }
        }).ignore();
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load salon employees: $e');
    }
  }

  static double _parseSalonPrice(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    if (value is String) {
      var cleaned = value.replaceAll(RegExp(r'[^\d.\-]'), '');
      // Handle multiple dots (e.g. "700.01 ر.س" → "700.01." after strip)
      final dotIndex = cleaned.indexOf('.');
      if (dotIndex >= 0) {
        cleaned = cleaned.substring(0, dotIndex + 1) +
            cleaned.substring(dotIndex + 1).replaceAll('.', '');
      }
      return double.tryParse(cleaned) ?? 0.0;
    }
    return 0.0;
  }

  /// Returns the raw service data map for a salon service by its product ID.
  Map<String, dynamic>? _findSalonServiceById(String productId) {
    for (final s in _salonServices) {
      if ((s['id'] ?? 0).toString() == productId) return s;
    }
    return null;
  }

  /// Returns the raw package data map for a salon package by its product ID.
  Map<String, dynamic>? _findSalonPackageById(String productId) {
    for (final s in _salonPackages) {
      if ((s['id'] ?? 0).toString() == productId) return s;
    }
    return null;
  }

  /// Loads the deposits (عرابين) that the currently selected customer has
  /// previously paid. In salon mode the cashier can apply one of these as a
  /// credit against the final invoice — the selected deposit_id flows into
  /// `/seller/calculate/branches/{id}/invoices` and the create-invoice call.
  ///
  /// Pass `null` to clear the list (e.g. when the customer is deselected).
  ///
  /// Strategy: try the customer-filter endpoint first
  /// (`/seller/filters/branches/{id}/allDeposits?customer_id=X`). If it returns
  /// empty, fall back to scanning the paginated deposits list
  /// (`/seller/branches/{id}/deposits`) and match by client name — this covers
  /// cases where the filter endpoint misses legitimate pending deposits that
  /// the cashier can plainly see on the deposits screen.
  Future<void> _loadCustomerDeposits(int? customerId) async {
    if (!_isSalonMode) return;
    if (customerId == null) {
      if (!mounted) return;
      setState(() {
        _customerDeposits = const [];
        _selectedDepositId = null;
        _depositsFetchCustomerId = null;
      });
      return;
    }
    _depositsFetchCustomerId = customerId;
    try {
      final svc = getIt<SalonEmployeeService>();
      debugPrint('💰 [DEPOSIT] fetching for customer=$customerId');
      var list = await svc.getCustomerDeposits(customerId);
      if (!mounted) return;
      if (_depositsFetchCustomerId != customerId) return;
      debugPrint(
          '💰 [DEPOSIT] filter endpoint returned ${list.length} for customer=$customerId');

      if (list.isEmpty) {
        final fallback = await _findDepositsByCustomerName(customerId);
        if (!mounted) return;
        if (_depositsFetchCustomerId != customerId) return;
        if (fallback.isNotEmpty) {
          debugPrint(
              '💰 [DEPOSIT] fallback matched ${fallback.length} by customer name');
          list = fallback;
        }
      }

      debugPrint(
          '💰 [DEPOSIT] final list for customer=$customerId: '
          '${list.map((d) => '${d['label']}=${d['price']}').join(', ')}');
      setState(() {
        _customerDeposits = list;
        if (_selectedDepositId != null &&
            !list.any((d) => _parseDepositId(d['value']) == _selectedDepositId)) {
          _selectedDepositId = null;
        }
      });
    } catch (e) {
      debugPrint('⚠️ Failed to load customer deposits: $e');
      if (!mounted) return;
      if (_depositsFetchCustomerId != customerId) return;
      setState(() {
        _customerDeposits = const [];
        _selectedDepositId = null;
      });
    }
  }

  /// Fallback: scan the paginated `/seller/branches/{id}/deposits` list, keep
  /// only PENDING deposits (status=1) whose `user.name` matches the selected
  /// customer's name, and convert them into the filter-endpoint shape the
  /// picker expects (`{label, value, price}`).
  Future<List<Map<String, dynamic>>> _findDepositsByCustomerName(
      int customerId) async {
    final customerName = _selectedCustomer?.name.trim().toLowerCase();
    if (customerName == null || customerName.isEmpty) return const [];

    try {
      final svc = getIt<SalonEmployeeService>();
      final response = await svc.getDeposits(page: 1, perPage: 100);
      dynamic raw = response['data'];
      if (raw is Map) {
        raw = raw['collection'] is Map ? (raw['collection'] as Map)['data'] : raw['data'];
      }
      if (raw is! List) return const [];

      final matches = <Map<String, dynamic>>[];
      for (final item in raw) {
        if (item is! Map) continue;
        final status = item['status'];
        final isPending = status == 1 || status == '1';
        if (!isPending) continue;

        final user = item['user'];
        final userName = (user is Map ? user['name']?.toString() : null)
            ?.trim()
            .toLowerCase();
        if (userName == null || userName != customerName) continue;

        final id = _parseDepositId(item['id']);
        if (id == null) continue;

        // Extract numeric price from strings like "50.00 ر.س".
        final rawTotal = item['total']?.toString() ?? '';
        final numeric = RegExp(r'[0-9]+(\.[0-9]+)?').firstMatch(rawTotal);
        final totalWithTax =
            numeric != null ? double.tryParse(numeric.group(0)!) ?? 0.0 : 0.0;
        // Deposits list returns tax-inclusive `total`; reverse the active
        // branch's VAT so the field matches the filter endpoint's `price`
        // (pre-tax principal). When the branch has tax disabled the
        // multiplier collapses to 1.0 — the principal equals the total.
        final taxMultiplier = 1.0 + ApiConstants.effectiveTaxRate;
        final price = totalWithTax > 0 ? totalWithTax / taxMultiplier : 0.0;

        matches.add({
          'label': item['invoice_number']?.toString() ?? '#DP-$id',
          'value': id,
          'price': double.parse(price.toStringAsFixed(ApiConstants.digitsNumber)),
          'is_active': true,
          'cash_back': null,
          'equal_qty': null,
          'children': const [],
        });
      }
      return matches;
    } catch (e) {
      debugPrint('⚠️ Fallback deposits scan failed: $e');
      return const [];
    }
  }

  static int? _parseDepositId(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  /// Pre-tax principal of the currently selected deposit, or 0 if nothing is
  /// selected / the deposit can't be found in the cached customer list. Used
  /// to locally reject deposits that would exceed the invoice subtotal (server
  /// returns 422 otherwise).
  double _lookupSelectedDepositPrice() {
    final id = _selectedDepositId;
    if (id == null) return 0.0;
    for (final d in _customerDeposits) {
      if (_parseDepositId(d['value']) == id) {
        final p = d['price'];
        if (p is num) return p.toDouble();
        if (p is String) return double.tryParse(p) ?? 0.0;
        return 0.0;
      }
    }
    return 0.0;
  }

  /// Switches the salon service type toggle and reloads data.
  void _onSalonServiceTypeChanged(String type) {
    if (type == _salonServiceType) return;
    setState(() {
      _salonServiceType = type;
      _isLoading = true;
      _isLastPage = false;
      _salonCurrentPage = 1;
      _selectedCategory = 'all';
    });
    _loadSalonServices(page: 1);
  }
}
