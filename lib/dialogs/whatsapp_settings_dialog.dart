import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../services/api/country_code_service.dart';
import '../services/app_themes.dart';
import '../services/language_service.dart';
import '../services/whatsapp_service.dart';
import '../widgets/country_code_picker.dart';

/// Settings dialog for the WAWP WhatsApp bridge.
///
/// Fields: default country code + message template. WAWP credentials
/// (instance id / access token) are owned by the branch on the server
/// and synced via `/seller/branches/{id}/settings` — the host can no
/// longer override them locally.
class WhatsAppSettingsDialog extends StatefulWidget {
  const WhatsAppSettingsDialog({super.key});

  @override
  State<WhatsAppSettingsDialog> createState() => _WhatsAppSettingsDialogState();
}

class _WhatsAppSettingsDialogState extends State<WhatsAppSettingsDialog> {
  late final TextEditingController _template;
  late final TextEditingController _testPhone;
  late CountryOption _country;

  bool _saving = false;
  bool _testing = false;
  String? _testMessage;
  Color? _testColor;

  @override
  void initState() {
    super.initState();
    final cfg = whatsAppService.config;
    _template = TextEditingController(text: cfg.messageTemplate);
    _testPhone = TextEditingController();

    // Resolve the saved country code against the loaded list so the
    // picker shows the matching country name (not just the digits).
    final savedDigits = cfg.defaultCountryCode.replaceAll(RegExp(r'[^0-9]'), '');
    final match = countryCodeService.options.firstWhere(
      (c) => c.digits == savedDigits,
      orElse: () => countryCodeService.defaultForBranch(),
    );
    _country = match;
  }

  @override
  void dispose() {
    _template.dispose();
    _testPhone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await whatsAppService.updateConfig(
      whatsAppService.config.copyWith(
        defaultCountryCode: _country.areaCode,
        messageTemplate: _template.text.trim().isEmpty
            ? whatsAppService.config.messageTemplate
            : _template.text,
      ),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.of(context).pop(true);
  }

  Future<void> _sendTest() async {
    final phone = _testPhone.text.trim();
    if (phone.isEmpty) {
      setState(() {
        _testMessage = translationService.t('whatsapp_settings_test_empty');
        _testColor = const Color(0xFFDC2626);
      });
      return;
    }

    // Flush unsaved country-code / template tweaks so the test uses what
    // the host just typed. WAWP credentials come from the backend — not
    // touched here.
    await whatsAppService.updateConfig(
      whatsAppService.config.copyWith(
        defaultCountryCode: _country.areaCode,
        messageTemplate: _template.text.trim().isEmpty
            ? whatsAppService.config.messageTemplate
            : _template.text,
      ),
    );

    setState(() {
      _testing = true;
      _testMessage = null;
    });

    final result = await whatsAppService.sendTableReady(
      rawPhone: phone,
      customerName:
          translationService.t('whatsapp_settings_test_customer'),
      tableNumber: '1',
    );

    if (!mounted) return;
    setState(() {
      _testing = false;
      if (result.ok) {
        final key = result.deliveredVia == WhatsAppSendChannel.wawpApi
            ? 'whatsapp_settings_test_api_ok'
            : 'whatsapp_settings_test_deeplink_ok';
        _testMessage = translationService.t(key);
        _testColor = const Color(0xFF059669);
      } else {
        _testMessage = translationService.t(
          'whatsapp_settings_test_failed',
          args: {'reason': result.errorMessage ?? ''},
        );
        _testColor = const Color(0xFFDC2626);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      backgroundColor: context.appSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Directionality(
        textDirection: translationService.isRTL
            ? TextDirection.rtl
            : TextDirection.ltr,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(context),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _credentialsBanner(context),
                      const SizedBox(height: 14),
                      _label(translationService.t(
                        'whatsapp_settings_country_code',
                      )),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: CountryCodePicker(
                          initial: _country,
                          onChanged: (c) => setState(() => _country = c),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _label(translationService.t(
                        'whatsapp_settings_template',
                      )),
                      TextField(
                        controller: _template,
                        maxLines: 3,
                        style: TextStyle(color: context.appText),
                        decoration: _decoration(
                          hint: translationService.t(
                            'whatsapp_settings_template_hint',
                          ),
                          context: context,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        translationService.t(
                          'whatsapp_settings_template_help',
                        ),
                        style: TextStyle(
                          fontSize: 11,
                          color: context.appTextMuted,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Divider(color: context.appBorder, height: 1),
                      const SizedBox(height: 14),
                      Text(
                        translationService.t('whatsapp_settings_test_title'),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: context.appText,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _testPhone,
                              keyboardType: TextInputType.phone,
                              style: TextStyle(color: context.appText),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                  RegExp(r'[0-9+ ]'),
                                ),
                              ],
                              decoration: _decoration(
                                hint: '+966 5xxxxxxxx',
                                context: context,
                                icon: LucideIcons.phone,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          FilledButton.icon(
                            onPressed: _testing ? null : _sendTest,
                            icon: _testing
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(LucideIcons.send, size: 16),
                            label: Text(
                              translationService.t(
                                'whatsapp_settings_test_button',
                              ),
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: context.appPrimary,
                            ),
                          ),
                        ],
                      ),
                      if (_testMessage != null) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Icon(
                              _testColor == const Color(0xFF059669)
                                  ? LucideIcons.checkCircle
                                  : LucideIcons.alertCircle,
                              size: 16,
                              color: _testColor,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                _testMessage!,
                                style: TextStyle(
                                  color: _testColor,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              _buildFooter(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
        color: Color(0xFF25D366),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Row(
        children: [
          const Icon(LucideIcons.messageSquare, color: Colors.white, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              translationService.t('whatsapp_settings_title'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(false),
            icon: const Icon(LucideIcons.x, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: context.appBorder)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(translationService.t('cancel')),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(LucideIcons.check, size: 16),
              label: Text(translationService.t('save')),
              style: FilledButton.styleFrom(
                backgroundColor: context.appPrimary,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: context.appText,
        ),
      ),
    );
  }

  /// Read-only banner that tells the host whether the WAWP credentials
  /// have been pulled from the server. The instance id is shown so they
  /// can confirm the right branch is wired up; the access token is
  /// never displayed.
  Widget _credentialsBanner(BuildContext context) {
    final cfg = whatsAppService.config;
    final isReady = cfg.isApiReady;
    final color = isReady ? const Color(0xFF059669) : const Color(0xFFD97706);
    final icon =
        isReady ? LucideIcons.checkCircle : LucideIcons.alertTriangle;
    final titleKey = isReady
        ? 'whatsapp_settings_creds_synced_title'
        : 'whatsapp_settings_creds_missing_title';
    final bodyKey = isReady
        ? 'whatsapp_settings_creds_synced_body'
        : 'whatsapp_settings_creds_missing_body';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  translationService.t(titleKey),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  translationService.t(bodyKey),
                  style: TextStyle(
                    fontSize: 11,
                    color: context.appTextMuted,
                  ),
                ),
                if (isReady && (cfg.instanceId ?? '').isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Instance ID: ${cfg.instanceId}',
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: context.appText,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _decoration({
    required String hint,
    required BuildContext context,
    IconData? icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: context.appTextMuted),
      prefixIcon: icon != null
          ? Icon(icon, size: 18, color: context.appTextMuted)
          : null,
      suffixIcon: suffix,
      filled: true,
      fillColor: context.appSurfaceAlt,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: context.appBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: context.appBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: context.appPrimary, width: 1.5),
      ),
    );
  }
}
