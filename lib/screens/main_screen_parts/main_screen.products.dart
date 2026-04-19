// ignore_for_file: invalid_use_of_protected_member, unused_element, unused_element_parameter, dead_code, dead_null_aware_expression
part of '../main_screen.dart';

extension MainScreenProducts on _MainScreenState {
  Future<void> _switchCategory(String categoryId) async {
    if (categoryId == _selectedCategory) return;

    // In menu list mode, filter locally - no API call needed
    if (_isMenuListActive) {
      // setState مرة واحدة بس بدل اتنين عشان نقلل الـ rebuilds
      setState(() {
        _selectedCategory = categoryId;
        _currentPage = 1;
        _isLastPage = false;
        _allProducts = categoryId == 'all'
            ? _menuListProducts
            : _menuListProducts
                .where((p) => p.categoryId == categoryId)
                .toList();
      });
      return;
    }

    // Salon mode: reload services with category filter
    if (_isSalonMode) {
      setState(() {
        _selectedCategory = categoryId;
        _isLoading = true;
        _isLastPage = false;
        _salonCurrentPage = 1;
      });
      await _loadSalonServices(page: 1, categoryId: categoryId);
      return;
    }

    final productService = getIt<ProductService>();

    // عرض الكاش فوراً بدون loading - مع تحديث الكاتيجوري في نفس الـ setState
    List<Product> cached = [];
    try {
      cached = await productService.getCachedProducts(categoryId);
    } catch (_) {}

    if (!mounted) return;
    // setState مرة واحدة: تحديث الكاتيجوري + المنتجات المخزنة مع بعض
    setState(() {
      _selectedCategory = categoryId;
      _currentPage = 1;
      _isLastPage = false;
      if (cached.isNotEmpty) {
        _allProducts = cached;
      }
    });

    // جلب البيانات الجديدة من الـ API في الخلفية
    try {
      final products = await productService.getProducts(
        categoryId: categoryId,
        page: 1,
      );
      if (mounted) {
        setState(() {
          _allProducts = products;
          _isLastPage = products.length < 100;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadData({String? categoryId}) async {
    if (!_canCallBranchApis()) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = translationService.t('session_incomplete_error');
        });
      }
      return;
    }

    try {
      setState(() {
        _isLoading = true;
        _error = null;
        _currentPage = 1;
        _isLastPage = false;
        if (categoryId != null) {
          _selectedCategory = categoryId;
        }
      });

      // ── Salon mode: load services instead of meals ──────────────────
      if (_isSalonMode) {
        final branchService = getIt<BranchService>();
        final orderService = getIt<OrderService>();

        // Load pay methods, booking settings, salon services & employees in parallel
        final fPayMethods = branchService.getEnabledPayMethods();
        final fBooking = orderService.getBookingSettings();
        _loadTaxConfiguration(branchService: branchService).ignore();
        _loadCachedDevicesThenRefresh().ignore();
        _loadPromoCodes().ignore();
        branchService.fetchAndCacheBranchReceiptInfo().then((_) => _prewarmReceiptCache()).ignore();
        _loadSalonServices(categoryId: categoryId);
        _loadSalonEmployees();

        // Load service categories for the category bar
        final fServiceCategories = BaseClient()
            .get(ApiConstants.serviceCategoriesEndpoint)
            .catchError((_) => <String, dynamic>{});

        Map<String, bool> salonPayMethods = {};
        try {
          salonPayMethods = await fPayMethods;
        } catch (_) {}

        BookingSettings salonBookingSettings = BookingSettings(
          typeOptions: [],
          tableOptions: [],
        );
        try {
          salonBookingSettings = await fBooking;
        } catch (_) {}

        // Parse service categories
        List<CategoryModel> serviceCategories = [];
        try {
          final catResponse = await fServiceCategories;
          if (catResponse is Map && catResponse['data'] is List) {
            serviceCategories = (catResponse['data'] as List)
                .map((e) => CategoryModel.fromJson(e as Map<String, dynamic>))
                .toList();
          }
        } catch (_) {}

        // Ensure 'All' category exists
        if (!serviceCategories.any((c) => c.id == 'all')) {
          serviceCategories.insert(
            0,
            CategoryModel(
              id: 'all',
              name: translationService.t('all'),
              icon: LucideIcons.filter,
            ),
          );
        }

        if (mounted) {
          // Build order type options for salon (keep 'services' as default)
          final List<Map<String, dynamic>> salonTypeOptions = [];
          for (final option in salonBookingSettings.typeOptions) {
            salonTypeOptions.add({
              'value': option.value.toString().trim(),
              'label': option.label,
            });
          }
          if (salonTypeOptions.isEmpty) {
            salonTypeOptions.add({
              'value': 'services',
              'label': _trUi('خدمات', 'Services'),
            });
          }

          setState(() {
            if (salonPayMethods.isNotEmpty) _enabledPayMethods = salonPayMethods;
            _orderTypeOptions = salonTypeOptions;
            if (_selectedOrderType.isEmpty) _selectedOrderType = 'services';
            _categories = serviceCategories;
            _sortedCategoriesCache = null;
            _isLoading = false;
          });
        }
        return;
      }

      final productService = getIt<ProductService>();
      final branchService = getIt<BranchService>();
      final orderService = getIt<OrderService>();

      // Load each resource independently so one failure doesn't kill everything
      List<CategoryModel> categories = [];
      List<CategoryModel> categoriesWithMeals = [];
      List<Product> products = [];
      Map<String, bool> payMethods = {
        'cash': false,
        'card': false,
        'mada': false,
        'visa': false,
        'benefit': false,
        'stc': false,
        'bank_transfer': false,
        'wallet': false,
        'cheque': false,
        'petty_cash': false,
        'pay_later': false,
        'tabby': false,
        'tamara': false,
        'keeta': false,
        'my_fatoorah': false,
        'jahez': false,
        'talabat': false,
      };
      String? payMethodsNotice;
      BookingSettings bookingSettings = BookingSettings(
        typeOptions: [],
        tableOptions: [],
      );

      // ── Phase 1: Serve cached data instantly (no network wait) ──────────
      try {
        final cachedCats = await productService.getCachedMealCategories();
        final cachedProds =
            await productService.getCachedProducts(_selectedCategory);
        final cachedPay = await branchService.getCachedPayMethods();
        if (mounted && (cachedCats.isNotEmpty || cachedProds.isNotEmpty)) {
          var displayCats = List<CategoryModel>.from(cachedCats);
          if (displayCats.isNotEmpty &&
              !displayCats.any((c) => c.id == 'all')) {
            displayCats.insert(
              0,
              CategoryModel(
                id: 'all',
                name: translationService.t('all'),
                icon: LucideIcons.filter,
              ),
            );
          }
          setState(() {
            if (displayCats.isNotEmpty) {
              _categories = displayCats;
              _sortedCategoriesCache = null;
              _originalCategories = List.from(displayCats);
            }
            if (cachedProds.isNotEmpty) {
              _allProducts = cachedProds;
              _isLastPage = cachedProds.length < 100;
            }
            if (cachedPay != null) _enabledPayMethods = cachedPay;
            _isLoading = false;
          });
        }
      } catch (_) {}

      // ── Phase 2: Fetch all fresh data in parallel ─────────────────────
      // Start every request at the same time — none blocks another
      final fCategories = productService
          .getMealCategories()
          .catchError((_) => <CategoryModel>[]);
      final fCategoriesWithMeals = productService
          .getCategoriesWithMeals()
          .catchError((_) => <CategoryModel>[]);
      final fProducts =
          productService.getProducts(categoryId: _selectedCategory, page: 1);
      final fPayMethods = branchService.getEnabledPayMethods();
      final fBooking = orderService.getBookingSettings();

      // Tax + devices + promo codes + receipt cache: load in background
      _loadTaxConfiguration(branchService: branchService).ignore();
      _loadCachedDevicesThenRefresh().ignore();
      _loadPromoCodes().ignore();
      _fetchAvailableMenuLists().ignore();
      branchService.fetchAndCacheBranchReceiptInfo().then((_) => _prewarmReceiptCache()).ignore();

      // Wait for all main data in parallel
      await Future.wait([
        fCategories,
        fCategoriesWithMeals,
        fProducts,
        fPayMethods,
        fBooking
      ]);

      categories = await fCategories;
      categoriesWithMeals = await fCategoriesWithMeals;
      products = await fProducts;
      try {
        payMethods = await fPayMethods;
        payMethodsNotice = branchService.lastPayMethodsNotice;
      } catch (_) {}

      try {
        bookingSettings = await fBooking;
        print('📋 Type Options from API:');
        if (bookingSettings.typeOptions.isNotEmpty) {
          for (var i = 0; i < bookingSettings.typeOptions.length; i++) {
            final type = bookingSettings.typeOptions[i];
            print('  ${i + 1}. value="${type.value}", label="${type.label}"');
          }
        } else {
          print('  ⚠️  No type options returned from API');
        }
      } catch (_) {}

      _isLastPage = products.length < 100;

      final useArabicUi = _useArabicUi;

      String englishTypeLabel(String value, String fallback) {
        switch (value.trim().toLowerCase()) {
          case 'restaurant_pickup':
            return 'Pickup';
          case 'restaurant_internal':
            return 'Dine In';
          case 'restaurant_delivery':
            return 'Delivery';
          case 'restaurant_parking':
          case 'cars':
          case 'car':
            return 'Cars';
          case 'services':
          case 'service':
          case 'restaurant_services':
            return 'Local';
          default:
            return fallback;
        }
      }

      String arabicTypeLabel(String value, String fallback) {
        switch (value.trim().toLowerCase()) {
          case 'restaurant_pickup':
            return 'سفري';
          case 'restaurant_internal':
            return 'طاولة داخلية';
          case 'restaurant_delivery':
            return 'توصيل';
          case 'restaurant_parking':
          case 'cars':
          case 'car':
            return 'سيارات';
          case 'services':
          case 'service':
          case 'restaurant_services':
            return 'محلي';
          default:
            return fallback;
        }
      }

      bool isRestaurantTypeValue(String value) {
        final normalized = value.trim().toLowerCase();
        switch (normalized) {
          case 'restaurant_pickup':
          case 'pickup':
          case 'takeaway':
          case 'take_away':
          case 'restaurant_takeaway':
          case 'restaurant_take_away':
          case 'restaurant_internal':
          case 'restaurant_table':
          case 'table':
          case 'dine_in':
          case 'dinein':
          case 'internal':
          case 'inside':
          case 'restaurant_delivery':
          case 'delivery':
          case 'home_delivery':
          case 'restaurant_home_delivery':
          case 'restaurant_parking':
          case 'parking':
          case 'drive_through':
          case 'drive-through':
          case 'cars':
          case 'car':
          case 'services':
          case 'service':
          case 'restaurant_services':
            return true;
          default:
            return false;
        }
      }

      String resolveOrderTypeLabel(String value, String fallback) {
        final normalized = _normalizeOrderTypeValue(value);
        final known = useArabicUi
            ? arabicTypeLabel(normalized, fallback)
            : englishTypeLabel(normalized, fallback);
        if (known.trim().isNotEmpty && known.trim() != fallback.trim()) {
          return known;
        }
        final extracted = _readLocalizedText(fallback)?.trim();
        if (extracted != null && extracted.isNotEmpty) return extracted;
        final sanitized = fallback.trim();
        if (sanitized.isNotEmpty) return sanitized;
        return useArabicUi ? 'سفري' : 'Pickup';
      }

      final seenValues = <String>{};
      final List<Map<String, dynamic>> typeOptions = [];
      for (final option in bookingSettings.typeOptions) {
        final rawValue = option.value.toString().trim();
        if (rawValue.isEmpty || !isRestaurantTypeValue(rawValue)) continue;
        final normalized = _normalizeOrderTypeValue(rawValue);
        if (!seenValues.add(normalized)) continue;
        typeOptions.add({
          'value': normalized,
          'label': resolveOrderTypeLabel(rawValue, option.label),
        });
      }

      if (typeOptions.isEmpty) {
        typeOptions.addAll([
          {'value': 'services', 'label': _trUi('محلي', 'Local')},
          {'value': 'restaurant_pickup', 'label': _trUi('سفري', 'Pickup')},
          {'value': 'restaurant_parking', 'label': _trUi('سيارات', 'Cars')},
          {'value': 'restaurant_delivery', 'label': _trUi('توصيل', 'Delivery')},
          {
            'value': 'restaurant_internal',
            'label': _trUi('طاولة داخلية', 'Dine In'),
          },
        ]);
      }

      print(
          '✅ Order Type Options Loaded: ${typeOptions.map((e) => e['value']).toList()}');
      print('✅ Current Branch ID: ${ApiConstants.branchId}');

      categories = _mergeUniqueCategories([
        ...categories,
        ...categoriesWithMeals,
      ]);

      // Ensure 'All' category exists
      if (!categories.any((c) => c.id == 'all')) {
        categories.insert(
          0,
          CategoryModel(
            id: 'all',
            name: translationService.t('all'),
            icon: LucideIcons.filter,
          ),
        );
      }

      if (mounted) {
        setState(() {
          _categories = categories;
          _sortedCategoriesCache = null;
          _originalCategories = List.from(categories);
          _allProducts = products;
          _enabledPayMethods = payMethods;
          _orderTypeOptions = typeOptions;

          // Keep current selection only if it's still valid and non-empty.
          if (_orderTypeOptions.isNotEmpty) {
            final selectedNormalized = _selectedOrderType.trim().toLowerCase();
            final hasValidCurrentSelection = selectedNormalized.isNotEmpty &&
                selectedNormalized != 'null' &&
                _orderTypeOptions.any((option) {
                  final optionValue =
                      option['value']?.toString().trim().toLowerCase() ?? '';
                  return optionValue == selectedNormalized;
                });

            if (!hasValidCurrentSelection) {
              _selectedOrderType = _preferredNonTableOrderType();
            }
          } else {
            // Fallback if no options from backend
            if (_selectedOrderType.isEmpty ||
                _selectedOrderType.toLowerCase() == 'null') {
              _selectedOrderType = 'services';
            }
          }

          _isLoading = false;
        });
        final notice = payMethodsNotice?.trim() ?? '';
        if (notice.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(notice),
              backgroundColor: const Color(0xFF0F766E),
              action: SnackBarAction(
                label: 'إعادة المحاولة',
                textColor: Colors.white,
                onPressed: _loadData,
              ),
            ),
          );
        }
      }
    } catch (e) {
      // Check if it's a 401 Unauthorized error
      if (e is UnauthorizedException) {
        print('User not authenticated (401), redirecting to login...');
        return;
      }
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  List<CategoryModel> _mergeUniqueCategories(Iterable<dynamic> source) {
    final byId = <String, CategoryModel>{};
    final byName = <String, CategoryModel>{};

    for (final item in source) {
      CategoryModel? category;
      if (item is CategoryModel) {
        category = item;
      } else if (item is Map<String, dynamic>) {
        try {
          category = CategoryModel.fromJson(item);
        } catch (_) {
          category = null;
        }
      } else if (item is Map) {
        try {
          category = CategoryModel.fromJson(
            item.map((key, value) => MapEntry(key.toString(), value)),
          );
        } catch (_) {
          category = null;
        }
      }

      if (category == null) continue;

      final id = category.id.trim();
      final name = category.name.trim().toLowerCase();
      if (id.isNotEmpty && id != 'all') {
        byId.putIfAbsent(id, () => category!);
      } else if (name.isNotEmpty && name != translationService.t('all')) {
        byName.putIfAbsent(name, () => category!);
      }
    }

    return [...byId.values, ...byName.values];
  }

  void _onProductsScroll() {
    if (_isLastPage || _isLoadingMore) return;
    final pos = _productsScrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 200) {
      _loadMoreProducts();
    }
  }

  Future<void> _loadMoreProducts() async {
    if (_isLoadingMore || _isLastPage) return;

    // Salon mode: delegate to salon-specific pagination
    if (_isSalonMode) {
      return _loadMoreSalonServices();
    }

    setState(() {
      _isLoadingMore = true;
    });

    try {
      final productService = getIt<ProductService>();
      final nextPage = _currentPage + 1;
      final products = await productService.getProducts(
        categoryId: _selectedCategory,
        page: nextPage,
      );

      if (mounted) {
        setState(() {
          _allProducts.addAll(products);
          _currentPage = nextPage;
          _isLoadingMore = false;
          _isLastPage = products.length < 100;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(translationService.t('error_loading_products', args: {'error': e.toString()}))),
        );
      }
    }
  }

  /// Strips Arabic diacritics (tashkeel) and normalises common letter variants
  /// so that search is diacritic-insensitive and handles alef/hamza/ta marbuta.
  static final _diacriticsRegex = RegExp(r'[\u064B-\u065F\u0670\u0640]');
  static final _alefVariantsRegex = RegExp(r'[إأآا]');
  static final _whitespaceRegex = RegExp(r'\s+');

  static String _normalizeArabic(String s) {
    var r = s.replaceAll(_diacriticsRegex, '');
    r = r.replaceAll(_alefVariantsRegex, 'ا');
    r = r.replaceAll('ة', 'ه');
    r = r.replaceAll('ى', 'ي');
    return r.toLowerCase();
  }

  List<Product> get _filteredProducts {
    final raw = _searchQuery.trim();
    if (raw.isEmpty) return _allProducts;

    final normalized = _normalizeArabic(raw);
    final words =
        normalized.split(_whitespaceRegex).where((w) => w.isNotEmpty).toList();

    // Score: higher = better match
    int score(Product p) {
      final name = _normalizeArabic(p.name);
      // Exact match
      if (name == normalized) return 4;
      // Starts with the full query
      if (name.startsWith(normalized)) return 3;
      // All words appear in the name
      if (words.every((w) => name.contains(w))) return 2;
      // Any word appears in the name
      if (words.any((w) => name.contains(w))) return 1;
      return 0;
    }

    final results = <({Product product, int score})>[];
    for (final p in _allProducts) {
      final s = score(p);
      if (s > 0) results.add((product: p, score: s));
    }
    results.sort((a, b) => b.score.compareTo(a.score));
    return results.map((r) => r.product).toList();
  }
}
