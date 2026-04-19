import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../locator.dart';
import '../../models.dart';
import '../../services/api/error_handler.dart';
import '../../services/display_app_service.dart';
import '../../services/language_service.dart';
import '../../services/app_themes.dart';

class DisplayDevicesTabView extends StatefulWidget {
  final List<DeviceConfig> devices;
  final Future<void> Function(DeviceConfig) onAddDevice;
  final Future<void> Function(String) onRemoveDevice;
  final bool cdsEnabled;
  final bool kdsEnabled;

  const DisplayDevicesTabView({
    super.key,
    required this.devices,
    required this.onAddDevice,
    required this.onRemoveDevice,
    required this.cdsEnabled,
    required this.kdsEnabled,
  });

  @override
  State<DisplayDevicesTabView> createState() => _DisplayDevicesTabViewState();
}

class _DisplayDevicesTabViewState extends State<DisplayDevicesTabView> {
  final DisplayAppService _displayService = getIt<DisplayAppService>();
  String? _busyId;

  String _t(String key, {Map<String, dynamic>? args}) {
    return translationService.t(key, args: args);
  }

  bool _isDisplayDevice(DeviceConfig d) {
    final type = d.type.trim().toLowerCase();
    return d.id.startsWith('kitchen:') ||
        type == 'kds' ||
        type == 'kitchen_screen' ||
        type == 'order_viewer' ||
        type == 'cds' ||
        type == 'customer_display';
  }

  DisplayMode _modeForDevice(DeviceConfig d) {
    final type = d.type.trim().toLowerCase();
    if (d.id.startsWith('kitchen:')) {
      final isExplicitCds = type == 'cds' || type == 'customer_display';
      return isExplicitCds ? DisplayMode.cds : DisplayMode.kds;
    }
    if (type == 'cds' || type == 'customer_display' || type == 'order_viewer') {
      return DisplayMode.cds;
    }
    return DisplayMode.kds;
  }

  String _modeLabel(DeviceConfig d) {
    return _modeForDevice(d) == DisplayMode.cds ? 'CDS' : 'KDS';
  }

  bool _isModeVisible(DisplayMode mode) {
    return mode == DisplayMode.cds ? widget.cdsEnabled : widget.kdsEnabled;
  }

  Future<void> _reconnect(DeviceConfig device) async {
    setState(() => _busyId = device.id);
    try {
      await _displayService.connectWithMode(
        device.ip,
        port: int.tryParse(device.port) ?? 8080,
        mode: _modeForDevice(device),
      );
      if (!mounted) return;
      setState(() => device.isOnline = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              'display_link_success',
              args: {'mode': _modeLabel(device)},
            ),
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => device.isOnline = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              'display_link_failed',
              args: {'error': e},
            ),
          ),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  void _showAddDisplayDialog() {
    if (!widget.cdsEnabled && !widget.kdsEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_t('display_devices_hidden_by_settings')),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (context) => _AddDisplayDialog(
        onAdd: widget.onAddDevice,
        cdsEnabled: widget.cdsEnabled,
        kdsEnabled: widget.kdsEnabled,
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: context.isDark
              ? [
                  context.appPrimary.withValues(alpha: 0.15),
                  context.appPrimary.withValues(alpha: 0.08),
                ]
              : const [Color(0xFFFFF7ED), Color(0xFFFFFBEB)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: context.isDark
              ? context.appPrimary.withValues(alpha: 0.4)
              : const Color(0xFFFED7AA),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 900;

          final titleBlock = Row(
            children: [
              Container(
                width: compact ? 36 : 42,
                height: compact ? 36 : 42,
                decoration: BoxDecoration(
                  color: context.appCardBg,
                  borderRadius: BorderRadius.circular(compact ? 8 : 10),
                ),
                child: Icon(LucideIcons.monitor,
                    color: const Color(0xFFF58220), size: compact ? 18 : 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _t('display_devices_management_title'),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: compact ? 16 : 18,
                  ),
                ),
              ),
            ],
          );

          final addButton = ElevatedButton.icon(
            onPressed: (!widget.cdsEnabled && !widget.kdsEnabled)
                ? null
                : _showAddDisplayDialog,
            icon: Icon(LucideIcons.plus, size: compact ? 14 : 16),
            label: Text(_t('add')),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF58220),
              foregroundColor: Colors.white,
              padding: compact
                  ? const EdgeInsets.symmetric(horizontal: 12, vertical: 8)
                  : null,
            ),
          );

          if (compact && constraints.maxWidth < 480) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                titleBlock,
                const SizedBox(height: 12),
                addButton,
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: titleBlock),
              const SizedBox(width: 12),
              addButton,
            ],
          );
        },
      ),
    );
  }

  Widget _buildDisplayCard(DeviceConfig d, {required bool compact}) {
    final expectedMode = _modeLabel(d);
    final isCurrent =
        _displayService.connectedIp == d.ip && _displayService.isConnected;

    return Container(
      decoration: BoxDecoration(
        color: context.appCardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.appBorder),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      expectedMode == 'CDS'
                          ? LucideIcons.tv
                          : LucideIcons.utensils,
                      color: const Color(0xFFF58220),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: expectedMode == 'CDS'
                            ? const Color(0xFFEFF6FF)
                            : const Color(0xFFFFF7ED),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        expectedMode,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  d.name,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(
                  '${d.ip}:${d.port}',
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  isCurrent
                      ? _t('connected')
                      : (d.isOnline ? _t('online') : _t('not_connected')),
                  style: TextStyle(
                    color: isCurrent ? Colors.green : Colors.grey,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: context.appSurfaceAlt,
              border: Border(top: BorderSide(color: context.appBorder)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: _busyId == d.id ? null : () => _reconnect(d),
                    child: _busyId == d.id
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(_t('reconnect')),
                  ),
                ),
                VerticalDivider(width: 1, color: context.appBorder),
                Expanded(
                  child: TextButton(
                    onPressed: () => widget.onRemoveDevice(d.id),
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                    child: Text(_t('delete')),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final displays = widget.devices
        .where(_isDisplayDevice)
        .where((device) => _isModeVisible(_modeForDevice(device)))
        .toList(growable: false);

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 900;

        return Container(
          color: context.appBg,
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: displays.isEmpty
                    ? Center(
                        child: Text(
                          (!widget.cdsEnabled && !widget.kdsEnabled)
                              ? _t('display_devices_hidden_by_settings')
                              : _t('no_display_devices_added'),
                          style: const TextStyle(color: Color(0xFF64748B)),
                        ),
                      )
                    : compact
                        ? ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            itemCount: displays.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              return _buildDisplayCard(
                                displays[index],
                                compact: true,
                              );
                            },
                          )
                        : GridView.builder(
                            padding: const EdgeInsets.all(16),
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 360,
                              childAspectRatio: 1.08,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                            ),
                            itemCount: displays.length,
                            itemBuilder: (context, index) {
                              return _buildDisplayCard(
                                displays[index],
                                compact: false,
                              );
                            },
                          ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AddDisplayDialog extends StatefulWidget {
  final Future<void> Function(DeviceConfig) onAdd;
  final bool cdsEnabled;
  final bool kdsEnabled;

  const _AddDisplayDialog({
    required this.onAdd,
    required this.cdsEnabled,
    required this.kdsEnabled,
  });

  @override
  State<_AddDisplayDialog> createState() => _AddDisplayDialogState();
}

class _AddDisplayDialogState extends State<_AddDisplayDialog> {
  final _formKey = GlobalKey<FormState>();
  String _name = '';
  String _ip = '';
  String _port = '8080';
  late DisplayMode _mode;
  bool _saving = false;

  String _t(String key, {Map<String, dynamic>? args}) {
    return translationService.t(key, args: args);
  }

  @override
  void initState() {
    super.initState();
    _mode = widget.cdsEnabled ? DisplayMode.cds : DisplayMode.kds;
  }

  Future<void> _submit() async {
    print('🖥️ [Display] _submit called');
    print(
        '🖥️ [Display] cdsEnabled: ${widget.cdsEnabled}, kdsEnabled: ${widget.kdsEnabled}');
    print('🖥️ [Display] selected mode: $_mode');

    if (!_formKey.currentState!.validate()) {
      print('🖥️ [Display] Form validation failed');
      return;
    }
    if (_mode == DisplayMode.cds && !widget.cdsEnabled) {
      print('🖥️ [Display] CDS not enabled, returning');
      return;
    }
    if (_mode == DisplayMode.kds && !widget.kdsEnabled) {
      print('🖥️ [Display] KDS not enabled, returning');
      return;
    }
    _formKey.currentState!.save();
    print('🖥️ [Display] Form saved: name=$_name, ip=$_ip, port=$_port');

    setState(() => _saving = true);
    try {
      final device = DeviceConfig(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: _name.trim(),
        ip: _ip,
        port: _port,
        type: _mode == DisplayMode.cds ? 'customer_display' : 'kds',
        model: 'display',
        copies: 1,
      );
      print('🖥️ [Display] Creating device: ${device.toJson()}');
      await widget.onAdd(device);
      print('🖥️ [Display] Device added successfully');
      if (mounted) Navigator.pop(context);
    } catch (e) {
      print('🖥️ [Display] Error adding device: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ErrorHandler.toUserMessage(
              e,
              fallback: _t('display_link_failed', args: {'error': e}),
            ),
          ),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_t('add_display_screen')),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (widget.cdsEnabled)
                      ChoiceChip(
                        label: const Text('CDS'),
                        selected: _mode == DisplayMode.cds,
                        onSelected: (_) =>
                            setState(() => _mode = DisplayMode.cds),
                      ),
                    if (widget.kdsEnabled)
                      ChoiceChip(
                        label: const Text('KDS'),
                        selected: _mode == DisplayMode.kds,
                        onSelected: (_) =>
                            setState(() => _mode = DisplayMode.kds),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  decoration: InputDecoration(labelText: _t('printer_name')),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? _t('required') : null,
                  onSaved: (v) => _name = v ?? '',
                ),
                TextFormField(
                  decoration: InputDecoration(labelText: translationService.t('ip_label')),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? _t('required') : null,
                  onSaved: (v) => _ip = v ?? '',
                ),
                TextFormField(
                  initialValue: _port,
                  decoration: InputDecoration(labelText: translationService.t('port_label')),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? _t('required') : null,
                  onSaved: (v) => _port = v ?? '8080',
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: Text(_t('cancel')),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_t('save')),
        ),
      ],
    );
  }
}
