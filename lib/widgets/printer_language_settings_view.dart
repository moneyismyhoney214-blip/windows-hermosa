import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../services/app_themes.dart';
import '../services/language_service.dart';
import '../services/printer_language_settings_service.dart';

/// Local printer / receipt language settings (primary + optional secondary).
///
/// These values drive which translations appear on cashier receipts and
/// kitchen tickets — independently of the UI language and of the server-side
/// branch settings. Persisted on device via [PrinterLanguageSettingsService].
class PrinterLanguageSettingsView extends StatefulWidget {
  const PrinterLanguageSettingsView({super.key});

  @override
  State<PrinterLanguageSettingsView> createState() =>
      _PrinterLanguageSettingsViewState();
}

class _PrinterLanguageSettingsViewState
    extends State<PrinterLanguageSettingsView> {
  final PrinterLanguageSettingsService _svc = printerLanguageSettings;

  bool get _useArabicUi {
    final code = translationService.currentLanguageCode.trim().toLowerCase();
    return code.startsWith('ar') || code.startsWith('ur');
  }

  String _tr(String ar, String en) => _useArabicUi ? ar : en;

  @override
  void initState() {
    super.initState();
    _svc.addListener(_onChange);
  }

  @override
  void dispose() {
    _svc.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  List<AppLanguage> get _languages => SupportedLanguages.all
      .where((l) =>
          PrinterLanguageSettingsService.supportedCodes.contains(l.code))
      .toList(growable: false);

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.appCardBg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF58220).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  LucideIcons.printer,
                  color: Color(0xFFF58220),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _tr('لغة الطباعة', 'Printer Language'),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _tr(
              'تتحكم هذه الإعدادات في اللغة الظاهرة على فواتير الكاشير وتذاكر المطبخ.',
              'Controls the language shown on cashier receipts and kitchen tickets.',
            ),
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
          ),
          const SizedBox(height: 16),
          _buildDropdown(
            label: _tr('اللغة الأساسية', 'Primary Language'),
            value: _svc.primary,
            onChanged: (code) {
              if (code != null) _svc.setPrimary(code);
            },
          ),
          const SizedBox(height: 12),
          _buildAllowSecondaryToggle(),
          if (_svc.allowSecondary) ...[
            const SizedBox(height: 12),
            _buildDropdown(
              label: _tr('اللغة الثانوية', 'Secondary Language'),
              value: _svc.secondary,
              disabledCode: _svc.primary,
              disabledHint: _tr(
                'لا يمكن أن تطابق اللغة الأساسية',
                'Cannot match the primary language',
              ),
              onChanged: (code) {
                if (code != null) _svc.setSecondary(code);
              },
            ),
          ],
          const SizedBox(height: 8),
          _buildPreview(isDark: isDark),
        ],
      ),
    );
  }

  Widget _buildDropdown({
    required String label,
    required String value,
    required ValueChanged<String?> onChanged,
    String? disabledCode,
    String? disabledHint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: context.isDark ? Colors.white : Colors.black87,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: context.appCardBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: context.appBorder),
          ),
          child: DropdownButton<String>(
            value: value,
            isExpanded: true,
            underline: const SizedBox.shrink(),
            dropdownColor: context.appCardBg,
            onChanged: onChanged,
            items: _languages.map((lang) {
              final isDisabled = disabledCode != null && lang.code == disabledCode;
              return DropdownMenuItem<String>(
                value: lang.code,
                enabled: !isDisabled,
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 28,
                      decoration: BoxDecoration(
                        color: isDisabled
                            ? Colors.grey.shade300
                            : const Color(0xFFF58220),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Center(
                        child: Text(
                          lang.code.toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '${lang.nativeName} — ${lang.name}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isDisabled
                              ? Colors.grey
                              : (context.isDark ? Colors.white : Colors.black87),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
        if (disabledCode != null && value == disabledCode && disabledHint != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              disabledHint,
              style: const TextStyle(fontSize: 12, color: Color(0xFFDC2626)),
            ),
          ),
      ],
    );
  }

  Widget _buildAllowSecondaryToggle() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: context.appCardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.appBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _tr(
                'طباعة لغة ثانوية على الإيصال',
                'Print a secondary language on the receipt',
              ),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: context.isDark ? Colors.white : Colors.black87,
              ),
            ),
          ),
          Switch.adaptive(
            value: _svc.allowSecondary,
            activeThumbColor: const Color(0xFFF58220),
            onChanged: (v) => _svc.setAllowSecondary(v),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview({required bool isDark}) {
    final primaryLang = SupportedLanguages.getByCode(_svc.primary);
    final secondaryLang = SupportedLanguages.getByCode(_svc.secondary);
    final showSecondary =
        _svc.allowSecondary && _svc.primary != _svc.secondary;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF58220).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFFF58220).withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          const Icon(LucideIcons.info, size: 16, color: Color(0xFFF58220)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              showSecondary
                  ? _tr(
                      'الفواتير ستُطبع بـ ${primaryLang.nativeName} وأسفلها ${secondaryLang.nativeName}.',
                      'Receipts print in ${primaryLang.nativeName} with ${secondaryLang.nativeName} below.',
                    )
                  : _tr(
                      'الفواتير ستُطبع بـ ${primaryLang.nativeName} فقط.',
                      'Receipts print in ${primaryLang.nativeName} only.',
                    ),
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
