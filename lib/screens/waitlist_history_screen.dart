import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../models/waitlist_entry.dart';
import '../services/app_themes.dart';
import '../services/language_service.dart';
import '../services/waitlist_service.dart';

/// Full-screen log of past waitlist parties — seated + cancelled.
///
/// Two tabs because the outcomes are fundamentally different (seated =
/// success, cancelled = walk-away / manual clear) and the host usually
/// wants to look at one at a time.
class WaitlistHistoryScreen extends StatefulWidget {
  const WaitlistHistoryScreen({super.key});

  static Future<void> push(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const WaitlistHistoryScreen(),
      ),
    );
  }

  @override
  State<WaitlistHistoryScreen> createState() => _WaitlistHistoryScreenState();
}

class _WaitlistHistoryScreenState extends State<WaitlistHistoryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    waitlistService.addListener(_onStore);
  }

  @override
  void dispose() {
    waitlistService.removeListener(_onStore);
    _tabController.dispose();
    super.dispose();
  }

  void _onStore() {
    if (mounted) setState(() {});
  }

  Future<void> _confirmClearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.appSurface,
        title: Text(
          translationService.t('waitlist_history_clear_title'),
          style: TextStyle(color: ctx.appText),
        ),
        content: Text(
          translationService.t('waitlist_history_clear_body'),
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
            child: Text(translationService.t('waitlist_history_clear_confirm')),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await waitlistService.clearHistory();
    }
  }

  @override
  Widget build(BuildContext context) {
    final history = waitlistService.history;
    final seated = history
        .where((e) => e.status == WaitlistStatus.seated)
        .toList(growable: false);
    final cancelled = history
        .where((e) => e.status == WaitlistStatus.cancelled)
        .toList(growable: false);

    return Directionality(
      textDirection:
          translationService.isRTL ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: context.appBg,
        appBar: AppBar(
          backgroundColor: context.appHeaderBg,
          foregroundColor: context.appText,
          elevation: 0,
          title: Text(
            translationService.t('waitlist_history_title'),
            style: TextStyle(
              color: context.appText,
              fontWeight: FontWeight.w800,
            ),
          ),
          actions: [
            if (history.isNotEmpty)
              IconButton(
                tooltip: translationService.t('waitlist_history_clear_title'),
                onPressed: _confirmClearAll,
                icon: Icon(LucideIcons.trash2, color: context.appDanger),
              ),
          ],
          bottom: TabBar(
            controller: _tabController,
            labelColor: context.appPrimary,
            unselectedLabelColor: context.appTextMuted,
            indicatorColor: context.appPrimary,
            labelStyle: const TextStyle(fontWeight: FontWeight.w800),
            tabs: [
              Tab(
                text: translationService.t(
                  'waitlist_history_tab_seated',
                  args: {'count': '${seated.length}'},
                ),
              ),
              Tab(
                text: translationService.t(
                  'waitlist_history_tab_cancelled',
                  args: {'count': '${cancelled.length}'},
                ),
              ),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            _HistoryList(
              entries: seated,
              emptyKey: 'waitlist_history_empty_seated',
              icon: LucideIcons.checkCircle,
              accent: const Color(0xFF059669),
            ),
            _HistoryList(
              entries: cancelled,
              emptyKey: 'waitlist_history_empty_cancelled',
              icon: LucideIcons.xCircle,
              accent: const Color(0xFFDC2626),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryList extends StatelessWidget {
  final List<WaitlistEntry> entries;
  final String emptyKey;
  final IconData icon;
  final Color accent;

  const _HistoryList({
    required this.entries,
    required this.emptyKey,
    required this.icon,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: accent, size: 32),
              ),
              const SizedBox(height: 14),
              Text(
                translationService.t(emptyKey),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: context.appTextMuted,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      itemCount: entries.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _HistoryCard(entry: entries[i], accent: accent),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  final WaitlistEntry entry;
  final Color accent;

  const _HistoryCard({required this.entry, required this.accent});

  @override
  Widget build(BuildContext context) {
    final wait = _computeWaitDuration(entry);
    final finishedAt = entry.notifiedAt ?? entry.createdAt;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.appSurfaceAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.appBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _initial(entry.customerName),
                  style: TextStyle(
                    color: accent,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
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
                      entry.customerName,
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
                        Flexible(
                          child: Text(
                            _formatPhone(entry.phoneNumber),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: context.appTextMuted,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              _outcomePill(context),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _chip(
                context: context,
                icon: LucideIcons.users,
                label: translationService.t(
                  'waitlist_party_of',
                  args: {'count': '${entry.partySize}'},
                ),
              ),
              _chip(
                context: context,
                icon: LucideIcons.clock,
                label: translationService.t(
                  'waitlist_history_wait',
                  args: {'count': '$wait'},
                ),
              ),
              if (entry.assignedTableNumber != null)
                _chip(
                  context: context,
                  icon: LucideIcons.layoutGrid,
                  label: translationService.t(
                    'waitlist_notified_to',
                    args: {'table': entry.assignedTableNumber},
                  ),
                ),
              _chip(
                context: context,
                icon: LucideIcons.calendar,
                label: _formatDate(finishedAt),
              ),
            ],
          ),
          if ((entry.notes ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              entry.notes!,
              style: TextStyle(
                color: context.appTextMuted,
                fontSize: 11,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _outcomePill(BuildContext context) {
    final isSeated = entry.status == WaitlistStatus.seated;
    final label = translationService.t(
      isSeated ? 'waitlist_history_outcome_seated' : 'waitlist_history_outcome_cancelled',
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isSeated ? LucideIcons.checkCircle : LucideIcons.xCircle,
            size: 11,
            color: accent,
          ),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              color: accent,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip({
    required BuildContext context,
    required IconData icon,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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

  int _computeWaitDuration(WaitlistEntry e) {
    final from = e.createdAt;
    final to = e.notifiedAt ?? e.createdAt;
    final diff = to.difference(from);
    return diff.inMinutes < 0 ? 0 : diff.inMinutes;
  }

  String _initial(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    return trimmed.characters.first.toUpperCase();
  }

  String _formatPhone(String raw) {
    if (raw.isEmpty) return raw;
    final buf = StringBuffer('+');
    for (int i = 0; i < raw.length; i++) {
      if (i == 3 || i == 6) buf.write(' ');
      buf.write(raw[i]);
    }
    return buf.toString();
  }

  String _formatDate(DateTime dt) {
    final local = dt.toLocal();
    final now = DateTime.now();
    final sameDay = local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    if (sameDay) {
      return translationService.t(
        'waitlist_history_today_at',
        args: {'time': '$hh:$mm'},
      );
    }
    final y = local.year;
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }
}
