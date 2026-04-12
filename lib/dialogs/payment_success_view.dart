import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../services/api/api_constants.dart';
import '../services/language_service.dart';

class PaymentSuccessView extends StatelessWidget {
  final double amount;
  final String orderId;
  final String type;
  final bool showInvoiceButton;
  final VoidCallback onNewOrder;
  final VoidCallback onPrint;
  final VoidCallback? onGoToOrders;

  const PaymentSuccessView({
    super.key,
    required this.amount,
    required this.orderId,
    required this.type,
    this.showInvoiceButton = true,
    required this.onNewOrder,
    required this.onPrint,
    this.onGoToOrders,
  });

  @override
  Widget build(BuildContext context) {
    final isPayment = type == 'payment';
    final color = isPayment ? Colors.green : Colors.orange;

    return Scaffold(
      backgroundColor:
          Colors.transparent, // Handled by dialog barrier, but safe here
      body: Container(
        color: const Color(0xFFF8FAFC),
        width: double.infinity,
        height: double.infinity,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: Container(
                padding: const EdgeInsets.all(40),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(32),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 20)
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                          color: color[50], shape: BoxShape.circle),
                      child: Icon(
                          isPayment
                              ? LucideIcons.checkCircle
                              : LucideIcons.clock,
                          size: 48,
                          color: color),
                    ),
                    const SizedBox(height: 24),
                    Text(
                        isPayment
                            ? translationService.t('payment_success')
                            : translationService.t('order_saved_success'),
                        style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E293B))),
                    const SizedBox(height: 8),
                    Text(
                        isPayment
                            ? translationService.t('transaction_recorded')
                            : translationService.t('order_sent_to_kitchen'),
                        style: const TextStyle(
                            fontSize: 16, color: Color(0xFF64748B))),
                    const SizedBox(height: 32),

                    // Details Card
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFE2E8F0))),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(translationService.t('order_number'),
                                  style: const TextStyle(
                                      color: Color(0xFF64748B))),
                              Text(orderId,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18)),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(translationService.t('total_amount'),
                                  style: const TextStyle(
                                      color: Color(0xFF64748B))),
                              Text(
                                  '${amount.toStringAsFixed(2)} ${ApiConstants.currency}',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 24,
                                      color: color)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Buttons
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton.icon(
                        onPressed: onNewOrder,
                        icon: const Icon(LucideIcons.arrowRight),
                        label: Text(translationService.t('new_order'),
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFF58220),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12))),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // For Pay Later orders, show "Go to Orders" button
                    // For Payment orders, show "View Invoice" button
                    if (!isPayment && onGoToOrders != null)
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: OutlinedButton.icon(
                          onPressed: onGoToOrders,
                          icon: const Icon(LucideIcons.list),
                          label: Text(translationService.t('orders'),
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold)),
                          style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF64748B),
                              side: const BorderSide(
                                  color: Color(0xFFE2E8F0), width: 2),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12))),
                        ),
                      )
                    else if (showInvoiceButton)
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: OutlinedButton.icon(
                          onPressed: onPrint,
                          icon: const Icon(LucideIcons.eye),
                          label: Text(translationService.t('view_invoice'),
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold)),
                          style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF64748B),
                              side: const BorderSide(
                                  color: Color(0xFFE2E8F0), width: 2),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12))),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
