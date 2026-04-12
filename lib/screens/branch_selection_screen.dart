import 'package:flutter/material.dart';
import '../models/branch.dart';
import '../services/api/auth_service.dart';
import '../services/api/api_constants.dart';
import '../services/language_service.dart';
import '../locator.dart';
import 'main_screen.dart';

class BranchSelectionScreen extends StatefulWidget {
  final List<Branch> branches;

  const BranchSelectionScreen({super.key, required this.branches});

  @override
  State<BranchSelectionScreen> createState() => _BranchSelectionScreenState();
}

class _BranchSelectionScreenState extends State<BranchSelectionScreen> {
  bool _isSelecting = false;

  Future<void> _selectBranch(Branch branch) async {
    setState(() => _isSelecting = true);

    try {
      final authService = getIt<AuthService>();

      // Update global constants
      ApiConstants.branchId = branch.id;
      ApiConstants.currency = branch.taxObject.currency;

      // Persist the choice
      final token = authService.getToken();
      if (token != null) {
        // This will save the new branch ID and currency to SharedPreferences
        // We might need to expose a more direct method if this is too heavy
        await authService.initialize(
            force: true); // Reload and save logic inside
        // Actually AuthService needs a direct way to save just branch
      }

      // Instead of relying on internal private methods, we'll use a new method we'll add to AuthService
      await authService.updateActiveBranch(branch);

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MainScreen()),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              translationService.t(
                'branch_select_error',
                args: {'error': e},
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSelecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRTL = translationService.isRTL;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 500),
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  translationService.t('choose_branch_title'),
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  translationService.t('choose_branch_subtitle'),
                  style: const TextStyle(
                    fontSize: 16,
                    color: Color(0xFF64748B),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 40),
                Expanded(
                  child: ListView.separated(
                    itemCount: widget.branches.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final branch = widget.branches[index];
                      return InkWell(
                        onTap:
                            _isSelecting ? null : () => _selectBranch(branch),
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.02),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFF7ED),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.storefront,
                                  color: Color(0xFFF58220),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      branch.name,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF1E293B),
                                      ),
                                    ),
                                    Text(
                                      branch.district,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: Color(0xFF64748B),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                isRTL
                                    ? Icons.chevron_left
                                    : Icons.chevron_right,
                                color: const Color(0xFF94A3B8),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (_isSelecting)
                  const Padding(
                    padding: EdgeInsets.only(top: 20),
                    child: Center(child: CircularProgressIndicator()),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
