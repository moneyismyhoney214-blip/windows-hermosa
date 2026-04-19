import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../models/customer.dart';
import '../services/api/customer_service.dart';
import '../locator.dart';
import '../services/language_service.dart';
import '../services/app_themes.dart';

class CustomersScreen extends StatefulWidget {
  final VoidCallback onBack;

  const CustomersScreen({super.key, required this.onBack});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  final CustomerService _customerService = getIt<CustomerService>();

  List<Customer> _customers = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  String? _error;
  String _searchQuery = '';
  int _currentPage = 1;
  bool _hasMore = true;
  Timer? _searchDebounce;

  final ScrollController _scrollController = ScrollController();

  String _t(String key, {Map<String, dynamic>? args}) {
    return translationService.t(key, args: args);
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadCustomers();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoadingMore &&
        _hasMore) {
      _loadMoreCustomers();
    }
  }

  Future<void> _loadCustomers({bool refresh = false}) async {
    if (refresh) {
      _currentPage = 1;
      _customers = [];
      _hasMore = true;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final customers = await _customerService.getCustomers(
        page: _currentPage,
        search: _searchQuery.isEmpty ? null : _searchQuery,
      );

      if (mounted) {
        setState(() {
          if (refresh) {
            _customers = customers;
          } else {
            _customers.addAll(customers);
          }
          _isLoading = false;
          _hasMore = customers.length >= 10;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadMoreCustomers() async {
    if (_isLoadingMore) return;

    setState(() => _isLoadingMore = true);

    try {
      final nextPage = _currentPage + 1;
      final customers = await _customerService.getCustomers(
        page: nextPage,
        search: _searchQuery.isEmpty ? null : _searchQuery,
      );

      if (mounted) {
        setState(() {
          _customers.addAll(customers);
          _currentPage = nextPage;
          _isLoadingMore = false;
          _hasMore = customers.length >= 10;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  void _onSearch(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) {
        setState(() => _searchQuery = value);
        _loadCustomers(refresh: true);
      }
    });
  }

  Future<void> _addCustomer() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => const CustomerFormDialog(),
    );

    if (result == true) {
      _loadCustomers(refresh: true);
    }
  }

  Future<void> _editCustomer(Customer customer) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => CustomerFormDialog(customer: customer),
    );

    if (result == true) {
      _loadCustomers(refresh: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isCompact = width < 900;
    final isRTL = translationService.isRTL;
    final horizontalPadding = isCompact ? 12.0 : 24.0;
    final searchField = TextField(
      onChanged: _onSearch,
      decoration: InputDecoration(
        hintText: _t('customers_search_hint'),
        prefixIcon: const Icon(LucideIcons.search, size: 20),
        filled: true,
        fillColor: const Color(0xFFF1F5F9),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      ),
    );

    return Scaffold(
      backgroundColor: context.appBg,
      body: Directionality(
        textDirection: isRTL ? TextDirection.rtl : TextDirection.ltr,
        child: Column(
          children: [
            // Header
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: horizontalPadding,
                vertical: 12,
              ),
              color: context.appCardBg,
              child: isCompact
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            IconButton(
                              icon: Icon(
                                isRTL
                                    ? LucideIcons.chevronRight
                                    : LucideIcons.chevronLeft,
                              ),
                              onPressed: widget.onBack,
                            ),
                            Expanded(
                              child: Text(
                                _t('customers'),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 40),
                          ],
                        ),
                        const SizedBox(height: 8),
                        searchField,
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          onPressed: _addCustomer,
                          icon: const Icon(LucideIcons.plus, size: 18),
                          label: Text(_t('add_customer')),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFF58220),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        IconButton(
                          icon: Icon(
                            isRTL
                                ? LucideIcons.chevronRight
                                : LucideIcons.chevronLeft,
                          ),
                          onPressed: widget.onBack,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _t('customers'),
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        const Spacer(),
                        SizedBox(
                          width: 300,
                          child: searchField,
                        ),
                        const SizedBox(width: 16),
                        ElevatedButton.icon(
                          onPressed: _addCustomer,
                          icon: const Icon(LucideIcons.plus, size: 18),
                          label: Text(_t('add_customer')),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFF58220),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ],
                    ),
            ),

            // Content
            Expanded(
              child: _isLoading && _customers.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('${_t('error')}: $_error',
                                  style: const TextStyle(color: Colors.red)),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: () => _loadCustomers(refresh: true),
                                child: Text(_t('try_again')),
                              ),
                            ],
                          ),
                        )
                      : _customers.isEmpty
                          ? Center(child: Text(_t('no_customers')))
                          : ListView.separated(
                              controller: _scrollController,
                              padding: EdgeInsets.all(horizontalPadding),
                              itemCount:
                                  _customers.length + (_isLoadingMore ? 1 : 0),
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (context, index) {
                                if (index == _customers.length) {
                                  return const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 16),
                                    child: Center(
                                        child: CircularProgressIndicator()),
                                  );
                                }

                                final customer = _customers[index];
                                return _CustomerCard(
                                  customer: customer,
                                  onEdit: () => _editCustomer(customer),
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

class _CustomerCard extends StatelessWidget {
  final Customer customer;
  final VoidCallback onEdit;

  const _CustomerCard({required this.customer, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.sizeOf(context).width < 560;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.appCardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.appBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: const Color(0xFFFFF7ED),
                backgroundImage: customer.avatar != null
                    ? NetworkImage(customer.avatar!)
                    : null,
                child: customer.avatar == null
                    ? const Icon(LucideIcons.user, color: Color(0xFFC2410C))
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  customer.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              IconButton(
                icon: const Icon(LucideIcons.edit2,
                    size: 20, color: Color(0xFFF58220)),
                onPressed: onEdit,
              ),
            ],
          ),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              if (customer.mobile != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(LucideIcons.phone, size: 14, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(
                      customer.mobile!,
                      style: const TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                  ],
                ),
              if (customer.email != null)
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: isCompact ? 220 : 320),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(LucideIcons.mail,
                          size: 14, color: Colors.grey),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          customer.email!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              const TextStyle(color: Colors.grey, fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class CustomerFormDialog extends StatefulWidget {
  final Customer? customer;

  const CustomerFormDialog({super.key, this.customer});

  @override
  State<CustomerFormDialog> createState() => _CustomerFormDialogState();
}

class _CustomerFormDialogState extends State<CustomerFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _customerService = getIt<CustomerService>();

  late TextEditingController _nameController;
  late TextEditingController _mobileController;

  bool _isLoading = false;

  String _t(String key, {Map<String, dynamic>? args}) {
    return translationService.t(key, args: args);
  }

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.customer?.name);
    _mobileController = TextEditingController(text: widget.customer?.mobile);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _mobileController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final existingType = (widget.customer?.type ?? '').trim();
    final data = <String, String>{
      'name': _nameController.text,
      'mobile': _mobileController.text,
      'country_id': '1', // Default
      'city_id': '1', // Default
      'type': existingType.isNotEmpty ? existingType : 'individual',
    };

    try {
      if (widget.customer != null) {
        await _customerService.updateCustomer(widget.customer!.id, data);
      } else {
        await _customerService.createCustomer(data);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_t('error')}: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isCompact = size.width < 520;
    final dialogWidth =
        (size.width - (isCompact ? 24 : 48)).clamp(280.0, 420.0).toDouble();
    final maxHeight = (size.height * 0.85).clamp(420.0, 600.0).toDouble();

    return Dialog(
      insetPadding:
          EdgeInsets.symmetric(horizontal: isCompact ? 12 : 24, vertical: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: dialogWidth,
        constraints: BoxConstraints(maxHeight: maxHeight),
        padding: EdgeInsets.all(isCompact ? 16 : 24),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        widget.customer != null
                            ? _t('edit_customer_data')
                            : _t('add_new_customer'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: isCompact ? 18 : 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(LucideIcons.x),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _buildTextField(
                  controller: _nameController,
                  label: _t('customer_name'),
                  hint: _t('customer_name_hint'),
                  validator: (v) =>
                      v?.isEmpty == true ? _t('customer_name_required') : null,
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _mobileController,
                  label: _t('phone_number'),
                  hint: '05xxxxxxxx',
                  keyboardType: TextInputType.phone,
                  validator: (v) {
                    if (v?.isEmpty == true) return _t('phone_required');
                    return null;
                  },
                ),
                const SizedBox(height: 32),
                isCompact
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ElevatedButton(
                            onPressed: _isLoading ? null : _save,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFF58220),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                        color: Colors.white, strokeWidth: 2))
                                : Text(widget.customer != null
                                    ? _t('update_data')
                                    : _t('save_customer')),
                          ),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: Text(
                              _t('cancel'),
                              style: const TextStyle(color: Colors.grey),
                            ),
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : _save,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFF58220),
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                              child: _isLoading
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                          color: Colors.white, strokeWidth: 2))
                                  : Text(widget.customer != null
                                      ? _t('update_data')
                                      : _t('save_customer')),
                            ),
                          ),
                          const SizedBox(width: 12),
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 16, horizontal: 24),
                            ),
                            child: Text(
                              _t('cancel'),
                              style: const TextStyle(color: Colors.grey),
                            ),
                          ),
                        ],
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          validator: validator,
          keyboardType: keyboardType,
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFF58220)),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
      ],
    );
  }
}
