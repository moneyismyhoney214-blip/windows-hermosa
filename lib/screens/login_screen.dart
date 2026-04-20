import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/api/auth_service.dart';
import '../services/api/base_client.dart';
import '../services/language_service.dart';
import '../services/app_themes.dart';
import '../locator.dart';
import '../models/branch.dart';
import 'branch_selection_screen.dart';
import 'forgot_password_screen.dart';
import 'main_screen.dart';
import '../waiter_module/waiter_module_entry.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  String? _errorMessage;
  bool _obscurePassword = true;

  /// Toggles the "Forgot password?" link under the password field. Kept as
  /// a named flag (instead of deleting the code) so we can re-enable the
  /// flow in one line once the backend side is fully ready.
  static const bool _showForgotPassword = false;

  @override
  void initState() {
    super.initState();
    translationService.addListener(_onLanguageChanged);
  }

  @override
  void dispose() {
    translationService.removeListener(_onLanguageChanged);
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _onLanguageChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  List<Branch> _mergeUniqueBranches(Iterable<Branch> source) {
    final byId = <int, Branch>{};
    for (final branch in source) {
      if (branch.id <= 0) continue;
      byId.putIfAbsent(branch.id, () => branch);
    }
    return byId.values.toList();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authService = getIt<AuthService>();
      print('🔐 Attempting login for: ${_emailController.text.trim()}');
      print('🔐 AuthService instance: ${authService.hashCode}');

      // Use loginWithEmail which maps email to username for the JWT API
      final result = await authService.loginWithEmail(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        rememberMe: 0,
      );

      print('🔐 Login API call completed');
      print('🔐 Login result: $result');

      // Verify token was set
      final token = BaseClient().getToken();
      print('🔐 Token after login: ${token != null ? "EXISTS" : "NULL"}');
      if (token == null || token.isEmpty) {
        throw Exception('Token not set after login');
      }

      print('✅ Login successful, token verified');

      // Extract branches from result
      List<Branch> branchesFromLogin = [];
      if (result['data'] != null && result['data']['branches'] is List) {
        branchesFromLogin = (result['data']['branches'] as List)
            .whereType<Map>()
            .map((e) =>
                Branch.fromJson(e.map((k, v) => MapEntry(k.toString(), v))))
            .toList();
      }

      List<Branch> branches = [];
      try {
        final fetched = await authService.getBranches();
        branches = _mergeUniqueBranches([...fetched, ...branchesFromLogin]);
      } catch (_) {
        // Keep flow resilient; main screen bootstrap handles final fallback.
        branches = branchesFromLogin;
      }

      if (mounted) {
        // Waiter accounts (role=WAITER on /seller/employees) skip the cashier
        // POS and land in the dedicated waiter module. With a single branch,
        // jump straight in; otherwise still show branch selection — that
        // screen will route waiters to WaiterModuleEntry on selection.
        final isWaiter = authService.isWaiter();

        if (isWaiter && branches.length <= 1) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const WaiterModuleEntry()),
          );
        } else if (branches.isNotEmpty) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => BranchSelectionScreen(branches: branches),
            ),
          );
        } else {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const MainScreen()),
          );
        }
      }
    } catch (e) {
      print('❌ Login error: $e');
      if (mounted) {
        setState(() {
          _errorMessage =
              '${translationService.t('login_error')}: ${e.toString()}';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final isSmallScreen = screenHeight < 600;
    final isDark = context.isDark;

    return Scaffold(
      backgroundColor: context.appBg,
      resizeToAvoidBottomInset: true,
      body: Directionality(
        textDirection:
            translationService.isRTL ? TextDirection.rtl : TextDirection.ltr,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: isSmallScreen ? 12 : 24,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight,
                  ),
                  child: IntrinsicHeight(
                    child: Column(
                      children: [
                        // Top Language Selector (Collapsed)
                        Align(
                          alignment: AlignmentDirectional.topEnd,
                          child: _buildLanguageDropdown(),
                        ),

                        Expanded(
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  constraints:
                                      const BoxConstraints(maxWidth: 400),
                                  padding:
                                      EdgeInsets.all(isSmallScreen ? 20 : 32),
                                  decoration: BoxDecoration(
                                    color: context.appCardBg,
                                    borderRadius: BorderRadius.circular(24),
                                    border: Border.all(
                                      color: context.appBorder,
                                      width: 1,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                            alpha: isDark ? 0.4 : 0.05),
                                        blurRadius: 20,
                                        offset: const Offset(0, 10),
                                      ),
                                    ],
                                  ),
                                  child: Form(
                                    key: _formKey,
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Text(
                                          translationService.t('login'),
                                          style: GoogleFonts.tajawal(
                                            fontSize: isSmallScreen ? 24 : 28,
                                            fontWeight: FontWeight.bold,
                                            color: context.appText,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                        SizedBox(height: isSmallScreen ? 4 : 8),
                                        Text(
                                          translationService
                                              .t('welcome_subtitle'),
                                          style: GoogleFonts.tajawal(
                                            fontSize: isSmallScreen ? 14 : 16,
                                            color: context.appTextMuted,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                        SizedBox(
                                            height: isSmallScreen ? 20 : 32),
                                        if (_errorMessage != null)
                                          Container(
                                            margin: const EdgeInsets.only(
                                                bottom: 16),
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              color: isDark
                                                  ? const Color(0xFF3B1717)
                                                  : const Color(0xFFFEE2E2),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              border: Border.all(
                                                  color: context.appDanger
                                                      .withValues(alpha: 0.3)),
                                            ),
                                            child: Row(
                                              children: [
                                                Icon(Icons.error_outline,
                                                    color: context.appDanger,
                                                    size: 20),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    _errorMessage!,
                                                    style: GoogleFonts.tajawal(
                                                      color: isDark
                                                          ? const Color(
                                                              0xFFFCA5A5)
                                                          : const Color(
                                                              0xFF7F1D1D),
                                                      fontSize: 13,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        TextFormField(
                                          controller: _emailController,
                                          keyboardType:
                                              TextInputType.emailAddress,
                                          textDirection: TextDirection.ltr,
                                          style: TextStyle(
                                              color: context.appText),
                                          decoration: InputDecoration(
                                            labelText:
                                                translationService.t('email'),
                                            hintText: 'example@email.com',
                                            filled: true,
                                            fillColor: context.appSurfaceAlt,
                                            prefixIcon: Icon(
                                                Icons.email_outlined,
                                                color: context.appTextMuted),
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              borderSide: BorderSide(
                                                  color: context.appBorder),
                                            ),
                                            enabledBorder: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              borderSide: BorderSide(
                                                  color: context.appBorder),
                                            ),
                                            focusedBorder: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              borderSide: BorderSide(
                                                  color: context.appPrimary,
                                                  width: 1.5),
                                            ),
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                    horizontal: 16,
                                                    vertical: 14),
                                          ),
                                          validator: (value) {
                                            if (value == null ||
                                                value.isEmpty) {
                                              return translationService
                                                  .t('required');
                                            }
                                            if (!value.contains('@')) {
                                              return translationService
                                                  .t('invalid_email');
                                            }
                                            return null;
                                          },
                                        ),
                                        const SizedBox(height: 16),
                                        TextFormField(
                                          controller: _passwordController,
                                          obscureText: _obscurePassword,
                                          style: TextStyle(
                                              color: context.appText),
                                          decoration: InputDecoration(
                                            labelText: translationService
                                                .t('password'),
                                            filled: true,
                                            fillColor: context.appSurfaceAlt,
                                            prefixIcon: Icon(Icons.lock_outline,
                                                color: context.appTextMuted),
                                            suffixIcon: IconButton(
                                              icon: Icon(
                                                  _obscurePassword
                                                      ? Icons.visibility_outlined
                                                      : Icons
                                                          .visibility_off_outlined,
                                                  color: context.appTextMuted),
                                              onPressed: () => setState(() =>
                                                  _obscurePassword =
                                                      !_obscurePassword),
                                            ),
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              borderSide: BorderSide(
                                                  color: context.appBorder),
                                            ),
                                            enabledBorder: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              borderSide: BorderSide(
                                                  color: context.appBorder),
                                            ),
                                            focusedBorder: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              borderSide: BorderSide(
                                                  color: context.appPrimary,
                                                  width: 1.5),
                                            ),
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                    horizontal: 16,
                                                    vertical: 14),
                                          ),
                                          validator: (value) => value == null ||
                                                  value.isEmpty
                                              ? translationService.t('required')
                                              : null,
                                          onFieldSubmitted: (_) => _login(),
                                        ),
                                        // "Forgot password?" link is hidden
                                        // temporarily while the backend
                                        // wires up the full flow. Flip
                                        // `_showForgotPassword` to true (or
                                        // delete this guard) to restore the
                                        // button — the navigation target and
                                        // screen are still in place.
                                        if (_showForgotPassword)
                                          Align(
                                            alignment: AlignmentDirectional
                                                .centerStart,
                                            child: TextButton(
                                              onPressed: _isLoading
                                                  ? null
                                                  : () {
                                                      Navigator.of(context).push(
                                                        MaterialPageRoute(
                                                          builder: (_) =>
                                                              const ForgotPasswordScreen(),
                                                        ),
                                                      );
                                                    },
                                              style: TextButton.styleFrom(
                                                padding: EdgeInsets.zero,
                                                minimumSize: const Size(0, 32),
                                                tapTargetSize:
                                                    MaterialTapTargetSize
                                                        .shrinkWrap,
                                                foregroundColor:
                                                    context.appPrimary,
                                              ),
                                              child: Text(
                                                translationService
                                                    .t('forgot_password'),
                                                style: GoogleFonts.tajawal(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          ),
                                        SizedBox(
                                            height: isSmallScreen ? 16 : 24),
                                        SizedBox(
                                          height: 48,
                                          child: ElevatedButton(
                                            onPressed:
                                                _isLoading ? null : _login,
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor:
                                                  context.appPrimary,
                                              foregroundColor: Colors.white,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              elevation: 0,
                                            ),
                                            child: _isLoading
                                                ? const SizedBox(
                                                    width: 24,
                                                    height: 24,
                                                    child:
                                                        CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      color: Colors.white,
                                                    ),
                                                  )
                                                : Text(
                                                    translationService
                                                        .t('login'),
                                                    style: GoogleFonts.tajawal(
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildLanguageDropdown() {
    final currentLang = SupportedLanguages.getByCode(
        translationService.currentLocale.languageCode);
    final isDark = context.isDark;

    return PopupMenuButton<String>(
      onSelected: (code) => translationService.setLanguage(code),
      offset: const Offset(0, 40),
      color: context.appCardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: context.appCardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.appBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.language, size: 18, color: context.appPrimary),
            const SizedBox(width: 8),
            Text(
              currentLang.nativeName,
              style: GoogleFonts.tajawal(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: context.appText,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.keyboard_arrow_down,
                size: 18, color: context.appTextMuted),
          ],
        ),
      ),
      itemBuilder: (context) => SupportedLanguages.all.map((lang) {
        final isSelected =
            translationService.currentLocale.languageCode == lang.code;
        return PopupMenuItem<String>(
          value: lang.code,
          child: Row(
            children: [
              Text(
                lang.nativeName,
                style: GoogleFonts.tajawal(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? context.appPrimary : context.appText,
                ),
              ),
              if (isSelected) ...[
                const Spacer(),
                Icon(Icons.check, size: 16, color: context.appPrimary),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }
}
