part of '../reports_screen.dart';

// Card / statistics-grid builders + pure helpers extracted from
// reports_screen.dart. Methods stay instance members on
// `_ReportsScreenState` via the extension, so callers (`build`, the tab
// builders) keep their existing invocation syntax.

extension _ReportsScreenCards on _ReportsScreenState {
  Widget _buildStatisticsCards(BuildContext context, Map<String, dynamic> statistics) {
    final cards = <Widget>[];

    // Map of payment methods to their display info
    final paymentMethodsInfo = {
      'cash': {
        'label': translationService.t('cash_payment'),
        'icon': LucideIcons.banknote,
        'color': const Color(0xFF10B981),
        'bgColor': const Color(0xFFECFDF5),
      },
      'card': {
        'label': translationService.t('card_payment'),
        'icon': LucideIcons.creditCard,
        'color': const Color(0xFF3B82F6),
        'bgColor': const Color(0xFFEFF6FF),
      },
      'benefit': {
        'label': translationService.t('benefit_pay'),
        'icon': LucideIcons.smartphone,
        'color': const Color(0xFF8B5CF6),
        'bgColor': const Color(0xFFF3E8FF),
      },
      'stc': {
        'label': translationService.t('stc_pay'),
        'icon': LucideIcons.wallet,
        'color': const Color(0xFFF59E0B),
        'bgColor': const Color(0xFFFEF3C7),
      },
      'bank_transfer': {
        'label': translationService.t('bank_transfer'),
        'icon': LucideIcons.send,
        'color': const Color(0xFF0EA5E9),
        'bgColor': const Color(0xFFE0F2FE),
      },
      'wallet': {
        'label': translationService.t('wallet'),
        'icon': LucideIcons.wallet,
        'color': const Color(0xFF14B8A6),
        'bgColor': const Color(0xFFCCFBF1),
      },
      'cheque': {
        'label': translationService.t('cheque'),
        'icon': LucideIcons.fileCheck,
        'color': const Color(0xFF92400E),
        'bgColor': const Color(0xFFFEF3C7),
      },
      'petty_cash': {
        'label': translationService.t('petty_cash'),
        'icon': LucideIcons.banknote,
        'color': const Color(0xFF0F766E),
        'bgColor': const Color(0xFFCCFBF1),
      },
      'pay_later': {
        'label': translationService.t('pay_later'),
        'icon': LucideIcons.clock,
        'color': const Color(0xFF6366F1),
        'bgColor': const Color(0xFFE0E7FF),
      },
      'tabby': {
        'label': translationService.t('tabby'),
        'icon': LucideIcons.creditCard,
        'color': context.appTextMuted,
        'bgColor': context.appSurfaceAlt,
      },
      'tamara': {
        'label': translationService.t('tamara'),
        'icon': LucideIcons.creditCard,
        'color': const Color(0xFF7C3AED),
        'bgColor': const Color(0xFFF3E8FF),
      },
      'keeta': {
        'label': translationService.t('keeta'),
        'icon': LucideIcons.truck,
        'color': const Color(0xFFF97316),
        'bgColor': const Color(0xFFFEE2E2),
      },
      'kita': {
        'label': translationService.t('keeta'),
        'icon': LucideIcons.truck,
        'color': const Color(0xFFF97316),
        'bgColor': const Color(0xFFFEE2E2),
      },
      'my_fatoorah': {
        'label': translationService.t('my_fatoorah'),
        'icon': LucideIcons.wallet,
        'color': const Color(0xFF06B6D4),
        'bgColor': const Color(0xFFCFFAFE),
      },
      'jahez': {
        'label': translationService.t('jahez'),
        'icon': LucideIcons.truck,
        'color': const Color(0xFF16A34A),
        'bgColor': const Color(0xFFDCFCE7),
      },
      'gahez': {
        'label': translationService.t('jahez'),
        'icon': LucideIcons.truck,
        'color': const Color(0xFF16A34A),
        'bgColor': const Color(0xFFDCFCE7),
      },
      'talabat': {
        'label': translationService.t('talabat'),
        'icon': LucideIcons.shoppingBag,
        'color': const Color(0xFFDC2626),
        'bgColor': const Color(0xFFFEE2E2),
      },
      'hunger_station': {
        'label': translationService.t('hunger_station'),
        'icon': LucideIcons.truck,
        'color': const Color(0xFFEA580C),
        'bgColor': context.isDark
            ? const Color(0xFFF58220).withValues(alpha: 0.15)
            : const Color(0xFFFFF7ED),
      },
      'hungerstation': {
        'label': translationService.t('hunger_station'),
        'icon': LucideIcons.truck,
        'color': const Color(0xFFEA580C),
        'bgColor': context.isDark
            ? const Color(0xFFF58220).withValues(alpha: 0.15)
            : const Color(0xFFFFF7ED),
      },
      'total': {
        'label': translationService.t('total_amount'),
        'icon': LucideIcons.trendingUp,
        'color': const Color(0xFFF58220),
        'bgColor': context.isDark
            ? const Color(0xFFF58220).withValues(alpha: 0.15)
            : const Color(0xFFFFF7ED),
      },
    };

    statistics.forEach((key, value) {
      final info = paymentMethodsInfo[key] ?? {
        'label': key,
        'icon': LucideIcons.dollarSign,
        'color': context.appTextMuted,
        'bgColor': context.appSurfaceAlt,
      };

      cards.add(
        _buildSummaryCard(
          title: info['label'] as String,
          value: _parseDouble(value),
          icon: info['icon'] as IconData,
          color: info['color'] as Color,
          bgColor: info['bgColor'] as Color,
        ),
      );
    });

    // Responsive grid — 3 columns on wide tablets, otherwise 2.
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth >= 760 ? 3 : 2;
        const gap = 12.0;
        final rows = <Widget>[];
        for (var i = 0; i < cards.length; i += cols) {
          final rowChildren = <Widget>[];
          for (var j = 0; j < cols; j++) {
            if (j > 0) rowChildren.add(const SizedBox(width: gap));
            final idx = i + j;
            rowChildren.add(Expanded(
              child: idx < cards.length ? cards[idx] : const SizedBox(),
            ));
          }
          rows.add(Row(children: rowChildren));
          if (i + cols < cards.length) rows.add(const SizedBox(height: gap));
        }
        return Column(children: rows);
      },
    );
  }

  double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  String _formatDate(DateTime date) {
    return DateFormat('yyyy/MM/dd', 'ar').format(date);
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: _ReportsScreenState._accent.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(LucideIcons.fileBarChart,
                  size: 44, color: _ReportsScreenState._accent),
            ),
            const SizedBox(height: 20),
            Text(
              translationService.t('no_data_available'),
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: context.appText,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              translationService.t('select_period_to_view_reports'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: context.appTextMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard({
    required String title,
    required double value,
    required IconData icon,
    required Color color,
    required Color bgColor,
    bool isNegative = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.appCardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.appBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: context.appTextMuted, fontSize: 12.5),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              '${_formatter.format(value)} ${ApiConstants.currency}',
              style: TextStyle(
                color: isNegative ? Colors.red : context.appText,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
