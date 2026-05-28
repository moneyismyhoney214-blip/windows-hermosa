import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../services/api/api_constants.dart';
import '../services/api/base_client.dart';
import '../services/app_themes.dart';
import '../services/language_service.dart';

/// Picks a single salon service from the branch catalog so the edit-order
/// dialog can hand it (along with the employee/date/time picker) to
/// [SalonServiceSelectionDialog].
///
/// Returns the raw service map shape produced by
/// `/seller/branches/{branchId}/bookings/create?type=services` — the same
/// shape [SalonServiceSelectionDialog] consumes:
///
/// ```json
/// {
///   "id": 1625,
///   "name": "مكياج وسط",
///   "image": "...",
///   "price": "250.00 ر.س",
///   "minutes": 75,
///   "minutes_format": "75 min",
///   "addons": [...],
///   "addons_groups": [...]
/// }
/// ```
class SalonServicePickerDialog extends StatefulWidget {
  const SalonServicePickerDialog({super.key});

  static Future<Map<String, dynamic>?> show(BuildContext context) {
    return showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const SalonServicePickerDialog(),
    );
  }

  @override
  State<SalonServicePickerDialog> createState() =>
      _SalonServicePickerDialogState();
}

class _SalonServicePickerDialogState extends State<SalonServicePickerDialog> {
  static const _brand = Color(0xFFF58220);
  static const _brandLight = Color(0xFFFFF7ED);

  final BaseClient _client = BaseClient();
  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  Timer? _searchDebounce;

  List<Map<String, dynamic>> _categories = [];
  String? _selectedCategoryId;
  final List<Map<String, dynamic>> _services = [];
  bool _loadingCategories = true;
  bool _loadingServices = true;
  bool _loadingMore = false;
  int _currentPage = 1;
  int _lastPage = 1;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _loadServices(reset: true);
    _scrollCtrl.addListener(() {
      if (_scrollCtrl.position.pixels >=
              _scrollCtrl.position.maxScrollExtent - 200 &&
          !_loadingMore &&
          _currentPage < _lastPage) {
        _loadMore();
      }
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    try {
      final resp = await _client.get(
        '/seller/filters/resource/branches/${ApiConstants.branchId}/categories?scope=types&type=services&all=false',
      );
      final data = (resp is Map ? resp['data'] : resp);
      if (data is List && mounted) {
        setState(() {
          _categories = data
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          _loadingCategories = false;
        });
      } else if (mounted) {
        setState(() => _loadingCategories = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loadingCategories = false);
    }
  }

  Future<void> _loadServices({bool reset = false}) async {
    if (reset) {
      setState(() {
        _services.clear();
        _currentPage = 1;
        _lastPage = 1;
        _loadingServices = true;
      });
    }
    try {
      final params = <String, String>{
        'type': 'services',
        'is_favourite': '0',
        'is_home': '0',
        'is_delivery': '0',
        'page': _currentPage.toString(),
        'per_page': '24',
        'search': _search,
      };
      if (_selectedCategoryId != null && _selectedCategoryId != 'all') {
        params['category_id'] = _selectedCategoryId!;
      }
      final query = params.entries
          .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
          .join('&');
      final resp = await _client.get(
        '/seller/branches/${ApiConstants.branchId}/bookings/create?$query',
      );

      // Response shape: { data: { collection: { data: [...], current_page, last_page } } }
      List<Map<String, dynamic>> items = const [];
      int lastPage = 1;
      int currentPage = _currentPage;
      if (resp is Map) {
        final data = resp['data'] is Map ? resp['data'] as Map : resp;
        final collection = data['collection'];
        if (collection is Map) {
          lastPage = (collection['last_page'] as num?)?.toInt() ?? 1;
          currentPage =
              (collection['current_page'] as num?)?.toInt() ?? _currentPage;
          final inner = collection['data'];
          if (inner is List) {
            items = inner
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
          }
        } else if (data['services'] is List) {
          items = (data['services'] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      }

      if (!mounted) return;
      setState(() {
        if (reset) _services.clear();
        _services.addAll(items);
        _currentPage = currentPage;
        _lastPage = lastPage;
        _loadingServices = false;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingServices = false;
          _loadingMore = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _currentPage >= _lastPage) return;
    setState(() {
      _loadingMore = true;
      _currentPage += 1;
    });
    await _loadServices();
  }

  void _onCategoryTap(String? id) {
    if (_selectedCategoryId == id) return;
    setState(() => _selectedCategoryId = id);
    _loadServices(reset: true);
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      _search = value.trim();
      _loadServices(reset: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final width = size.width.clamp(360.0, 720.0).toDouble();
    final height = (size.height * 0.85).clamp(420.0, 860.0).toDouble();

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: width,
        height: height,
        child: Column(
          children: [
            _buildHeader(),
            _buildSearch(),
            _buildCategories(),
            const Divider(height: 1),
            Expanded(child: _buildList()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_brand, Color(0xFFEA580C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          const Icon(LucideIcons.scissors, color: Colors.white, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              translationService.t('choose_service'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildSearch() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: TextField(
        controller: _searchCtrl,
        onChanged: _onSearchChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: translationService.t('search_service'),
          prefixIcon: const Icon(LucideIcons.search, size: 18),
          isDense: true,
          filled: true,
          fillColor: const Color(0xFFF8FAFC),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
            borderSide: const BorderSide(color: _brand, width: 1.5),
          ),
        ),
      ),
    );
  }

  Widget _buildCategories() {
    if (_loadingCategories) {
      return const SizedBox(
        height: 48,
        child: Center(
            child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          _buildCategoryChip(null, translationService.t('all')),
          for (final cat in _categories)
            _buildCategoryChip(
              cat['id']?.toString(),
              cat['name']?.toString() ?? '',
            ),
        ],
      ),
    );
  }

  Widget _buildCategoryChip(String? id, String label) {
    final isSelected = _selectedCategoryId == id;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: ChoiceChip(
        label: Text(label,
            style: TextStyle(
                color: isSelected ? Colors.white : const Color(0xFF334155),
                fontWeight: FontWeight.w600,
                fontSize: 12.5)),
        selected: isSelected,
        onSelected: (_) => _onCategoryTap(id),
        backgroundColor: _brandLight,
        selectedColor: _brand,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
                color: isSelected ? _brand : const Color(0xFFFCD9B6))),
      ),
    );
  }

  Widget _buildList() {
    if (_loadingServices && _services.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: _brand));
    }
    if (_services.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.scissors,
                size: 40, color: Colors.grey.shade400),
            const SizedBox(height: 8),
            Text(
              translationService.t('no_services'),
              style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
            ),
          ],
        ),
      );
    }
    return ListView.separated(
      controller: _scrollCtrl,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      itemCount: _services.length + (_loadingMore ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        if (i >= _services.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
                child: SizedBox(
                    width: 22,
                    height: 22,
                    child:
                        CircularProgressIndicator(strokeWidth: 2.4, color: _brand))),
          );
        }
        return _buildServiceTile(_services[i]);
      },
    );
  }

  Widget _buildServiceTile(Map<String, dynamic> service) {
    final name = (service['name'] ?? '').toString();
    final priceText = service['price']?.toString() ?? '';
    final minutes = service['minutes_format']?.toString() ?? '';
    return Material(
      color: context.appCardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.pop(context, service),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                    color: _brandLight,
                    borderRadius: BorderRadius.circular(10)),
                alignment: Alignment.center,
                child:
                    const Icon(LucideIcons.scissors, color: _brand, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: context.appText)),
                    if (minutes.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(minutes,
                          style: TextStyle(
                              fontSize: 11.5,
                              color: Colors.grey.shade500)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(priceText,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _brand)),
            ],
          ),
        ),
      ),
    );
  }
}
