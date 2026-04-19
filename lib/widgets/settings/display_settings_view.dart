import 'package:flutter/material.dart';
import '../../services/display_app_service.dart';
import '../../locator.dart';
import '../../services/language_service.dart';
import '../../dialogs/improved_display_connection_dialog.dart';
import '../../services/app_themes.dart';

class DisplaySettingsView extends StatefulWidget {
  const DisplaySettingsView({Key? key}) : super(key: key);

  @override
  State<DisplaySettingsView> createState() => _DisplaySettingsViewState();
}

class _DisplaySettingsViewState extends State<DisplaySettingsView> {
  late DisplayAppService _displayService;

  @override
  void initState() {
    super.initState();
    _displayService = getIt<DisplayAppService>();
    _displayService.addListener(_onServiceUpdate);
  }

  @override
  void dispose() {
    _displayService.removeListener(_onServiceUpdate);
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          _buildHeader(),
          const SizedBox(height: 24),

          // Connection Status Card
          _buildConnectionCard(),
          const SizedBox(height: 24),

          // Mode Selection
          if (_displayService.isConnected) ...[
            _buildModeSelection(),
            const SizedBox(height: 24),
          ],

          // Info Section
          _buildInfoSection(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          translationService.t('display_app_settings'),
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          translationService.t('display_app_settings_description'),
          style: const TextStyle(
            fontSize: 14,
            color: Color(0xFF64748B),
          ),
        ),
      ],
    );
  }

  Widget _buildConnectionCard() {
    final isConnected = _displayService.isConnected;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: context.appCardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isConnected
                      ? const Color(0xFFF0FDF4)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isConnected ? Icons.tv : Icons.tv_off,
                  color: isConnected
                      ? const Color(0xFF22C55E)
                      : const Color(0xFF64748B),
                  size: 32,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      translationService.t('display_app'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isConnected
                          ? '${translationService.t('connected')}: ${_displayService.connectedIp}'
                          : translationService.t('not_connected'),
                      style: TextStyle(
                        fontSize: 14,
                        color: isConnected
                            ? const Color(0xFF22C55E)
                            : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              if (isConnected)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Color(0xFF22C55E),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        translationService.t('online'),
                        style: const TextStyle(
                          color: Color(0xFF22C55E),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _showConnectionDialog(),
                  icon: Icon(isConnected ? Icons.settings : Icons.link),
                  label: Text(
                    isConnected
                        ? translationService.t('manage_connection')
                        : translationService.t('connect_to_display'),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF58220),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              if (isConnected) ...[
                const SizedBox(width: 12),
                TextButton.icon(
                  onPressed: () => _displayService.disconnect(),
                  icon: const Icon(Icons.link_off, color: Color(0xFFEF4444)),
                  label: Text(
                    translationService.t('disconnect'),
                    style: const TextStyle(color: Color(0xFFEF4444)),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        vertical: 16, horizontal: 24),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          // NearPay Capability Indicator
          if (isConnected && _displayService.supportsNearPay)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF22C55E)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.credit_card,
                    color: Color(0xFF22C55E),
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'NearPay متاح',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF22C55E),
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'يمكنك استخدام الدفع الإلكتروني عبر Tap to Pay',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.check_circle,
                    color: Color(0xFF22C55E),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildModeSelection() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: context.appCardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            translationService.t('display_mode'),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            translationService.t('display_mode_description'),
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildModeCard(
                  DisplayMode.cds,
                  translationService.t('cds_mode'),
                  translationService.t('customer_display_system'),
                  Icons.people,
                  const Color(0xFFF58220),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildModeCard(
                  DisplayMode.kds,
                  translationService.t('kds_mode'),
                  translationService.t('kitchen_display_system'),
                  Icons.kitchen,
                  const Color(0xFFF59E0B),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModeCard(
    DisplayMode mode,
    String title,
    String description,
    IconData icon,
    Color color,
  ) {
    final isSelected = _displayService.currentMode == mode;

    return Material(
      color: isSelected ? color.withValues(alpha: 0.1) : Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => _displayService.setMode(mode),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(
              color: isSelected ? color : Colors.grey[300]!,
              width: isSelected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: color, size: 24),
                  const Spacer(),
                  if (isSelected)
                    Icon(Icons.check_circle, color: color, size: 20),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isSelected ? color : Colors.grey[800],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoSection() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: context.appBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            translationService.t('about_display_app'),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          _buildInfoItem(
            Icons.cast_connected,
            translationService.t('cds_mode'),
            translationService.t('cds_mode_info'),
          ),
          const SizedBox(height: 12),
          _buildInfoItem(
            Icons.kitchen,
            translationService.t('kds_mode'),
            translationService.t('kds_mode_info'),
          ),
          const SizedBox(height: 12),
          _buildInfoItem(
            Icons.wifi,
            translationService.t('connection_info'),
            translationService.t('connection_info_desc'),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem(IconData icon, String title, String description) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: const Color(0xFF64748B)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showConnectionDialog() {
    showDialog(
      context: context,
      builder: (context) => ImprovedDisplayConnectionDialog(
        onConnect: (ip, port, mode) async {
          final targetMode =
              mode.toLowerCase() == 'cds' ? DisplayMode.cds : DisplayMode.kds;
          await _displayService.connectWithMode(
            ip,
            port: port,
            mode: targetMode,
          );
        },
        onDisconnect: () => _displayService.disconnect(),
        isConnected: _displayService.isConnected,
        currentIp: _displayService.connectedIp,
      ),
    );
  }
}
