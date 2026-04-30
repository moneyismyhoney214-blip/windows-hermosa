import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../services/api/country_code_service.dart';
import '../services/app_themes.dart';
import '../services/language_service.dart';

/// Compact button that shows the current country's `area_code` (e.g.
/// `+966`) and opens a searchable bottom sheet to switch it. Designed
/// to sit next to a phone TextField as either a `prefix` or a leading
/// adornment.
class CountryCodePicker extends StatefulWidget {
  /// Initial selection. When null we fall back to the active branch's
  /// country (or Saudi if the country list hasn't loaded yet).
  final CountryOption? initial;

  /// Called every time the host picks a new country.
  final ValueChanged<CountryOption> onChanged;

  /// Optional label override (e.g. "Country code"). When null the
  /// button renders the area code only.
  final String? label;

  const CountryCodePicker({
    super.key,
    required this.onChanged,
    this.initial,
    this.label,
  });

  @override
  State<CountryCodePicker> createState() => _CountryCodePickerState();
}

class _CountryCodePickerState extends State<CountryCodePicker> {
  CountryOption? _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initial ?? countryCodeService.defaultForBranch();
    // Trigger background load so the sheet has the full list when the
    // host taps. If the cache is already warm this is a no-op.
    countryCodeService.load().then((list) {
      if (!mounted) return;
      // Re-resolve the default selection in case the freshly-loaded
      // list contains a better match for the active branch.
      if (widget.initial == null) {
        final fresh = countryCodeService.defaultForBranch();
        if (fresh.value != _selected?.value) {
          setState(() => _selected = fresh);
          widget.onChanged(fresh);
        }
      } else {
        setState(() {});
      }
    });
  }

  @override
  void didUpdateWidget(covariant CountryCodePicker old) {
    super.didUpdateWidget(old);
    final next = widget.initial;
    if (next != null && next.value != _selected?.value) {
      setState(() => _selected = next);
    }
  }

  Future<void> _openPicker() async {
    final picked = await showModalBottomSheet<CountryOption>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.appSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _CountryPickerSheet(selected: _selected),
    );
    if (picked != null && picked.value != _selected?.value) {
      setState(() => _selected = picked);
      widget.onChanged(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected ?? countryCodeService.defaultForBranch();
    return InkWell(
      onTap: _openPicker,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: context.appSurfaceAlt,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: context.appBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.globe, size: 16, color: context.appTextMuted),
            const SizedBox(width: 8),
            Text(
              selected.areaCode,
              style: TextStyle(
                color: context.appText,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              LucideIcons.chevronDown,
              size: 16,
              color: context.appTextMuted,
            ),
          ],
        ),
      ),
    );
  }
}

class _CountryPickerSheet extends StatefulWidget {
  final CountryOption? selected;

  const _CountryPickerSheet({required this.selected});

  @override
  State<_CountryPickerSheet> createState() => _CountryPickerSheetState();
}

class _CountryPickerSheetState extends State<_CountryPickerSheet> {
  final TextEditingController _query = TextEditingController();
  List<CountryOption> _all = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    // Hydrate from whatever the service already has, then refresh.
    _all = countryCodeService.options;
    _loading = _all.isEmpty;
    countryCodeService.load().then((list) {
      if (!mounted) return;
      setState(() {
        _all = list;
        _loading = false;
      });
    });
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  List<CountryOption> get _filtered {
    final q = _query.text.trim().toLowerCase();
    if (q.isEmpty) return _all;
    return _all.where((c) {
      return c.label.toLowerCase().contains(q) ||
          c.areaCode.contains(q) ||
          c.digits.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Directionality(
      textDirection:
          translationService.isRTL ? TextDirection.rtl : TextDirection.ltr,
      child: Padding(
        padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
        child: SizedBox(
          height: mq.size.height * 0.7,
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: context.appBorder,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: [
                    Icon(LucideIcons.globe, size: 18, color: context.appPrimary),
                    const SizedBox(width: 8),
                    Text(
                      translationService.t('country_code_picker_title'),
                      style: TextStyle(
                        color: context.appText,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: TextField(
                  controller: _query,
                  onChanged: (_) => setState(() {}),
                  style: TextStyle(color: context.appText),
                  decoration: InputDecoration(
                    hintText: translationService.t('country_code_picker_search'),
                    hintStyle: TextStyle(color: context.appTextMuted),
                    prefixIcon: Icon(
                      LucideIcons.search,
                      size: 18,
                      color: context.appTextMuted,
                    ),
                    filled: true,
                    fillColor: context.appSurfaceAlt,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                      borderSide:
                          BorderSide(color: context.appPrimary, width: 1.5),
                    ),
                  ),
                ),
              ),
              Expanded(child: _buildList(context)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final list = _filtered;
    if (list.isEmpty) {
      return Center(
        child: Text(
          translationService.t('country_code_picker_empty'),
          style: TextStyle(color: context.appTextMuted),
        ),
      );
    }
    return ListView.separated(
      itemCount: list.length,
      separatorBuilder: (_, __) =>
          Divider(color: context.appBorder, height: 1),
      itemBuilder: (_, i) {
        final c = list[i];
        final isSelected = widget.selected?.value == c.value;
        return ListTile(
          dense: true,
          onTap: () => Navigator.of(context).pop(c),
          title: Text(
            c.label,
            style: TextStyle(
              color: context.appText,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                c.areaCode,
                style: TextStyle(
                  color: context.appPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
              if (isSelected) ...[
                const SizedBox(width: 8),
                Icon(LucideIcons.check, size: 18, color: context.appPrimary),
              ],
            ],
          ),
        );
      },
    );
  }
}
