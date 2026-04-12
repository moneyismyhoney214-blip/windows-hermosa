import 'package:flutter/material.dart';
import '../../locator.dart';
import '../../services/cashier_sound_service.dart';
import '../../services/language_service.dart';

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
  final bool printKitchenInvoices;
  final ValueChanged<bool> onPrintKitchenInvoicesChanged;
  final bool allowPrintWithKds;
  final ValueChanged<bool> onAllowPrintWithKdsChanged;
  final double mealIconScale;
  final ValueChanged<double> onMealIconScaleChanged;
  final double sidebarIconScale;
  final ValueChanged<double> onSidebarIconScaleChanged;

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
    required this.printKitchenInvoices,
    required this.onPrintKitchenInvoicesChanged,
    required this.allowPrintWithKds,
    required this.onAllowPrintWithKdsChanged,
    required this.mealIconScale,
    required this.onMealIconScaleChanged,
    required this.sidebarIconScale,
    required this.onSidebarIconScaleChanged,
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
          style: const TextStyle(
            fontSize: 12,
            color: Color(0xFF94A3B8),
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 6),
        Container(height: 1, color: const Color(0xFFE2E8F0)),
        const SizedBox(height: 12),
      ],
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
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: const Color(0xFFF58220),
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
        color: const Color(0xFFF8F8F8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          Text(
            _t('cashier_settings_title'),
            style: TextStyle(
              fontSize: isCompact ? 16 : 18,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _t('cashier_settings_description'),
            style: TextStyle(
              fontSize: isCompact ? 12 : 13,
              color: const Color(0xFF94A3B8),
            ),
          ),
          const SizedBox(height: 16),
          _buildSectionHeader(_t('settings_section_customers')),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: _buildSettingRow(
              title: _t('require_customer_selection'),
              description: _t('require_customer_selection_hint'),
              value: widget.requireCustomerSelection,
              onChanged: widget.onRequireCustomerSelectionChanged,
            ),
          ),
          const SizedBox(height: 16),
          _buildSectionHeader(_t('settings_section_printing')),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              children: [
                _buildSettingRow(
                  title: _t('auto_print_cashier'),
                  description: _t('auto_print_cashier_hint'),
                  value: widget.autoPrintCashier,
                  onChanged: widget.onAutoPrintCashierChanged,
                ),
                const Divider(height: 1, color: Color(0xFFE2E8F0)),
                _buildSettingRow(
                  title: _t('auto_print_customer'),
                  description: _t('auto_print_customer_hint'),
                  value: widget.autoPrintCustomer,
                  onChanged: widget.onAutoPrintCustomerChanged,
                ),
                const Divider(height: 1, color: Color(0xFFE2E8F0)),
                _buildSettingRow(
                  title: _t('print_kitchen_invoices'),
                  description: _t('print_kitchen_invoices_hint'),
                  value: widget.printKitchenInvoices,
                  onChanged: widget.onPrintKitchenInvoicesChanged,
                ),
                const Divider(height: 1, color: Color(0xFFE2E8F0)),
                _buildSettingRow(
                  title: _t('allow_print_with_kds'),
                  description: _t('allow_print_with_kds_hint'),
                  value: widget.allowPrintWithKds,
                  onChanged: widget.onAllowPrintWithKdsChanged,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildSectionHeader(_t('settings_section_ui')),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _t('meal_icon_size'),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _t('meal_icon_size_hint'),
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF94A3B8),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<double>(
                  initialValue: _normalizeIconScale(widget.mealIconScale),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 0.85,
                      child: Text(_t('size_small')),
                    ),
                    DropdownMenuItem(
                      value: 1.0,
                      child: Text(_t('size_medium')),
                    ),
                    DropdownMenuItem(
                      value: 1.15,
                      child: Text(_t('size_large')),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    widget.onMealIconScaleChanged(value);
                  },
                ),
                const SizedBox(height: 16),
                Text(
                  _t('sidebar_icon_size'),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _t('sidebar_icon_size_hint'),
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF94A3B8),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<double>(
                  initialValue: _normalizeIconScale(
                    widget.sidebarIconScale,
                    options: const [0.85, 1.0, 1.4],
                  ),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 0.85,
                      child: Text(_t('size_small')),
                    ),
                    DropdownMenuItem(
                      value: 1.0,
                      child: Text(_t('size_medium')),
                    ),
                    DropdownMenuItem(
                      value: 1.4,
                      child: Text(_t('size_large')),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    widget.onSidebarIconScaleChanged(value);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildSectionHeader(_t('settings_section_devices')),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              children: [
                _buildSettingRow(
                  title: _t('enable_cds'),
                  description: _t('enable_cds_hint'),
                  value: widget.cdsEnabled,
                  onChanged: widget.onCdsEnabledChanged,
                ),
                const Divider(height: 1, color: Color(0xFFE2E8F0)),
                _buildSettingRow(
                  title: _t('enable_kds'),
                  description: _t('enable_kds_hint'),
                  value: widget.kdsEnabled,
                  onChanged: widget.onKdsEnabledChanged,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildSectionHeader(_t('settings_section_sound')),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
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
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _t('cashier_buttons_sound_hint'),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF94A3B8),
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
                          const Icon(Icons.volume_down,
                              color: Color(0xFF94A3B8)),
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
                          const Icon(Icons.volume_up,
                              color: Color(0xFF94A3B8)),
                          const SizedBox(width: 8),
                          Text(
                            '${(_volume * 100).round()}%',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF0F172A),
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
}
