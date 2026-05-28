// _AddDisplayDialog + state — split from printer_settings_view.dart for size.
part of '../printer_settings_view.dart';

class _AddDisplayDialog extends StatefulWidget {
  final Future<void> Function(DeviceConfig) onAdd;

  const _AddDisplayDialog({required this.onAdd});

  @override
  State<_AddDisplayDialog> createState() => _AddDisplayDialogState();
}

class _AddDisplayDialogState extends State<_AddDisplayDialog> {
  final _formKey = GlobalKey<FormState>();
  String _name = '';
  String _ip = '';
  String _port = '8080';
  DisplayMode _selectedMode = DisplayMode.cds;
  bool _submitting = false;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();
    setState(() => _submitting = true);
    try {
      final isCds = _selectedMode == DisplayMode.cds;
      await widget.onAdd(DeviceConfig(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: _name.trim(),
        ip: _ip,
        port: _port,
        type: isCds ? 'customer_display' : 'kds',
        model: 'display',
        isOnline: false,
        copies: 1,
      ));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 3),
          content: Text('فشل إضافة الشاشة: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 460,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: context.appCardBg,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: const BoxDecoration(
                color: Color(0xFFFFF7ED),
                border: Border(bottom: BorderSide(color: Color(0xFFFED7AA))),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('رجوع'),
                  ),
                  const Text(
                    'إضافة شاشة عرض',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  TextButton(
                    onPressed: _submitting ? null : _submit,
                    child: _submitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text(
                            'حفظ',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                  ),
                ],
              ),
            ),
            SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _modeCard(
                            label: 'CDS',
                            subtitle: 'شاشة العملاء',
                            icon: LucideIcons.monitor,
                            selected: _selectedMode == DisplayMode.cds,
                            onTap: () {
                              setState(() => _selectedMode = DisplayMode.cds);
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _modeCard(
                            label: 'KDS',
                            subtitle: 'شاشة المطبخ',
                            icon: LucideIcons.utensils,
                            selected: _selectedMode == DisplayMode.kds,
                            onTap: () {
                              setState(() => _selectedMode = DisplayMode.kds);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _buildTextField('الاسم', (val) => _name = val ?? ''),
                    const Divider(height: 1),
                    _buildTextField('عنوان الايبي', (val) => _ip = val!,
                        hint: '192.168.1.xxx', isLtr: true),
                    const Divider(height: 1),
                    _buildTextField('المنفذ', (val) => _port = val!,
                        hint: '8080', isLtr: true, isNumber: true),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _modeCard({
    required String label,
    required String subtitle,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFFF7ED) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? const Color(0xFFF58220) : const Color(0xFFE2E8F0),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: selected ? const Color(0xFFF58220) : Colors.grey),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: selected ? const Color(0xFFF58220) : Colors.black87,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(String label, FormFieldSetter<String> onSaved,
      {String? hint, bool isLtr = false, bool isNumber = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(label,
                style: const TextStyle(
                    color: Color(0xFF64748B), fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: TextFormField(
              onSaved: onSaved,
              validator: (val) => val == null || val.isEmpty ? 'مطلوب' : null,
              textAlign: TextAlign.left,
              textDirection: isLtr ? TextDirection.ltr : TextDirection.rtl,
              keyboardType:
                  isNumber ? TextInputType.number : TextInputType.text,
              decoration: InputDecoration(
                hintText: hint,
                hintTextDirection: TextDirection.ltr,
                hintStyle: const TextStyle(
                    color: Color(0xFF94A3B8), fontWeight: FontWeight.normal),
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                isDense: true,
              ),
              style: const TextStyle(
                  fontWeight: FontWeight.bold, color: Colors.black),
            ),
          ),
        ],
      ),
    );
  }
}
