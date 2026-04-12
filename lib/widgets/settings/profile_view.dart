import 'package:flutter/material.dart';
import '../../services/api/profile_service.dart';
import '../../locator.dart';
import '../../services/language_service.dart';

class ProfileView extends StatefulWidget {
  final bool showPageHeader;
  final bool compactMode;

  const ProfileView({
    super.key,
    this.showPageHeader = true,
    this.compactMode = false,
  });

  @override
  State<ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<ProfileView> {
  final ProfileService _profileService = getIt<ProfileService>();
  ProfileData? _profileData;
  bool _isLoading = true;
  String? _error;

  bool get _useArabicUi {
    final code = translationService.currentLanguageCode.trim().toLowerCase();
    return code.startsWith('ar') || code.startsWith('ur');
  }

  String _tr(String ar, String en) => _useArabicUi ? ar : en;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final profile = await _profileService.getProfileData();

      if (mounted) {
        setState(() {
          _profileData = profile;
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

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isCompact = widget.compactMode || width < 700;
    final isVeryCompact = widget.compactMode || width < 420;
    final compactLayout = widget.compactMode || width < 430;
    final pagePadding = widget.showPageHeader
        ? (isVeryCompact ? 12.0 : (isCompact ? 16.0 : 32.0))
        : (compactLayout ? 10.0 : 14.0);
    final cardPadding = compactLayout ? 14.0 : (isCompact ? 18.0 : 32.0);
    final sectionGap = compactLayout ? 18.0 : (isVeryCompact ? 20.0 : 32.0);
    final titleFontSize = compactLayout ? 22.0 : (isCompact ? 26.0 : 28.0);
    final subtitleFontSize =
        compactLayout ? 13.0 : (isVeryCompact ? 14.0 : 16.0);

    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red.shade300),
            const SizedBox(height: 16),
            Text(
              _tr(
                'حدث خطأ أثناء تحميل الملف الشخصي',
                'Error loading profile data',
              ),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.red.shade700,
              ),
            ),
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: Colors.grey.shade600)),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadProfile,
              icon: const Icon(Icons.refresh),
              label: Text(_tr('إعادة المحاولة', 'Retry')),
            ),
          ],
        ),
      );
    }

    if (_profileData == null) {
      return Center(
        child: Text(_tr('لا توجد بيانات', 'No data available')),
      );
    }

    final arabicName = _profileData!.fullname.ar.trim();
    final englishName = _profileData!.fullname.en.trim();
    final primaryName = _useArabicUi
        ? (arabicName.isNotEmpty ? arabicName : englishName)
        : (englishName.isNotEmpty ? englishName : arabicName);
    final secondaryName =
        (_useArabicUi && englishName.isNotEmpty && englishName != primaryName)
            ? englishName
            : '';
    final compactInfo = compactLayout;

    return SingleChildScrollView(
      padding: EdgeInsets.all(pagePadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.showPageHeader) ...[
            Text(
              _tr('الملف الشخصي', 'Profile'),
              style: TextStyle(
                fontSize: titleFontSize,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _tr(
                'معلومات الحساب والإعدادات الشخصية',
                'Account information and personal settings',
              ),
              style: TextStyle(
                fontSize: subtitleFontSize,
                color: Colors.grey.shade600,
              ),
            ),
            SizedBox(height: sectionGap),
          ],
          if (!widget.showPageHeader) const SizedBox(height: 4),

          // Profile Card
          Container(
            padding: EdgeInsets.all(cardPadding),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(compactLayout ? 16 : 24),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: compactLayout ? 8 : 20,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              children: [
                // Avatar and Name
                LayoutBuilder(
                  builder: (context, constraints) {
                    final compactHeader =
                        compactLayout || constraints.maxWidth < 760;
                    final avatarSize = compactLayout
                        ? 84.0
                        : (constraints.maxWidth < 380 ? 88.0 : 120.0);
                    final initialsFontSize = compactLayout
                        ? 26.0
                        : (constraints.maxWidth < 380 ? 28.0 : 36.0);
                    final nameFontSize = compactLayout
                        ? 20.0
                        : (constraints.maxWidth < 380 ? 24.0 : 32.0);
                    final secondaryNameFontSize = compactLayout
                        ? 14.0
                        : (constraints.maxWidth < 380 ? 16.0 : 18.0);

                    final avatar = Container(
                      width: avatarSize,
                      height: avatarSize,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF7ED),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFFF58220),
                          width: 4,
                        ),
                      ),
                      child: _profileData!.avatar != null &&
                              _profileData!.avatar!.isNotEmpty
                          ? ClipOval(
                              child: Image.network(
                                _profileData!.getAvatarUrl(),
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return Center(
                                    child: Text(
                                      _getInitials(primaryName),
                                      style: TextStyle(
                                        fontSize: initialsFontSize,
                                        fontWeight: FontWeight.bold,
                                        color: const Color(0xFFF58220),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            )
                          : Center(
                              child: Text(
                                _getInitials(primaryName),
                                style: TextStyle(
                                  fontSize: initialsFontSize,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFFF58220),
                                ),
                              ),
                            ),
                    );

                    final userInfo = Column(
                      crossAxisAlignment: compactHeader
                          ? CrossAxisAlignment.center
                          : CrossAxisAlignment.start,
                      children: [
                        Text(
                          primaryName,
                          textAlign: compactHeader
                              ? TextAlign.center
                              : TextAlign.start,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: nameFontSize,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (secondaryName.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            secondaryName,
                            textAlign: compactHeader
                                ? TextAlign.center
                                : TextAlign.start,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: secondaryNameFontSize,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFFF58220).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.verified_user,
                                size: 18,
                                color: _profileData!.isVerified
                                    ? Colors.green
                                    : Colors.orange,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _profileData!.roleDisplay,
                                style: const TextStyle(
                                  color: Color(0xFFF58220),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );

                    final statusBadge = Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: compactLayout ? 14 : 20,
                        vertical: compactLayout ? 8 : 10,
                      ),
                      decoration: BoxDecoration(
                        color: _profileData!.isVerified
                            ? Colors.green.shade50
                            : Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(
                          color: _profileData!.isVerified
                              ? Colors.green.shade200
                              : Colors.orange.shade200,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _profileData!.isVerified
                                ? Icons.verified
                                : Icons.pending,
                            color: _profileData!.isVerified
                                ? Colors.green
                                : Colors.orange,
                            size: compactLayout ? 18 : 20,
                          ),
                          SizedBox(width: compactLayout ? 6 : 8),
                          Text(
                            _profileData!.isVerified
                                ? _tr('تم التحقق', 'Verified')
                                : _tr('بانتظار التحقق', 'Pending verification'),
                            style: TextStyle(
                              color: _profileData!.isVerified
                                  ? Colors.green
                                  : Colors.orange,
                              fontWeight: FontWeight.w600,
                              fontSize: compactLayout ? 13 : 14,
                            ),
                          ),
                        ],
                      ),
                    );

                    if (compactHeader) {
                      return Column(
                        children: [
                          avatar,
                          SizedBox(height: compactLayout ? 14 : 20),
                          userInfo,
                          SizedBox(height: compactLayout ? 12 : 16),
                          statusBadge,
                        ],
                      );
                    }

                    return Row(
                      children: [
                        avatar,
                        const SizedBox(width: 24),
                        Expanded(child: userInfo),
                        Flexible(child: statusBadge),
                      ],
                    );
                  },
                ),

                SizedBox(height: sectionGap),
                Divider(color: Colors.grey.shade200),
                SizedBox(height: sectionGap),

                // Contact Information
                _buildSectionTitle(
                  _tr('معلومات التواصل', 'Contact Information'),
                  compact: compactInfo,
                ),
                const SizedBox(height: 20),
                _buildInfoRow(
                  icon: Icons.email,
                  label: _tr('البريد الإلكتروني', 'Email'),
                  value: _profileData!.email,
                  compact: compactInfo,
                ),
                if (_profileData!.mobile != null)
                  _buildInfoRow(
                    icon: Icons.phone,
                    label: _tr('رقم الهاتف', 'Phone Number'),
                    value: _profileData!.mobile!,
                    compact: compactInfo,
                  ),

                SizedBox(height: sectionGap),
                Divider(color: Colors.grey.shade200),
                SizedBox(height: sectionGap),

                // Account Information
                _buildSectionTitle(
                  _tr('معلومات الحساب', 'Account Information'),
                  compact: compactInfo,
                ),
                const SizedBox(height: 20),
                _buildInfoRow(
                  icon: Icons.numbers,
                  label: _tr('معرف الحساب', 'Account ID'),
                  value: '#${_profileData!.id}',
                  compact: compactInfo,
                ),
                _buildInfoRow(
                  icon: Icons.location_city,
                  label: _tr('الدولة', 'Country'),
                  value: _tr(
                    'الدولة ${_profileData!.countryId}',
                    'Country ${_profileData!.countryId}',
                  ),
                  compact: compactInfo,
                ),
                _buildInfoRow(
                  icon: Icons.location_on,
                  label: _tr('المدينة', 'City'),
                  value: _tr(
                    'المدينة ${_profileData!.cityId}',
                    'City ${_profileData!.cityId}',
                  ),
                  compact: compactInfo,
                ),

                SizedBox(height: sectionGap),
                Divider(color: Colors.grey.shade200),
                SizedBox(height: sectionGap),

                // Device Information
                _buildSectionTitle(
                  _tr('معلومات الجهاز والاتصال',
                      'Device & Connection Information'),
                  compact: compactInfo,
                ),
                const SizedBox(height: 20),
                if (_profileData!.ip != null)
                  _buildInfoRow(
                    icon: Icons.computer,
                    label: _tr('عنوان IP', 'IP Address'),
                    value: _profileData!.ip!,
                    compact: compactInfo,
                  ),
                _buildInfoRow(
                  icon: Icons.router,
                  label: _tr('حالة المنفذ', 'Port Status'),
                  value: _profileData!.portStatus
                      ? _tr('متصل', 'Connected')
                      : _tr('غير متصل', 'Disconnected'),
                  valueColor:
                      _profileData!.portStatus ? Colors.green : Colors.red,
                  compact: compactInfo,
                ),
                if (_profileData!.port != null)
                  _buildInfoRow(
                    icon: Icons.settings_ethernet,
                    label: _tr('المنفذ', 'Port'),
                    value: _profileData!.port!,
                    compact: compactInfo,
                  ),
                if (_profileData!.serialPort != null)
                  _buildInfoRow(
                    icon: Icons.usb,
                    label: _tr('منفذ USB', 'USB Port'),
                    value: _profileData!.serialPort!,
                    compact: compactInfo,
                  ),

                SizedBox(height: sectionGap),
                Divider(color: Colors.grey.shade200),
                SizedBox(height: sectionGap),

                // Additional Info
                _buildSectionTitle(
                  _tr('معلومات إضافية', 'Additional Information'),
                  compact: compactInfo,
                ),
                const SizedBox(height: 20),
                _buildInfoRow(
                  icon: Icons.calendar_today,
                  label: _tr('تاريخ اليوم', 'Today Date'),
                  value: _profileData!.today,
                  compact: compactInfo,
                ),
                if (_profileData!.birthdate != null)
                  _buildInfoRow(
                    icon: Icons.cake,
                    label: _tr('تاريخ الميلاد', 'Birth Date'),
                    value: _profileData!.birthdate!,
                    compact: compactInfo,
                  ),
                if (_profileData!.pays.isNotEmpty)
                  _buildInfoRow(
                    icon: Icons.account_balance_wallet,
                    label: _tr('طرق الدفع', 'Payment Methods'),
                    value: _tr(
                      '${_profileData!.pays.length} طريقة',
                      '${_profileData!.pays.length} methods',
                    ),
                    compact: compactInfo,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, {bool compact = false}) {
    return Row(
      children: [
        Container(
          width: compact ? 3 : 4,
          height: compact ? 20 : 24,
          decoration: BoxDecoration(
            color: const Color(0xFFF58220),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: compact ? 17 : 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
    bool compact = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: compact ? 12 : 16),
      child: Row(
        children: [
          Container(
            width: compact ? 40 : 44,
            height: compact ? 40 : 44,
            decoration: BoxDecoration(
              color: const Color(0xFFF58220).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(compact ? 10 : 12),
            ),
            child: Icon(
              icon,
              color: const Color(0xFFF58220),
              size: compact ? 20 : 22,
            ),
          ),
          SizedBox(width: compact ? 12 : 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: compact ? 13 : 14,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: compact ? 15 : 16,
                    fontWeight: FontWeight.w600,
                    color: valueColor ?? Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getInitials(String name) {
    if (name.isEmpty) return '?';
    final parts = name.split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name[0].toUpperCase();
  }
}
