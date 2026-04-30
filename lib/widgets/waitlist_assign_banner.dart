import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../models/waitlist_entry.dart';
import '../services/language_service.dart';
import '../services/waitlist_assign_controller.dart';

/// Top-of-screen banner that appears whenever the shared assign
/// controller has a pending waitlist entry. Both the cashier and the
/// waiter tables screens plant this at the top of their column so the
/// host sees identical chrome regardless of which module they're in.
///
/// Tapping the × dismisses assign mode without notifying anyone.
class WaitlistAssignBanner extends StatelessWidget {
  const WaitlistAssignBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: waitlistAssignController,
      builder: (context, _) {
        final entry = waitlistAssignController.pending;
        return AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOutCubic,
          alignment: Alignment.topCenter,
          child: entry == null
              ? const SizedBox(width: double.infinity)
              : _Banner(entry: entry),
        );
      },
    );
  }
}

class _Banner extends StatelessWidget {
  final WaitlistEntry entry;
  const _Banner({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFEF3C7),
      child: SafeArea(
        bottom: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Color(0xFFF59E0B), width: 1.2),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: Color(0xFFF59E0B),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  LucideIcons.mousePointerClick,
                  color: Colors.white,
                  size: 16,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      translationService.t(
                        'waitlist_assign_banner_title',
                        args: {'name': entry.customerName},
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF92400E),
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      translationService.t(
                        'waitlist_assign_banner_hint',
                        args: {'count': '${entry.partySize}'},
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFB45309),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: translationService.t('cancel'),
                onPressed: waitlistAssignController.clear,
                icon: const Icon(
                  LucideIcons.x,
                  color: Color(0xFF92400E),
                  size: 18,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
