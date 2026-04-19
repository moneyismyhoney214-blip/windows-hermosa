import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../models/customer.dart';
import '../services/api/customer_service.dart';
import '../locator.dart';
import '../screens/customers_screen.dart'; // To reuse CustomerFormDialog
import '../services/language_service.dart';

class CustomerSelectionDialog extends StatefulWidget {
  const CustomerSelectionDialog({super.key});

  @override
  State<CustomerSelectionDialog> createState() =>
      _CustomerSelectionDialogState();
}

class _CustomerSelectionDialogState extends State<CustomerSelectionDialog> {
  final CustomerService _customerService = getIt<CustomerService>();
  final TextEditingController _searchController = TextEditingController();

  List<Customer> _customers = [];
  bool _isLoading = false;
  String _searchQuery = '';
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  Future<void> _loadCustomers() async {
    setState(() => _isLoading = true);
    try {
      final customers = await _customerService.getCustomers(
        search: _searchQuery.isEmpty ? null : _searchQuery,
      );
      if (mounted) {
        setState(() {
          _customers = customers;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(translationService.t('error_loading_customers', args: {'error': e.toString()}))),
        );
      }
    }
  }

  void _onSearch(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) {
        setState(() => _searchQuery = value);
        _loadCustomers();
      }
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _addNewCustomer() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => const CustomerFormDialog(),
    );

    if (result == true) {
      _loadCustomers();
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isCompact = size.width < 620;
    final insetPadding = EdgeInsets.symmetric(
      horizontal: isCompact ? 12 : 24,
      vertical: isCompact ? 16 : 24,
    );
    final dialogWidth =
        (size.width - insetPadding.horizontal).clamp(280.0, 560.0).toDouble();
    final dialogHeight =
        (size.height - insetPadding.vertical).clamp(420.0, 700.0).toDouble();

    return Dialog(
      insetPadding: insetPadding,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: dialogWidth,
        height: dialogHeight,
        padding: EdgeInsets.all(isCompact ? 14 : 24),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Text(
                    'اختيار عميل',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(LucideIcons.x),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: _onSearch,
                    decoration: InputDecoration(
                      hintText: translationService.t('customer_search_dialog_hint'),
                      prefixIcon: const Icon(LucideIcons.search, size: 18),
                      filled: true,
                      fillColor: const Color(0xFFF1F5F9),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 16),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _addNewCustomer,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF58220),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.all(12),
                  ),
                  child: const Icon(LucideIcons.plus),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _customers.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(LucideIcons.userX,
                                  size: 48, color: Colors.grey),
                              const SizedBox(height: 16),
                              const Text('لا يوجد نتائج لهذا البحث',
                                  style: TextStyle(color: Colors.grey)),
                              const SizedBox(height: 16),
                              ElevatedButton.icon(
                                onPressed: _addNewCustomer,
                                icon: const Icon(LucideIcons.plus, size: 18),
                                label: Text(translationService.t('add_new_customer')),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFF58220),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          itemCount: _customers.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final customer = _customers[index];
                            return ListTile(
                              onTap: () => Navigator.pop(context, customer),
                              leading: CircleAvatar(
                                backgroundColor: const Color(0xFFFFF7ED),
                                child: const Icon(LucideIcons.user,
                                    color: Color(0xFFC2410C), size: 20),
                              ),
                              title: Text(customer.name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                              subtitle: customer.mobile != null
                                  ? Text(customer.mobile!)
                                  : null,
                              trailing:
                                  const Icon(LucideIcons.chevronLeft, size: 16),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
