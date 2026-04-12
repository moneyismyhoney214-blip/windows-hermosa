import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../screens/qr_scanner_screen.dart';
import '../services/language_service.dart';

/// نموذج جهاز العرض المحفوظ
class SavedDisplayDevice {
  final String id;
  final String name;
  String ip;
  int port;
  String mode; // 'cds' or 'kds'
  DateTime lastConnected;
  bool isConnected;

  SavedDisplayDevice({
    required this.id,
    required this.name,
    required this.ip,
    required this.port,
    this.mode = 'cds',
    required this.lastConnected,
    this.isConnected = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'ip': ip,
        'port': port,
        'mode': mode,
        'lastConnected': lastConnected.millisecondsSinceEpoch,
        'isConnected': isConnected,
      };

  factory SavedDisplayDevice.fromJson(Map<String, dynamic> json) =>
      SavedDisplayDevice(
        id: json['id'],
        name: json['name'],
        ip: json['ip'],
        port: json['port'],
        mode: json['mode'] ?? 'cds',
        lastConnected:
            DateTime.fromMillisecondsSinceEpoch(json['lastConnected']),
        isConnected: json['isConnected'] ?? false,
      );
}

/// مدير الأجهزة المحفوظة
class SavedDevicesManager {
  static const String _storageKey = 'saved_display_devices';

  static Future<List<SavedDisplayDevice>> getSavedDevices() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString(_storageKey);

    if (data == null || data.isEmpty) return [];

    try {
      final List<dynamic> jsonList = jsonDecode(data);
      return jsonList.map((json) => SavedDisplayDevice.fromJson(json)).toList();
    } catch (e) {
      return [];
    }
  }

  static Future<void> saveDevice(SavedDisplayDevice device) async {
    final prefs = await SharedPreferences.getInstance();
    final devices = await getSavedDevices();

    // تحديث إذا كان موجوداً أو إضافة جديد
    final index = devices.indexWhere((d) => d.id == device.id);
    if (index >= 0) {
      devices[index] = device;
    } else {
      devices.add(device);
    }

    // ترتيب حسب آخر اتصال
    devices.sort((a, b) => b.lastConnected.compareTo(a.lastConnected));

    final String data = jsonEncode(devices.map((d) => d.toJson()).toList());
    await prefs.setString(_storageKey, data);
  }

  static Future<void> deleteDevice(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final devices = await getSavedDevices();
    devices.removeWhere((d) => d.id == id);

    final String data = jsonEncode(devices.map((d) => d.toJson()).toList());
    await prefs.setString(_storageKey, data);
  }

  static Future<void> updateConnectionStatus(
      String id, bool isConnected) async {
    final devices = await getSavedDevices();
    final index = devices.indexWhere((d) => d.id == id);
    if (index >= 0) {
      devices[index].isConnected = isConnected;
      devices[index].lastConnected = DateTime.now();
      await saveDevice(devices[index]);
    }
  }
}

/// dialog الاتصال المحسن
class ImprovedDisplayConnectionDialog extends StatefulWidget {
  final Function(String ip, int port, String mode) onConnect;
  final VoidCallback? onDisconnect;
  final bool isConnected;
  final String? currentIp;

  const ImprovedDisplayConnectionDialog({
    super.key,
    required this.onConnect,
    this.onDisconnect,
    this.isConnected = false,
    this.currentIp,
  });

  @override
  State<ImprovedDisplayConnectionDialog> createState() =>
      _ImprovedDisplayConnectionDialogState();
}

class _ImprovedDisplayConnectionDialogState
    extends State<ImprovedDisplayConnectionDialog> {
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _portController =
      TextEditingController(text: '8080');
  List<SavedDisplayDevice> _savedDevices = [];
  bool _isLoading = true;
  String? _selectedMode;
  int _selectedPort = 8080;
  final translationService = TranslationService();

  @override
  void initState() {
    super.initState();
    _loadSavedDevices();
  }

  @override
  void dispose() {
    _ipController.dispose();
    _nameController.dispose();
    _portController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedDevices() async {
    final devices = await SavedDevicesManager.getSavedDevices();
    if (!mounted) return;
    setState(() {
      _savedDevices = devices;
      _isLoading = false;
    });
  }

  Future<void> _saveNewDevice(String ip, int port, String mode) async {
    final fallbackName = mode == 'kds' ? 'KDS $ip' : 'CDS $ip';
    final device = SavedDisplayDevice(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name:
          _nameController.text.isNotEmpty ? _nameController.text : fallbackName,
      ip: ip,
      port: port,
      mode: mode,
      lastConnected: DateTime.now(),
      isConnected: true,
    );
    await SavedDevicesManager.saveDevice(device);
    await _loadSavedDevices();
  }

  void _connectToDevice(SavedDisplayDevice device) async {
    await SavedDevicesManager.updateConnectionStatus(device.id, true);
    if (!mounted) return;
    widget.onConnect(device.ip, device.port, device.mode);
    Navigator.pop(context);
  }

  void _deleteDevice(SavedDisplayDevice device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(translationService.t('delete_device'),
            style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
        content: Text(
            translationService.t('confirm_delete_device', args: {'name': device.name}),
            style: GoogleFonts.tajawal()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(translationService.t('cancel'), style: GoogleFonts.tajawal()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(translationService.t('delete'), style: GoogleFonts.tajawal(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await SavedDevicesManager.deleteDevice(device.id);
      await _loadSavedDevices();
    }
  }

  void _showAddDeviceDialog() {
    _nameController.clear();
    _ipController.clear();
    _portController.text = '8080';
    // Reset selection when opening dialog
    String? tempSelectedMode = _selectedMode;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) =>
          StatefulBuilder(builder: (context, setDialogState) {
        return AlertDialog(
          scrollable: true,
          title: Text(translationService.t('add_new_device'),
              style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: translationService.t('device_name_optional'),
                  hintText: translationService.t('device_name_example'),
                  labelStyle: GoogleFonts.tajawal(),
                ),
                style: GoogleFonts.tajawal(),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _ipController,
                decoration: InputDecoration(
                  labelText: translationService.t('ip_address'),
                  hintText: '192.168.1.100',
                  labelStyle: GoogleFonts.tajawal(),
                ),
                style: GoogleFonts.tajawal(),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _portController,
                decoration: InputDecoration(
                  labelText: translationService.t('port_number'),
                  hintText: '8080',
                  labelStyle: GoogleFonts.tajawal(),
                ),
                style: GoogleFonts.tajawal(),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              Text(
                translationService.t('choose_screen_type'),
                style: GoogleFonts.tajawal(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  SizedBox(
                    width: 150,
                    child: _buildModeButton(
                      'cds',
                      translationService.t('customer_screen_cds'),
                      Icons.touch_app,
                      tempSelectedMode,
                      (mode) => setDialogState(() => tempSelectedMode = mode),
                    ),
                  ),
                  SizedBox(
                    width: 150,
                    child: _buildModeButton(
                      'kds',
                      translationService.t('kitchen_screen_kds'),
                      Icons.restaurant,
                      tempSelectedMode,
                      (mode) => setDialogState(() => tempSelectedMode = mode),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(translationService.t('cancel'), style: GoogleFonts.tajawal()),
            ),
            ElevatedButton(
              onPressed: tempSelectedMode == null || _ipController.text.isEmpty
                  ? null
                  : () async {
                      final parsedPort =
                          int.tryParse(_portController.text.trim()) ?? 8080;
                      if (parsedPort < 1 || parsedPort > 65535) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(translationService.t('invalid_port')),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }
                      _selectedPort = parsedPort;
                      _selectedMode = tempSelectedMode;
                      await _saveNewDevice(
                        _ipController.text.trim(),
                        _selectedPort,
                        _selectedMode!,
                      );
                      if (!dialogContext.mounted) return;
                      Navigator.pop(dialogContext);
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F172A),
              ),
              child: Text(
                translationService.t('save_only'),
                style: GoogleFonts.tajawal(color: Colors.white),
              ),
            ),
            ElevatedButton(
              onPressed: tempSelectedMode == null || _ipController.text.isEmpty
                  ? null
                  : () async {
                      final parsedPort =
                          int.tryParse(_portController.text.trim()) ?? 8080;
                      if (parsedPort < 1 || parsedPort > 65535) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(translationService.t('invalid_port')),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }
                      _selectedPort = parsedPort;
                      _selectedMode = tempSelectedMode;
                      await _saveNewDevice(
                        _ipController.text.trim(),
                        _selectedPort,
                        _selectedMode!,
                      );
                      if (!mounted || !dialogContext.mounted) return;
                      widget.onConnect(
                        _ipController.text.trim(),
                        _selectedPort,
                        _selectedMode!,
                      );
                      Navigator.pop(dialogContext);
                      Navigator.pop(context);
                    },
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF58220)),
              child: Text(translationService.t('connect_button'),
                  style: GoogleFonts.tajawal(color: Colors.white)),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildModeButton(String mode, String label, IconData icon,
      [String? selectedMode, Function(String)? onSelect]) {
    final currentSelection = selectedMode ?? _selectedMode;
    final isSelected = currentSelection == mode;
    return InkWell(
      onTap: () {
        if (onSelect != null) {
          onSelect(mode);
        } else {
          setState(() => _selectedMode = mode);
        }
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFF58220) : Colors.grey[200],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFFF58220) : Colors.grey,
            width: 2,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: isSelected ? Colors.white : Colors.grey[700]),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: GoogleFonts.tajawal(
                color: isSelected ? Colors.white : Colors.grey[700],
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _scanQRCode() {
    final parentContext = context;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => QRScannerScreen(
          onConnect: (ip, port, mode) async {
            await _saveNewDevice(ip, port, mode);
            if (!mounted || !parentContext.mounted) return;
            widget.onConnect(ip, port, mode);
            Navigator.pop(parentContext);
          },
        ),
      ),
    );
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
        (size.height - insetPadding.vertical).clamp(460.0, 780.0).toDouble();

    return Dialog(
      insetPadding: insetPadding,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        width: dialogWidth,
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: EdgeInsets.all(isCompact ? 16 : 24),
              decoration: const BoxDecoration(
                color: Color(0xFFF58220),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Row(
                children: [
                  const Icon(LucideIcons.monitor,
                      color: Colors.white, size: 32),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          translationService.t('display_screens'),
                          style: GoogleFonts.tajawal(
                            color: Colors.white,
                            fontSize: isCompact ? 20 : 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          translationService.t('display_devices_management_title'),
                          style: GoogleFonts.tajawal(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.isConnected)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.green,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.check_circle,
                              color: Colors.white, size: 16),
                          const SizedBox(width: 4),
                          Text(
                            translationService.t('connected'),
                            style: GoogleFonts.tajawal(
                                color: Colors.white,
                                fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),

            // Content
            Flexible(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _savedDevices.isEmpty
                      ? _buildEmptyState()
                      : _buildDevicesList(),
            ),

            // Actions
            Container(
              padding: EdgeInsets.all(isCompact ? 12 : 16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  // Quick Actions
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final stacked = constraints.maxWidth < 420;
                      final qrBtn = ElevatedButton.icon(
                        onPressed: _scanQRCode,
                        icon: const Icon(LucideIcons.qrCode),
                        label: Text(translationService.t('scan_qr_code'),
                            style: GoogleFonts.tajawal(
                                fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0F172A),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      );
                      final manualBtn = ElevatedButton.icon(
                        onPressed: _showAddDeviceDialog,
                        icon: const Icon(LucideIcons.plus),
                        label: Text(translationService.t('add_manual'),
                            style: GoogleFonts.tajawal(
                                fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFF58220),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      );

                      if (!stacked) {
                        return Row(
                          children: [
                            Expanded(child: qrBtn),
                            const SizedBox(width: 8),
                            Expanded(child: manualBtn),
                          ],
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          qrBtn,
                          const SizedBox(height: 8),
                          manualBtn,
                        ],
                      );
                    },
                  ),

                  if (widget.isConnected && widget.onDisconnect != null) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          widget.onDisconnect!();
                          Navigator.pop(context);
                        },
                        icon: const Icon(LucideIcons.logOut, color: Colors.red),
                        label: Text(translationService.t('disconnect'),
                            style: GoogleFonts.tajawal(
                                color: Colors.red,
                                fontWeight: FontWeight.bold)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.red),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.monitor, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              translationService.t('no_saved_devices'),
              style: GoogleFonts.tajawal(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              translationService.t('add_device_or_scan_qr'),
              textAlign: TextAlign.center,
              style: GoogleFonts.tajawal(
                fontSize: 14,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDevicesList() {
    return ListView.separated(
      shrinkWrap: true,
      padding: const EdgeInsets.all(16),
      itemCount: _savedDevices.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final device = _savedDevices[index];
        return _buildDeviceCard(device);
      },
    );
  }

  Widget _buildDeviceCard(SavedDisplayDevice device) {
    final isCurrentDevice = widget.isConnected && widget.currentIp == device.ip;

    return Card(
      elevation: isCurrentDevice ? 4 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isCurrentDevice ? const Color(0xFFF58220) : Colors.transparent,
          width: 2,
        ),
      ),
      child: InkWell(
        onTap: () => _connectToDevice(device),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Icon
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: device.mode == 'cds'
                      ? const Color(0xFFF58220).withValues(alpha: 0.1)
                      : Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  device.mode == 'cds'
                      ? LucideIcons.monitor
                      : LucideIcons.chefHat,
                  color: device.mode == 'cds'
                      ? const Color(0xFFF58220)
                      : Colors.blue,
                ),
              ),
              const SizedBox(width: 16),

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            device.name,
                            style: GoogleFonts.tajawal(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        if (isCurrentDevice)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.green,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              translationService.t('connected_now'),
                              style: GoogleFonts.tajawal(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${device.ip}:${device.port} • ${device.mode.toUpperCase()}',
                      style: GoogleFonts.tajawal(
                        color: Colors.grey[600],
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      translationService.t('last_connected') + ': ${_formatDate(device.lastConnected)}',
                      style: GoogleFonts.tajawal(
                        color: Colors.grey[500],
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),

              // Actions
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!isCurrentDevice)
                    IconButton(
                      onPressed: () => _connectToDevice(device),
                      icon: const Icon(LucideIcons.plug,
                          color: Color(0xFFF58220)),
                      tooltip: translationService.t('connect_tooltip'),
                    ),
                  IconButton(
                    onPressed: () => _deleteDevice(device),
                    icon: const Icon(LucideIcons.trash2, color: Colors.red),
                    tooltip: translationService.t('delete_tooltip'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) return translationService.t('time_now');
    if (diff.inHours < 1) return translationService.t('time_minutes_ago', args: {'minutes': diff.inMinutes.toString()});
    if (diff.inDays < 1) return translationService.t('time_hours_ago', args: {'hours': diff.inHours.toString()});
    return translationService.t('time_days_ago', args: {
      'day': date.day.toString(),
      'month': date.month.toString(),
      'year': date.year.toString(),
    });
  }
}
