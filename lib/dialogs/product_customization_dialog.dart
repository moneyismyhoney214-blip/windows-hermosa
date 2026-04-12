import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../models.dart';
import '../services/api/product_service.dart';
import '../locator.dart';

class ProductCustomizationDialog extends StatefulWidget {
  final Product product;
  final Function(Product, List<Extra>, double, String) onConfirm;
  final double taxRate;

  const ProductCustomizationDialog({
    super.key,
    required this.product,
    required this.onConfirm,
    this.taxRate = 0.0,
  });

  @override
  State<ProductCustomizationDialog> createState() =>
      _ProductCustomizationDialogState();
}

class _ProductCustomizationDialogState
    extends State<ProductCustomizationDialog> {
  static const _brand = Color(0xFFF58220);
  static const _brandLight = Color(0xFFFFF7ED);
  static const _brandBg = Color(0xFFFFF3E0);

  final Map<String, int> _selectedExtraQuantities = {};
  double _quantity = 1.0;
  final TextEditingController _notesController = TextEditingController();
  Map<String, List<Extra>> _groupedAddons = {};
  bool _isLoadingAddons = true;

  // ───────── lifecycle ─────────
  @override
  void initState() {
    super.initState();
    _loadAddons();
  }

  Future<void> _loadAddons() async {
    try {
      final productService = getIt<ProductService>();
      final addons =
          await productService.getMealAddonsGrouped(widget.product.id);
      if (mounted) setState(() { _groupedAddons = addons; _isLoadingAddons = false; });
    } catch (_) {
      if (mounted) setState(() => _isLoadingAddons = false);
    }
  }

  // ───────── selection helpers ─────────
  void _toggleExtra(String id) {
    setState(() {
      if (_selectedExtraQuantities.containsKey(id)) {
        _selectedExtraQuantities.remove(id);
      } else {
        _selectedExtraQuantities[id] = 1;
      }
    });
  }

  void _changeExtraQty(String id, int delta) {
    setState(() {
      final current = _selectedExtraQuantities[id];
      if (current == null) { if (delta > 0) _selectedExtraQuantities[id] = 1; return; }
      final next = current + delta;
      if (next <= 0) { _selectedExtraQuantities.remove(id); } else { _selectedExtraQuantities[id] = next; }
    });
  }

  List<Extra> get _allAvailableExtras {
    final merged = <String, Extra>{};
    for (final e in widget.product.extras) { merged[e.id] = e; }
    for (final g in _groupedAddons.values) { for (final e in g) { merged[e.id] = e; } }
    return merged.values.toList();
  }


  List<Extra> _buildSelectedExtrasExpanded() {
    final expanded = <Extra>[];
    for (final e in _allAvailableExtras.where((e) => _selectedExtraQuantities.containsKey(e.id))) {
      for (var i = 0; i < (_selectedExtraQuantities[e.id] ?? 1); i++) { expanded.add(e); }
    }
    return expanded;
  }

  void _onConfirm() {
    final notes = _notesController.text.trim();
    widget.onConfirm(widget.product, _buildSelectedExtrasExpanded(), _quantity, notes);
    Navigator.pop(context);
  }

  // ══════════════════════════════════════════════════════════
  //  BUILD
  // ══════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final isWide = screen.width >= 700;

    final hasGrouped = _groupedAddons.values.any((g) => g.isNotEmpty);
    final baseExtras = hasGrouped ? <Extra>[] : widget.product.extras;
    final visibleGroups = _groupedAddons.entries
        .where((e) => e.value.isNotEmpty)
        .where((e) => e.key.trim().toLowerCase() != 'global')
        .toList();

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: isWide ? 24 : 8,
        vertical: isWide ? 16 : 12,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: Container(
        width: isWide ? (screen.width * 0.85).clamp(700.0, 1200.0) : screen.width,
        height: (screen.height * 0.92).clamp(500.0, double.infinity),
        color: const Color(0xFFF4F4F4),
        child: Column(
          children: [
            _header(),
            Expanded(
              child: isWide
                  ? _wideBody(baseExtras, visibleGroups)
                  : _narrowBody(baseExtras, visibleGroups),
            ),
            _footer(),
          ],
        ),
      ),
    );
  }

  // ─────────────────────── HEADER ───────────────────────
  Widget _header() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      color: Colors.white,
      child: Row(
        children: [
          Container(
            width: 30, height: 30,
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.grey.shade400)),
            child: const Center(child: Text('Z', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(widget.product.name,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          InkWell(
            onTap: () => Navigator.pop(context),
            borderRadius: BorderRadius.circular(6),
            child: Container(
              width: 34, height: 34,
              decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(6)),
              child: const Icon(LucideIcons.x, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────── WIDE BODY (tablet) ───────────────────────
  Widget _wideBody(List<Extra> base, List<MapEntry<String, List<Extra>>> groups) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ─── Left 35% ───
        Expanded(
          flex: 35,
          child: _leftColumn(),
        ),
        const VerticalDivider(width: 1, thickness: 1, color: Color(0xFFE0E0E0)),
        // ─── Right 65% ───
        Expanded(
          flex: 65,
          child: _rightColumn(base, groups),
        ),
      ],
    );
  }

  // ─────────────────────── NARROW BODY (phone) ───────────────────────
  Widget _narrowBody(List<Extra> base, List<MapEntry<String, List<Extra>>> groups) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _productImage(),
          const SizedBox(height: 14),
          _quantityRow(),
          const SizedBox(height: 14),
          _priceChipsRow(),
          const SizedBox(height: 14),
          _notesField(),
          const SizedBox(height: 16),
          ..._addonWidgets(base, groups),
        ],
      ),
    );
  }

  // ─────────────────────── LEFT COLUMN ───────────────────────
  Widget _leftColumn() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Product image ──
          _productImage(),
          const SizedBox(height: 16),
          // ── Quantity ──
          _quantityRow(),
          const SizedBox(height: 18),
          // ── الأسعار ──
          const Text('الأسعار', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF333333))),
          const SizedBox(height: 8),
          _priceChipsRow(),
          const SizedBox(height: 18),
          // ── ملاحظات ──
          const Text('ملاحظات', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF333333))),
          const SizedBox(height: 8),
          _notesField(),
        ],
      ),
    );
  }

  // ─────────────────────── RIGHT COLUMN ───────────────────────
  Widget _rightColumn(List<Extra> base, List<MapEntry<String, List<Extra>>> groups) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _addonWidgets(base, groups),
      ),
    );
  }

  // ─────────────────────── ADDON SECTIONS ───────────────────────
  List<Widget> _addonWidgets(List<Extra> base, List<MapEntry<String, List<Extra>>> groups) {
    final w = <Widget>[];
    final hasAny = base.isNotEmpty || (!_isLoadingAddons && groups.isNotEmpty);

    if (hasAny) {
      w.add(const Padding(
        padding: EdgeInsets.only(bottom: 10),
        child: Text('الإضافات', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF333333))),
      ));
    }

    if (base.isNotEmpty) {
      w.add(_addonsGrid(base));
      w.add(const SizedBox(height: 10));
    }

    if (_isLoadingAddons) {
      w.add(const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Center(child: CircularProgressIndicator())));
    } else {
      for (final entry in groups) {
        w.add(_addonsGrid(entry.value));
        w.add(const SizedBox(height: 10));
      }
    }
    return w;
  }

  // ═══════════════════ COMPONENTS ═══════════════════

  // ── Product image (155 x 155) ──
  Widget _productImage() {
    final hasImg = widget.product.image != null && widget.product.image!.isNotEmpty;
    return Center(
      child: Container(
        width: 155, height: 155,
        decoration: BoxDecoration(color: _brandLight, borderRadius: BorderRadius.circular(10)),
        clipBehavior: Clip.antiAlias,
        child: hasImg
            ? Image.network(widget.product.image!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _imgPlaceholder())
            : _imgPlaceholder(),
      ),
    );
  }

  Widget _imgPlaceholder() {
    final initials = widget.product.name.length >= 2
        ? widget.product.name.substring(0, 2).toUpperCase()
        : widget.product.name.toUpperCase();
    return Center(child: Text(initials, style: const TextStyle(fontSize: 38, fontWeight: FontWeight.bold, color: _brand)));
  }

  // ── Quantity row (44px buttons) ──
  Widget _quantityRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _circleBtn(LucideIcons.minus, () => setState(() => _quantity = _quantity > 1 ? _quantity - 1 : 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: Text(
            _quantity % 1 == 0 ? _quantity.toStringAsFixed(0) : _quantity.toStringAsFixed(2),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
        ),
        _circleBtn(LucideIcons.plus, () => setState(() => _quantity += 1)),
      ],
    );
  }

  Widget _circleBtn(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        width: 44, height: 44,
        decoration: const BoxDecoration(color: _brand, shape: BoxShape.circle),
        child: Icon(icon, size: 22, color: Colors.white),
      ),
    );
  }

  // ── Price chips row ──
  Widget _priceChipsRow() {
    final price = widget.product.price * (1 + widget.taxRate);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _priceChip(price.toStringAsFixed(2), true),
      ],
    );
  }

  Widget _priceChip(String price, bool selected) {
    return Container(
      width: 80, height: 52,
      decoration: BoxDecoration(
        color: selected ? _brand : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: selected ? _brand : Colors.grey[350]!, width: 1.5),
      ),
      child: Center(
        child: Text(price, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: selected ? Colors.white : Colors.black87)),
      ),
    );
  }

  // ── Notes field ──
  Widget _notesField() {
    return TextField(
      controller: _notesController,
      maxLines: 3,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        hintText: 'أضف ملاحظات...',
        hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey[300]!)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey[300]!)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _brand)),
      ),
    );
  }

  // ── Addons grid (responsive 3/2/1 columns, aspect ~0.9) ──
  Widget _addonsGrid(List<Extra> extras) {
    return LayoutBuilder(builder: (context, box) {
      final cols = box.maxWidth >= 480 ? 3 : box.maxWidth >= 300 ? 2 : 1;
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          childAspectRatio: 0.88,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
        ),
        itemCount: extras.length,
        itemBuilder: (_, i) => _addonCard(extras[i]),
      );
    });
  }

  // ── Single addon card ──
  Widget _addonCard(Extra extra) {
    final selected = _selectedExtraQuantities.containsKey(extra.id);
    final qty = _selectedExtraQuantities[extra.id] ?? 1;

    return InkWell(
      onTap: () => _toggleExtra(extra.id),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? _brand : Colors.grey[300]!,
            width: selected ? 2.0 : 1.0,
          ),
        ),
        child: Column(
          children: [
            // ── Image area (60%) ──
            Expanded(
              flex: 6,
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: selected ? _brandBg : const Color(0xFFEEEEEE),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
                ),
                child: Center(
                  child: Text(
                    extra.name.length >= 2 ? extra.name.substring(0, 2).toUpperCase() : extra.name.toUpperCase(),
                    style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: selected ? _brand : Colors.grey[400]),
                  ),
                ),
              ),
            ),
            // ── Text area (40%) ──
            Expanded(
              flex: 4,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      extra.name,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      extra.price.toStringAsFixed(2),
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: selected ? _brand : Colors.grey[600]),
                    ),
                    if (selected) ...[
                      const SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _tinyBtn(LucideIcons.minus, const Color(0xFFEF5350), () => _changeExtraQty(extra.id, -1)),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Text('$qty', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          ),
                          _tinyBtn(LucideIcons.plus, _brand, () => _changeExtraQty(extra.id, 1)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tinyBtn(IconData icon, Color bg, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(11),
      child: Container(
        width: 22, height: 22,
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
        child: Icon(icon, size: 13, color: Colors.white),
      ),
    );
  }

  // ─────────────────────── FOOTER ───────────────────────
  Widget _footer() {
    return Container(
      width: double.infinity,
      height: 48,
      color: _brand,
      child: InkWell(
        onTap: _onConfirm,
        child: Center(
          child: Text(
            'إضافة',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ),
      ),
    );
  }
}
