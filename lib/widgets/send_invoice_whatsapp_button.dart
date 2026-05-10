import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../services/invoice_whatsapp_dispatcher.dart';
import '../services/language_service.dart';
import '../services/whatsapp_service.dart';

/// Button that sends the invoice PDF on WhatsApp via [invoiceWhatsAppDispatcher].
///
/// The button owns the full UX around a credit-sensitive feature:
///   - Hides itself entirely when the branch has no WAWP credentials.
///   - Stays enabled even when [customerPhone] is null — the dispatcher
///     fetches it from the backend's `getInvoice` response on demand,
///     so list rows that don't ship customer info can still send.
///   - Shows a spinner while the dispatcher is in-flight.
///   - Shows "Sent ✓" once successful, and gates a re-send behind a
///     confirmation dialog so a stray double-tap can't burn a second
///     credit silently.
///   - Listens to the dispatcher so its visual state stays correct even
///     when the user closes and reopens the dialog mid-session.
class SendInvoiceWhatsAppButton extends StatefulWidget {
  final String invoiceId;
  final String? customerPhone;
  final String? customerName;

  /// Display number used in the caption ("فاتورتك رقم {invoiceNumber}")
  /// and the suggested file name ("invoice_{invoiceNumber}.pdf"). Falls
  /// back to a generic caption + "invoice.pdf" when null.
  final String? invoiceNumber;

  /// Set to false to render a [FilledButton] (small surfaces) instead of
  /// the default [OutlinedButton.icon] (matches the print/refund row).
  final bool outlined;

  /// Optional fixed minimum size to align with siblings inside Row layouts.
  final Size? minimumSize;

  const SendInvoiceWhatsAppButton({
    super.key,
    required this.invoiceId,
    required this.customerPhone,
    this.customerName,
    this.invoiceNumber,
    this.outlined = true,
    this.minimumSize,
  });

  @override
  State<SendInvoiceWhatsAppButton> createState() => _SendInvoiceWhatsAppButtonState();
}

class _SendInvoiceWhatsAppButtonState extends State<SendInvoiceWhatsAppButton> {
  @override
  void initState() {
    super.initState();
    invoiceWhatsAppDispatcher.addListener(_onDispatcherChanged);
    whatsAppService.addListener(_onDispatcherChanged);
    // Lazy-init the WhatsApp service so config (and therefore
    // [WhatsAppConfig.isApiReady]) is populated. The branch settings
    // path seeds creds in memory regardless of `whatsapp_status`, so
    // simply waiting for initialize() is enough to know whether the
    // button can do anything useful.
    unawaited(whatsAppService.initialize());
  }

  @override
  void dispose() {
    invoiceWhatsAppDispatcher.removeListener(_onDispatcherChanged);
    whatsAppService.removeListener(_onDispatcherChanged);
    super.dispose();
  }

  void _onDispatcherChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _onPressed() async {
    final id = widget.invoiceId;
    final dispatcher = invoiceWhatsAppDispatcher;

    if (dispatcher.isInFlight(id)) return;

    bool force = false;
    if (dispatcher.isSent(id)) {
      final confirmed = await _confirmResend(context);
      if (confirmed != true) return;
      force = true;
    }

    final result = await dispatcher.sendInvoice(
      invoiceId: id,
      customerPhone: widget.customerPhone,
      customerName: widget.customerName,
      invoiceNumber: widget.invoiceNumber,
      force: force,
    );

    if (!mounted) return;
    _showFeedback(result);
  }

  Future<bool?> _confirmResend(BuildContext context) {
    final name = widget.customerName?.trim();
    final body = (name != null && name.isNotEmpty)
        ? translationService.t('invoice_whatsapp_resend_body_named', args: {'name': name})
        : translationService.t('invoice_whatsapp_resend_body');
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(translationService.t('invoice_whatsapp_resend_title')),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(translationService.t('cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF16A34A),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(translationService.t('invoice_whatsapp_resend_confirm')),
          ),
        ],
      ),
    );
  }

  void _showFeedback(WhatsAppDispatchResult result) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    String text;
    Color background;
    switch (result.outcome) {
      case WhatsAppDispatchOutcome.success:
        text = translationService.t('invoice_whatsapp_sent_ok');
        background = const Color(0xFF16A34A);
        break;
      case WhatsAppDispatchOutcome.alreadyInFlight:
        text = translationService.t('invoice_whatsapp_in_flight');
        background = const Color(0xFFCA8A04);
        break;
      case WhatsAppDispatchOutcome.alreadySent:
        text = translationService.t('invoice_whatsapp_already_sent');
        background = const Color(0xFFCA8A04);
        break;
      case WhatsAppDispatchOutcome.noCustomerPhone:
        text = translationService.t('invoice_whatsapp_no_customer');
        background = const Color(0xFFDC2626);
        break;
      case WhatsAppDispatchOutcome.credentialsMissing:
        text = translationService.t('invoice_whatsapp_creds_missing');
        background = const Color(0xFFDC2626);
        break;
      case WhatsAppDispatchOutcome.pdfUrlUnavailable:
        text = translationService.t('invoice_whatsapp_pdf_unavailable');
        background = const Color(0xFFDC2626);
        break;
      case WhatsAppDispatchOutcome.failure:
        final msg = result.errorMessage?.trim() ?? '';
        text = msg.isEmpty
            ? translationService.t('failed_to_send_whatsapp')
            : translationService.t('failed_to_send_whatsapp_with_reason', args: {'reason': msg});
        background = const Color(0xFFDC2626);
        break;
    }

    messenger.showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: background,
      duration: const Duration(seconds: 3),
    ));
  }

  @override
  Widget build(BuildContext context) {
    // Mirror the waiter waitlist gate: show the button whenever the
    // branch has WAWP credentials configured, ignoring the
    // `ApiConstants.whatsappEnabled` toggle. That toggle is a backend
    // policy flag (does the merchant want WhatsApp at all?) which the
    // waitlist *does* respect — but on the cashier side, removing it
    // here means the merchant can send invoices over WhatsApp the
    // moment they paste WAWP creds into branch settings, without
    // having to also flip an additional flag.
    if (!whatsAppService.config.isApiReady) {
      return const SizedBox.shrink();
    }

    final inFlight = invoiceWhatsAppDispatcher.isInFlight(widget.invoiceId);
    final sent = invoiceWhatsAppDispatcher.isSent(widget.invoiceId);
    // Only disable while a request is in-flight. The dispatcher fetches
    // the customer phone from the backend on demand when the row didn't
    // ship one (list rows often skip nested customer info), so we no
    // longer pre-emptively grey out the button — if no phone exists, the
    // dispatcher returns `noCustomerPhone` and the snackbar explains it.
    final disabled = inFlight;

    final IconData iconData;
    final String labelKey;
    if (inFlight) {
      iconData = LucideIcons.loader;
      labelKey = 'invoice_whatsapp_sending';
    } else if (sent) {
      iconData = LucideIcons.checkCircle2;
      labelKey = 'invoice_whatsapp_sent_label';
    } else {
      iconData = LucideIcons.fileText;
      labelKey = 'send_invoice_whatsapp';
    }

    final icon = inFlight
        ? const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(iconData, size: 18);
    final label = Text(translationService.t(labelKey));

    final color = sent ? const Color(0xFF16A34A) : const Color(0xFF16A34A);
    final minSize = widget.minimumSize ?? const Size.fromHeight(48);

    final Widget button;
    if (widget.outlined) {
      button = OutlinedButton.icon(
        onPressed: disabled ? null : _onPressed,
        icon: icon,
        label: label,
        style: OutlinedButton.styleFrom(
          minimumSize: minSize,
          foregroundColor: color,
          side: BorderSide(color: color),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } else {
      button = FilledButton.icon(
        onPressed: disabled ? null : _onPressed,
        icon: icon,
        label: label,
        style: FilledButton.styleFrom(
          minimumSize: minSize,
          backgroundColor: color,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }

    return button;
  }
}
