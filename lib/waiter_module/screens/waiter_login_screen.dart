import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../services/app_themes.dart';
import '../../services/api/api_constants.dart';
import '../../services/language_service.dart';
import '../services/waiter_controller.dart';
import '../services/waiter_session_service.dart';
import 'waiter_home_screen.dart';

/// Entry screen for the waiter module — the user types or picks the name
/// that will show up on peer devices and table cards.
class WaiterLoginScreen extends StatefulWidget {
  final WaiterSessionService session;
  final WaiterController controller;

  const WaiterLoginScreen({
    super.key,
    required this.session,
    required this.controller,
  });

  @override
  State<WaiterLoginScreen> createState() => _WaiterLoginScreenState();
}

class _WaiterLoginScreenState extends State<WaiterLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.session.self?.name;
    if (existing != null && existing.isNotEmpty) {
      _nameCtrl.text = existing;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await widget.session.signIn(
        name: _nameCtrl.text.trim(),
        branchId: ApiConstants.branchId.toString(),
      );
      await widget.controller.start();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => WaiterHomeScreen(controller: widget.controller),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appBg,
      body: SafeArea(
        child: LayoutBuilder(builder: (_, constraints) {
          return SingleChildScrollView(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: _buildCard(context),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildCard(BuildContext context) {
    return Card(
      elevation: 0,
      color: context.appSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: context.appBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: context.appPrimary.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      LucideIcons.bellRing,
                      color: context.appPrimary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          translationService.t('waiter_module_title'),
                          style: TextStyle(
                            color: context.appText,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          translationService.t('waiter_module_subtitle'),
                          style: TextStyle(
                            color: context.appTextMuted,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _nameCtrl,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _signIn(),
                style: TextStyle(color: context.appText),
                decoration: InputDecoration(
                  labelText: translationService.t('waiter_name'),
                  prefixIcon: const Icon(LucideIcons.user),
                  filled: true,
                  fillColor: context.appSurfaceAlt,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: context.appBorder),
                  ),
                ),
                validator: (v) {
                  if (v == null || v.trim().length < 2) {
                    return translationService.t('waiter_name_required');
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _busy ? null : _signIn,
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(LucideIcons.logIn),
                  label: Text(translationService.t('waiter_start_shift')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.appPrimary,
                    foregroundColor: Colors.white,
                    textStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
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
