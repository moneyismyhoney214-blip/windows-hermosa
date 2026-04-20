import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../locator.dart';
import '../../models.dart';
import '../../services/api/table_service.dart';
import '../../services/app_themes.dart';
import '../../services/language_service.dart';
import '../services/waiter_controller.dart';
import '../services/waiter_table_registry.dart';
import '../theme/waiter_design.dart';
import '../widgets/skeleton_grid.dart';
import '../widgets/waiter_table_card.dart';
import 'waiter_order_screen.dart';

/// Grid view of every table in the branch, with ownership and status
/// overlaid from the live [WaiterTableRegistry].
class WaiterTablesScreen extends StatefulWidget {
  final WaiterController controller;

  const WaiterTablesScreen({super.key, required this.controller});

  @override
  State<WaiterTablesScreen> createState() => _WaiterTablesScreenState();
}

class _WaiterTablesScreenState extends State<WaiterTablesScreen> {
  final TableService _tableService = getIt<TableService>();
  final WaiterTableRegistry _registry = getIt<WaiterTableRegistry>();

  List<TableItem> _tables = const [];
  bool _loading = true;
  Object? _error;
  StreamSubscription<WaiterTableEventEnvelope>? _eventSub;

  @override
  void initState() {
    super.initState();
    _load();
    _registry.addListener(_onRegistry);
    _eventSub = widget.controller.onTableEvent
        .listen((env) => _registry.apply(env.event));
  }

  @override
  void dispose() {
    _registry.removeListener(_onRegistry);
    _eventSub?.cancel();
    super.dispose();
  }

  void _onRegistry() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final tables = await _tableService.getTables();
      if (!mounted) return;
      setState(() {
        _tables = tables
            .where((t) => t.isActive)
            .toList()
          ..sort((a, b) {
            final aNum = int.tryParse(a.number) ?? 0;
            final bNum = int.tryParse(b.number) ?? 0;
            return aNum.compareTo(bNum);
          });
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _openTable(TableItem table) {
    final me = widget.controller.session.self;
    if (me == null) return;

    final ownerId = _registry.ownerIdFor(table.id);
    if (ownerId != null && ownerId != me.id) {
      _showBorrowDialog(table, ownerId);
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WaiterOrderScreen(
          table: table,
          controller: widget.controller,
        ),
      ),
    );
  }

  void _showBorrowDialog(TableItem table, String ownerId) {
    // Waiter-to-waiter calls are disabled — only the cashier rings the
    // bell. We still show an info dialog so the tapping waiter knows
    // the table is taken instead of letting them silently overwrite.
    final owner = widget.controller.roster.byId(ownerId);
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: context.appSurface,
        title: Text(translationService.t('waiter_table_owned_title')),
        content: Text(
          translationService.t(
            'waiter_table_owned_body',
            args: {
              'table': table.number,
              'name': owner?.name ?? '—',
            },
          ),
        ),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: context.appPrimary),
            onPressed: () => Navigator.of(context).pop(),
            child: Text(translationService.t('waiter_close')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SkeletonTablesGrid();
    }
    if (_error != null) {
      return _ErrorView(onRetry: _load, error: _error!);
    }
    if (_tables.isEmpty) {
      return _EmptyView(onRefresh: _load);
    }
    return RefreshIndicator(
      color: context.appPrimary,
      onRefresh: _load,
      child: LayoutBuilder(builder: (_, constraints) {
        // Pick card size based on viewport:
        //   phone (<420)  → 1 column
        //   tablet / split → 2 columns
        //   larger → auto-fit cards of ~220 wide
        final w = constraints.maxWidth;
        final maxExtent = w < 420 ? w : 220.0;
        return GridView.builder(
          padding: const EdgeInsets.all(WaiterSpacing.md),
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: maxExtent,
            mainAxisSpacing: WaiterSpacing.sm + 2,
            crossAxisSpacing: WaiterSpacing.sm + 2,
            childAspectRatio: 1.35,
          ),
          itemCount: _tables.length,
          itemBuilder: (_, i) {
            final t = _tables[i];
            final ownerId = _registry.ownerIdFor(t.id);
            final ownerName = _registry.ownerNameFor(t.id) ??
                (ownerId != null
                    ? widget.controller.roster.byId(ownerId)?.name
                    : null);
            // Mirror the registry's ownership onto the TableItem's status so
            // the card colors match even before the backend reflects it.
            final overlaid = t
              ..status = ownerId != null
                  ? TableStatus.occupied
                  : (t.status == TableStatus.printed
                      ? TableStatus.printed
                      : TableStatus.available)
              ..waiterName = ownerName ?? t.waiterName;
            return WaiterTableCard(
              table: overlaid,
              currentWaiterId: widget.controller.session.self!.id,
              ownerWaiterId: ownerId,
              ownerWaiterName: ownerName,
              guestCount: _registry.guestCountFor(t.id),
              onTap: () => _openTable(t),
            );
          },
        );
      }),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final VoidCallback onRetry;
  final Object error;
  const _ErrorView({required this.onRetry, required this.error});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.alertCircle,
              size: 42, color: context.appDanger),
          const SizedBox(height: 8),
          Text(translationService.t('waiter_tables_load_failed'),
              style: TextStyle(color: context.appText)),
          const SizedBox(height: 4),
          Text('$error',
              style: TextStyle(color: context.appTextMuted, fontSize: 12)),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(LucideIcons.rotateCcw),
            label: Text(translationService.t('waiter_retry')),
          ),
        ],
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  final VoidCallback onRefresh;
  const _EmptyView({required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.armchair,
              size: 42, color: context.appTextMuted),
          const SizedBox(height: 8),
          Text(translationService.t('waiter_tables_empty'),
              style: TextStyle(color: context.appText)),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRefresh,
            icon: const Icon(LucideIcons.rotateCcw),
            label: Text(translationService.t('waiter_retry')),
          ),
        ],
      ),
    );
  }
}
