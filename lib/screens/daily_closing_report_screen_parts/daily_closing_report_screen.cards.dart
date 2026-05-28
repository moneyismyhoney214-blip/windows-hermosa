part of '../daily_closing_report_screen.dart';

// Card-building widgets + small pure helpers extracted from
// daily_closing_report_screen.dart. Stays a `part of` so the methods remain
// instance methods on `_DailyClosingReportScreenState` (via extension) with
// the same private visibility they had inline.

extension _DailyClosingReportScreenCards on _DailyClosingReportScreenState {
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            translationService.t('no_data_available'),
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey.shade600,
            ),
          ),
        ],
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
    final formatter = NumberFormat('#,##0.00', 'ar');

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDecoration(),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${formatter.format(value)} ${ApiConstants.currency}',
                  style: TextStyle(
                    color: isNegative ? Colors.red : Colors.black87,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required Color bgColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDecoration(),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.black87,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBranchInfo(Map<String, dynamic> report) {
    final branchName = report['branch_name']?.toString() ?? '-';
    final cashierName = report['cashier_name']?.toString() ?? '-';
    final dateRange = report['date_range']?.toString() ?? '-';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            translationService.t('report_info'),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          _buildInfoRow(translationService.t('branch'), branchName, LucideIcons.building),
          const SizedBox(height: 12),
          _buildInfoRow(translationService.t('cashier'), cashierName, LucideIcons.user),
          const SizedBox(height: 12),
          _buildInfoRow(translationService.t('period'), dateRange, LucideIcons.calendar),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 20, color: const Color(0xFFF58220)),
        const SizedBox(width: 12),
        Text(
          '$label: ',
          style: TextStyle(
            color: Colors.grey.shade600,
            fontWeight: FontWeight.w500,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.05),
          blurRadius: 10,
          offset: const Offset(0, 2),
        ),
      ],
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
}
