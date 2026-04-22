import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../locator.dart';
import '../../screens/login_screen.dart';
import '../../services/api/auth_service.dart';
import '../../services/app_themes.dart';
import '../../services/language_service.dart';
import '../models/waiter.dart';
import '../services/waiter_controller.dart';
import '../theme/waiter_design.dart';
import '../widgets/waiter_status_chip.dart';
import 'waiter_printer_settings_screen.dart';

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
      padding: const EdgeInsets.all(WaiterSpacing.lg),
      children: [
        _header(context, me),
        const SizedBox(height: WaiterSpacing.xl),
        Text(
          translationService.t('waiter_set_status'),
          style: TextStyle(
            color: context.appTextMuted,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: WaiterSpacing.sm),
        Wrap(
          spacing: WaiterSpacing.sm,
          runSpacing: WaiterSpacing.sm,
          children: [
            for (final s in [
              WaiterStatus.free,
              WaiterStatus.busy,
              WaiterStatus.onBreak,
            ])
              _StatusChoice(
                status: s,
                selected: me.status == s,
                onTap: () {
                  unawaited(WaiterHaptics.tick());
                  widget.controller.setStatus(s);
                },
              ),
          ],
        ),
        const SizedBox(height: WaiterSpacing.xxl),
        SizedBox(
          height: WaiterSizes.primaryButtonHeight,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: context.appPrimary,
              side: BorderSide(color: context.appPrimary),
              padding: const EdgeInsets.symmetric(
                vertical: WaiterSpacing.md + 2,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(WaiterRadius.md),
              ),
            ),
            icon: const Icon(LucideIcons.settings),
            label: const Text('إعدادات الأجهزة والطباعة'),
            onPressed: _openPrinterSettings,
          ),
        ),
        const SizedBox(height: WaiterSpacing.md),
        SizedBox(
          height: WaiterSizes.primaryButtonHeight,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: context.appDanger,
              side: BorderSide(color: context.appDanger),
              padding: const EdgeInsets.symmetric(
                vertical: WaiterSpacing.md + 2,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(WaiterRadius.md),
              ),
            ),
            icon: const Icon(LucideIcons.logOut),
            label: Text(translationService.t('waiter_end_shift')),
            onPressed: _confirmEndShift,
          ),
        ),
      ],
    );
  }

  void _openPrinterSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const WaiterPrinterSettingsScreen(),
      ),
    );
  }

  Future<void> _confirmEndShift() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.appSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WaiterRadius.lg),
        ),
        title: Text(translationService.t('waiter_end_shift')),
        content: const Text(
          'هل أنت متأكد من تسجيل الخروج؟ سيتم إنهاء جلستك على هذا الجهاز.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(translationService.t('waiter_cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: context.appDanger,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(translationService.t('waiter_end_shift')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    unawaited(WaiterHaptics.warn());
    // Full logout, in order:
    //   1. Tear down the mesh controller so no outgoing broadcasts can
    //      race the signOut.
    //   2. Clear session-scoped stores (drafts, pickups, messages,
    //      table registry) so the next user on this device starts
    //      fresh. Must run AFTER stop() — otherwise in-flight message
    //      handlers may re-populate the stores.
    //   3. Sign out from the waiter session (local name/branch reset).
    //   4. Call AuthService.logout() to revoke the backend token; this
    //      is the step the old popUntil flow missed, so the waiter
    //      module re-entry path would auto-sign the user back in.
    //   5. Navigate to LoginScreen via pushAndRemoveUntil so even when
    //      WaiterModuleEntry is the root route (the cashier's
    //      pushReplacement path) the stack is fully cleared.
    try {
      await widget.controller.stop();
    } catch (e) {
      debugPrint('⚠️ Waiter logout stop failed: $e');
    }
    try {
      widget.controller.clearSessionStores();
    } catch (e) {
      debugPrint('⚠️ Waiter logout store clear failed: $e');
    }
    try {
      await widget.controller.session.signOut();
    } catch (e) {
      debugPrint('⚠️ Waiter logout session signOut failed: $e');
    }
    try {
      await getIt<AuthService>().logout();
    } catch (e) {
      debugPrint('⚠️ Waiter logout AuthService.logout failed: $e');
    }
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
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
