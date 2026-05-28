// ignore_for_file: avoid_dynamic_calls
//
// JSON wire-boundary / message-dispatch layer — dynamic accesses here are
// known and accepted pending the typed-model refactor planned in
// audit_2026_05_19.md (split models.dart, introduce concrete DTOs).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../locator.dart';
import '../models/branch.dart';
import '../services/api/auth_service.dart';
import '../services/api/base_client.dart';
import '../services/app_themes.dart';
import '../services/language_service.dart';
import '../services/logger_service.dart';
import '../services/security/secure_token_store.dart';
import '../waiter_module/waiter_module_entry.dart';
import 'branch_selection_screen.dart';
import 'forgot_password_screen.dart';
import 'legal_page_screen.dart';
import 'main_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _emailFocusNode = FocusNode();
  bool _isLoading = false;
  String? _errorMessage;
  bool _obscurePassword = true;
  bool _rememberMe = true;
  List<SavedAccount> _savedAccounts = const [];

  /// Toggles the "Forgot password?" link under the password field. Kept as
  /// a named flag (instead of deleting the code) so we can re-enable the
  /// flow in one line once the backend side is fully ready.
  static const bool _showForgotPassword = true;

  @override
  void initState() {
    super.initState();
    translationService.addListener(_onLanguageChanged);
    unawaited(_loadSavedAccounts());
  }

  Future<void> _loadSavedAccounts() async {
    final accounts = await secureTokenStore.readAccounts();
    if (!mounted) return;
    setState(() {
      _savedAccounts = accounts;
    });
    // Fields stay blank on purpose — after logout the user expects an
    // empty form. Picking a row from the dropdown is the only thing that
    // fills both email + password.
  }

  void _applySavedAccount(SavedAccount account) {
    _emailController.text = account.email;
    _passwordController.text = account.password;
    _emailFocusNode.unfocus();
    setState(() {});
  }

  Future<void> _forgetAccount(SavedAccount account) async {
    await secureTokenStore.deleteAccount(account.email);
    if (!mounted) return;
    setState(() {
      _savedAccounts = _savedAccounts
          .where((a) => a.email.toLowerCase() != account.email.toLowerCase())
          .toList();
    });
  }

  Future<void> _clearAllSavedAccounts() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(translationService.t('clear_all_accounts')),
        content: Text(translationService.t('clear_all_accounts_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(translationService.t('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: context.appDanger),
            child: Text(translationService.t('delete')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await secureTokenStore.clearAccounts();
    if (!mounted) return;
    setState(() => _savedAccounts = const []);
  }

  void _openManageAccountsSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.appCardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            Future<void> removeOne(SavedAccount account) async {
              await secureTokenStore.deleteAccount(account.email);
              if (!mounted) return;
              setState(() {
                _savedAccounts = _savedAccounts
                    .where((a) =>
                        a.email.toLowerCase() != account.email.toLowerCase())
                    .toList();
              });
              // The bottom sheet keeps its own snapshot; refresh it too.
              setSheetState(() {});
              if (sheetContext.mounted) {
                ScaffoldMessenger.of(sheetContext).showSnackBar(
                  SnackBar(
                    content:
                        Text(translationService.t('account_deleted')),
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            }

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.manage_accounts_outlined,
                            color: context.appPrimary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            translationService.t('saved_accounts'),
                            style: GoogleFonts.tajawal(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: context.appText,
                            ),
                          ),
                        ),
                        if (_savedAccounts.isNotEmpty)
                          TextButton.icon(
                            onPressed: () async {
                              Navigator.of(sheetContext).pop();
                              await _clearAllSavedAccounts();
                            },
                            icon: Icon(Icons.delete_sweep_outlined,
                                size: 18, color: context.appDanger),
                            label: Text(
                              translationService.t('clear_all_accounts'),
                              style: GoogleFonts.tajawal(
                                fontSize: 12,
                                color: context.appDanger,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              minimumSize: const Size(0, 32),
                              tapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_savedAccounts.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: Center(
                          child: Text(
                            translationService.t('no_saved_accounts'),
                            style: TextStyle(color: context.appTextMuted),
                          ),
                        ),
                      )
                    else
                      ConstrainedBox(
                        constraints:
                            const BoxConstraints(maxHeight: 360),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: _savedAccounts.length,
                          separatorBuilder: (_, __) => Divider(
                            height: 1,
                            color: context.appBorder,
                          ),
                          itemBuilder: (context, index) {
                            final account = _savedAccounts[index];
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 4),
                              leading: CircleAvatar(
                                backgroundColor:
                                    context.appPrimary.withValues(alpha: 0.12),
                                child: Icon(Icons.person_outline,
                                    color: context.appPrimary),
                              ),
                              title: Text(
                                account.email,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: context.appText,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                '••••••••',
                                style: TextStyle(
                                  color: context.appTextMuted,
                                  letterSpacing: 1.5,
                                ),
                              ),
                              trailing: IconButton(
                                tooltip: translationService.t('delete'),
                                icon: Icon(Icons.delete_outline,
                                    color: context.appDanger),
                                onPressed: () => removeOne(account),
                              ),
                              onTap: () {
                                Navigator.of(sheetContext).pop();
                                _applySavedAccount(account);
                              },
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    translationService.removeListener(_onLanguageChanged);
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocusNode.dispose();
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
      // No PII/token material in breadcrumbs.
      Log.d('login', 'attempting authentication');

      final result = await authService.loginWithEmail(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        rememberMe: 0,
      );

      final token = BaseClient().getToken();
      if (token == null || token.isEmpty) {
        throw Exception('Token not set after login');
      }
      Log.d('login', 'token verified after login');

      // Persist credentials only after the server confirms they're valid,
      // so the autocomplete dropdown has a verified entry next time.
      if (_rememberMe) {
        await secureTokenStore.upsertAccount(
          _emailController.text.trim(),
          _passwordController.text,
        );
      } else {
        await secureTokenStore.deleteAccount(_emailController.text.trim());
      }

      List<Branch> branchesFromLogin = [];
      if (result['data'] != null && result['data']['branches'] is List) {
        branchesFromLogin = (result['data']['branches'] as List)
            .whereType<Map>()
            .map((e) =>
                Branch.fromJson(e.map((k, v) => MapEntry(k.toString(), v))))
            .toList();
      }

      // WAITERs lack /seller/branches permission — hitting it 401s and BaseClient's onUnauthorized signs them out. Login payload already embeds their branches; skip the fetch.
      final isWaiter = authService.isWaiter();
      List<Branch> branches = branchesFromLogin;
      if (!isWaiter) {
        try {
          final fetched = await authService.getBranches();
          branches = _mergeUniqueBranches([...fetched, ...branchesFromLogin]);
        } catch (e) {
          Log.d('catch', 'non-fatal: $e');
          branches = branchesFromLogin;
        }
      }

      if (mounted) {
        // Waiters skip the cashier POS for the dedicated waiter module (single branch jumps straight in).

        if (isWaiter && branches.length <= 1) {
          unawaited(Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const WaiterModuleEntry()),
          ));
        } else if (branches.isNotEmpty) {
          unawaited(Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => BranchSelectionScreen(branches: branches),
            ),
          ));
        } else {
          unawaited(Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const MainScreen()),
          ));
        }
      }
    } catch (e, st) {
      Log.e('login', 'authentication failed', error: e, stackTrace: st);
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
                                        _buildEmailAutocompleteField(
                                            isDark: isDark),
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
                                        const SizedBox(height: 4),
                                        InkWell(
                                          onTap: _isLoading
                                              ? null
                                              : () => setState(() =>
                                                  _rememberMe = !_rememberMe),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 6),
                                            child: Row(
                                              children: [
                                                SizedBox(
                                                  width: 22,
                                                  height: 22,
                                                  child: Checkbox(
                                                    value: _rememberMe,
                                                    onChanged: _isLoading
                                                        ? null
                                                        : (v) => setState(() =>
                                                            _rememberMe =
                                                                v ?? false),
                                                    activeColor:
                                                        context.appPrimary,
                                                    materialTapTargetSize:
                                                        MaterialTapTargetSize
                                                            .shrinkWrap,
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Text(
                                                  translationService
                                                      .t('remember_me'),
                                                  style: GoogleFonts.tajawal(
                                                    fontSize: 13,
                                                    color: context.appText,
                                                    fontWeight:
                                                        FontWeight.w500,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            // Forgot-password is hidden pending backend wiring; flip `_showForgotPassword` to restore.
                                            if (_showForgotPassword)
                                              TextButton(
                                                onPressed: _isLoading
                                                    ? null
                                                    : () {
                                                        Navigator.of(context)
                                                            .push(
                                                          MaterialPageRoute(
                                                            builder: (_) =>
                                                                const ForgotPasswordScreen(),
                                                          ),
                                                        );
                                                      },
                                                style: TextButton.styleFrom(
                                                  padding: EdgeInsets.zero,
                                                  minimumSize:
                                                      const Size(0, 32),
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
                                                    fontWeight:
                                                        FontWeight.w600,
                                                  ),
                                                ),
                                              )
                                            else
                                              const SizedBox.shrink(),
                                            if (_savedAccounts.isNotEmpty)
                                              TextButton.icon(
                                                onPressed: _isLoading
                                                    ? null
                                                    : _openManageAccountsSheet,
                                                icon: Icon(
                                                  Icons.manage_accounts_outlined,
                                                  size: 16,
                                                  color: context.appTextMuted,
                                                ),
                                                style: TextButton.styleFrom(
                                                  padding: EdgeInsets.zero,
                                                  minimumSize:
                                                      const Size(0, 32),
                                                  tapTargetSize:
                                                      MaterialTapTargetSize
                                                          .shrinkWrap,
                                                  foregroundColor:
                                                      context.appTextMuted,
                                                ),
                                                label: Text(
                                                  translationService.t(
                                                      'manage_saved_accounts'),
                                                  style: GoogleFonts.tajawal(
                                                    fontSize: 12,
                                                    fontWeight:
                                                        FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                          ],
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
                        const SizedBox(height: 16),
                        _buildLegalLinks(),
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

  /// Email input with a Google-style autocomplete dropdown of previously
  /// saved accounts. Filters by case-insensitive prefix or substring on
  /// the email. Selecting an entry auto-fills the password field too.
  Widget _buildEmailAutocompleteField({required bool isDark}) {
    return RawAutocomplete<SavedAccount>(
      textEditingController: _emailController,
      focusNode: _emailFocusNode,
      displayStringForOption: (account) => account.email,
      optionsBuilder: (textEditingValue) {
        if (_savedAccounts.isEmpty) {
          return const Iterable<SavedAccount>.empty();
        }
        final q = textEditingValue.text.trim().toLowerCase();
        // Empty field → show every saved account (full list on first focus).
        if (q.isEmpty) return _savedAccounts;
        // One exact match means "you've already picked this one" → hide the
        // dropdown so it doesn't cover the password field.
        final lowered =
            _savedAccounts.map((a) => a.email.toLowerCase()).toList();
        if (lowered.length == 1 && lowered.first == q) {
          return const Iterable<SavedAccount>.empty();
        }
        return _savedAccounts
            .where((a) => a.email.toLowerCase().contains(q))
            .toList();
      },
      onSelected: _applySavedAccount,
      fieldViewBuilder:
          (context, controller, focusNode, onFieldSubmitted) {
        return TextFormField(
          controller: controller,
          focusNode: focusNode,
          keyboardType: TextInputType.emailAddress,
          textDirection: TextDirection.ltr,
          style: TextStyle(color: context.appText),
          decoration: InputDecoration(
            labelText: translationService.t('email'),
            hintText: 'example@email.com',
            filled: true,
            fillColor: context.appSurfaceAlt,
            prefixIcon:
                Icon(Icons.email_outlined, color: context.appTextMuted),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: context.appBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: context.appBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  BorderSide(color: context.appPrimary, width: 1.5),
            ),
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 14),
          ),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return translationService.t('required');
            }
            if (!value.contains('@')) {
              return translationService.t('invalid_email');
            }
            return null;
          },
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: AlignmentDirectional.topStart,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            color: context.appCardBg,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240, maxWidth: 400),
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: options.length,
                separatorBuilder: (_, __) => Divider(
                  height: 1,
                  color: context.appBorder,
                ),
                itemBuilder: (context, index) {
                  final account = options.elementAt(index);
                  return InkWell(
                    onTap: () => onSelected(account),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      child: Row(
                        children: [
                          Icon(Icons.key_outlined,
                              size: 18, color: context.appPrimary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  account.email,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: context.appText,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '••••••••',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: context.appTextMuted,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: translationService.t('delete'),
                            visualDensity: VisualDensity.compact,
                            icon: Icon(Icons.close,
                                size: 18, color: context.appTextMuted),
                            onPressed: () => _forgetAccount(account),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLegalLinks() {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 4,
      children: [
        _legalLink(
          label: translationService.t('privacy_policy'),
          slug: 'privacy-policy',
        ),
        Text(
          '•',
          style: GoogleFonts.tajawal(
            fontSize: 12,
            color: context.appTextMuted,
          ),
        ),
        _legalLink(
          label: translationService.t('terms_conditions'),
          slug: 'terms-conditions',
        ),
      ],
    );
  }

  Widget _legalLink({required String label, required String slug}) {
    return TextButton(
      onPressed: _isLoading ? null : () => _openLegalPage(slug, label),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: const Size(0, 28),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: context.appPrimary,
      ),
      child: Text(
        label,
        style: GoogleFonts.tajawal(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          decoration: TextDecoration.underline,
        ),
      ),
    );
  }

  /// Open the static legal page in-app. Content is fetched from
  /// `portal.hermosaapp.com/staticPages/<slug>` (locale follows the
  /// active `Accept-Language`) and rendered as HTML. The screen also
  /// exposes an "open in browser" action that points at the canonical
  /// `v2.hermosaapp.com/pages/<slug>` web copy.
  void _openLegalPage(String slug, String fallbackTitle) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LegalPageScreen(
          slug: slug,
          fallbackTitle: fallbackTitle,
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
