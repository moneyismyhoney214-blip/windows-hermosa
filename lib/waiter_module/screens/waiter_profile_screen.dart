import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../services/app_themes.dart';
import '../../services/language_service.dart';
import '../models/waiter.dart';
import '../services/waiter_controller.dart';
import '../widgets/waiter_status_chip.dart';

/// Profile / status screen — lets the waiter change their availability and
/// end their shift (which broadcasts `WAITER_LEAVE` to peers).
class WaiterProfileScreen extends StatefulWidget {
  final WaiterController controller;
  const WaiterProfileScreen({super.key, required this.controller});

  @override
  State<WaiterProfileScreen> createState() => _WaiterProfileScreenState();
}

class _WaiterProfileScreenState extends State<WaiterProfileScreen> {
  @override
  void initState() {
    super.initState();
    widget.controller.session.addListener(_refresh);
  }

  @override
  void dispose() {
    widget.controller.session.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final me = widget.controller.session.self;
    if (me == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _header(context, me),
        const SizedBox(height: 24),
        Text(
          translationService.t('waiter_set_status'),
          style: TextStyle(
            color: context.appTextMuted,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in [
              WaiterStatus.free,
              WaiterStatus.busy,
              WaiterStatus.onBreak,
            ])
              _StatusChoice(
                status: s,
                selected: me.status == s,
                onTap: () => widget.controller.setStatus(s),
              ),
          ],
        ),
        const SizedBox(height: 32),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: context.appDanger,
            side: BorderSide(color: context.appDanger),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          icon: const Icon(LucideIcons.logOut),
          label: Text(translationService.t('waiter_end_shift')),
          onPressed: () async {
            // Always run signOut even if stop() throws — otherwise a
            // failed network teardown would leave the device "signed in"
            // from the session's perspective, and the next open would
            // skip the login screen and try to re-use a half-dead shift.
            try {
              await widget.controller.stop();
            } catch (e) {
              debugPrint('⚠️ Waiter end-shift stop failed: $e');
            }
            try {
              await widget.controller.session.signOut();
            } catch (e) {
              debugPrint('⚠️ Waiter end-shift signOut failed: $e');
            }
            if (!mounted) return;
            Navigator.of(context).popUntil((r) => r.isFirst);
          },
        ),
      ],
    );
  }

  Widget _header(BuildContext context, Waiter me) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.appBorder),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: context.appPrimary.withValues(alpha: 0.2),
            child: Text(
              me.name.isNotEmpty ? me.name[0].toUpperCase() : '?',
              style: TextStyle(
                color: context.appPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  me.name,
                  style: TextStyle(
                    color: context.appText,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                WaiterStatusChip(status: me.status),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChoice extends StatelessWidget {
  final WaiterStatus status;
  final bool selected;
  final VoidCallback onTap;

  const _StatusChoice({
    required this.status,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? context.appPrimary.withValues(alpha: 0.14)
          : context.appSurfaceAlt,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? context.appPrimary : context.appBorder,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: WaiterStatusChip(
            status: status,
            fontSize: 13,
            padding: EdgeInsets.zero,
          ),
        ),
      ),
    );
  }
}
