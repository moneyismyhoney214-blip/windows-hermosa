// ignore_for_file: invalid_use_of_protected_member, unused_element, unused_element_parameter, dead_code, dead_null_aware_expression
part of '../main_screen.dart';

extension MainScreenBuildWidgets on _MainScreenState {
  Widget _buildContent() {
    return _isLoading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      LucideIcons.alertCircle,
                      size: 48,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '${translationService.t('error')}: $_error',
                      style: const TextStyle(color: Colors.red),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _loadData,
                      child: Text(translationService.t('try_again')),
                    ),
                  ],
                ),
              )
            : Column(
                children: [
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        if (constraints.maxWidth <= 0) {
                          return const SizedBox.shrink();
                        }
                        // نحسب الـ filtered products مرة واحدة بس بدل ما نحسبها 6 مرات
                        final products = _filteredProducts;
                        if (products.isEmpty) {
                          return Center(
                            child: Text(
                              translationService.t('no_products'),
                              style: const TextStyle(
                                fontSize: 18,
                                color: Colors.grey,
                              ),
                            ),
                          );
                        }
                        final availableWidth = constraints.maxWidth;
                        final availableHeight = constraints.maxHeight;
                        final isPhoneLike = availableWidth < 700;
                        final iconScale = _mealIconScale.clamp(0.85, 1.15);
                        final gridPadding =
                            (availableWidth * 0.02).clamp(10.0, 24.0);
                        final gridSpacing =
                            (availableWidth * 0.012).clamp(8.0, 16.0);
                        final preferredTileWidth = isPhoneLike
                            ? (availableWidth * 0.36).clamp(120.0, 210.0) *
                                iconScale
                            : (availableWidth * 0.18).clamp(140.0, 220.0) *
                                iconScale;

                        final rawCount = ((availableWidth -
                                    (gridPadding * 2) +
                                    gridSpacing) /
                                (preferredTileWidth + gridSpacing))
                            .floor();
                        final crossAxisCount = isPhoneLike
                            ? rawCount.clamp(1, 4)
                            : rawCount.clamp(3, 5);

                        final tileWidth = (availableWidth -
                                (gridPadding * 2) -
                                (gridSpacing * (crossAxisCount - 1))) /
                            crossAxisCount;
                        final baseTileHeight = (!isPhoneLike &&
                                availableHeight.isFinite &&
                                availableHeight > 0)
                            ? ((availableHeight -
                                    (gridPadding * 2) -
                                    (gridSpacing * 2)) /
                                3)
                            : (tileWidth * 1.35);
                        final tileHeight = (isPhoneLike
                                ? baseTileHeight
                                : baseTileHeight * iconScale)
                            .clamp(170.0, 360.0);
                        final childAspectRatio = tileWidth / tileHeight;

                        return CustomScrollView(
                          controller: _productsScrollController,
                          physics: const BouncingScrollPhysics(),
                          slivers: [
                            SliverPadding(
                              padding: EdgeInsets.all(gridPadding),
                              sliver: SliverGrid(
                                delegate: SliverChildBuilderDelegate(
                                  (context, index) {
                                    final product = products[index];
                                    return ProductCard(
                                      key: ValueKey(product.id),
                                      product: product,
                                      isDisabled: _mealAvailabilityService
                                          .isMealDisabled(
                                        product.id,
                                      ),
                                      taxRate: _isTaxEnabled ? _taxRate : 0.0,
                                      onTap: () => _onProductTap(product),
                                      onQuickAdd: () => _addToCartWithExtras(
                                        product,
                                        const <Extra>[],
                                        1.0,
                                        '',
                                      ),
                                    );
                                  },
                                  childCount: products.length,
                                ),
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: crossAxisCount,
                                  childAspectRatio: childAspectRatio,
                                  crossAxisSpacing: gridSpacing,
                                  mainAxisSpacing: gridSpacing,
                                ),
                              ),
                            ),
                            if (!_isLastPage && _isLoadingMore)
                              const SliverToBoxAdapter(
                                child: Padding(
                                  padding: EdgeInsets.all(24),
                                  child: Center(
                                    child: SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Color(0xFFF58220),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              );
  }

  Widget _buildSearchHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: context.appHeaderBg,
        border: Border(bottom: BorderSide(color: context.appBorder)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 940;
          final searchMaxWidth = isNarrow ? constraints.maxWidth : 420.0;
          final userInfo = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _userName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      _userRole,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  color: Color(0xFFFFF7ED),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    _initials,
                    style: const TextStyle(
                      color: Color(0xFFC2410C),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          );

          final searchInput = Container(
            height: 42,
            decoration: BoxDecoration(
              color: context.appSurfaceAlt,
              borderRadius: BorderRadius.circular(12),
            ),
            child: TextField(
              onChanged: (val) {
                  _searchDebounce?.cancel();
                  _searchDebounce = Timer(const Duration(milliseconds: 300), () {
                    if (mounted) setState(() => _searchQuery = val);
                  });
                },
              decoration: InputDecoration(
                hintText: translationService.t('search_products'),
                prefixIcon: const Icon(LucideIcons.search, size: 20),
                filled: true,
                fillColor: context.appSurfaceAlt,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 0,
                  horizontal: 16,
                ),
              ),
            ),
          );

          final searchField = SizedBox(
            width: searchMaxWidth,
            child: Row(
              children: [
                _buildMoreMenu(),
                const SizedBox(width: 8),
                Expanded(child: searchInput),
              ],
            ),
          );

          if (isNarrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                searchField,
                const SizedBox(height: 12),
                Align(alignment: Alignment.centerLeft, child: userInfo),
              ],
            );
          }

          return Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: searchField,
                ),
              ),
              const SizedBox(width: 16),
              Flexible(
                  child:
                      Align(alignment: Alignment.centerRight, child: userInfo)),
            ],
          );
        },
      ),
    );
  }

  /// Salon mode toggle bar: switch between "خدمات" (Services) and "باقات الخدمات" (Package Services).
  Widget _buildSalonServiceTypeBar() {
    Widget _pill(String label, String value, IconData icon) {
      final isActive = _salonServiceType == value;
      return InkWell(
        onTap: () => _onSalonServiceTypeChanged(value),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFFF58220) : const Color(0xFFE2E8F0),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: isActive ? Colors.white : const Color(0xFF64748B),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: isActive ? Colors.white : const Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      margin: const EdgeInsets.only(bottom: 4),
      color: Colors.transparent,
      child: Row(
        children: [
          _pill(_trUi('خدمات', 'Services'), 'services', LucideIcons.scissors),
          const SizedBox(width: 8),
          _pill(_trUi('باقات الخدمات', 'Package Services'), 'packageServices', LucideIcons.package2),
        ],
      ),
    );
  }

  Widget _buildHungerstationBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      margin: const EdgeInsets.only(bottom: 4),
      color: _isMenuListActive
          ? (context.isDark
              ? context.appPrimary.withValues(alpha: 0.12)
              : const Color(0xFFFFF7ED))
          : Colors.transparent,
      child: Row(
        children: [
          // Menu selector button
          InkWell(
            onTap: _showMenuListPicker,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _isMenuListActive
                    ? context.appPrimary
                    : context.appSurfaceAlt,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _isMenuListActive ? Icons.restaurant_menu : Icons.storefront,
                    size: 16,
                    color: _isMenuListActive ? Colors.white : context.appText,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _isMenuListActive
                        ? _activeMenuListName
                        : _trUi('المينيو الأساسي', 'Main Menu'),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _isMenuListActive ? Colors.white : context.appText,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.arrow_drop_down,
                    size: 18,
                    color: _isMenuListActive ? Colors.white : context.appText,
                  ),
                ],
              ),
            ),
          ),
          // Price type selector (only when a menu list is active)
          if (_isMenuListActive) ...[
            const SizedBox(width: 12),
            _buildPriceTypeChip(
              label: _trUi('توصيل', 'Delivery'),
              value: 'delivery',
              icon: Icons.delivery_dining,
            ),
            const SizedBox(width: 6),
            _buildPriceTypeChip(
              label: _trUi('استلام', 'Pickup'),
              value: 'pickup',
              icon: Icons.shopping_bag_outlined,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPriceTypeChip({
    required String label,
    required String value,
    required IconData icon,
  }) {
    final isActive = _menuListPriceType == value;
    return InkWell(
      onTap: () => _switchMenuListPriceType(value),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF2563EB) : context.appCardBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive ? const Color(0xFF2563EB) : context.appBorder,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: isActive ? Colors.white : context.appText),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isActive ? Colors.white : context.appText,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVerticalCategoryBar() {
    if (_categories.isEmpty) return const SizedBox.shrink();
    final sorted = _sortedCategoriesCache ??= List<CategoryModel>.from(_categories)
      ..sort((a, b) {
        if (a.id == 'all') return -1;
        if (b.id == 'all') return 1;
        final aPinned = _pinnedCategoryIds.contains(a.id) ? 0 : 1;
        final bPinned = _pinnedCategoryIds.contains(b.id) ? 0 : 1;
        return aPinned.compareTo(bPinned);
      });
    final catScale = _sidebarIconScale.clamp(0.85, 1.4);
    final sidebarWidth = (120.0 * catScale).clamp(100.0, 170.0);
    final catFontSize = 12.0 * catScale;
    final catPadV = 12.0 * catScale;
    return Container(
      width: sidebarWidth,
      decoration: BoxDecoration(
        color: context.appSurfaceAlt,
      ),
      child: Directionality(
        textDirection: translationService.isRTL ? ui.TextDirection.rtl : ui.TextDirection.ltr,
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          itemCount: sorted.length,
          itemBuilder: (context, index) {
            final item = sorted[index];
            final isActive = _selectedCategory == item.id && _activeTab == 'home';
            final isPinned = _pinnedCategoryIds.contains(item.id);
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: GestureDetector(
                onLongPress: () {
                  setState(() {
                    if (_pinnedCategoryIds.contains(item.id)) {
                      _pinnedCategoryIds.remove(item.id);
                    } else {
                      _pinnedCategoryIds.add(item.id);
                    }
                    _sortedCategoriesCache = null;
                  });
                },
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => _switchCategory(item.id),
                    borderRadius: BorderRadius.circular(12),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: double.infinity,
                          padding: EdgeInsets.symmetric(horizontal: 6, vertical: catPadV),
                          decoration: BoxDecoration(
                            color: isActive ? context.appPrimary : context.appCardBg,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isActive
                                  ? context.appPrimary
                                  : context.appBorder,
                            ),
                            boxShadow: isActive
                                ? [
                                    BoxShadow(
                                      color: context.appPrimary.withValues(alpha: 0.3),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ]
                                : null,
                          ),
                          child: Center(
                            child: Text(
                              item.name,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isActive
                                    ? Colors.white
                                    : context.appText,
                                fontWeight: FontWeight.w600,
                                fontSize: catFontSize,
                                height: 1.2,
                              ),
                            ),
                          ),
                        ),
                        if (isPinned)
                          Positioned(
                            top: -4,
                            right: -4,
                            child: Container(
                              width: 18,
                              height: 18,
                              decoration: BoxDecoration(
                                color: const Color(0xFF3B82F6),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 1.5),
                              ),
                              child: const Icon(
                                LucideIcons.pin,
                                size: 10,
                                color: Colors.white,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildShiftedVerticalCategoryBar() {
    return Transform.translate(
      offset: const Offset(-15, 0),
      child: RepaintBoundary(child: _buildVerticalCategoryBar()),
    );
  }

  Widget _buildCategoryBar() {
    if (_categories.isEmpty) return const SizedBox.shrink();
    // Use cached sorted list - invalidated when categories or pins change
    final sorted = _sortedCategoriesCache ??= List<CategoryModel>.from(_categories)
      ..sort((a, b) {
        if (a.id == 'all') return -1;
        if (b.id == 'all') return 1;
        final aPinned = _pinnedCategoryIds.contains(a.id) ? 0 : 1;
        final bPinned = _pinnedCategoryIds.contains(b.id) ? 0 : 1;
        return aPinned.compareTo(bPinned);
      });
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        final catScale = _sidebarIconScale.clamp(0.85, 1.4);
        // Responsive sizes (scaled by sidebar icon scale)
        final boxWidth = (screenWidth < 600 ? 80.0 : (screenWidth < 1000 ? 95.0 : 110.0)) * catScale;
        final boxHeight = (screenWidth < 600 ? 78.0 : (screenWidth < 1000 ? 90.0 : 100.0)) * catScale;
        final fontSize = (screenWidth < 600 ? 11.0 : (screenWidth < 1000 ? 12.0 : 13.0)) * catScale;
        final spacing = screenWidth < 600 ? 10.0 : (screenWidth < 1000 ? 12.0 : 14.0);
        final borderRadius = screenWidth < 600 ? 12.0 : 14.0;
        final pinSize = screenWidth < 600 ? 18.0 : 22.0;
        final pinIconSize = screenWidth < 600 ? 10.0 : 12.0;

        return Container(
          margin: const EdgeInsets.only(bottom: 4),
          child: Directionality(
            textDirection: translationService.isRTL ? ui.TextDirection.rtl : ui.TextDirection.ltr,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
              children: List.generate(sorted.length, (index) {
                final item = sorted[index];
                final isActive = _selectedCategory == item.id && _activeTab == 'home';
                final isPinned = _pinnedCategoryIds.contains(item.id);
                return Padding(
                  padding: EdgeInsets.only(right: index < sorted.length - 1 ? spacing : 0),
                  child: Material(
                    color: Colors.transparent,
                    child: GestureDetector(
                      onLongPress: () {
                        setState(() {
                          if (_pinnedCategoryIds.contains(item.id)) {
                            _pinnedCategoryIds.remove(item.id);
                          } else {
                            _pinnedCategoryIds.add(item.id);
                          }
                          _sortedCategoriesCache = null;
                        });
                      },
                      child: InkWell(
                        onTap: () => _switchCategory(item.id),
                        borderRadius: BorderRadius.circular(borderRadius),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: boxWidth,
                              height: boxHeight,
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                              decoration: BoxDecoration(
                                color: isActive ? context.appPrimary : context.appCardBg,
                                borderRadius: BorderRadius.circular(borderRadius),
                                border: Border.all(
                                  color: isActive
                                      ? context.appPrimary
                                      : context.appBorder,
                                ),
                                boxShadow: isActive
                                    ? [
                                        BoxShadow(
                                          color: context.appPrimary.withValues(alpha: 0.3),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Center(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                  child: Text(
                                    item.name,
                                    textAlign: TextAlign.center,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: isActive
                                          ? Colors.white
                                          : context.appText,
                                      fontWeight: FontWeight.w600,
                                      fontSize: fontSize,
                                      height: 1.2,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            if (isPinned)
                              Positioned(
                                top: -4,
                                right: -4,
                                child: Container(
                                  width: pinSize,
                                  height: pinSize,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF3B82F6),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 1.5),
                                  ),
                                  child: Icon(
                                    LucideIcons.pin,
                                    size: pinIconSize,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
        );
      },
    );
  }

  Widget _buildMoreMenu({Color? iconColor}) {
    return PopupMenuButton<String>(
      icon: Icon(LucideIcons.menu, color: iconColor ?? const Color(0xFF64748B)),
      tooltip: translationService.t('settings'),
      onSelected: (value) {
        switch (value) {
          case 'settings':
            setState(() => _activeTab = 'settings');
            break;
          case 'switch_branch':
            _handleSwitchBranch();
            break;
          case 'logout':
            _handleLogout();
            break;
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'switch_branch',
          child: Row(
            children: [
              const Icon(LucideIcons.repeat, size: 18, color: Color(0xFF64748B)),
              const SizedBox(width: 12),
              Text(translationService.t('switch_branch')),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'settings',
          child: Row(
            children: [
              const Icon(LucideIcons.settings, size: 18, color: Color(0xFF64748B)),
              const SizedBox(width: 12),
              Text(translationService.t('settings')),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'logout',
          child: Row(
            children: [
              const Icon(LucideIcons.logOut, size: 18, color: Colors.red),
              const SizedBox(width: 12),
              Text(
                translationService.t('logout'),
                style: const TextStyle(color: Colors.red),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNavTabs() {
    final sidebarScale = _sidebarIconScale.clamp(0.85, 1.4);
    final iconSize = 18.0 * sidebarScale;
    final fontSize = 14.0 * sidebarScale;
    final hPad = 20.0 * sidebarScale;
    final vPad = 10.0 * sidebarScale;
    final tabHeight = (80.0 * sidebarScale).clamp(68.0, 112.0);
    return Container(
      height: tabHeight,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _effectiveNavItems.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final item = _effectiveNavItems[index];
          final isSelected = _activeTab == item.id;
          final tabLabel = _navLabel(item.id);
          return InkWell(
            onTap: () => setState(() => _activeTab = item.id),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
              decoration: BoxDecoration(
                color: isSelected ? context.appPrimary : context.appCardBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected
                      ? context.appPrimary
                      : context.appBorder,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    item.icon,
                    size: iconSize,
                    color: isSelected ? Colors.white : context.appText,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    tabLabel,
                    style: TextStyle(
                      fontSize: fontSize,
                      color: isSelected ? Colors.white : context.appText,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _navLabel(String id) {
    switch (id) {
      case 'home':
        return translationService.t('home');
      case 'orders':
        return _isSalonMode
            ? _trUi('تذاكر مراجعه', 'Review Tickets')
            : translationService.t('orders');
      case 'invoices':
        return translationService.t('invoices');
      case 'tables':
        return translationService.t('tables');
      case 'deposits':
        return _trUi('العرابين', 'Deposits');
      case 'customers':
        return translationService.t('customers');
      case 'reports':
        return translationService.t('reports');
      case 'settings':
        return translationService.t('settings');
      default:
        return id;
    }
  }

  double _resolveOrderPanelWidth(
    double viewportWidth, {
    required bool hasPinnedSidebar,
  }) {
    final proposed = viewportWidth * (hasPinnedSidebar ? 0.30 : 0.35);
    final maxWidth = hasPinnedSidebar ? 430.0 : 390.0;
    return proposed.clamp(300.0, maxWidth).toDouble();
  }

  Widget _buildOrderPanel() {
    return OrderPanel(
      cart: _cart,
      totalAmount: _totalAmount,
      onUpdateQuantity: _updateQuantity,
      onRemove: _removeFromCart,
      onDiscount: _updateDiscount,
      onToggleFree: _toggleFree,
      onClear: _clearCart,
      onOrderDiscount: _setOrderDiscount,
      onToggleOrderFree: _toggleOrderFreeState,
      isOrderFree: _isOrderFree,
      orderDiscount: _orderDiscount,
      selectedTable: _selectedTable,
      onCancelTable: () => setState(() {
        _selectedTable = null;
        _lastSelectedTable = null;
      }),
      selectedCustomer: _selectedCustomer,
      onSelectCustomer: (customer) =>
          setState(() => _selectedCustomer = customer),
      onPay: _handlePay,
      onPayLater: _handlePayLater,
      onBookingLongPress: _showBookingDetails,
      onShowItemDetails: _showMealDetailsForCartItem,
      selectedOrderType: _selectedOrderType,
      typeOptions: _orderTypeOptions, // Pass real options
      cdsEnabled: _isCdsEnabled,
      kdsEnabled: _isKdsEnabled,
      taxRate: _taxRate,
      onOrderTypeChanged: (v) {
        setState(() {
          _selectedOrderType = v;
          if (!_isCarOrderType(v)) {
            _carNumberController.clear();
          }
          if (!_isTableOrderType(v)) {
            _selectedTable = null;
            _lastSelectedTable = null;
          }
          if (_isTableOrderType(v) && _selectedTable == null) {
            _activeTab = 'tables';
          }
        });
      },
      onBrowsePromocodes: _showPromocodesSheet,
      appliedPromoCode: _activePromoCode,
      onClearPromoCode: () => _applyPromoCode(null),
      requireCustomerSelection: _requireCustomerSelection,
      carNumberController: _carNumberController,
      onApplyCoupon: (code) async {
        final normalizedCode = code.trim();
        if (normalizedCode.isEmpty) {
          await _showPromocodesSheet();
          return;
        }

        // Show loading
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) =>
              const Center(child: CircularProgressIndicator()),
        );

        try {
          final promoService = PromoCodeService();
          final promo = await promoService.getPromoCodeByCode(normalizedCode);

          if (mounted) Navigator.pop(context); // Close loading

          if (promo != null && mounted) {
            _applyPromoCode(promo);

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    translationService.t(
                      'promo_applied',
                      args: {'code': promo.code},
                    ),
                  ),
                  backgroundColor: Colors.green,
                ),
              );
            }
          } else {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(translationService.t('promo_invalid')),
                  backgroundColor: Colors.red,
                ),
              );
            }
          }
        } catch (e) {
          if (mounted) Navigator.pop(context);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  translationService.t(
                    'promo_apply_error',
                    args: {'error': e},
                  ),
                ),
              ),
            );
          }
        }
      },
      orderNotesController: _orderNotesController,
      isSalonMode: _isSalonMode,
    );
  }
}
