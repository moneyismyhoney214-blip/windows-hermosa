import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../services/display_app_service.dart';
import '../locator.dart';
import '../services/language_service.dart';
import '../screens/qr_scanner_screen.dart';

class DisplayConnectionDialog extends StatefulWidget {
  const DisplayConnectionDialog({Key? key}) : super(key: key);

  @override
  State<DisplayConnectionDialog> createState() =>
      _DisplayConnectionDialogState();
}

class _DisplayConnectionDialogState extends State<DisplayConnectionDialog> {
  final _ipController = TextEditingController();
  late DisplayAppService _displayService;

  @override
  void initState() {
    super.initState();
    _displayService = getIt<DisplayAppService>();
    _displayService.addListener(_onServiceUpdate);

    // Auto-fill with last connected IP if not currently connected
    if (_displayService.status != ConnectionStatus.connected &&
        _displayService.connectedIp != null) {
      _ipController.text = _displayService.connectedIp!;
    }
  }

  @override
  void dispose() {
    _ipController.dispose();
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
    final size = MediaQuery.sizeOf(context);
    final isCompact = size.width < 620;
    final insetPadding = EdgeInsets.symmetric(
      horizontal: isCompact ? 12 : 24,
      vertical: isCompact ? 16 : 24,
    );
    final dialogWidth =
        (size.width - insetPadding.horizontal).clamp(280.0, 560.0).toDouble();
    final maxHeight =
        (size.height - insetPadding.vertical).clamp(420.0, 760.0).toDouble();

    return Dialog(
      insetPadding: insetPadding,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 8,
      child: Container(
        width: dialogWidth,
        constraints: BoxConstraints(maxHeight: maxHeight),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          color: Colors.white,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header with Gradient
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: isCompact ? 16 : 24,
                vertical: isCompact ? 14 : 20,
              ),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFF58220), Color(0xFFFF9D4D)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Row(
                children: [
                  const Icon(LucideIcons.monitor,
                      color: Colors.white, size: 28),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          translationService.t('display_app_connection'),
                          style: GoogleFonts.tajawal(
                            fontSize: isCompact ? 18 : 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          _getStatusText(),
                          style: GoogleFonts.tajawal(
                            fontSize: 13,
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon:
                        const Icon(Icons.close, color: Colors.white, size: 24),
                  ),
                ],
              ),
            ),

            // Scrollable Content
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(isCompact ? 14 : 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_displayService.status == ConnectionStatus.connected)
                      _buildConnectedView()
                    else ...[
                      _buildLastDeviceCard(),
                      const SizedBox(height: 24),
                      _buildConnectionForm(),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getStatusText() {
    switch (_displayService.status) {
      case ConnectionStatus.connected:
        return 'متصل بنجاح';
      case ConnectionStatus.connecting:
        return 'جاري الاتصال...';
      case ConnectionStatus.reconnecting:
        return 'جاري إعادة الاتصال...';
      case ConnectionStatus.error:
        return 'خطأ في الاتصال';
      case ConnectionStatus.disconnected:
        return 'غير متصل';
    }
  }

  Widget _buildLastDeviceCard() {
    if (_displayService.connectedIp == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.history,
                  size: 18, color: Color(0xFF64748B)),
              const SizedBox(width: 8),
              Text(
                'الجهاز المحفوظ',
                style: GoogleFonts.tajawal(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF64748B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth < 420;
              final connectButton = ElevatedButton(
                onPressed: _displayService.status == ConnectionStatus.connecting
                    ? null
                    : () =>
                        _displayService.connect(_displayService.connectedIp!),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF58220),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
                child: Text('ربط الآن',
                    style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
              );

              final info = Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _displayService.connectedIp!,
                      style: GoogleFonts.tajawal(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF1E293B),
                      ),
                    ),
                    Text(
                      'آخر اتصال ناجح',
                      style: GoogleFonts.tajawal(
                          fontSize: 12, color: const Color(0xFF94A3B8)),
                    ),
                  ],
                ),
              );

              if (!stacked) {
                return Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF58220).withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(LucideIcons.tablet,
                          color: Color(0xFFF58220), size: 20),
                    ),
                    const SizedBox(width: 12),
                    info,
                    connectButton,
                  ],
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF58220).withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(LucideIcons.tablet,
                            color: Color(0xFFF58220), size: 20),
                      ),
                      const SizedBox(width: 12),
                      info,
                    ],
                  ),
                  const SizedBox(height: 10),
                  connectButton,
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'إضافة جهاز جديد',
          style: GoogleFonts.tajawal(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF1E293B),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _ipController,
          style: GoogleFonts.tajawal(),
          decoration: InputDecoration(
            labelText: translationService.t('display_app_ip_address'),
            hintText: '192.168.x.x',
            prefixIcon: const Icon(LucideIcons.wifi, size: 20),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xFFF58220), width: 2),
            ),
          ),
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 16),

        // Action Buttons Row
        LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth < 420;
            final qrButton = OutlinedButton.icon(
              onPressed: _openQRScanner,
              icon: const Icon(LucideIcons.qrCode, size: 18),
              label: Text('مسح QR',
                  style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                foregroundColor: const Color(0xFF10B981),
                side: const BorderSide(color: Color(0xFF10B981)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
            );
            final saveButton = ElevatedButton.icon(
              onPressed: _displayService.status == ConnectionStatus.connecting
                  ? null
                  : () => _displayService.connect(_ipController.text),
              icon: _displayService.status == ConnectionStatus.connecting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(LucideIcons.link, size: 18),
              label: Text(
                _displayService.status == ConnectionStatus.connecting
                    ? 'جاري الربط'
                    : 'حفظ وربط',
                style: GoogleFonts.tajawal(fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                backgroundColor: const Color(0xFFF58220),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
            );

            if (!stacked) {
              return Row(
                children: [
                  Expanded(child: qrButton),
                  const SizedBox(width: 12),
                  Expanded(child: saveButton),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                qrButton,
                const SizedBox(height: 8),
                saveButton,
              ],
            );
          },
        ),

        if (_displayService.errorMessage != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFEE2E2)),
            ),
            child: Row(
              children: [
                const Icon(LucideIcons.alertCircle,
                    color: Color(0xFFEF4444), size: 18),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _displayService.errorMessage!,
                    style: GoogleFonts.tajawal(
                        color: Color(0xFFB91C1C), fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  void _openQRScanner() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => QRScannerScreen(
          onConnect: (ip, port, mode) {
            _displayService.connect(ip, port: port);
            if (mode == 'CDS') {
              _displayService.setMode(DisplayMode.cds);
            } else if (mode == 'KDS') {
              _displayService.setMode(DisplayMode.kds);
            }
          },
        ),
      ),
    );
  }

  Widget _buildConnectedView() {
    return Column(
      children: [
        // Connection Info Card
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFFF0FDF4),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFDCFCE7)),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: Color(0xFF22C55E),
                  shape: BoxShape.circle,
                ),
                child: const Icon(LucideIcons.check,
                    color: Colors.white, size: 32),
              ),
              const SizedBox(height: 16),
              Text(
                'متصل بـ ${_displayService.connectedIp}',
                style: GoogleFonts.tajawal(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: const Color(0xFF14532D),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'نظام العرض جاهز لاستقبال البيانات',
                style: GoogleFonts.tajawal(
                    color: const Color(0xFF166534), fontSize: 13),
              ),
            ],
          ),
        ),

        const SizedBox(height: 32),

        Text(
          'اختر وضع العرض',
          style: GoogleFonts.tajawal(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: const Color(0xFF1E293B),
          ),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth < 430;
            if (!stacked) {
              return Row(
                children: [
                  Expanded(
                    child: _buildModeButton(
                      DisplayMode.cds,
                      'وضع العميل',
                      LucideIcons.users,
                      'شاشة CDS للعملاء',
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildModeButton(
                      DisplayMode.kds,
                      'وضع المطبخ',
                      LucideIcons.utensils,
                      'شاشة KDS للمطبخ',
                    ),
                  ),
                ],
              );
            }
            return Column(
              children: [
                _buildModeButton(
                  DisplayMode.cds,
                  'وضع العميل',
                  LucideIcons.users,
                  'شاشة CDS للعملاء',
                ),
                const SizedBox(height: 12),
                _buildModeButton(
                  DisplayMode.kds,
                  'وضع المطبخ',
                  LucideIcons.utensils,
                  'شاشة KDS للمطبخ',
                ),
              ],
            );
          },
        ),

        const SizedBox(height: 32),

        // Footer Buttons
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton.icon(
              onPressed: () => _displayService.disconnect(),
              icon: const Icon(LucideIcons.link2Off,
                  color: Color(0xFFEF4444), size: 18),
              label: Text(
                'قطع الاتصال',
                style: GoogleFonts.tajawal(
                    color: const Color(0xFFEF4444),
                    fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildModeButton(
    DisplayMode mode,
    String title,
    IconData icon,
    String subtitle,
  ) {
    final isSelected = _displayService.currentMode == mode;
    return Material(
      color: isSelected ? const Color(0xFFFFF7ED) : const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: () => _displayService.setMode(mode),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          decoration: BoxDecoration(
            border: Border.all(
              color: isSelected
                  ? const Color(0xFFF58220)
                  : const Color(0xFFE2E8F0),
              width: isSelected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: isSelected
                    ? const Color(0xFFF58220)
                    : const Color(0xFF64748B),
                size: 36,
              ),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: GoogleFonts.tajawal(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: isSelected
                      ? const Color(0xFFF58220)
                      : const Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: GoogleFonts.tajawal(
                  fontSize: 11,
                  color: const Color(0xFF94A3B8),
                ),
              ),
              if (isSelected)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                        color: Color(0xFFF58220), shape: BoxShape.circle),
                    child:
                        const Icon(Icons.check, color: Colors.white, size: 14),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
