// ignore_for_file: invalid_use_of_protected_member, unused_element, unused_element_parameter, dead_code, dead_null_aware_expression
part of '../main_screen.dart';

extension MainScreenPromo on _MainScreenState {
  void _applyPromoCode(PromoCode? promo) {
    setState(() {
      _activePromoCode = promo;
      // Don't clear manual discount — both should stack
    });
  }

  Future<void> _loadPromoCodes() async {
    try {
      final promos = await PromoCodeService().getPromoCodes();
      if (mounted) {
        setState(() => _cachedPromoCodes = promos);
      }
    } catch (e) {
      print('⚠️ Failed to load promo codes: $e');
    }
  }

  Future<void> _showPromocodesSheet() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final promoService = PromoCodeService();
      final promocodes = await promoService.getAllPromoCodes();

      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }

      if (!mounted) return;
      if (promocodes.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(translationService.t('promo_none_available')),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      final selected = await showDialog<PromoCode>(
        context: context,
        builder: (context) => _PromoCodesDialog(
          promocodes: promocodes,
          activePromoId: _activePromoCode?.id,
        ),
      );

      if (selected != null && mounted) {
        _applyPromoCode(selected);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              translationService.t(
                'promo_applied',
                args: {'code': selected.code},
              ),
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              translationService.t(
                'promo_fetch_error',
                args: {'error': e},
              ),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Promo Codes Dialog with search
// ---------------------------------------------------------------------------
class _PromoCodesDialog extends StatefulWidget {
  final List<PromoCode> promocodes;
  final String? activePromoId;

  const _PromoCodesDialog({
    required this.promocodes,
    this.activePromoId,
  });

  @override
  State<_PromoCodesDialog> createState() => _PromoCodesDialogState();
}

class _PromoCodesDialogState extends State<_PromoCodesDialog> {
  final _searchController = TextEditingController();
  List<PromoCode> _filtered = [];
  bool _isSearching = false;
  Timer? _debounce;

  bool get _useArabicUi {
    final code = translationService.currentLanguageCode.trim().toLowerCase();
    return code.startsWith('ar') || code.startsWith('ur');
  }

  String _tr(String ar, String en) => _useArabicUi ? ar : en;

  @override
  void initState() {
    super.initState();
    _filtered = widget.promocodes;
    _searchController.addListener(_onSearch);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearch() {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      setState(() {
        _filtered = widget.promocodes;
        _isSearching = false;
      });
      return;
    }

    // بحث محلي أولاً بالاسم
    final localResults = widget.promocodes
        .where((p) => p.code.toLowerCase().contains(query))
        .toList();
    setState(() => _filtered = localResults);

    // بحث بالكود من الـ API بعد تأخير
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      if (!mounted) return;
      setState(() => _isSearching = true);
      try {
        final promoService = PromoCodeService();
        final apiResult = await promoService.getPromoCodeByCode(query);
        if (!mounted) return;
        if (apiResult != null) {
          // أضف النتيجة من الـ API لو مش موجودة محلياً
          final exists = localResults.any((p) => p.id == apiResult.id);
          if (!exists) {
            setState(() {
              _filtered = [apiResult, ...localResults];
            });
          }
        }
      } catch (_) {}
      if (mounted) setState(() => _isSearching = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 480,
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              decoration: const BoxDecoration(
                color: Color(0xFFF58220),
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(LucideIcons.badgePercent,
                      color: Colors.white, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _tr('الكوبونات والعروض', 'Coupons & Offers'),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.x,
                        color: Colors.white, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Search bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: _tr('ابحث عن كوبون...', 'Search coupon...'),
                  hintStyle:
                      const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                  prefixIcon: const Icon(LucideIcons.search,
                      size: 18, color: Color(0xFF94A3B8)),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFFF58220)),
                  ),
                ),
              ),
            ),

            // Loading indicator
            if (_isSearching)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: LinearProgressIndicator(
                  minHeight: 2,
                  color: Color(0xFFF58220),
                ),
              ),

            // List
            Flexible(
              child: _filtered.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(LucideIcons.searchX,
                                size: 40, color: Color(0xFFCBD5E1)),
                            const SizedBox(height: 12),
                            Text(
                              _tr('لا توجد كوبونات', 'No coupons found'),
                              style: const TextStyle(
                                  color: Color(0xFF94A3B8), fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      itemCount: _filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final promo = _filtered[index];
                        return _buildPromoCard(promo);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPromoCard(PromoCode promo) {
    final isCurrentlyApplied = widget.activePromoId == promo.id;
    final isActive = promo.isActive;

    // Discount text
    final discountText = promo.type == DiscountType.percentage
        ? '${promo.discount.toStringAsFixed(0)}%'
        : '${promo.discount.toStringAsFixed(2)} ${ApiConstants.currency}';

    return GestureDetector(
      onTap: isActive
          ? () => Navigator.pop(context, promo)
          : null,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isCurrentlyApplied
              ? const Color(0xFFFFF7ED)
              : (isActive ? Colors.white : const Color(0xFFF8FAFC)),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isCurrentlyApplied
                ? const Color(0xFFF58220)
                : (isActive
                    ? const Color(0xFFE2E8F0)
                    : const Color(0xFFE2E8F0)),
            width: isCurrentlyApplied ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            // Discount badge
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: isActive
                    ? const Color(0xFFF58220).withValues(alpha: 0.1)
                    : const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Text(
                discountText,
                style: TextStyle(
                  fontSize: promo.type == DiscountType.percentage ? 18 : 13,
                  fontWeight: FontWeight.bold,
                  color: isActive
                      ? const Color(0xFFF58220)
                      : const Color(0xFF94A3B8),
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(width: 12),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          promo.code,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: isActive
                                ? const Color(0xFF1E293B)
                                : const Color(0xFF94A3B8),
                          ),
                        ),
                      ),
                      if (isCurrentlyApplied)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF22C55E),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            _tr('مطبّق', 'Applied'),
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        )
                      else if (!isActive)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            _tr('منتهي', 'Expired'),
                            style: const TextStyle(
                              fontSize: 10,
                              color: Color(0xFFEF4444),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),

                  // Details row
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      // Discount type
                      _infoChip(
                        icon: LucideIcons.percent,
                        text: promo.type == DiscountType.percentage
                            ? _tr('خصم نسبة', 'Percentage')
                            : _tr('خصم ثابت', 'Fixed'),
                      ),
                      // Max discount
                      if (promo.maxDiscount != null)
                        _infoChip(
                          icon: LucideIcons.arrowUpCircle,
                          text:
                              '${_tr('حد أقصى', 'Max')}: ${promo.maxDiscountDisplay ?? '${promo.maxDiscount!.toStringAsFixed(2)} ${ApiConstants.currency}'}',
                        ),
                      // Min pay
                      if (promo.minPay != null)
                        _infoChip(
                          icon: LucideIcons.wallet,
                          text:
                              '${_tr('حد أدنى', 'Min')}: ${promo.minPayDisplay ?? '${promo.minPay!.toStringAsFixed(2)} ${ApiConstants.currency}'}',
                        ),
                      // Max uses
                      if (promo.maxUse != null)
                        _infoChip(
                          icon: LucideIcons.repeat,
                          text:
                              '${_tr('عدد الاستخدام', 'Uses')}: ${promo.maxUse}',
                        ),
                    ],
                  ),

                  // Validity dates
                  if (promo.durationFrom != null ||
                      promo.durationTo != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(LucideIcons.calendar,
                            size: 12, color: Color(0xFF94A3B8)),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            _formatDateRange(
                                promo.durationFrom, promo.durationTo),
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF94A3B8),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            // Apply arrow
            if (isActive && !isCurrentlyApplied)
              const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(LucideIcons.chevronLeft,
                    size: 20, color: Color(0xFFF58220)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _infoChip({required IconData icon, required String text}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: const Color(0xFF94A3B8)),
        const SizedBox(width: 3),
        Text(
          text,
          style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
        ),
      ],
    );
  }

  String _formatDateRange(String? from, String? to) {
    String formatDate(String raw) {
      try {
        final dt = DateTime.parse(raw);
        return DateFormat('yyyy/MM/dd').format(dt);
      } catch (_) {
        return raw.length > 10 ? raw.substring(0, 10) : raw;
      }
    }

    if (from != null && to != null) {
      return '${formatDate(from)} - ${formatDate(to)}';
    } else if (from != null) {
      return '${_tr('من', 'From')}: ${formatDate(from)}';
    } else if (to != null) {
      return '${_tr('حتى', 'Until')}: ${formatDate(to)}';
    }
    return '';
  }
}
