import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../services/app_themes.dart';
import '../models/waiter.dart';
import '../services/waiter_controller.dart';

/// Cashier-only dialog for sending a message to one waiter or broadcasting
/// to all waiters at once. Thin UI over [WaiterController.sendMessage] —
/// the protocol (first-wins accept for broadcasts, sound/vibration on the
/// receiver) is already in place.
class SendCashierMessageDialog extends StatefulWidget {
  final WaiterController controller;

  /// When non-null the dialog opens with that waiter selected. Pass the
  /// waiter id; the name is resolved from the roster.
  final String? initialRecipientId;

  /// Optional table context — attached to the message so the waiter's
  /// notification card shows which table the cashier was pointing at.
  final String? tableId;
  final String? tableNumber;

  const SendCashierMessageDialog({
    super.key,
    required this.controller,
    this.initialRecipientId,
    this.tableId,
    this.tableNumber,
  });

  @override
  State<SendCashierMessageDialog> createState() =>
      _SendCashierMessageDialogState();
}

class _SendCashierMessageDialogState extends State<SendCashierMessageDialog> {
  static const String _broadcastKey = '*';

  final _textCtrl = TextEditingController();
  bool _ring = true;
  late String _recipient;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _recipient = widget.initialRecipientId ?? _broadcastKey;
    widget.controller.roster.addListener(_onRosterChanged);
  }

  @override
  void dispose() {
    widget.controller.roster.removeListener(_onRosterChanged);
    _textCtrl.dispose();
    super.dispose();
  }

  void _onRosterChanged() {
    if (!mounted) return;
    // If the selected waiter went offline, fall back to broadcast so the
    // send button doesn't send into a void.
    if (_recipient != _broadcastKey) {
      final stillOnline = _onlineWaiters().any((w) => w.id == _recipient);
      if (!stillOnline) {
        setState(() => _recipient = _broadcastKey);
      } else {
        setState(() {});
      }
    } else {
      setState(() {});
    }
  }

  List<Waiter> _onlineWaiters() {
    return widget.controller.roster.all
        .where((w) => !w.isViewer && w.status != WaiterStatus.offline)
        .toList(growable: false);
  }

  void _send() {
    if (_sending) return;
    final online = _onlineWaiters();
    if (online.isEmpty && _recipient != _broadcastKey) {
      // Race: waiter went offline between selection and submit.
      _recipient = _broadcastKey;
    }
    final text = _textCtrl.text.trim();
    if (text.isEmpty && !_ring) {
      // Nothing to deliver — at least one of text or ring should land.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('اكتب رسالة أو فعّل الجرس على الأقل.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    setState(() => _sending = true);
    try {
      widget.controller.sendMessage(
        toWaiterId: _recipient == _broadcastKey ? null : _recipient,
        text: text,
        tableId: widget.tableId,
        tableNumber: widget.tableNumber,
        isCall: _ring,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on StateError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر الإرسال: $e')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final online = _onlineWaiters();
    final isBroadcast = _recipient == _broadcastKey;

    return AlertDialog(
      backgroundColor: context.appSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(
            isBroadcast ? LucideIcons.megaphone : LucideIcons.send,
            color: context.appPrimary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isBroadcast ? 'رسالة لجميع النوادل' : 'رسالة لنادل محدد',
              style: TextStyle(color: context.appText, fontSize: 17),
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildRecipientPicker(context, online),
            const SizedBox(height: 12),
            if (widget.tableNumber != null &&
                widget.tableNumber!.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Icon(LucideIcons.armchair,
                        size: 14, color: context.appTextMuted),
                    const SizedBox(width: 6),
                    Text(
                      'الطاولة ${widget.tableNumber}',
                      style: TextStyle(
                        color: context.appText,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            TextField(
              controller: _textCtrl,
              minLines: 2,
              maxLines: 5,
              style: TextStyle(color: context.appText),
              decoration: InputDecoration(
                hintText: 'اكتب الرسالة (اختياري)',
                filled: true,
                fillColor: context.appSurfaceAlt,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: context.appBorder),
                ),
              ),
            ),
            const SizedBox(height: 6),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _ring,
              onChanged: (v) => setState(() => _ring = v ?? false),
              dense: true,
              title: const Text('تشغيل نغمة التنبيه'),
              subtitle: Text(
                'يرنّ الجهاز المستهدف ويهتز',
                style: TextStyle(color: context.appTextMuted, fontSize: 11),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed:
              _sending ? null : () => Navigator.of(context).pop(false),
          child: const Text('إلغاء'),
        ),
        FilledButton.icon(
          onPressed: _sending ? null : _send,
          style: FilledButton.styleFrom(
            backgroundColor: context.appPrimary,
            foregroundColor: Colors.white,
          ),
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
          label: const Text('إرسال'),
        ),
      ],
    );
  }

  Widget _buildRecipientPicker(BuildContext context, List<Waiter> online) {
    // When there's no one to directly address the picker collapses to a
    // single "broadcast" chip — no point rendering the dropdown.
    if (online.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: context.appSurfaceAlt,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(LucideIcons.userX, size: 16, color: context.appTextMuted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'لا يوجد نادل متصل — سترسل كطلب عام يظهر لأول من يفتح التطبيق.',
                style: TextStyle(color: context.appTextMuted, fontSize: 12),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: context.appSurfaceAlt,
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: _recipient,
          icon: Icon(LucideIcons.chevronDown, color: context.appTextMuted),
          style: TextStyle(color: context.appText, fontSize: 14),
          dropdownColor: context.appSurface,
          onChanged: (v) {
            if (v == null) return;
            setState(() => _recipient = v);
          },
          items: [
            DropdownMenuItem<String>(
              value: _broadcastKey,
              child: Row(
                children: [
                  Icon(LucideIcons.megaphone,
                      size: 15, color: context.appPrimary),
                  const SizedBox(width: 8),
                  Text('جميع النوادل (${online.length})'),
                ],
              ),
            ),
            ...online.map(
              (w) => DropdownMenuItem<String>(
                value: w.id,
                child: Row(
                  children: [
                    Icon(LucideIcons.user,
                        size: 15, color: context.appTextMuted),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        w.name.isEmpty ? w.id : w.name,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
