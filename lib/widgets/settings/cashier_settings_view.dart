import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../locator.dart';
import '../../services/cashier_sound_service.dart';
import '../../services/language_service.dart';
import '../../services/theme_service.dart';
import '../../services/app_themes.dart';
import '../../services/api/api_constants.dart';

class CashierSettingsView extends StatefulWidget {
  final bool requireCustomerSelection;
  final ValueChanged<bool> onRequireCustomerSelectionChanged;
  final bool cdsEnabled;
  final bool kdsEnabled;
  final ValueChanged<bool> onCdsEnabledChanged;
  final ValueChanged<bool> onKdsEnabledChanged;
  final bool autoPrintCashier;
  final ValueChanged<bool> onAutoPrintCashierChanged;
  final bool autoPrintCustomer;
  final ValueChanged<bool> onAutoPrintCustomerChanged;
  final bool autoPrintCustomerSecondCopy;
  final ValueChanged<bool> onAutoPrintCustomerSecondCopyChanged;
  final bool printKitchenInvoices;
  final ValueChanged<bool> onPrintKitchenInvoicesChanged;
  final bool allowPrintWithKds;
  final ValueChanged<bool> onAllowPrintWithKdsChanged;
  final double mealIconScale;
  final ValueChanged<double> onMealIconScaleChanged;
  final double sidebarIconScale;
  final ValueChanged<double> onSidebarIconScaleChanged;
  final bool categoryLayoutVertical;
  final ValueChanged<bool> onCategoryLayoutVerticalChanged;

  const CashierSettingsView({
    super.key,
    required this.requireCustomerSelection,
    required this.onRequireCustomerSelectionChanged,
    required this.cdsEnabled,
    required this.kdsEnabled,
    required this.onCdsEnabledChanged,
    required this.onKdsEnabledChanged,
    required this.autoPrintCashier,
    required this.onAutoPrintCashierChanged,
    required this.autoPrintCustomer,
    required this.onAutoPrintCustomerChanged,
    required this.autoPrintCustomerSecondCopy,
    required this.onAutoPrintCustomerSecondCopyChanged,
    required this.printKitchenInvoices,
    required this.onPrintKitchenInvoicesChanged,
    required this.allowPrintWithKds,
    required this.onAllowPrintWithKdsChanged,
    required this.mealIconScale,
    required this.onMealIconScaleChanged,
    required this.sidebarIconScale,
    required this.onSidebarIconScaleChanged,
    required this.categoryLayoutVertical,
    required this.onCategoryLayoutVerticalChanged,
  });

  @override
  State<CashierSettingsView> createState() => _CashierSettingsViewState();
}

class _CashierSettingsViewState extends State<CashierSettingsView> {
  late final CashierSoundService _soundService;
  bool _isMuted = false;
  double _volume = 0.6;
  bool _loadingSound = true;

  String _t(String key, {Map<String, dynamic>? args}) {
    return translationService.t(key, args: args);
  }

  Widget _buildSectionHeader(String title) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            color: context.appTextMuted,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 6),
        Container(height: 1, color: context.appBorder),
        const SizedBox(height: 12),
      ],
    );
  }

  /// Three-way theme selector: Light / Dark / System.
  Widget _buildThemeSelector() {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark ? cs.onSurface : const Color(0xFF0F172A);
    final hintColor = isDark ? cs.onSurface.withValues(alpha: 0.6) : const Color(0xFF94A3B8);
    final borderColor = isDark ? cs.outline : const Color(0xFFE2E8F0);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isDark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
                size: 18,
                color: cs.primary,
              ),
              const SizedBox(width: 8),
              Text(
                _t('settings_theme_title'),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: titleColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 26),
            child: Text(
              _t('settings_theme_hint'),
              style: TextStyle(fontSize: 12, color: hintColor),
            ),
          ),
          const SizedBox(height: 12),
          ListenableBuilder(
            listenable: themeService,
            builder: (context, _) {
              return Row(
                children: [
                  Expanded(
                    child: _buildThemeOption(
                      mode: ThemeMode.light,
                      icon: Icons.light_mode_outlined,
                      label: _t('settings_theme_light'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildThemeOption(
                      mode: ThemeMode.dark,
                      icon: Icons.dark_mode_outlined,
                      label: _t('settings_theme_dark'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildThemeOption(
                      mode: ThemeMode.system,
                      icon: Icons.settings_suggest_outlined,
                      label: _t('settings_theme_system'),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildThemeOption({
    required ThemeMode mode,
    required IconData icon,
    required String label,
  }) {
    final cs = Theme.of(context).colorScheme;
    final selected = themeService.themeMode == mode;
    final bg = selected ? cs.primary.withValues(alpha: 0.12) : cs.surfaceContainerHighest;
    final border = selected ? cs.primary : cs.outline;
    final fg = selected ? cs.primary : cs.onSurface.withValues(alpha: 0.7);

    return InkWell(
      onTap: () => themeService.setMode(mode),
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: border, width: selected ? 1.5 : 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: fg),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingRow({
    required String title,
    required String description,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: context.appText,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
                    color: context.appTextMuted,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: context.appPrimary,
          ),
        ],
      ),
    );
  }

  double _normalizeIconScale(
    double value, {
    List<double> options = const [0.85, 1.0, 1.15],
  }) {
    var closest = options.first;
    var bestDiff = (value - closest).abs();
    for (final option in options.skip(1)) {
      final diff = (value - option).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        closest = option;
      }
    }
    return closest;
  }

  @override
  void initState() {
    super.initState();
    _soundService = getIt<CashierSoundService>();
    _loadSoundState();
  }

  Future<void> _loadSoundState() async {
    await _soundService.initialize();
    if (!mounted) return;
    setState(() {
      _isMuted = _soundService.isMuted;
      _volume = _soundService.volume;
      _loadingSound = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isCompact = width < 420;
    return SingleChildScrollView(
      padding: EdgeInsets.all(isCompact ? 12 : 24),
      child: Container(
        color: context.appBg,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          Text(
            _t('cashier_settings_title'),
            style: TextStyle(
              fontSize: isCompact ? 16 : 18,
              fontWeight: FontWeight.bold,
              color: context.appText,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _t('cashier_settings_description'),
            style: TextStyle(
              fontSize: isCompact ? 12 : 13,
              color: context.appTextMuted,
            ),
          ),
          // Customer-required toggle is restaurant-only. The salon flow
          // already enforces a customer on every booking (deposits, employee
          // calendar, history, ZATCA invoice all key off the customer), so
          // exposing the toggle there is misleading — there's nothing it can
          // actually disable.
          if (ApiConstants.branchModule != 'salons') ...[
            const SizedBox(height: 16),
            _buildSectionHeader(_t('settings_section_customers')),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: context.appSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.appBorder),
              ),
              child: _buildSettingRow(
                title: _t('require_customer_selection'),
                description: _t('require_customer_selection_hint'),
                value: widget.requireCustomerSelection,
                onChanged: widget.onRequireCustomerSelectionChanged,
              ),
            ),
          ],
          const SizedBox(height: 16),
          _buildSectionHeader(_t('settings_section_printing')),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: context.appSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.appBorder),
            ),
            child: _buildSettingRow(
              title: _t('auto_print_customer_second_copy'),
              description: _t('auto_print_customer_second_copy_hint'),
              value: widget.autoPrintCustomerSecondCopy,
              onChanged: widget.onAutoPrintCustomerSecondCopyChanged,
            ),
          ),
          const SizedBox(height: 16),
          _buildSectionHeader(_t('settings_section_ui')),
          _buildThemeSelector(),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: context.appSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.appBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildIconScaleRow(
                  title: _t('meal_icon_size'),
                  hint: _t('meal_icon_size_hint'),
                  current: widget.mealIconScale,
                  // Meal-card slider runs continuously between 75% and
                  // 150%. The chip-list (small/medium/large) is still
                  // shown for accessibility, but the dialog renders as
                  // a slider so the user can land on any intermediate
                  // value and watch the cards resize live.
                  options: const [0.75, 1.0, 1.5],
                  defaultValue: 1.0,
                  previewKind: _IconPreviewKind.meal,
                  useSlider: true,
                  onSave: widget.onMealIconScaleChanged,
                ),
                const SizedBox(height: 16),
                _buildIconScaleRow(
                  title: _t('sidebar_icon_size'),
                  hint: _t('sidebar_icon_size_hint'),
                  current: widget.sidebarIconScale,
                  options: const [0.85, 1.0, 1.4],
                  defaultValue: 1.0,
                  previewKind: _IconPreviewKind.sidebar,
                  useSlider: false,
                  onSave: widget.onSidebarIconScaleChanged,
                ),
                const SizedBox(height: 16),
                const Divider(height: 1, color: Color(0xFFE2E8F0)),
                const SizedBox(height: 12),
                Text(
                  _t('category_layout'),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: context.appText,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _t('category_layout_hint'),
                  style: TextStyle(
                    fontSize: 12,
                    color: context.appTextMuted,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => widget.onCategoryLayoutVerticalChanged(false),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: !widget.categoryLayoutVertical
                                ? const Color(0xFFF58220)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: !widget.categoryLayoutVertical
                                  ? const Color(0xFFF58220)
                                  : const Color(0xFFE2E8F0),
                            ),
                          ),
                          child: Column(
                            children: [
                              Icon(
                                Icons.view_column_outlined,
                                color: !widget.categoryLayoutVertical
                                    ? Colors.white
                                    : const Color(0xFF64748B),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _t('category_layout_horizontal'),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: !widget.categoryLayoutVertical
                                      ? Colors.white
                                      : const Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => widget.onCategoryLayoutVerticalChanged(true),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: widget.categoryLayoutVertical
                                ? const Color(0xFFF58220)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: widget.categoryLayoutVertical
                                  ? const Color(0xFFF58220)
                                  : const Color(0xFFE2E8F0),
                            ),
                          ),
                          child: Column(
                            children: [
                              Icon(
                                Icons.table_rows_outlined,
                                color: widget.categoryLayoutVertical
                                    ? Colors.white
                                    : const Color(0xFF64748B),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _t('category_layout_vertical'),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: widget.categoryLayoutVertical
                                      ? Colors.white
                                      : const Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildSectionHeader(_t('settings_section_sound')),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.appSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.appBorder),
            ),
            child: _loadingSound
                ? const LinearProgressIndicator(minHeight: 2)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _t('cashier_buttons_sound'),
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: context.appText,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _t('cashier_buttons_sound_hint'),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: context.appTextMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: _isMuted,
                            onChanged: (value) async {
                              setState(() => _isMuted = value);
                              await _soundService.setMuted(value);
                            },
                            activeThumbColor: const Color(0xFFF58220),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.volume_down,
                              color: context.appTextMuted),
                          Expanded(
                            child: Slider(
                              value: _volume,
                              min: 0,
                              max: 1,
                              divisions: 20,
                              label: '${(_volume * 100).round()}%',
                              activeColor: const Color(0xFFF58220),
                              onChanged: _isMuted
                                  ? null
                                  : (value) async {
                                      setState(() => _volume = value);
                                      await _soundService.setVolume(value);
                                    },
                              onChangeEnd: _isMuted
                                  ? null
                                  : (value) async {
                                      await _soundService.setVolume(value);
                                    },
                            ),
                          ),
                          Icon(Icons.volume_up,
                              color: context.appTextMuted),
                          const SizedBox(width: 8),
                          Text(
                            '${(_volume * 100).round()}%',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: context.appText,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
        ],
      ),
    ),
  );
  }

  /// Compact summary row for an icon-scale setting. The "current" value is
  /// always populated (defaults set on first launch), so the row reads as
  /// "title — currentLabel ✓ افتراضي  [Edit]". Tapping Edit opens a live
  /// preview dialog driven by [showDialog]; the dialog only commits on
  /// "Save" so users can experiment without forcing a state write.
  Widget _buildIconScaleRow({
    required String title,
    required String hint,
    required double current,
    required List<double> options,
    required double defaultValue,
    required _IconPreviewKind previewKind,
    required ValueChanged<double> onSave,
    bool useSlider = false,
  }) {
    // For chip-mode rows we snap to the closest discrete option; for
    // slider-mode the saved value is continuous and we just pick the
    // nearest option for the *label* on this row.
    final normalized = useSlider
        ? current.clamp(options.first, options.last).toDouble()
        : _normalizeIconScale(current, options: options);
    final label = _scaleLabel(normalized, options);
    final isDefault =
        (normalized - defaultValue).abs() < 0.001;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: context.appBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.appBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: context.appText,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hint,
                  style: TextStyle(
                    fontSize: 11,
                    color: context.appTextMuted,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF58220).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        label,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFF58220),
                        ),
                      ),
                    ),
                    if (isDefault) ...[
                      const SizedBox(width: 6),
                      Text(
                        '· ${_t('default')}',
                        style: TextStyle(
                          fontSize: 11,
                          color: context.appTextMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: () => _openIconSizeDialog(
              title: title,
              current: normalized,
              options: options,
              defaultValue: defaultValue,
              previewKind: previewKind,
              useSlider: useSlider,
              onSave: onSave,
            ),
            icon: const Icon(LucideIcons.sliders, size: 14),
            label: Text(_t('edit')),
            style: OutlinedButton.styleFrom(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _scaleLabel(double value, List<double> options) {
    if (value <= options.first) return _t('size_small');
    if (value >= options.last) return _t('size_large');
    return _t('size_medium');
  }

  Future<void> _openIconSizeDialog({
    required String title,
    required double current,
    required List<double> options,
    required double defaultValue,
    required _IconPreviewKind previewKind,
    required ValueChanged<double> onSave,
    bool useSlider = false,
  }) async {
    final picked = await showDialog<double>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _IconSizePreviewDialog(
        title: title,
        initial: current,
        options: options,
        defaultValue: defaultValue,
        previewKind: previewKind,
        useSlider: useSlider,
      ),
    );
    if (picked == null) return;
    onSave(picked);
  }
}

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
    // Mirror the home grid's scaling formula in main_screen.build_widgets:
    // tile width grows linearly with the iconScale, and the aspect ratio
    // around 1:1.35 keeps the card readable at the smallest sizes. At
    // 150% the three cards exceed the dialog width, so the row is wrapped
    // in a horizontal scroll view to show the *real* size instead of
    // shrinking the cards to fit (which would defeat the purpose of the
    // preview).
    final scale = _selected.clamp(0.75, 1.5);
    final baseWidth = 110.0;
    final tileWidth = baseWidth * scale;
    final tileHeight = tileWidth * 1.35;
    final spacing = 12.0;
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
        // Just the percentage — the small/medium/large word was misleading
        // since the slider is continuous. Numeric % is the single source
        // of truth for the slider's current value.
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
    // Visual ratios are tuned to match the real home-grid ProductCard so
    // the dialog preview reads as "what the user will see" rather than
    // an abstract scaling demo. Image area takes ~60% of the card,
    // title + price share the remaining 40%.
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
