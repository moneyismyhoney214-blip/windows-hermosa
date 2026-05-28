// Extracted from cashier_settings_view.dart (2026-05-19 audit).
part of 'cashier_settings_view.dart';

enum _IconPreviewKind { meal, sidebar }

/// Modal that previews how the chosen icon scale will look on the home
/// grid (meal cards) or the side nav. Lets the user move through the
/// three discrete sizes — small / medium / large — with the live preview
/// rebuilding instantly so the choice is never blind.
class _IconSizePreviewDialog extends StatefulWidget {
  final String title;
  final double initial;
  final List<double> options;
  final double defaultValue;
  final _IconPreviewKind previewKind;
  /// When true the dialog renders a [Slider] (continuous between
  /// `options.first` and `options.last`) instead of three discrete chips.
  /// Used for the meal-card scale where the user wants to fine-tune.
  final bool useSlider;

  const _IconSizePreviewDialog({
    required this.title,
    required this.initial,
    required this.options,
    required this.defaultValue,
    required this.previewKind,
    this.useSlider = false,
  });

  @override
  State<_IconSizePreviewDialog> createState() => _IconSizePreviewDialogState();
}

class _IconSizePreviewDialogState extends State<_IconSizePreviewDialog> {
  late double _selected;

  String _t(String key) => translationService.t(key);

  @override
  void initState() {
    super.initState();
    _selected = widget.initial;
  }

  String _labelFor(double v) {
    if (v <= widget.options.first) return _t('size_small');
    if (v >= widget.options.last) return _t('size_large');
    return _t('size_medium');
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final dialogWidth = (size.width * 0.86).clamp(320.0, 520.0).toDouble();

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SizedBox(
        width: dialogWidth,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(LucideIcons.sliders,
                      color: Color(0xFFF58220), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: context.appText,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(LucideIcons.x, size: 18),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildPreview(),
              const SizedBox(height: 16),
              Text(
                _t('icon_size_choose'),
                style: TextStyle(
                  fontSize: 12,
                  color: context.appTextMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              if (widget.useSlider)
                _buildSlider()
              else
                Row(
                  children: widget.options.map((opt) {
                    final selected = (opt - _selected).abs() < 0.001;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: _SizeChoiceChip(
                          label: _labelFor(opt),
                          selected: selected,
                          onTap: () => setState(() => _selected = opt),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              const SizedBox(height: 16),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () => setState(
                        () => _selected = widget.defaultValue),
                    icon: const Icon(LucideIcons.rotateCcw, size: 14),
                    label: Text(_t('reset_to_default')),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(_t('cancel')),
                  ),
                  const SizedBox(width: 4),
                  ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context, _selected),
                    icon: const Icon(LucideIcons.check, size: 14),
                    label: Text(_t('save')),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF58220),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreview() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: context.appBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.appBorder),
      ),
      child: widget.previewKind == _IconPreviewKind.meal
          ? _buildMealPreview()
          : _buildSidebarPreview(),
    );
  }

  Widget _buildMealPreview() {
    // Mirrors home-grid scaling; wraps in horizontal scroll at 150%.
    final scale = _selected.clamp(0.75, 1.5);
    const baseWidth = 110.0;
    final tileWidth = baseWidth * scale;
    final tileHeight = tileWidth * 1.35;
    const spacing = 12.0;
    return SizedBox(
      height: tileHeight + 8,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ..._previewSampleCards(tileWidth, tileHeight, spacing),
          ],
        ),
      ),
    );
  }

  List<Widget> _previewSampleCards(
    double tileWidth,
    double tileHeight,
    double spacing,
  ) {
    final isSalon = ApiConstants.branchModule == 'salons';
    final samples = isSalon
        ? const [
            (LucideIcons.scissors, 'مكياج خطوبة', '350.00'),
            (LucideIcons.gift, 'باقة شعر', '500.00'),
            (LucideIcons.sparkles, 'تنظيف', '120.00'),
          ]
        : const [
            (LucideIcons.pizza, 'بيتزا', '85.00'),
            (LucideIcons.beef, 'برجر لحم', '65.00'),
            (LucideIcons.coffee, 'قهوة', '20.00'),
          ];
    final widgets = <Widget>[];
    for (var i = 0; i < samples.length; i++) {
      if (i > 0) widgets.add(SizedBox(width: spacing));
      final s = samples[i];
      widgets.add(_MealPreviewCard(
        width: tileWidth,
        height: tileHeight,
        icon: s.$1,
        label: s.$2,
        price: s.$3,
      ));
    }
    return widgets;
  }

  /// Continuous slider for the meal-card scale. Range is the dialog's
  /// `[options.first, options.last]` interval; divisions land on every
  /// 5% step so the cashier sees a discrete tick when dragging instead
  /// of a hard-to-control free float.
  Widget _buildSlider() {
    final min = widget.options.first;
    final max = widget.options.last;
    final divisions = ((max - min) / 0.05).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Text(
            '${(_selected * 100).round()}%',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFFF58220),
            ),
          ),
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: const Color(0xFFF58220),
            thumbColor: const Color(0xFFF58220),
            overlayColor: const Color(0xFFF58220).withValues(alpha: 0.2),
            inactiveTrackColor:
                const Color(0xFFF58220).withValues(alpha: 0.2),
            valueIndicatorColor: const Color(0xFFF58220),
          ),
          child: Slider(
            value: _selected.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions > 0 ? divisions : null,
            label: '${(_selected * 100).round()}%',
            onChanged: (v) => setState(() => _selected = v),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${(min * 100).round()}%',
              style:
                  TextStyle(fontSize: 11, color: context.appTextMuted),
            ),
            Text(
              '${(max * 100).round()}%',
              style:
                  TextStyle(fontSize: 11, color: context.appTextMuted),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSidebarPreview() {
    final scale = _selected.clamp(0.85, 1.4);
    final iconSize = 18.0 * scale;
    final fontSize = 14.0 * scale;
    final hPad = 20.0 * scale;
    final vPad = 10.0 * scale;
    final tabHeight = (80.0 * scale).clamp(68.0, 112.0);
    return SizedBox(
      height: tabHeight,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _SidebarPreviewItem(
            icon: LucideIcons.layoutDashboard,
            label: _t('home'),
            iconSize: iconSize,
            fontSize: fontSize,
            hPad: hPad,
            vPad: vPad,
            selected: true,
          ),
          const SizedBox(width: 8),
          _SidebarPreviewItem(
            icon: LucideIcons.receipt,
            label: _t('invoices'),
            iconSize: iconSize,
            fontSize: fontSize,
            hPad: hPad,
            vPad: vPad,
          ),
          const SizedBox(width: 8),
          _SidebarPreviewItem(
            icon: LucideIcons.settings,
            label: _t('settings'),
            iconSize: iconSize,
            fontSize: fontSize,
            hPad: hPad,
            vPad: vPad,
          ),
        ],
      ),
    );
  }
}

class _SizeChoiceChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SizeChoiceChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFFF58220)
              : context.appCardBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? const Color(0xFFF58220)
                : context.appBorder,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : context.appText,
            ),
          ),
        ),
      ),
    );
  }
}

class _MealPreviewCard extends StatelessWidget {
  final double width;
  final double height;
  final IconData icon;
  final String label;
  final String price;

  const _MealPreviewCard({
    required this.width,
    required this.height,
    required this.icon,
    required this.label,
    required this.price,
  });

  @override
  Widget build(BuildContext context) {
    // Image area ~60%, title + price the remaining 40% (matches home-grid).
    final imageHeight = height * 0.6;
    return SizedBox(
      width: width,
      height: height,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: context.appCardBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: context.appBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: imageHeight,
              color: const Color(0xFFFFF7ED),
              alignment: Alignment.center,
              child: Icon(
                icon,
                size: imageHeight * 0.45,
                color: const Color(0xFFF58220),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11 * (width / 110.0),
                        fontWeight: FontWeight.w700,
                        color: context.appText,
                      ),
                    ),
                    Text(
                      price,
                      style: TextStyle(
                        fontSize: 11 * (width / 110.0),
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFFF58220),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarPreviewItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final double iconSize;
  final double fontSize;
  final double hPad;
  final double vPad;
  final bool selected;

  const _SidebarPreviewItem({
    required this.icon,
    required this.label,
    required this.iconSize,
    required this.fontSize,
    required this.hPad,
    required this.vPad,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
      decoration: BoxDecoration(
        color:
            selected ? const Color(0xFFF58220) : context.appCardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected
              ? const Color(0xFFF58220)
              : context.appBorder,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: iconSize,
            color: selected ? Colors.white : context.appText,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: fontSize,
              color: selected ? Colors.white : context.appText,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
