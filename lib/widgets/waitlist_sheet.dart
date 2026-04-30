import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../dialogs/waitlist_entry_dialog.dart';
import '../dialogs/whatsapp_settings_dialog.dart';
import '../models/waitlist_entry.dart';
import '../screens/waitlist_history_screen.dart';
import '../services/app_themes.dart';
import '../services/language_service.dart';
import '../services/waitlist_assign_controller.dart';
import '../services/waitlist_service.dart';

/// The full waitlist management sheet.
///
/// Modal bottom sheet because the host typically opens it from the
/// tables screen, does one action (add party, or pick someone to seat)
/// and dismisses. A full-screen route would feel heavy.
///
/// Returns `true` when an assign flow was started — the host screen
/// uses that signal to show its "pick a table" banner immediately.
class WaitlistSheet extends StatefulWidget {
  const WaitlistSheet({super.key});

  /// Convenience launcher so callers don't have to wire up the sheet
  /// shape / constraints themselves.
  static Future<bool?> show(BuildContext context) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const WaitlistSheet(),
    );
  }

  @override
  State<WaitlistSheet> createState() => _WaitlistSheetState();
}

class _WaitlistSheetState extends State<WaitlistSheet> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    waitlistService.addListener(_onStore);
    // One-minute ticker so the "waited 14 min" labels update without
    // needing to rebuild from the outside.
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    waitlistService.removeListener(_onStore);
    _tick?.cancel();
    super.dispose();
  }

  void _onStore() {
    if (mounted) setState(() {});
  }

  Future<void> _addEntry() async {
    final entry = await WaitlistEntryDialog.show(context);
    if (entry == null) return;
    await waitlistService.add(entry);
  }

  Future<void> _editEntry(WaitlistEntry existing) async {
    final updated = await WaitlistEntryDialog.show(
      context,
      existing: existing,
    );
    if (updated == null) return;
    await waitlistService.update(updated);
  }

  Future<void> _confirmRemove(WaitlistEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.appSurface,
        title: Text(
          translationService.t('waitlist_remove_title'),
          style: TextStyle(color: ctx.appText),
        ),
        content: Text(
          translationService.t(
            'waitlist_remove_body',
            args: {'name': entry.customerName},
          ),
          style: TextStyle(color: ctx.appText),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(translationService.t('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(translationService.t('waitlist_remove_confirm')),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await waitlistService.remove(entry.id);
    }
  }

  void _beginAssign(WaitlistEntry entry) {
    waitlistAssignController.beginAssign(entry);
    Navigator.of(context).pop(true);
  }

  Future<void> _openSettings() async {
    await showDialog<bool>(
      context: context,
      builder: (_) => const WhatsAppSettingsDialog(),
    );
  }

  Future<void> _openHistory() async {
    await WaitlistHistoryScreen.push(context);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final entries =
        waitlistService.active; // only active parties in the sheet list

    return Directionality(
      textDirection:
          translationService.isRTL ? TextDirection.rtl : TextDirection.ltr,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: size.height * 0.88,
        ),
        decoration: BoxDecoration(
          color: context.appSurface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildGrabber(context),
            _buildHeader(context, count: entries.length),
            const SizedBox(height: 4),
            Flexible(
              child: entries.isEmpty
                  ? _buildEmpty(context)
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      itemCount: entries.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => _buildEntryCard(entries[i]),
                    ),
            ),
            SafeArea(
              top: false,
              child: _buildBottomBar(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGrabber(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        width: 44,
        height: 4,
        decoration: BoxDecoration(
          color: context.appBorder,
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, {required int count}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: context.appPrimary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(LucideIcons.clock, color: context.appPrimary, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  translationService.t('waitlist_title'),
                  style: TextStyle(
                    color: context.appText,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  translationService.t(
                    'waitlist_subtitle_count',
                    args: {'count': '$count'},
                  ),
                  style: TextStyle(
                    color: context.appTextMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: translationService.t('waitlist_history_title'),
            onPressed: _openHistory,
            icon: Icon(LucideIcons.history, color: context.appTextMuted),
          ),
          IconButton(
            tooltip: translationService.t('whatsapp_settings_title'),
            onPressed: _openSettings,
            icon: Icon(LucideIcons.settings, color: context.appTextMuted),
          ),
          IconButton(
            tooltip: translationService.t('close'),
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(LucideIcons.x, color: context.appTextMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: context.appPrimary.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(LucideIcons.users,
                color: context.appPrimary, size: 32),
          ),
          const SizedBox(height: 14),
          Text(
            translationService.t('waitlist_empty_title'),
            style: TextStyle(
              color: context.appText,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            translationService.t('waitlist_empty_body'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.appTextMuted,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEntryCard(WaitlistEntry e) {
    final waited = e.minutesWaiting();
    final isNotified = e.status == WaitlistStatus.notified;

    return Material(
      color: context.appSurfaceAlt,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _editEntry(e),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isNotified
                          ? const Color(0xFF10B981).withValues(alpha: 0.14)
                          : context.appPrimary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _initial(e.customerName),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: isNotified
                            ? const Color(0xFF059669)
                            : context.appPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          e.customerName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.appText,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(LucideIcons.phone,
                                size: 11, color: context.appTextMuted),
                            const SizedBox(width: 3),
                            Text(
                              _formatPhone(e.phoneNumber),
                              style: TextStyle(
                                color: context.appTextMuted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  _statusBadge(e, waited),
                  PopupMenuButton<String>(
                    tooltip: translationService.t('options'),
                    icon: Icon(LucideIcons.moreVertical,
                        size: 18, color: context.appTextMuted),
                    onSelected: (v) async {
                      switch (v) {
                        case 'edit':
                          await _editEntry(e);
                          break;
                        case 'cancel':
                          await waitlistService.cancel(e.id);
                          break;
                        case 'remove':
                          await _confirmRemove(e);
                          break;
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'edit',
                        child: _menuRow(
                          icon: LucideIcons.edit3,
                          label: translationService.t('edit'),
                          color: const Color(0xFF2563EB),
                        ),
                      ),
                      if (isNotified)
                        PopupMenuItem(
                          value: 'cancel',
                          child: _menuRow(
                            icon: LucideIcons.undo2,
                            label: translationService.t(
                              'waitlist_revert_to_waiting',
                            ),
                            color: const Color(0xFFB45309),
                          ),
                        ),
                      PopupMenuItem(
                        value: 'remove',
                        child: _menuRow(
                          icon: LucideIcons.trash2,
                          label: translationService.t('waitlist_remove'),
                          color: const Color(0xFFDC2626),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _chip(
                    icon: LucideIcons.users,
                    label: translationService.t(
                      'waitlist_party_of',
                      args: {'count': '${e.partySize}'},
                    ),
                  ),
                  const SizedBox(width: 6),
                  _chip(
                    icon: LucideIcons.messageSquare,
                    label: 'WhatsApp',
                  ),
                  if ((e.notes ?? '').isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Flexible(
                      child: _chip(
                        icon: LucideIcons.stickyNote,
                        label: e.notes!,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _beginAssign(e),
                  icon: Icon(
                    isNotified
                        ? LucideIcons.refreshCw
                        : LucideIcons.layoutGrid,
                    size: 16,
                  ),
                  label: Text(
                    translationService.t(
                      isNotified
                          ? 'waitlist_reassign_cta'
                          : 'waitlist_assign_cta',
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: isNotified
                        ? const Color(0xFF059669)
                        : context.appPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusBadge(WaitlistEntry e, int waited) {
    if (e.status == WaitlistStatus.notified) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFF10B981).withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.checkCircle,
                size: 11, color: Color(0xFF059669)),
            const SizedBox(width: 3),
            Text(
              e.assignedTableNumber != null
                  ? translationService.t(
                      'waitlist_notified_to',
                      args: {'table': e.assignedTableNumber!},
                    )
                  : translationService.t('waitlist_status_notified'),
              style: const TextStyle(
                color: Color(0xFF059669),
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: context.appPrimary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.clock, size: 11, color: context.appPrimary),
          const SizedBox(width: 3),
          Text(
            translationService.t(
              'waitlist_waited_minutes',
              args: {'count': '$waited'},
            ),
            style: TextStyle(
              color: context.appPrimary,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.appBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: context.appTextMuted),
          const SizedBox(width: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: context.appText,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _menuRow({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(color: color, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: context.appBorder)),
      ),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: _addEntry,
          icon: const Icon(LucideIcons.userPlus, size: 18),
          label: Text(translationService.t('waitlist_add_cta')),
          style: FilledButton.styleFrom(
            backgroundColor: context.appPrimary,
            padding: const EdgeInsets.symmetric(vertical: 14),
            textStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }

  String _initial(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    final first = trimmed.characters.first;
    return first.toUpperCase();
  }

  /// Display the phone grouped so long numbers don't crush the card.
  /// Keeps digits-only (no `+`) and inserts thin spaces every 3–4
  /// digits for readability.
  String _formatPhone(String raw) {
    if (raw.isEmpty) return raw;
    final buf = StringBuffer('+');
    for (int i = 0; i < raw.length; i++) {
      // Country code (first 3) → separator → 3 → separator → rest.
      if (i == 3 || i == 6) buf.write(' ');
      buf.write(raw[i]);
    }
    return buf.toString();
  }
}
