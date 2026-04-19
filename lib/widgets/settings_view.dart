import 'package:flutter/material.dart';
import '../models.dart';
import 'settings/printers_tab_view.dart';
import 'settings/display_devices_tab_view.dart';
import 'settings/profile_view.dart';
import 'settings/cashier_settings_view.dart';
import 'language_selector.dart';
import 'printer_language_settings_view.dart';
import '../services/api/auth_service.dart';
import '../services/language_service.dart';
import '../screens/login_screen.dart';
import '../services/app_themes.dart';

class SettingsView extends StatefulWidget {
  final List<DeviceConfig> devices;
  final List<CategoryModel> categories;
  final Future<void> Function(DeviceConfig) onAddDevice;
  final Future<void> Function(String) onRemoveDevice;
  final bool requireCustomerSelection;
  final ValueChanged<bool> onRequireCustomerSelectionChanged;
  final bool cdsEnabled;
  final bool kdsEnabled;
  final ValueChanged<bool> onCdsEnabledChanged;
  final ValueChanged<bool> onKdsEnabledChanged;
  final bool autoPrintCashier;
  final ValueChanged<bool> onAutoPrintCashierChanged;
  final bool autoPrintCustomer;
  final ValueChanged<bool> onAutoPrintCustomerChanged;
  final bool autoPrintCustomerSecondCopy;
  final ValueChanged<bool> onAutoPrintCustomerSecondCopyChanged;
  final bool printKitchenInvoices;
  final ValueChanged<bool> onPrintKitchenInvoicesChanged;
  final bool allowPrintWithKds;
  final ValueChanged<bool> onAllowPrintWithKdsChanged;
  final double mealIconScale;
  final ValueChanged<double> onMealIconScaleChanged;
  final double sidebarIconScale;
  final ValueChanged<double> onSidebarIconScaleChanged;
  final bool categoryLayoutVertical;
  final ValueChanged<bool> onCategoryLayoutVerticalChanged;
  final VoidCallback? onBack;
  final VoidCallback? onSwitchBranch;

  const SettingsView({
    super.key,
    required this.devices,
    required this.categories,
    required this.onAddDevice,
    required this.onRemoveDevice,
    required this.requireCustomerSelection,
    required this.onRequireCustomerSelectionChanged,
    required this.cdsEnabled,
    required this.kdsEnabled,
    required this.onCdsEnabledChanged,
    required this.onKdsEnabledChanged,
    required this.autoPrintCashier,
    required this.onAutoPrintCashierChanged,
    required this.autoPrintCustomer,
    required this.onAutoPrintCustomerChanged,
    required this.autoPrintCustomerSecondCopy,
    required this.onAutoPrintCustomerSecondCopyChanged,
    required this.printKitchenInvoices,
    required this.onPrintKitchenInvoicesChanged,
    required this.allowPrintWithKds,
    required this.onAllowPrintWithKdsChanged,
    required this.mealIconScale,
    required this.onMealIconScaleChanged,
    required this.sidebarIconScale,
    required this.onSidebarIconScaleChanged,
    required this.categoryLayoutVertical,
    required this.onCategoryLayoutVerticalChanged,
    this.onBack,
    this.onSwitchBranch,
  });

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  int _selectedIndex = 0;
  String? _branchName;
  bool _isLoadingBranch = true;

  List<_SettingsTab> get _tabs => [
        _SettingsTab(
            icon: Icons.person, label: translationService.t('profile')),
        _SettingsTab(
          icon: Icons.devices,
          label: translationService.t('devices'),
        ),
        _SettingsTab(
          icon: Icons.point_of_sale,
          label: translationService.t('cashier'),
        ),
        _SettingsTab(
            icon: Icons.language, label: translationService.t('language')),
      ];

  Widget _buildContent({required bool isSmallScreen}) {
    switch (_selectedIndex) {
      case 0:
        return ProfileView(
          showPageHeader: !isSmallScreen,
          compactMode: isSmallScreen,
        );
      case 1:
        return _DevicesSettingsCombined(
          devices: widget.devices,
          categories: widget.categories,
          onAddDevice: widget.onAddDevice,
          onRemoveDevice: widget.onRemoveDevice,
          cdsEnabled: widget.cdsEnabled,
          kdsEnabled: widget.kdsEnabled,
        );
      case 2:
        return CashierSettingsView(
          requireCustomerSelection: widget.requireCustomerSelection,
          onRequireCustomerSelectionChanged:
              widget.onRequireCustomerSelectionChanged,
          cdsEnabled: widget.cdsEnabled,
          kdsEnabled: widget.kdsEnabled,
          onCdsEnabledChanged: widget.onCdsEnabledChanged,
          onKdsEnabledChanged: widget.onKdsEnabledChanged,
          autoPrintCashier: widget.autoPrintCashier,
          onAutoPrintCashierChanged: widget.onAutoPrintCashierChanged,
          autoPrintCustomer: widget.autoPrintCustomer,
          onAutoPrintCustomerChanged: widget.onAutoPrintCustomerChanged,
          autoPrintCustomerSecondCopy: widget.autoPrintCustomerSecondCopy,
          onAutoPrintCustomerSecondCopyChanged:
              widget.onAutoPrintCustomerSecondCopyChanged,
          printKitchenInvoices: widget.printKitchenInvoices,
          onPrintKitchenInvoicesChanged: widget.onPrintKitchenInvoicesChanged,
          allowPrintWithKds: widget.allowPrintWithKds,
          onAllowPrintWithKdsChanged: widget.onAllowPrintWithKdsChanged,
          mealIconScale: widget.mealIconScale,
          onMealIconScaleChanged: widget.onMealIconScaleChanged,
          sidebarIconScale: widget.sidebarIconScale,
          onSidebarIconScaleChanged: widget.onSidebarIconScaleChanged,
          categoryLayoutVertical: widget.categoryLayoutVertical,
          onCategoryLayoutVerticalChanged: widget.onCategoryLayoutVerticalChanged,
        );
      case 3:
        return SingleChildScrollView(
          padding: EdgeInsets.all(isSmallScreen ? 12 : 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: const [
              LanguageSelector(),
              SizedBox(height: 16),
              PrinterLanguageSettingsView(),
            ],
          ),
        );
      default:
        return ProfileView(
          showPageHeader: !isSmallScreen,
          compactMode: isSmallScreen,
        );
    }
  }

  @override
  void initState() {
    super.initState();
    _loadBranchName();
  }

  Future<void> _loadBranchName() async {
    try {
      final branchName = await AuthService().getBranchName();
      if (mounted) {
        setState(() {
          _branchName = branchName;
          _isLoadingBranch = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingBranch = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection:
          translationService.isRTL ? TextDirection.rtl : TextDirection.ltr,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isSmallScreen = constraints.maxWidth < 900;

          if (isSmallScreen) {
            final isVeryNarrow = constraints.maxWidth < 390;
            return Scaffold(
              backgroundColor: context.appBg,
              appBar: AppBar(
                backgroundColor: context.appCardBg,
                elevation: 0,
                leading: widget.onBack != null
                    ? IconButton(
                        icon: Icon(
                          translationService.isRTL
                              ? Icons.chevron_right
                              : Icons.chevron_left,
                          color: context.appTextMuted,
                        ),
                        onPressed: widget.onBack,
                      )
                    : null,
                title: Text(
                  translationService.t('settings'),
                  style: const TextStyle(
                    color: Color(0xFF1E293B),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              body: Column(
                children: [
                  if (_isLoadingBranch || _branchName != null)
                    Container(
                      width: double.infinity,
                      margin: EdgeInsets.fromLTRB(
                        isVeryNarrow ? 8 : 12,
                        10,
                        isVeryNarrow ? 8 : 12,
                        4,
                      ),
                      padding: EdgeInsets.symmetric(
                        horizontal: isVeryNarrow ? 10 : 12,
                        vertical: isVeryNarrow ? 8 : 10,
                      ),
                      decoration: BoxDecoration(
                        color: context.appCardBg,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: context.appBorder),
                      ),
                      child: _isLoadingBranch
                          ? const LinearProgressIndicator(minHeight: 2)
                          : Row(
                              children: [
                                const Icon(
                                  Icons.store,
                                  size: 15,
                                  color: Color(0xFFF58220),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _branchName!,
                                    style: TextStyle(
                                      color: const Color(0xFFF58220),
                                      fontWeight: FontWeight.w700,
                                      fontSize: isVeryNarrow ? 12 : 13,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (widget.onSwitchBranch != null)
                                  TextButton.icon(
                                    onPressed: widget.onSwitchBranch,
                                    icon: const Icon(Icons.swap_horiz, size: 18),
                                    label: Text(
                                      translationService.t('switch_branch'),
                                      style: TextStyle(fontSize: isVeryNarrow ? 11 : 12),
                                    ),
                                    style: TextButton.styleFrom(
                                      foregroundColor: const Color(0xFF64748B),
                                      padding: const EdgeInsets.symmetric(horizontal: 8),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  ),
                              ],
                            ),
                    ),
                  _buildMobileTabs(
                    width: constraints.maxWidth,
                    isVeryNarrow: isVeryNarrow,
                  ),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      switchInCurve: Curves.easeOut,
                      switchOutCurve: Curves.easeIn,
                      child: Container(
                        key: ValueKey<int>(_selectedIndex),
                        width: double.infinity,
                        margin: EdgeInsets.fromLTRB(
                          isVeryNarrow ? 8 : 10,
                          4,
                          isVeryNarrow ? 8 : 10,
                          0,
                        ),
                        decoration: BoxDecoration(
                          color: context.appCardBg,
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(isVeryNarrow ? 14 : 18),
                          ),
                          border: Border.all(color: context.appBorder),
                        ),
                        child: _buildContent(isSmallScreen: true),
                      ),
                    ),
                  ),
                  SafeArea(
                    top: false,
                    child: Container(
                      width: double.infinity,
                      padding: EdgeInsets.fromLTRB(
                        isVeryNarrow ? 8 : 12,
                        8,
                        isVeryNarrow ? 8 : 12,
                        12,
                      ),
                      child: _buildLogoutButton(),
                    ),
                  ),
                ],
              ),
            );
          }

          return Scaffold(
            backgroundColor: context.appBg,
            body: Row(
              children: [
                // Sidebar for settings tabs
                Container(
                  width: 280,
                  decoration: BoxDecoration(
                    color: context.appCardBg,
                    border: Border(
                      left: translationService.isRTL
                          ? BorderSide(color: Colors.grey.shade200)
                          : BorderSide.none,
                      right: !translationService.isRTL
                          ? BorderSide(color: Colors.grey.shade200)
                          : BorderSide.none,
                    ),
                  ),
                  child: Column(
                    children: [
                      // Header
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: Colors.grey.shade200),
                          ),
                        ),
                        child: Column(
                          children: [
                            if (widget.onBack != null)
                              Row(
                                children: [
                                  IconButton(
                                    icon: Icon(translationService.isRTL
                                        ? Icons.chevron_right
                                        : Icons.chevron_left),
                                    onPressed: widget.onBack,
                                    color: context.appTextMuted,
                                  ),
                                  Text(
                                    translationService.t('back_to_main'),
                                    style: const TextStyle(
                                      color: Color(0xFF64748B),
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF58220),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.settings,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        translationService.t('settings'),
                                        style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      _isLoadingBranch
                                          ? const SizedBox(
                                              height: 14,
                                              width: 100,
                                              child: LinearProgressIndicator(
                                                  minHeight: 2),
                                            )
                                          : _branchName != null
                                              ? Row(
                                                  children: [
                                                    const Icon(
                                                      Icons.store,
                                                      size: 14,
                                                      color: Color(0xFFF58220),
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Flexible(
                                                      child: Text(
                                                        _branchName!,
                                                        style: const TextStyle(
                                                          color:
                                                              Color(0xFFF58220),
                                                          fontSize: 14,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        ),
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ),
                                                    if (widget.onSwitchBranch != null) ...[
                                                      const SizedBox(width: 8),
                                                      TextButton.icon(
                                                        onPressed: widget.onSwitchBranch,
                                                        icon: const Icon(Icons.swap_horiz, size: 18),
                                                        label: Text(translationService.t('switch_branch')),
                                                        style: TextButton.styleFrom(
                                                          foregroundColor: const Color(0xFF64748B),
                                                          padding: const EdgeInsets.symmetric(horizontal: 8),
                                                          visualDensity: VisualDensity.compact,
                                                        ),
                                                      ),
                                                    ],
                                                  ],
                                                )
                                              : Text(
                                                  translationService
                                                      .t('app_name'),
                                                  style: const TextStyle(
                                                    color: Colors.grey,
                                                    fontSize: 14,
                                                  ),
                                                ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // Tabs
                      Expanded(
                        child: ListView.builder(
                          itemCount: _tabs.length,
                          padding: const EdgeInsets.all(16),
                          itemBuilder: (context, index) {
                            final tab = _tabs[index];
                            final isSelected = _selectedIndex == index;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () =>
                                      setState(() => _selectedIndex = index),
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 14,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? const Color(0xFFF58220)
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          tab.icon,
                                          color: isSelected
                                              ? Colors.white
                                              : const Color(0xFF64748B),
                                          size: 22,
                                        ),
                                        const SizedBox(width: 12),
                                        Text(
                                          tab.label,
                                          style: TextStyle(
                                            color: isSelected
                                                ? Colors.white
                                                : const Color(0xFF64748B),
                                            fontWeight: FontWeight.w600,
                                            fontSize: 15,
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

                      // Logout button
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          border: Border(
                            top: BorderSide(color: Colors.grey.shade200),
                          ),
                        ),
                        child: _buildLogoutButton(),
                      ),
                    ],
                  ),
                ),

                // Content area
                Expanded(
                  child: _buildContent(isSmallScreen: false),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildMobileTabs({
    required double width,
    required bool isVeryNarrow,
  }) {
    if (!isVeryNarrow) {
      return SizedBox(
        height: 54,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
          itemCount: _tabs.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final tab = _tabs[index];
            final isSelected = _selectedIndex == index;
            return _buildMobileTabPill(
              tab: tab,
              isSelected: isSelected,
              onTap: () => setState(() => _selectedIndex = index),
            );
          },
        ),
      );
    }

    final cellWidth = ((width - 24 - 8) / 2).clamp(120.0, 220.0).toDouble();
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: List<Widget>.generate(_tabs.length, (index) {
          final tab = _tabs[index];
          final isSelected = _selectedIndex == index;
          return SizedBox(
            width: cellWidth,
            child: _buildMobileTabPill(
              tab: tab,
              isSelected: isSelected,
              fillWidth: true,
              onTap: () => setState(() => _selectedIndex = index),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildLogoutButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () async {
          await AuthService().logout();
          if (!mounted) return;
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (_) => const LoginScreen(),
            ),
            (route) => false,
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
          decoration: BoxDecoration(
            color: context.isDark
                ? const Color(0xFFEF4444).withValues(alpha: 0.15)
                : const Color(0xFFFEF2F2),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0xFFEF4444).withValues(alpha: 0.35),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.logout,
                color: Color(0xFFEF4444),
                size: 22,
              ),
              const SizedBox(width: 12),
              Text(
                translationService.t('logout'),
                style: const TextStyle(
                  color: Color(0xFFEF4444),
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMobileTabPill({
    required _SettingsTab tab,
    required bool isSelected,
    required VoidCallback onTap,
    bool fillWidth = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          width: fillWidth ? double.infinity : null,
          padding: EdgeInsets.symmetric(
            horizontal: fillWidth ? 10 : 14,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFF58220) : Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFFF58220)
                  : const Color(0xFFE2E8F0),
            ),
          ),
          child: Row(
            mainAxisSize: fillWidth ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment:
                fillWidth ? MainAxisAlignment.center : MainAxisAlignment.start,
            children: [
              Icon(
                tab.icon,
                size: 16,
                color: isSelected ? Colors.white : const Color(0xFF64748B),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  tab.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: fillWidth ? TextAlign.center : TextAlign.start,
                  style: TextStyle(
                    color: isSelected ? Colors.white : const Color(0xFF334155),
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsTab {
  final IconData icon;
  final String label;

  const _SettingsTab({required this.icon, required this.label});
}

class _DevicesSettingsCombined extends StatelessWidget {
  final List<DeviceConfig> devices;
  final List<CategoryModel> categories;
  final Future<void> Function(DeviceConfig) onAddDevice;
  final Future<void> Function(String) onRemoveDevice;
  final bool cdsEnabled;
  final bool kdsEnabled;

  const _DevicesSettingsCombined({
    required this.devices,
    required this.categories,
    required this.onAddDevice,
    required this.onRemoveDevice,
    required this.cdsEnabled,
    required this.kdsEnabled,
  });

  @override
  Widget build(BuildContext context) {
    final t = translationService;
    return DefaultTabController(
      length: 2,
      child: Container(
        color: context.appBg,
        child: Column(
          children: [
            Container(
              color: context.appBg,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: context.appSurfaceAlt,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.appBorder),
                ),
                child: TabBar(
                  isScrollable: false,
                  indicator: BoxDecoration(
                    color: context.appPrimary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  labelColor: Colors.white,
                  unselectedLabelColor: context.appTextMuted,
                  labelStyle: const TextStyle(fontWeight: FontWeight.w700),
                  dividerColor: Colors.transparent,
                  labelPadding: EdgeInsets.zero,
                  tabs: [
                    Tab(text: t.t('printers')),
                    Tab(text: t.t('cds_kds_devices')),
                  ],
                ),
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  PrintersTabView(
                    devices: devices,
                    categories: categories,
                    onAddDevice: onAddDevice,
                    onRemoveDevice: onRemoveDevice,
                  ),
                  DisplayDevicesTabView(
                    devices: devices,
                    onAddDevice: onAddDevice,
                    onRemoveDevice: onRemoveDevice,
                    cdsEnabled: cdsEnabled,
                    kdsEnabled: kdsEnabled,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
