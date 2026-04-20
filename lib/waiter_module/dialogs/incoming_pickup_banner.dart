import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../services/app_themes.dart';
import '../models/table_pickup_request.dart';
import '../services/waiter_controller.dart';
import '../theme/waiter_design.dart';

/// Banner that pops when a cashier broadcasts a "استلام" pickup request.
/// Offers a prominent accept button so the fastest waiter can claim the
/// table in a single tap; auto-dismisses after 12s so it can't linger
/// during a busy shift.
void showIncomingPickupBanner(
  BuildContext context,
  TablePickupRequest req,
  WaiterController controller,
) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;

  messenger.clearMaterialBanners();

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
        onPressed: () => messenger.hideCurrentMaterialBanner(),
        child: const Text('لاحقاً'),
      ),
      FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: context.appPrimary,
          minimumSize: const Size(100, WaiterSizes.minTapTarget),
        ),
        onPressed: () {
          unawaited(WaiterHaptics.success());
          controller.claimTablePickup(req.requestId);
          messenger.hideCurrentMaterialBanner();
        },
        icon: const Icon(LucideIcons.check, size: 16),
        label: const Text(
          'استلام',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    ],
  );

  messenger.showMaterialBanner(banner);
  Future.delayed(const Duration(seconds: 12), () {
    try {
      messenger.hideCurrentMaterialBanner();
    } catch (_) {}
  });
}
