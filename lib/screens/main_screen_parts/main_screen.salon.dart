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
