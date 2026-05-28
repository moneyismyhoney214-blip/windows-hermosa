import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../locator.dart';
import '../models/waitlist_entry.dart';
import '../services/api/branch_service.dart';
import '../services/api/country_code_service.dart';
import '../services/app_themes.dart';
import '../services/language_service.dart';
import '../services/waitlist_assign_controller.dart';
import '../services/waitlist_service.dart';
import '../services/whatsapp_service.dart';
import '../utils/ui_feedback.dart';
import '../waiter_module/services/waiter_controller.dart';

// SMS removed — every dispatch goes through WhatsApp (WAWP API → wa.me fallback).

/// Confirmation + send dialog used by both the cashier and waiter
/// screens. Shows the rendered message preview, lets the host flip
/// channels at the last second, and — on confirm — fires the send +
/// persists the waitlist status transition.
///
/// Returns `true` when a notification was successfully dispatched.
class WaitlistNotifyDialog extends StatefulWidget {
  final WaitlistEntry entry;
  final String tableId;
  final String tableNumber;

  const WaitlistNotifyDialog({
    super.key,
    required this.entry,
    required this.tableId,
    required this.tableNumber,
  });

  static Future<bool?> show(
    BuildContext context, {
    required WaitlistEntry entry,
    required String tableId,
    required String tableNumber,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => WaitlistNotifyDialog(
        entry: entry,
        tableId: tableId,
        tableNumber: tableNumber,
      ),
    );
  }

  @override
  State<WaitlistNotifyDialog> createState() => _WaitlistNotifyDialogState();
}

class _WaitlistNotifyDialogState extends State<WaitlistNotifyDialog> {
  bool _sending = false;

  String get _preview => whatsAppService.renderMessage(
        customerName: widget.entry.customerName,
        tableNumber: widget.tableNumber,
      );

  Future<void> _send() async {
    setState(() => _sending = true);

    // WAWP creds aren't persisted; pull from memory, branch-settings fetch, then LAN mesh — otherwise waiter falls back to host's personal WhatsApp.
    await whatsAppService.initialize();
    if (!whatsAppService.config.isApiReady) {
      debugPrint('📨 [Waitlist-WA] no WAWP creds yet — fetching branch settings');
      try {
        final s = await getIt<BranchService>().getBranchSettings(forceRefresh: true);
        debugPrint('📨 [Waitlist-WA] branch-settings whatsapp block: ${s['whatsapp']}');
      } catch (e) {
        debugPrint('📨 [Waitlist-WA] getBranchSettings failed: $e');
      }
    }
    if (!whatsAppService.config.isApiReady) {
      // Waiter device: prod the connected cashier to (re)push its config.
      try {
        final wc = getIt<WaiterController>();
        if (wc.isRunning) {
          wc.requestConfigSync();
          for (var i = 0; i < 12; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 250));
            if (whatsAppService.config.isApiReady) break;
          }
        }
      } catch (e) {
        debugPrint('📨 [Waitlist-WA] config-sync request failed: $e');
      }
    }
    debugPrint('📨 [Waitlist-WA] sending — isApiReady=${whatsAppService.config.isApiReady} '
        'instanceLen=${(whatsAppService.config.instanceId ?? '').length} '
        'tokenLen=${(whatsAppService.config.accessToken ?? '').length}');

    // Pass branch country code so prefix-less stored numbers (e.g. EG "1090081223") get normalized — otherwise WAWP rejects as +1/AG.
    final result = await whatsAppService.sendTableReady(
      rawPhone: widget.entry.phoneNumber,
      customerName: widget.entry.customerName,
      tableNumber: widget.tableNumber,
      countryCodeOverride: countryCodeService.defaultForBranch().areaCode,
    );
    debugPrint('📨 [Waitlist-WA] result — ok=${result.ok} '
        'via=${result.deliveredVia} err=${result.errorMessage}');

    if (!mounted) return;

    if (!result.ok) {
      setState(() => _sending = false);
      final reason = result.errorMessage ?? '';
      final key = _translateFailureReason(reason);
      _showErrorSnack(key);
      return;
    }

    await waitlistService.markNotified(
      entryId: widget.entry.id,
      tableId: widget.tableId,
      tableNumber: widget.tableNumber,
    );
    waitlistAssignController.clear();

    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  String _translateFailureReason(String reason) {
    // No wa.me fallback — non-phone failures funnel into a single support message.
    switch (reason) {
      case 'invalid_phone':
        return 'waitlist_send_error_phone';
      default:
        return 'waitlist_send_error_support';
    }
  }

  void _showErrorSnack(String key) {
    UiFeedback.error(context, translationService.t(key));
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
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _summaryRow(),
                    const SizedBox(height: 14),
                    _previewBox(),
                  ],
                ),
              ),
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
        color: Color(0xFF10B981),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Row(
        children: [
          const Icon(LucideIcons.send, color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              translationService.t('waitlist_notify_title'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          IconButton(
            onPressed:
                _sending ? null : () => Navigator.of(context).pop(false),
            icon: const Icon(LucideIcons.x, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.appSurfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.appBorder),
      ),
      child: Row(
        children: [
          _summaryBlock(
            icon: LucideIcons.user,
            label: translationService.t('waitlist_field_name'),
            value: widget.entry.customerName,
          ),
          Container(
            width: 1,
            height: 32,
            color: context.appBorder,
            margin: const EdgeInsets.symmetric(horizontal: 10),
          ),
          _summaryBlock(
            icon: LucideIcons.layoutGrid,
            label: translationService.t('waitlist_notify_table_label'),
            value: widget.tableNumber,
            highlight: true,
          ),
        ],
      ),
    );
  }

  Widget _summaryBlock({
    required IconData icon,
    required String label,
    required String value,
    bool highlight = false,
  }) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: context.appTextMuted),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: context.appTextMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              color: highlight ? const Color(0xFF059669) : context.appText,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _previewBox() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          translationService.t('waitlist_notify_preview_label'),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: context.appText,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFECFDF5),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0xFF10B981).withValues(alpha: 0.3),
            ),
          ),
          child: Text(
            _preview,
            style: const TextStyle(
              color: Color(0xFF065F46),
              fontSize: 13,
              height: 1.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFooter() {
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
                  _sending ? null : () => Navigator.of(context).pop(false),
              child: Text(translationService.t('cancel')),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: FilledButton.icon(
              onPressed: _sending ? null : _send,
              icon: _sending
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
                translationService.t('waitlist_notify_send'),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
