import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../locator.dart';
import '../../services/api/api_constants.dart';
import '../../services/app_themes.dart';
import '../../services/cashier_sound_service.dart';
import '../../services/language_service.dart';
import '../../services/theme_service.dart';

// Icon-size preview helpers were extracted to a `part` file (private API).
part 'cashier_settings_view.icon_preview.dart';

class CashierSettingsView extends StatefulWidget {
  final bool requireCustomerSelection;
  final ValueChanged<bool> onRequireCustomerSelectionChanged;
  /// Backend-enforced lock: when true, the require-customer toggle is forced
  /// on and rendered as read-only with an explanatory hint.
  final bool customerRequirementLocked;
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
    this.customerRequirementLocked = false,
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
    bool locked = false,
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
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: context.appText,
                        ),
                      ),
                    ),
                    if (locked) ...[
                      const SizedBox(width: 6),
                      Icon(LucideIcons.lock,
                          size: 14, color: context.appTextMuted),
                    ],
                  ],
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
            onChanged: locked ? null : onChanged,
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
          // Customer-required toggle is restaurant-only; salon always requires one.
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
                description: widget.customerRequirementLocked
                    ? _t('require_customer_selection_locked_hint')
                    : _t('require_customer_selection_hint'),
                value: widget.requireCustomerSelection,
                onChanged: widget.onRequireCustomerSelectionChanged,
                locked: widget.customerRequirementLocked,
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
                  title: ApiConstants.branchModule == 'salons'
                      ? _t('service_icon_size')
                      : _t('meal_icon_size'),
                  hint: ApiConstants.branchModule == 'salons'
                      ? _t('service_icon_size_hint')
                      : _t('meal_icon_size_hint'),
                  current: widget.mealIconScale,
                  // Meal-card slider runs 75%-150% continuously.
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
    // Chip-mode snaps to nearest option; slider-mode keeps continuous value.
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

