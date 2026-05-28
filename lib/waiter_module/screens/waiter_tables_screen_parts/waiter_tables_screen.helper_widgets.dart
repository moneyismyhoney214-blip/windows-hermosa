part of '../waiter_tables_screen.dart';

// Helper widgets + the _TableSection group struct extracted from the tail
// of waiter_tables_screen.dart. All identifiers stay library-private so the
// host screen is the only legal caller.

class _TableSection {
  final String key;
  final String title;
  final List<TableItem> tables;
  _TableSection({
    required this.key,
    required this.title,
    required this.tables,
  });
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

/// Grid picker shown to the waiter so they can choose which empty table
/// to relocate the current party to.
class _WaiterMigrateDestinationDialog extends StatelessWidget {
  final TableItem source;
  final List<TableItem> destinations;

  const _WaiterMigrateDestinationDialog({
    required this.source,
    required this.destinations,
  });

  @override
  Widget build(BuildContext context) {
    final sorted = [...destinations]
      ..sort((a, b) {
        final an = int.tryParse(a.number) ?? 0;
        final bn = int.tryParse(b.number) ?? 0;
        return an.compareTo(bn);
      });
    return AlertDialog(
      backgroundColor: context.appSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(LucideIcons.moveRight, color: Color(0xFF2563EB)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'نقل الطاولة ${source.number} إلى...',
              style: TextStyle(color: context.appText, fontSize: 17),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 380,
        height: 320,
        child: GridView.builder(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 120,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.1,
          ),
          itemCount: sorted.length,
          itemBuilder: (_, i) {
            final t = sorted[i];
            return InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => Navigator.of(context).pop(t),
              child: Ink(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.appBorder),
                  color: context.appSurfaceAlt,
                ),
                padding: const EdgeInsets.all(10),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(LucideIcons.armchair,
                        color: context.appSuccess, size: 26),
                    const SizedBox(height: 6),
                    Text(
                      t.number,
                      style: TextStyle(
                        color: context.appText,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${t.seats} أشخاص',
                      style: TextStyle(
                        color: context.appTextMuted,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(translationService.t('waiter_cancel')),
        ),
      ],
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
