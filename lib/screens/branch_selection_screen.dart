import 'dart:async';

import 'package:flutter/material.dart';

import '../locator.dart';
import '../models/branch.dart';
import '../services/api/api_constants.dart';
import '../services/api/auth_service.dart';
import '../services/app_themes.dart';
import '../services/language_service.dart';
import '../utils/ui_feedback.dart';
import '../waiter_module/waiter_module_entry.dart';
import 'main_screen.dart';

class BranchSelectionScreen extends StatefulWidget {
  final List<Branch> branches;

  const BranchSelectionScreen({super.key, required this.branches});

  @override
  State<BranchSelectionScreen> createState() => _BranchSelectionScreenState();
}

class _BranchSelectionScreenState extends State<BranchSelectionScreen> {
  bool _isSelecting = false;

  Future<void> _selectBranch(Branch branch) async {
    setState(() => _isSelecting = true);

    try {
      final authService = getIt<AuthService>();

      // Update global constants
      ApiConstants.branchId = branch.id;
      ApiConstants.currency = branch.taxObject.currency;
      ApiConstants.branchModule = branch.module;

      // Persist the choice
      final token = authService.getToken();
      if (token != null) {
        // This will save the new branch ID and currency to SharedPreferences
        // We might need to expose a more direct method if this is too heavy
        await authService.initialize(
            force: true); // Reload and save logic inside
        // Actually AuthService needs a direct way to save just branch
      }

      // Instead of relying on internal private methods, we'll use a new method we'll add to AuthService
      await authService.updateActiveBranch(branch);

      if (mounted) {
        // Waiters land in the waiter module — but only on a restaurant
        // branch. The waiter UX is table-service centric (floor plan,
        // KDS, pickup calls); a salon branch has no tables, so a waiter
        // account that picked a salon branch falls back to the POS rather
        // than booting into an empty, broken floor screen.
        final isRestaurant = branch.module != 'salons';
        final nextScreen = authService.isWaiter() && isRestaurant
            ? const WaiterModuleEntry()
            : const MainScreen();
        unawaited(Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => nextScreen),
        ));
      }
    } catch (e) {
      if (mounted) {
        UiFeedback.info(context, translationService.t(
                'branch_select_error',
                args: {'error': e},
              ));
      }
    } finally {
      if (mounted) setState(() => _isSelecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRTL = translationService.isRTL;

    return Scaffold(
      backgroundColor: context.appBg,
      body: SafeArea(
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 500),
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  translationService.t('choose_branch_title'),
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: context.appText,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  translationService.t('choose_branch_subtitle'),
                  style: const TextStyle(
                    fontSize: 16,
                    color: Color(0xFF64748B),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 40),
                Expanded(
                  child: ListView.separated(
                    itemCount: widget.branches.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final branch = widget.branches[index];
                      return InkWell(
                        onTap:
                            _isSelecting ? null : () => _selectBranch(branch),
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: context.appBorder),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.02),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFF7ED),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.storefront,
                                  color: Color(0xFFF58220),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      branch.name,
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: context.appText,
                                      ),
                                    ),
                                    Text(
                                      branch.district,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: Color(0xFF64748B),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    _SubscriptionExpiryChip(branch: branch),
                                  ],
                                ),
                              ),
                              Icon(
                                isRTL
                                    ? Icons.chevron_left
                                    : Icons.chevron_right,
                                color: const Color(0xFF94A3B8),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (_isSelecting)
                  const Padding(
                    padding: EdgeInsets.only(top: 20),
                    child: Center(child: CircularProgressIndicator()),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Subscription state derived from a branch's `count_days` + `today`
/// (the server-clock anchor, so we don't depend on the device's clock).
class _SubscriptionExpiryChip extends StatelessWidget {
  final Branch branch;
  const _SubscriptionExpiryChip({required this.branch});

  @override
  Widget build(BuildContext context) {
    final days = branch.countDays;
    final today = _parseToday(branch.taxObject.today);
    final expiryDate = today?.add(Duration(days: days));

    final (label, color) = _resolve(days, expiryDate);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.event_outlined, size: 14, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  (String, Color) _resolve(int days, DateTime? expiryDate) {
    if (days <= 0) {
      return (translationService.t('subscription_expired'),
          const Color(0xFFDC2626));
    }
    if (days == 1 || expiryDate != null && _isSameDay(expiryDate, DateTime.now())) {
      return (translationService.t('subscription_expires_today'),
          const Color(0xFFDC2626));
    }
    final Color color;
    if (days <= 7) {
      color = const Color(0xFFDC2626);
    } else if (days <= 30) {
      color = const Color(0xFFEA580C);
    } else {
      color = const Color(0xFF15803D);
    }
    final daysLabel = translationService.t(
      'subscription_expires_in_days',
      args: {'days': days},
    );
    if (expiryDate == null) return (daysLabel, color);
    final dateLabel = translationService.t(
      'subscription_expires_on',
      args: {'date': _formatDate(expiryDate)},
    );
    return ('$daysLabel · $dateLabel', color);
  }

  DateTime? _parseToday(String raw) {
    if (raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  String _formatDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
