// ignore_for_file: invalid_use_of_protected_member, unused_element, unused_element_parameter, dead_code, dead_null_aware_expression
part of '../main_screen.dart';

extension MainScreenMenuLists on _MainScreenState {
  Future<void> _fetchAvailableMenuLists() async {
    try {
      final productService = getIt<ProductService>();
      final lists = await productService.getMenuLists();
      debugPrint('🔍 [MenuLists] Raw API returned ${lists.length} items');
      for (var i = 0; i < lists.length; i++) {
        final m = lists[i];
        debugPrint('🔍 [MenuLists] #$i -> id=${m['id']} name=${m['name']} '
            'is_active=${m['is_active']} (type=${m['is_active']?.runtimeType})');
      }
      final filtered = lists.where((m) {
        final v = m['is_active'];
        return v == true || v == 1 || v == '1' || v?.toString().toLowerCase() == 'true';
      }).toList();
      debugPrint('🔍 [MenuLists] After is_active filter: ${filtered.length} items');
      if (mounted) {
        setState(() => _availableMenuLists = filtered);
      }
    } catch (e, st) {
      debugPrint('⚠️ Failed to fetch menu lists: $e');
      debugPrint('$st');
    }
  }

  Future<void> _loadMenuListDetails(int menuId) async {
    try {
      final productService = getIt<ProductService>();
      final data = await productService.getMenuListDetails(menuId);
      final rawCategories = data['categories'] as List? ?? [];

      // Build lookup from original categories by name (case-insensitive)
      final originalCatByName = <String, CategoryModel>{};
      for (final cat in _originalCategories) {
        if (cat.id != 'all') {
          originalCatByName[cat.name.trim().toLowerCase()] = cat;
        }
      }

      final categories = <CategoryModel>[];
      final products = <Product>[];

      for (final rawCat in rawCategories) {
        if (rawCat is! Map) continue;
        final catName = rawCat['name']?.toString() ?? '';
        // Match with original category by name to get the real ID
        final matched = originalCatByName[catName.trim().toLowerCase()];
        final catId = matched?.id ?? catName.hashCode.toString();
        categories.add(CategoryModel(id: catId, name: catName));

        final items = rawCat['items'] as List? ?? [];
        for (final rawItem in items) {
          if (rawItem is! Map) continue;
          final meal = rawItem['meal'] is Map ? rawItem['meal'] as Map : {};
          final deliveryPrice =
              double.tryParse(rawItem['delivery_price']?.toString() ?? '') ?? 0;
          final pickupPrice =
              double.tryParse(rawItem['pickup_price']?.toString() ?? '') ?? 0;
          final price = _menuListPriceType == 'delivery'
              ? deliveryPrice
              : pickupPrice;

          products.add(Product(
            id: meal['id']?.toString() ?? '',
            name: meal['name']?.toString() ?? '',
            nameAr: meal['name']?.toString() ?? '',
            nameEn: '',
            price: price,
            category: catName,
            categoryId: catId,
            image: meal['image']?.toString(),
          ));
        }
      }

      if (mounted) {
        setState(() {
          _menuListCategories = [
            CategoryModel(id: 'all', name: _trUi('الكل', 'All')),
            ...categories,
          ];
          _menuListProducts = products;
          _categories = _menuListCategories;
          _sortedCategoriesCache = null;
          _allProducts = _menuListProducts;
          _selectedCategory = 'all';
        });
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load menu list: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_trUi('فشل تحميل قائمة الأسعار', 'Failed to load price list')),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showMenuListPicker() async {
    if (_availableMenuLists.isEmpty) {
      await _fetchAvailableMenuLists();
    }
    if (_availableMenuLists.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_trUi('لا توجد قوائم أسعار', 'No price lists available')),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            Text(_trUi('اختر قائمة الأسعار', 'Choose Price List'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            // Warning if cart is not empty
            if (_cart.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFF59E0B)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: Color(0xFFF59E0B), size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _trUi('فضّي السلة أولاً عشان تقدر تبدل المينو', 'Clear cart first to switch menu'),
                          style: const TextStyle(fontSize: 12, color: Color(0xFF92400E)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (_cart.isNotEmpty) const SizedBox(height: 8),
            // "Main Menu" option to go back
            ListTile(
              leading: const Icon(Icons.storefront, color: Color(0xFF10B981)),
              title: Text(_trUi('المينيو الأساسي', 'Main Menu')),
              selected: !_isMenuListActive,
              enabled: _cart.isEmpty || !_isMenuListActive,
              onTap: () {
                if (_cart.isNotEmpty && _isMenuListActive) return;
                Navigator.pop(ctx);
                if (_isMenuListActive) {
                  setState(() {
                    _isMenuListActive = false;
                    _activeMenuListId = null;
                    _activeMenuListName = '';
                    _selectedCategory = 'all';
                  });
                  _loadData();
                }
              },
            ),
            const Divider(height: 1),
            ..._availableMenuLists.map((menu) {
              final id = menu['id'] as int? ?? 0;
              final menuType = menu['menu_type'] is Map ? menu['menu_type'] as Map : {};
              final name = menuType['name_display']?.toString() ?? 'قائمة $id';
              final count = menu['items_count'] ?? 0;
              final isCurrentMenu = _isMenuListActive && _activeMenuListId == id;
              final canSwitch = _cart.isEmpty || isCurrentMenu;
              return ListTile(
                leading: Icon(Icons.restaurant_menu,
                    color: canSwitch ? const Color(0xFFF58220) : Colors.grey),
                title: Text(name),
                subtitle: Text('$count ${_trUi('صنف', 'items')}'),
                selected: isCurrentMenu,
                enabled: canSwitch,
                onTap: () {
                  if (!canSwitch) return;
                  Navigator.pop(ctx);
                  setState(() {
                    if (!_isMenuListActive) {
                      _originalCategories = List.from(_categories);
                    }
                    _isMenuListActive = true;
                    _activeMenuListId = id;
                    _activeMenuListName = name;
                  });
                  _loadMenuListDetails(id);
                },
              );
            }),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _switchMenuListPriceType(String type) {
    if (type == _menuListPriceType || _activeMenuListId == null) return;
    setState(() => _menuListPriceType = type);
    _loadMenuListDetails(_activeMenuListId!);
  }
}
