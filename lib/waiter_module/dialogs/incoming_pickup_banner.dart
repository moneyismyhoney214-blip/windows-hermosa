import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../services/app_themes.dart';
import '../../services/language_service.dart';
import '../../services/logger_service.dart';
import '../models/table_pickup_request.dart';
import '../services/waiter_controller.dart';
import '../theme/waiter_design.dart';

/// Bumped on every banner shown so a stale dismiss callback (the 12s timer,
/// or an `onPickupUpdate` event arriving late) only hides the banner if it's
/// still the one on screen — without this a later banner could be cut short.
int _pickupBannerGeneration = 0;

/// Banner that pops when a cashier broadcasts a "استلام" pickup request.
/// Offers a prominent accept button so the fastest waiter can claim the
/// table in a single tap. Auto-dismisses when the request is claimed/cancelled
/// by anyone, and after 12s regardless so it can't linger during a busy shift.
void showIncomingPickupBanner(
  BuildContext context,
  TablePickupRequest req,
  WaiterController controller,
) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;

  messenger.clearMaterialBanners();
  final myGen = ++_pickupBannerGeneration;

  StreamSubscription<TablePickupRequest>? updateSub;
  var dismissed = false;
  void dismiss() {
    if (dismissed) return;
    dismissed = true;
    updateSub?.cancel();
    // Only hide if we're still the banner on screen — a newer banner may
    // have replaced us via `clearMaterialBanners()` already.
    if (_pickupBannerGeneration == myGen) {
      try {
        messenger.hideCurrentMaterialBanner();
      } catch (e) {
        Log.d('IncomingPickupBanner', 'hide-banner failed after dispose (non-fatal): $e');
      }
    }
  }

  // If any peer claims this pickup (or the cashier cancels it), drop the
  // banner — keeping a prominent "استلام" button up after the table's
  // already taken just misleads everyone staring at it.
  updateSub = controller.onPickupUpdate.listen((u) {
    if (u.requestId == req.requestId && !u.isPending) dismiss();
  });

  final tableLabel = req.tableNumber.isNotEmpty ? req.tableNumber : req.tableId;

  final banner = MaterialBanner(
    backgroundColor: context.appPrimary,
    content: Row(
      children: [
        const Icon(LucideIcons.handMetal, color: Colors.white),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'طلب استلام — طاولة $tableLabel',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              if ((req.note ?? '').isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  req.note!,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        style: TextButton.styleFrom(foregroundColor: Colors.white70),
        onPressed: dismiss,
        child: Text(translationService.t('waiter_pickup_later')),
      ),
      FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: context.appPrimary,
          minimumSize: const Size(100, WaiterSizes.minTapTarget),
        ),
        onPressed: () {
          // Did we actually win the claim? (Another waiter may have beaten us
          // by milliseconds — `claimTablePickup` returns the already-claimed
          // request in that case and broadcasts nothing.)
          final claimed = controller.claimTablePickup(req.requestId);
          final iWon = claimed != null &&
              claimed.claimedByWaiterId == controller.session.self?.id;
          unawaited(iWon ? WaiterHaptics.success() : WaiterHaptics.warn());
          dismiss();
        },
        icon: const Icon(LucideIcons.check, size: 16),
        label: Text(
          translationService.t('waiter_pickup_take'),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    ],
  );

  messenger.showMaterialBanner(banner);
  Future.delayed(const Duration(seconds: 12), dismiss);
}
