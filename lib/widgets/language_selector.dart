import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../services/language_service.dart';

class LanguageSelector extends StatefulWidget {
  const LanguageSelector({super.key});

  @override
  State<LanguageSelector> createState() => _LanguageSelectorState();
}

class _LanguageSelectorState extends State<LanguageSelector> {
  String? _pendingLanguageCode;
  bool _isChanging = false;

  @override
  void initState() {
    super.initState();
    translationService.addListener(_onLanguageChanged);
  }

  @override
  void dispose() {
    translationService.removeListener(_onLanguageChanged);
    super.dispose();
  }

  void _onLanguageChanged() {
    if (!mounted) return;
    setState(() {
      _pendingLanguageCode = null;
      _isChanging = false;
    });
  }

  String get _selectedLanguageCode =>
      _pendingLanguageCode ?? translationService.currentLanguageCode;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
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
                  LucideIcons.languages,
                  color: Color(0xFFF58220),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                translationService.t('select_language'),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...SupportedLanguages.all.map((lang) => _LanguageOption(
                language: lang,
                isSelected: _selectedLanguageCode == lang.code,
                onTap: () => _changeLanguage(lang.code),
              )),
        ],
      ),
    );
  }

  Future<void> _changeLanguage(String code) async {
    if (_isChanging) return;
    if (_selectedLanguageCode == code && _pendingLanguageCode == null) return;

    setState(() {
      _pendingLanguageCode = code;
      _isChanging = true;
    });

    try {
      await translationService.setLanguage(code);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _pendingLanguageCode = null;
        _isChanging = false;
      });
    }
  }
}

class _LanguageOption extends StatelessWidget {
  final AppLanguage language;
  final bool isSelected;
  final VoidCallback onTap;

  const _LanguageOption({
    required this.language,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFFF58220).withValues(alpha: 0.1)
                : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color:
                  isSelected ? const Color(0xFFF58220) : Colors.grey.shade200,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFFF58220)
                      : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    language.code.toUpperCase(),
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.grey.shade600,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      language.nativeName,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isSelected
                            ? const Color(0xFFF58220)
                            : Colors.black87,
                      ),
                    ),
                    Text(
                      language.name,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                const Icon(
                  LucideIcons.checkCircle,
                  color: Color(0xFFF58220),
                  size: 24,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
