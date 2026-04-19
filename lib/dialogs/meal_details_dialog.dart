import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../models.dart';
import '../services/api/api_constants.dart';
import '../services/api/product_service.dart';
import '../services/language_service.dart';
import '../locator.dart';
import '../services/app_themes.dart';

class MealDetailsDialog extends StatefulWidget {
  final Product product;

  const MealDetailsDialog({super.key, required this.product});

  @override
  State<MealDetailsDialog> createState() => _MealDetailsDialogState();
}

class _MealDetailsDialogState extends State<MealDetailsDialog> {
  bool _isLoading = true;
  Map<String, dynamic>? _mealDetails;
  String? _error;

  String _t(String key, {Map<String, dynamic>? args}) {
    return translationService.t(key, args: args);
  }

  @override
  void initState() {
    super.initState();
    _loadMealDetails();
  }

  Future<void> _loadMealDetails() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final productService = getIt<ProductService>();
      final details = await productService.getMealForEdit(widget.product.id);

      if (mounted) {
        setState(() {
          _mealDetails = details;
          _isLoading = false;
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

  String _resolveMealDescription() {
    final data = _mealDetails?['data'];
    if (data is Map) {
      final meal = data['meal'];
      if (meal is Map) {
        final descriptions = meal['descriptions'];
        if (descriptions is Map) {
          final currentLang =
              translationService.currentLanguageCode.trim().toLowerCase();
          final preferredCodes = <String>[
            currentLang,
            if (currentLang != 'en') 'en',
            if (currentLang != 'ar') 'ar',
          ];

          for (final code in preferredCodes) {
            final text = descriptions[code]?.toString().trim();
            if (text != null && text.isNotEmpty) return text;
          }
          for (final value in descriptions.values) {
            final text = value?.toString().trim();
            if (text != null && text.isNotEmpty) return text;
          }
        }
        final direct = meal['description']?.toString().trim();
        if (direct != null && direct.isNotEmpty) return direct;
      }
    }
    return _t('meal_description_unavailable');
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
        (size.height - insetPadding.vertical).clamp(460.0, 700.0).toDouble();

    return Dialog(
      insetPadding: insetPadding,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Column(
          children: [
            // Header
            Container(
              padding: EdgeInsets.all(isCompact ? 14 : 20),
              decoration: const BoxDecoration(
                color: Color(0xFFF58220),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.product.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_t('price')}: ${widget.product.price.toStringAsFixed(2)} ${ApiConstants.currency}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(LucideIcons.x, color: Colors.white),
                  ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                LucideIcons.alertCircle,
                                size: 48,
                                color: Colors.red,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                '${_t('error')}: $_error',
                                style: const TextStyle(color: Colors.red),
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: _loadMealDetails,
                                child: Text(_t('try_again')),
                              ),
                            ],
                          ),
                        )
                      : SingleChildScrollView(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Product Image
                              if (widget.product.image != null)
                                Center(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(16),
                                    child: CachedNetworkImage(
                                      imageUrl: widget.product.image!,
                                      height: isCompact ? 170 : 200,
                                      width: double.infinity,
                                      fit: BoxFit.cover,
                                      memCacheWidth: 500,
                                      fadeInDuration:
                                          const Duration(milliseconds: 120),
                                      placeholder: (context, url) => Container(
                                        height: isCompact ? 170 : 200,
                                        decoration: BoxDecoration(
                                          color: context.appBg,
                                          borderRadius:
                                              BorderRadius.circular(16),
                                        ),
                                      ),
                                      errorWidget:
                                          (context, error, stackTrace) =>
                                              Container(
                                        height: isCompact ? 170 : 200,
                                        decoration: BoxDecoration(
                                          color: context.appBg,
                                          borderRadius:
                                              BorderRadius.circular(16),
                                        ),
                                        child: const Icon(
                                          LucideIcons.image,
                                          size: 64,
                                          color: Color(0xFFCBD5E1),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),

                              const SizedBox(height: 20),

                              // Category
                              _buildInfoRow(
                                LucideIcons.tag,
                                _t('category_label'),
                                widget.product.category,
                              ),

                              const SizedBox(height: 12),

                              _buildInfoRow(
                                LucideIcons.fileText,
                                _t('meal_description_label'),
                                _resolveMealDescription(),
                              ),

                              const SizedBox(height: 12),

                              // Status
                              _buildInfoRow(
                                LucideIcons.activity,
                                _t('status'),
                                widget.product.isActive
                                    ? _t('available')
                                    : _t('not_available'),
                                valueColor: widget.product.isActive
                                    ? Colors.green
                                    : Colors.red,
                              ),

                              const SizedBox(height: 12),

                              // Product ID
                              _buildInfoRow(
                                LucideIcons.hash,
                                _t('product_id'),
                                widget.product.id.toString(),
                              ),

                              const SizedBox(height: 24),

                              // Extras/Add-ons Section
                              if (widget.product.extras.isNotEmpty) ...[
                                Text(
                                  _t('available_extras'),
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1E293B),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Container(
                                  decoration: BoxDecoration(
                                    color: context.appBg,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: context.appBorder,
                                    ),
                                  ),
                                  child: ListView.separated(
                                    shrinkWrap: true,
                                    physics:
                                        const NeverScrollableScrollPhysics(),
                                    itemCount: widget.product.extras.length,
                                    separatorBuilder: (_, __) => const Divider(
                                      height: 1,
                                      indent: 16,
                                      endIndent: 16,
                                    ),
                                    itemBuilder: (context, index) {
                                      final extra =
                                          widget.product.extras[index];
                                      return Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(8),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFFFF7ED),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: const Icon(
                                                LucideIcons.plus,
                                                size: 16,
                                                color: Color(0xFFF58220),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Text(
                                                extra.name,
                                                style: const TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                            Text(
                                              '+${extra.price.toStringAsFixed(2)} ${ApiConstants.currency}',
                                              style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.bold,
                                                color: Color(0xFFF58220),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],

                              if (widget.product.extras.isEmpty)
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: context.appBg,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        LucideIcons.info,
                                        size: 20,
                                        color: Colors.grey[600],
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        _t('no_product_extras'),
                                        style: TextStyle(
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
            ),

            // Footer
            Container(
              padding: EdgeInsets.all(isCompact ? 14 : 20),
              decoration: BoxDecoration(
                color: context.appBg,
                border: Border(top: BorderSide(color: Colors.grey[200]!)),
              ),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF58220),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    _t('close'),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value,
      {Color? valueColor}) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF7ED),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 18,
            color: const Color(0xFFF58220),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          '$label:',
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: valueColor ?? const Color(0xFF1E293B),
            ),
          ),
        ),
      ],
    );
  }
}
