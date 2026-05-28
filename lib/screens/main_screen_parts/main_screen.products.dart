// ignore_for_file: invalid_use_of_protected_member, unused_element, unused_element_parameter, dead_code, dead_null_aware_expression, library_private_types_in_public_api
part of '../main_screen.dart';

extension MainScreenProducts on _MainScreenState {
  Future<void> _switchCategory(String categoryId) async {
    if (categoryId == _selectedCategory) return;

    if (_isMenuListActive) {
      // Filter locally — no API call. Single setState to minimise rebuilds.
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

    // Paint cache immediately while the fresh fetch runs in the background.
    List<Product> cached = [];
    try {
      cached = await productService.getCachedProducts(categoryId);
    } catch (e) {
      Log.d('MainScreenProducts', 'cached products load for category switch failed (non-fatal): $e');
    }

    if (!mounted) return;
    setState(() {
      _selectedCategory = categoryId;
      _currentPage = 1;
      _isLastPage = false;
      if (cached.isNotEmpty) {
        _allProducts = cached;
      }
    });

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
    } catch (e) {
      Log.d('MainScreenProducts', 'refresh products from API failed (non-fatal): $e');
    }
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

      if (_isSalonMode) {
        final branchService = getIt<BranchService>();
        final orderService = getIt<OrderService>();

        final fPayMethods = branchService.getEnabledPayMethods();
        final fBooking = orderService.getBookingSettings();
        _loadTaxConfiguration(branchService: branchService).ignore();
        _loadCachedDevicesThenRefresh().ignore();
        _loadPromoCodes().ignore();
        branchService.fetchAndCacheBranchReceiptInfo().then((_) => _prewarmReceiptCache()).ignore();
        unawaited(_loadSalonServices(categoryId: categoryId));
        unawaited(_loadSalonEmployees());
        if (_salonBranchLogoUrl == null) {
          unawaited(_loadSalonBranchLogo());
        }

        final fServiceCategories = BaseClient()
            .get(ApiConstants.serviceCategoriesEndpoint)
            .catchError((_) => <String, dynamic>{});

        Map<String, bool> salonPayMethods = {};
        try {
          salonPayMethods = await fPayMethods;
        } catch (e) {
          Log.d('MainScreenProducts', 'salon pay-methods load failed (non-fatal): $e');
        }

        BookingSettings salonBookingSettings = BookingSettings(
          typeOptions: [],
          tableOptions: [],
        );
        try {
          salonBookingSettings = await fBooking;
        } catch (e) {
          Log.d('MainScreenProducts', 'salon booking-settings load failed (non-fatal): $e');
        }

        List<CategoryModel> serviceCategories = [];
        try {
          final catResponse = await fServiceCategories;
          if (catResponse is Map && catResponse['data'] is List) {
            serviceCategories = (catResponse['data'] as List)
                .map((e) => CategoryModel.fromJson(e as Map<String, dynamic>))
                .toList();
          }
        } catch (e) {
          Log.d('MainScreenProducts', 'service-categories parse failed (non-fatal): $e');
        }

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

      // Load each resource independently — one failure must not block the others.
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

      // Phase 1: paint cached data instantly.
      try {
        final cachedCats = await productService.getCachedMealCategories();
        final cachedProds =
            await productService.getCachedProducts(_selectedCategory);
        final cachedPay = await branchService.getCachedPayMethods();
        if (mounted && (cachedCats.isNotEmpty || cachedProds.isNotEmpty)) {
          final displayCats = List<CategoryModel>.from(cachedCats);
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
      } catch (e) {
        Log.d('MainScreenProducts', 'cached products/categories/pay-methods load failed (non-fatal): $e');
      }

      // Phase 2: fire all fresh requests in parallel.
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

      _loadTaxConfiguration(branchService: branchService).ignore();
      _loadCachedDevicesThenRefresh().ignore();
      _loadPromoCodes().ignore();
      _fetchAvailableMenuLists().ignore();
      branchService.fetchAndCacheBranchReceiptInfo().then((_) => _prewarmReceiptCache()).ignore();

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
      } catch (e) {
        Log.d('MainScreenProducts', 'restaurant pay-methods refresh failed (non-fatal): $e');
      }

      try {
        bookingSettings = await fBooking;
        if (bookingSettings.typeOptions.isEmpty) {
          Log.w('products', 'booking-settings returned zero type options');
        } else {
          Log.d('products',
              'booking-settings: ${bookingSettings.typeOptions.length} type options loaded');
        }
      } catch (_) {/* booking settings are best-effort */}

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

      Log.d('products',
          'order type options loaded: ${typeOptions.map((e) => e['value']).toList()} '
          '(branch=${ApiConstants.branchId})');

      categories = _mergeUniqueCategories([
        ...categories,
        ...categoriesWithMeals,
      ]);

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
              duration: const Duration(seconds: 3),
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
      if (e is UnauthorizedException) {
        Log.w('products', 'load aborted on 401 — global onUnauthorized will route to login');
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
        } catch (e) {
          Log.d('catch', 'non-fatal: $e');
          category = null;
        }
      } else if (item is Map) {
        try {
          category = CategoryModel.fromJson(
            item.map((key, value) => MapEntry(key.toString(), value)),
          );
        } catch (e) {
          Log.d('catch', 'non-fatal: $e');
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
        UiFeedback.info(context, translationService.t('error_loading_products', args: {'error': e.toString()}));
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

    // Score: 4=exact, 3=prefix, 2=all-words, 1=any-word.
    int score(Product p) {
      final name = _normalizeArabic(p.name);
      if (name == normalized) return 4;
      if (name.startsWith(normalized)) return 3;
      if (words.every((w) => name.contains(w))) return 2;
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
