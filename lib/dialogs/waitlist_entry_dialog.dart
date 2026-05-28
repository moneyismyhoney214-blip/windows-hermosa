import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../locator.dart';
import '../models/customer.dart';
import '../models/waitlist_entry.dart';
import '../services/api/country_code_service.dart';
import '../services/api/customer_service.dart';
import '../services/app_themes.dart';
import '../services/language_service.dart';
import '../services/whatsapp_service.dart';
import '../utils/ui_feedback.dart';
import '../widgets/country_code_picker.dart';
import 'customer_selection_dialog.dart';

/// Dialog for adding a new waitlist party or editing an existing one.
///
/// Deliberately terse: a host juggling a dinner rush needs to punch
/// name + phone + size and hit save without hunting for fields.
class WaitlistEntryDialog extends StatefulWidget {
  /// When null → add mode. When provided → edit mode; we pre-fill the
  /// fields and keep the original id / createdAt on save.
  final WaitlistEntry? existing;

  const WaitlistEntryDialog({super.key, this.existing});

  static Future<WaitlistEntry?> show(
    BuildContext context, {
    WaitlistEntry? existing,
  }) {
    return showDialog<WaitlistEntry>(
      context: context,
      builder: (_) => WaitlistEntryDialog(existing: existing),
    );
  }

  @override
  State<WaitlistEntryDialog> createState() => _WaitlistEntryDialogState();
}

class _WaitlistEntryDialogState extends State<WaitlistEntryDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _phone;
  int _partySize = 2;
  CountryOption _country = countryCodeService.defaultForBranch();

  /// Backend customer id linked to this party. Carried over in edit mode,
  /// set when the host picks an existing customer, or filled in by the
  /// `createCustomer` call on save when the host typed a fresh name+phone.
  String? _customerId;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.customerName ?? '');
    _phone = TextEditingController(text: e?.phoneNumber ?? '');
    _partySize = e?.partySize ?? 2;
    _customerId = e?.customerId;

    // Edit mode: detect country from stored number so the picker matches.
    _syncCountryFromPhone(e?.phoneNumber ?? '');
  }

  void _syncCountryFromPhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    // Require 11+ digits — bare local mobiles (e.g. EG 10-digit) would otherwise mis-detect as "+1" AG.
    if (digits.length < 11) return;
    for (final option in countryCodeService.options) {
      if (digits.startsWith(option.digits)) {
        _country = option;
        break;
      }
    }
  }

  /// Open the same customer picker the restaurant module uses — search +
  /// "add new". Picking one fills the name + phone and links the party to
  /// that customer id (so no fresh record gets created on save).
  Future<void> _pickExistingCustomer() async {
    final picked = await showDialog<Customer>(
      context: context,
      builder: (_) => const CustomerSelectionDialog(),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _name.text = picked.name;
      final mobile = picked.mobile?.trim() ?? '';
      if (mobile.isNotEmpty) {
        _phone.text = mobile;
        _syncCountryFromPhone(mobile);
      }
      _customerId = picked.id;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final name = _name.text.trim();
    // Normalize phone like the messaging layer would so persisted value matches what we'd dial.
    final normalizedPhone = whatsAppService.normalizePhone(
      _phone.text.trim(),
      countryCodeOverride: _country.areaCode,
    );

    // Create a real customer record for brand-new name+phone so booking carries `customer_id` instead of walking in anonymously.
    if (_customerId == null) {
      setState(() => _saving = true);
      try {
        final created = await getIt<CustomerService>().createCustomer({
          'name': name,
          'mobile': normalizedPhone,
        });
        _customerId = created.id;
      } catch (e) {
        if (mounted) {
          UiFeedback.warning(
            context,
            translationService.t(
              'waitlist_customer_create_failed',
              args: {'error': e.toString()},
            ),
          );
        }
        // Non-fatal — entry just won't be linked to a customer record.
      } finally {
        if (mounted) setState(() => _saving = false);
      }
    }

    if (!mounted) return;
    if (_isEdit) {
      final updated = widget.existing!.copyWith(
        customerName: name,
        phoneNumber: normalizedPhone,
        partySize: _partySize,
        customerId: _customerId,
      );
      Navigator.of(context).pop(updated);
    } else {
      Navigator.of(context).pop(
        WaitlistEntry(
          customerName: name,
          phoneNumber: normalizedPhone,
          partySize: _partySize,
          customerId: _customerId,
        ),
      );
    }
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
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(context),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: TextButton.icon(
                          onPressed: _saving ? null : _pickExistingCustomer,
                          icon: const Icon(LucideIcons.search, size: 16),
                          label: Text(
                            translationService.t('waitlist_pick_existing_customer'),
                          ),
                          style: TextButton.styleFrom(
                            foregroundColor: context.appPrimary,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      _label(translationService.t('waitlist_field_name')),
                      TextFormField(
                        controller: _name,
                        autofocus: !_isEdit,
                        textCapitalization: TextCapitalization.words,
                        style: TextStyle(color: context.appText),
                        decoration: _decoration(
                          hint: translationService.t(
                            'waitlist_field_name_hint',
                          ),
                          icon: LucideIcons.user,
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? translationService.t(
                                'waitlist_validation_name_required',
                              )
                            : null,
                      ),
                      const SizedBox(height: 14),
                      _label(translationService.t('waitlist_field_phone')),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CountryCodePicker(
                            initial: _country,
                            onChanged: (c) => setState(() => _country = c),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              controller: _phone,
                              keyboardType: TextInputType.phone,
                              style: TextStyle(color: context.appText),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                  RegExp(r'[0-9+ -]'),
                                ),
                              ],
                              decoration: _decoration(
                                hint: '5xxxxxxxx',
                                icon: LucideIcons.phone,
                              ),
                              validator: (v) {
                                final raw = v?.trim() ?? '';
                                final digits =
                                    raw.replaceAll(RegExp(r'\D'), '');
                                if (digits.length < 7) {
                                  return translationService.t(
                                    'waitlist_validation_phone_required',
                                  );
                                }
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _label(translationService.t(
                                  'waitlist_field_party_size',
                                )),
                                _partySizeStepper(),
                              ],
                            ),
                          ),
                        ],
                      ),
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
        color: Color(0xFFF58220),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Row(
        children: [
          Icon(
            _isEdit ? LucideIcons.edit3 : LucideIcons.userPlus,
            color: Colors.white,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              translationService.t(
                _isEdit ? 'waitlist_edit_title' : 'waitlist_add_title',
              ),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
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
              onPressed:
                  _saving ? null : () => Navigator.of(context).pop(),
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
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(
                      _isEdit ? LucideIcons.check : LucideIcons.plus,
                      size: 18,
                    ),
              label: Text(
                translationService.t(
                  _isEdit ? 'save' : 'waitlist_add_submit',
                ),
              ),
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

  Widget _partySizeStepper() {
    return Container(
      decoration: BoxDecoration(
        color: context.appSurfaceAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.appBorder),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(
        children: [
          _stepperBtn(
            icon: LucideIcons.minus,
            enabled: _partySize > 1,
            onTap: () => setState(() => _partySize--),
          ),
          Expanded(
            child: Center(
              child: Text(
                '$_partySize',
                style: TextStyle(
                  color: context.appText,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          _stepperBtn(
            icon: LucideIcons.plus,
            enabled: _partySize < 30,
            onTap: () => setState(() => _partySize++),
          ),
        ],
      ),
    );
  }

  Widget _stepperBtn({
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        child: Icon(
          icon,
          size: 18,
          color: enabled ? context.appPrimary : context.appTextMuted,
        ),
      ),
    );
  }


  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
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

  InputDecoration _decoration({
    required String hint,
    IconData? icon,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: context.appTextMuted),
      prefixIcon: icon != null
          ? Icon(icon, size: 18, color: context.appTextMuted)
          : null,
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
