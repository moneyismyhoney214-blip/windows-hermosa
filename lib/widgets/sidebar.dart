import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../models.dart';
import '../services/language_service.dart';

class Sidebar extends StatelessWidget {
  final String selectedCategory;
  final ValueChanged<String> onSelectCategory;
  final VoidCallback onSettingsTap;
  final VoidCallback onLogout;
  final VoidCallback onSwitchBranch;
  final String activeTab;
  final List<CategoryModel> categories;
  final double iconScale;

  const Sidebar({
    super.key,
    required this.selectedCategory,
    required this.onSelectCategory,
    required this.onSettingsTap,
    required this.onLogout,
    required this.onSwitchBranch,
    required this.activeTab,
    required this.categories,
    required this.iconScale,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // حساب العرض المناسب حسب حجم الشاشة
        final screenWidth = MediaQuery.of(context).size.width;
        final isVerySmallScreen = screenWidth < 400;
        final isSmallScreen = screenWidth < 600;
        
        final scale = iconScale.clamp(0.85, 1.4);

        // عرض الـ sidebar
        final sidebarWidth =
            isVerySmallScreen ? 70.0 : (isSmallScreen ? 85.0 : 112.0);

        // عرض الكروت
        final cardWidth =
            isVerySmallScreen ? 60.0 : (isSmallScreen ? 72.0 : 88.0);
        final cardHeight =
            isVerySmallScreen ? 60.0 : (isSmallScreen ? 68.0 : 78.0);

        // حجم اللوجو
        final logoSize =
            isVerySmallScreen ? 36.0 : (isSmallScreen ? 42.0 : 48.0);

        // حجم الأيقونات
        final baseIconSize =
            isVerySmallScreen ? 20.0 : (isSmallScreen ? 22.0 : 24.0);
        final baseImageSize =
            isVerySmallScreen ? 24.0 : (isSmallScreen ? 28.0 : 32.0);
        final maxIcon = (cardWidth - 12).clamp(16.0, cardWidth);
        final iconSize = (baseIconSize * scale).clamp(14.0, maxIcon);
        final imageSize = (baseImageSize * scale).clamp(16.0, maxIcon);
        
        // حجم الخط
        final fontSize =
            isVerySmallScreen ? 8.0 : (isSmallScreen ? 9.0 : 10.0);
        
        // حجم الأزرار السفلية
        final buttonSize =
            isVerySmallScreen ? 36.0 : (isSmallScreen ? 40.0 : 44.0);
        final baseButtonIconSize =
            isVerySmallScreen ? 16.0 : (isSmallScreen ? 18.0 : 20.0);
        final buttonIconSize =
            (baseButtonIconSize * scale).clamp(12.0, buttonSize - 12.0);
        
        // المسافات
        final verticalPadding =
            isVerySmallScreen ? 8.0 : (isSmallScreen ? 10.0 : 14.0);
        final logoMargin =
            isVerySmallScreen ? 12.0 : (isSmallScreen ? 16.0 : 20.0);
        final itemSpacing =
            isVerySmallScreen ? 6.0 : (isSmallScreen ? 8.0 : 10.0);
        final buttonSpacing =
            isVerySmallScreen ? 8.0 : (isSmallScreen ? 10.0 : 12.0);
        
        return Container(
          width: sidebarWidth,
          height: double.infinity,
          padding: EdgeInsets.symmetric(vertical: verticalPadding),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            border: Border(
              left: translationService.isRTL
                  ? const BorderSide(color: Color(0xFFE2E8F0))
                  : BorderSide.none,
              right: !translationService.isRTL
                  ? const BorderSide(color: Color(0xFFE2E8F0))
                  : BorderSide.none,
            ),
          ),
          child: Column(
            children: [
              // Logo
              Container(
                width: logoSize,
                height: logoSize,
                margin: EdgeInsets.only(bottom: logoMargin),
                decoration: BoxDecoration(
                  color: const Color(0xFFF58220),
                  borderRadius: BorderRadius.circular(isVerySmallScreen ? 8 : 12),
                ),
                child: Icon(
                  LucideIcons.store,
                  color: Colors.white,
                  size: iconSize,
                ),
              ),

              // Categories
              Expanded(
                child: ListView.separated(
                  itemCount: categories.length,
                  separatorBuilder: (_, __) => SizedBox(height: itemSpacing),
                  itemBuilder: (context, index) {
                    final item = categories[index];
                    final isActive =
                        selectedCategory == item.id && activeTab != 'settings';
                    return Center(
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => onSelectCategory(item.id),
                          borderRadius: BorderRadius.circular(isVerySmallScreen ? 8 : 12),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: cardWidth,
                            height: cardHeight,
                            decoration: BoxDecoration(
                              color: isActive
                                  ? const Color(0xFFFFEDD5)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(isVerySmallScreen ? 8 : 12),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (item.imageUrl != null &&
                                    item.imageUrl!.isNotEmpty)
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(isVerySmallScreen ? 6 : 8),
                                    child: Image.network(
                                      item.imageUrl!,
                                      width: imageSize,
                                      height: imageSize,
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error, stackTrace) =>
                                          Icon(
                                        item.icon,
                                        size: iconSize,
                                        color: isActive
                                            ? const Color(0xFFC2410C)
                                            : const Color(0xFF94A3B8),
                                      ),
                                    ),
                                  )
                                else
                                  Icon(
                                    item.icon,
                                    size: iconSize,
                                    color: isActive
                                        ? const Color(0xFFC2410C)
                                        : const Color(0xFF94A3B8),
                                  ),
                                SizedBox(height: isVerySmallScreen ? 2 : 4),
                                Padding(
                                  padding: EdgeInsets.symmetric(horizontal: isVerySmallScreen ? 2 : 4),
                                  child: Text(
                                    item.name,
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: fontSize,
                                      fontWeight: FontWeight.w500,
                                      color: isActive
                                          ? const Color(0xFFC2410C)
                                          : const Color(0xFF94A3B8),
                                      height: 1.2,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              // System Actions
              Divider(height: isVerySmallScreen ? 24 : 32),
              IconButton(
                onPressed: onSwitchBranch,
                tooltip: translationService.t('switch_branch'),
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFFF1F5F9),
                  foregroundColor: const Color(0xFF64748B),
                  fixedSize: Size(buttonSize, buttonSize),
                ),
                icon: Icon(LucideIcons.repeat, size: buttonIconSize),
              ),
              SizedBox(height: buttonSpacing),
              IconButton(
                onPressed: onSettingsTap,
                tooltip: translationService.t('settings'),
                style: IconButton.styleFrom(
                  backgroundColor: activeTab == 'settings'
                      ? const Color(0xFFF58220)
                      : const Color(0xFFF1F5F9),
                  foregroundColor: activeTab == 'settings'
                      ? Colors.white
                      : const Color(0xFF64748B),
                  fixedSize: Size(buttonSize, buttonSize),
                ),
                icon: Icon(LucideIcons.settings, size: buttonIconSize),
              ),
              SizedBox(height: buttonSpacing),
              IconButton(
                onPressed: onLogout,
                tooltip: translationService.t('logout'),
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFFFEF2F2),
                  foregroundColor: const Color(0xFFEF4444),
                  fixedSize: Size(buttonSize, buttonSize),
                ),
                icon: Icon(LucideIcons.logOut, size: buttonIconSize),
              ),
            ],
          ),
        );
      },
    );
  }
}
