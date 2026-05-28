part of '../edit_order_dialog.dart';

// Helpers split from edit_order_dialog.dart: _QtyButton, _EditableOrderItem, _ProductPickerDialog (library-private).

class _QtyButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;

  const _QtyButton({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: context.appSurfaceAlt,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: context.appBorder),
        ),
        child: Icon(icon, size: 14, color: context.appText),
      ),
    );
  }
}

class _EditableOrderItem {
  final String mealId;
  String name;
  double quantity;
  double unitPrice;
  final List<Extra> extras;
  final String notes;
  final Map<String, String>? localizedNames;

  /// Salon-only payload mirroring the booking-create `card[i]` shape.
  /// Set when the row represents a salon `booking_service` (existing or
  /// freshly added through SalonServiceSelectionDialog). Restaurant rows
  /// leave this null.
  Map<String, dynamic>? salonData;

  _EditableOrderItem({
    required this.mealId,
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.extras,
    required this.notes,
    this.localizedNames,
    this.salonData,
  });

  double get totalPrice {
    final extrasTotal = extras.fold<double>(0.0, (sum, e) => sum + e.price);
    return (unitPrice + extrasTotal) * quantity;
  }

  bool isSameLine(_EditableOrderItem other) {
    if (mealId != other.mealId) return false;
    if (notes.trim() != other.notes.trim()) return false;
    final a = extras.map((e) => e.id).toList()..sort();
    final b = other.extras.map((e) => e.id).toList()..sort();
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Map<String, dynamic> toPayload() {
    return {
      'meal_id': mealId,
      'meal_name': name,
      'item_name': name,
      'quantity': quantity.round().clamp(1, 9999),
      'price': unitPrice,
      'unit_price': unitPrice,
      if (notes.isNotEmpty) 'note': notes,
      if (extras.isNotEmpty)
        'addons': extras
            .map((e) => int.tryParse(e.id.toString().trim()))
            .whereType<int>()
            .toList(),
    };
  }

  static _EditableOrderItem fromProduct(
    Product product, {
    double quantity = 1,
    List<Extra> extras = const [],
    String notes = '',
  }) {
    return _EditableOrderItem(
      mealId: product.id,
      name: product.name,
      quantity: quantity,
      unitPrice: product.price,
      extras: extras,
      notes: notes,
      localizedNames: product.localizedNames.isNotEmpty ? product.localizedNames : null,
    );
  }

  /// Build an editable row from a freshly-picked salon service. The dialog
  /// returns a payload identical in shape to the salon `card[i]` row, so we
  /// stash it on `salonData` for the save handler to re-emit verbatim.
  static _EditableOrderItem fromSalonResult(Map<String, dynamic> result) {
    final unit = result['unitPrice'] is num
        ? (result['unitPrice'] as num).toDouble()
        : double.tryParse(result['unitPrice']?.toString() ?? '') ?? 0.0;
    final qty = result['quantity'] is num
        ? (result['quantity'] as num).toInt()
        : int.tryParse(result['quantity']?.toString() ?? '') ?? 1;
    return _EditableOrderItem(
      // Synthetic id distinguishes new rows from existing booking_service_ids; save handler emits plain card[i].
      mealId:
          'new_${DateTime.now().microsecondsSinceEpoch}_${result['service_id']}',
      name: result['item_name']?.toString() ?? '',
      quantity: qty.toDouble(),
      unitPrice: unit,
      extras: const [],
      notes: '',
      salonData: Map<String, dynamic>.from(result),
    );
  }

  static _EditableOrderItem fromMap(Map<String, dynamic> map) {
    final langCode = translationService.currentLanguageCode
        .trim()
        .toLowerCase();
    final useAr = langCode.startsWith('ar') || langCode.startsWith('ur');
    final preferredLang = useAr ? 'ar' : 'en';

    String? resolveLocalized(dynamic value) {
      if (value == null) return null;
      if (value is Map) {
        final localized = value[preferredLang]?.toString().trim();
        if (localized != null && localized.isNotEmpty) return localized;
        for (final v in value.values) {
          final s = v?.toString().trim() ?? '';
          if (s.isNotEmpty) return s;
        }
        return null;
      }
      final s = value.toString().trim();
      if (s.startsWith('{') && s.contains('"ar"')) {
        try {
          final parsed = Map<String, dynamic>.from(jsonDecode(s) as Map);
          return resolveLocalized(parsed);
        } catch (e) {
          Log.d('EditOrderDialog', 'localized field JSON decode failed (non-fatal): $e');
        }
      }
      return s.isNotEmpty ? s : null;
    }

    String? pickText(List<dynamic> values) {
      for (final value in values) {
        final text = resolveLocalized(value);
        if (text != null && text.isNotEmpty) return text;
      }
      return null;
    }

    String mealId = pickText([
          map['meal_id'],
          map['product_id'],
          map['item_id'],
          map['id'],
          map['meal'] is Map ? (map['meal'] as Map)['id'] : null,
        ]) ??
        '';
    if (mealId.isEmpty) {
      mealId = DateTime.now().millisecondsSinceEpoch.toString();
    }

    final mealMap = map['meal'] is Map
        ? (map['meal'] as Map).map((k, v) => MapEntry(k.toString(), v))
        : <String, dynamic>{};
    final serviceMap = map['service'] is Map
        ? (map['service'] as Map).map((k, v) => MapEntry(k.toString(), v))
        : <String, dynamic>{};

    // Salon rows expose `service_name`; restaurant rows use `meal_name` — check service first or salon falls back to "Item".
    final name = pickText([
          map['service_name'],
          map['meal_name'],
          map['item_name'],
          map['name'],
          map['title'],
          mealMap['name'],
          serviceMap['name'],
        ]) ??
        'Item';

    double parseNum(dynamic value) {
      if (value == null) return 0.0;
      if (value is num) return value.toDouble();
      if (value is Map) return 0.0;
      final cleaned =
          value.toString().replaceAll(',', '').replaceAll(RegExp(r'[^\d.\-]'), '');
      return double.tryParse(cleaned) ?? 0.0;
    }

    final quantity = parseNum(map['quantity']).clamp(1, 9999).toDouble();
    var unitPrice =
        parseNum(map['unit_price'] ?? map['unitPrice'] ?? map['price']);
    if (unitPrice == 0 && mealMap.isNotEmpty) {
      unitPrice = parseNum(mealMap['price'] ?? mealMap['unit_price']);
    }

    final extras = <Extra>[];
    final extrasRaw = map['extras'] ??
        map['addons'] ??
        map['add_ons'] ??
        map['options'] ??
        map['modifiers'] ??
        map['operations'];
    if (extrasRaw is List) {
      for (final entry in extrasRaw) {
        if (entry is Map) {
          extras.add(Extra.fromJson(
              entry.map((k, v) => MapEntry(k.toString(), v))));
        } else if (entry != null) {
          extras.add(Extra(id: entry.toString(), name: entry.toString(), price: 0));
        }
      }
    } else if (extrasRaw is Map) {
      final nested = extrasRaw['operations'] ?? extrasRaw['items'];
      if (nested is List) {
        for (final entry in nested) {
          if (entry is Map) {
            extras.add(Extra.fromJson(
                entry.map((k, v) => MapEntry(k.toString(), v))));
          }
        }
      }
    }

    final Map<String, String>? locNames;
    final mt = map['meal_name_translations'];
    if (mt is Map) {
      locNames = {};
      for (final e in mt.entries) {
        final v = e.value?.toString().trim() ?? '';
        if (v.isNotEmpty) locNames[e.key.toString()] = v;
      }
    } else {
      locNames = null;
    }

    return _EditableOrderItem(
      mealId: mealId,
      name: name,
      quantity: quantity,
      unitPrice: unitPrice,
      extras: extras,
      notes: map['note']?.toString() ?? map['notes']?.toString() ?? '',
      localizedNames: locNames,
    );
  }
}

class _ProductPickerDialog extends StatefulWidget {
  final double taxRate;
  const _ProductPickerDialog({this.taxRate = 0.0});

  @override
  State<_ProductPickerDialog> createState() => _ProductPickerDialogState();
}

class _ProductPickerDialogState extends State<_ProductPickerDialog> {
  final ProductService _productService = getIt<ProductService>();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  String? get _salonPlaceholderLogo {
    if (ApiConstants.branchModule != 'salons') return null;
    final cached = getIt<BranchService>().cachedBranchReceiptInfo;
    if (cached == null) return null;
    String url = (cached['branch_logo_url']?.toString() ?? '').trim();
    if (url.isEmpty) {
      final branch = cached['branch'];
      if (branch is Map) {
        for (final key in const ['logo', 'image']) {
          final v = branch[key]?.toString().trim() ?? '';
          if (v.isNotEmpty && v.toLowerCase() != 'null') {
            url = v;
            break;
          }
        }
      }
    }
    if (url.isEmpty) return null;
    if (url.startsWith('/')) url = '${ApiConstants.baseUrl}$url';
    return url;
  }

  List<CategoryModel> _categories = [];
  List<Product> _products = [];
  String _selectedCategory = 'all';
  bool _isLoading = false;
  bool _isLastPage = false;
  int _page = 1;

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _loadProducts();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 180 &&
        !_isLoading &&
        !_isLastPage) {
      _loadMore();
    }
  }

  Future<void> _loadCategories() async {
    try {
      final categories = await _productService.getMealCategories();
      if (!mounted) return;
      setState(() => _categories = categories);
    } catch (e) {
      Log.d('catch', 'non-fatal: $e');
    }
  }

  Future<void> _loadProducts({bool reset = true}) async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    if (reset) {
      _page = 1;
      _isLastPage = false;
    }

    try {
      final products = await _productService.getProducts(
        categoryId: _selectedCategory,
        page: _page,
      );
      if (!mounted) return;
      setState(() {
        if (reset) {
          _products = products;
        } else {
          _products.addAll(products);
        }
        _isLastPage = products.length < 10;
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_isLastPage || _isLoading) return;
    setState(() => _page += 1);
    await _loadProducts(reset: false);
  }

  List<Product> get _filteredProducts {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _products;
    return _products
        .where((p) => p.name.toLowerCase().contains(query))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isCompact = size.width < 700;
    final dialogWidth = isCompact ? size.width * 0.92 : size.width * 0.8;
    final dialogHeight = isCompact ? size.height * 0.82 : size.height * 0.78;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      translationService.t('select_item'),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: translationService.t('search_items'),
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: context.appSurfaceAlt,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_categories.isNotEmpty)
              SizedBox(
                height: 40,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: _categories.length + 1,
                  itemBuilder: (context, index) {
                    final isAll = index == 0;
                    final category =
                        isAll ? null : _categories[index - 1];
                    final label = isAll
                        ? translationService.t('all')
                        : category?.name ?? '';
                    final value = isAll ? 'all' : category!.id;
                    final selected = _selectedCategory == value;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        selected: selected,
                        label: Text(label),
                        onSelected: (_) {
                          setState(() => _selectedCategory = value);
                          _loadProducts(reset: true);
                        },
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: _filteredProducts.isEmpty && !_isLoading
                  ? Center(
                      child: Text(
                        translationService.t('no_products'),
                        style: const TextStyle(color: Colors.grey),
                      ),
                    )
                  : GridView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(16),
                      gridDelegate:
                          SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: isCompact ? 2 : 4,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: isCompact ? 0.72 : 0.78,
                      ),
                      itemCount: _filteredProducts.length +
                          (_isLoading || !_isLastPage ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index >= _filteredProducts.length) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        final product = _filteredProducts[index];
                        return ProductCard(
                          product: product,
                          taxRate: widget.taxRate,
                          priceIsTaxInclusive:
                              ApiConstants.branchModule == 'salons',
                          placeholderImageUrl: _salonPlaceholderLogo,
                          onTap: () => Navigator.pop(context, product),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
