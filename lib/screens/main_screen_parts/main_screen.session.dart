// ignore_for_file: invalid_use_of_protected_member, unused_element, unused_element_parameter, dead_code, dead_null_aware_expression
part of '../main_screen.dart';

extension MainScreenSession on _MainScreenState {
  bool _canCallBranchApis() {
    final token = BaseClient().getToken();
    return token != null && token.isNotEmpty && ApiConstants.branchId > 0;
  }

  Future<void> _redirectToLogin() async {
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const LoginScreen()),
      (route) => false,
    );
  }

  Future<void> _bootstrapSessionAndLoad() async {
    if (_isBootstrappingSession) return;
    _isBootstrappingSession = true;

    try {
      final authService = getIt<AuthService>();
      final hasToken =
          await authService.ensureSessionReady(requireBranch: false);
      if (!hasToken) {
        await _redirectToLogin();
        return;
      }

      if (ApiConstants.branchId <= 0) {
        final branches = await authService.getBranches();
        if (!mounted) return;
        if (branches.isEmpty) {
          setState(() {
            _error = 'لا يوجد فرع متاح لهذا الحساب';
            _isLoading = false;
          });
          return;
        }

        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => BranchSelectionScreen(branches: branches),
          ),
        );
        return;
      }

      // Ensure branchModule is resolved (login response may lack it)
      if (ApiConstants.branchModule.isEmpty) {
        try {
          final authService = getIt<AuthService>();
          final branches = await authService.getBranches();
          final match = branches.where((b) => b.id == ApiConstants.branchId);
          if (match.isNotEmpty && match.first.module.isNotEmpty) {
            ApiConstants.branchModule = match.first.module;
          }
        } catch (_) {}
      }

      // PERF: parallelize the independent bootstrap calls. Cashier settings,
      // user profile, branch settings, and initial data have no inter-deps,
      // so run them concurrently instead of sequentially.
      final branchService = getIt<BranchService>();
      unawaited(branchService.getBranchSettings());
      unawaited(branchService.fetchAndCacheBranchReceiptInfo().then((_) {
        _prewarmReceiptCache();
      }));
      await Future.wait<void>([
        _loadCashierSettings(),
        _loadUserData(),
        _loadData(),
      ]);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    } finally {
      _isBootstrappingSession = false;
    }
  }

  void _prewarmReceiptCache() {
    final receiptInfo = getIt<BranchService>().cachedBranchReceiptInfo;
    if (receiptInfo == null) return;

    final branch = receiptInfo['branch'];
    if (branch is Map) {
      _cachedBranchMap = Map<String, dynamic>.from(branch);
      final seller = branch['seller'];
      final originalSeller = branch['original_seller'];
      if (seller is Map && (seller as Map).isNotEmpty) {
        _cachedSellerInfo ??= Map<String, dynamic>.from(seller);
      } else if (originalSeller is Map && (originalSeller as Map).isNotEmpty) {
        _cachedSellerInfo ??= Map<String, dynamic>.from(originalSeller);
      }
    }
    _cachedBranchAddressEn = receiptInfo['branch_address_en']?.toString();
    _cachedSellerNameEn = receiptInfo['seller_name_en']?.toString();
    debugPrint('✅ Receipt cache prewarmed (seller=${_cachedSellerInfo != null}, branch=${_cachedBranchMap != null})');
  }

  Future<void> _loadUserData() async {
    final authService = getIt<AuthService>();

    // First try from cached/stored data
    final cachedUser = authService.getUser();
    if (cachedUser != null) {
      _updateUserUI(cachedUser);
    }

    // Then fetch fresh profile from API
    try {
      final profile = await authService.getProfile();
      if (profile['data'] != null) {
        _updateUserUI(profile['data']);
      }
    } catch (e) {
      print('⚠️ Failed to fetch fresh profile: $e');
    }
  }

  void _updateUserUI(Map<String, dynamic> user) {
    _lastUserData = user.map((k, v) => MapEntry(k.toString(), v));
    final options = user['options'];
    final optionsMap = options is Map
        ? options.map((k, v) => MapEntry(k.toString(), v))
        : const <String, dynamic>{};
    final nearPayEnabledFromProfile = optionsMap['nearpay'] == true;
    getIt<DisplayAppService>().setProfileNearPayOption(
      nearPayEnabledFromProfile,
    );
    // Gate the local SDK on the same profile flag — mirrors what the reference
    // Display App does when it receives NEARPAY_INIT over WebSocket
    // (display_app/lib/services/socket_service.dart: setNearPayEnabled).
    NearPayConfigService().setNearPayEnabled(nearPayEnabledFromProfile);
    debugPrint(
      '🔷 Profile options: nearpay=$nearPayEnabledFromProfile '
      '(raw options keys: ${optionsMap.keys.join(',')})',
    );
    // Pre-warm the JWT cache so AUTH_CHALLENGE always gets a JWT immediately.
    if (nearPayEnabledFromProfile) {
      NearPayService().generateJwt().then((_) {}).catchError((Object e) {
        debugPrint('⚠️ NearPay JWT pre-warm failed: $e');
      });
      // Bootstrap the local NearPay SDK (same flow the reference Display App
      // runs after receiving NEARPAY_INIT over WebSocket).
      NearPayBootstrap.ensureInitialized().then((ok) {
        debugPrint(ok
            ? '✅ NearPayBootstrap: SDK ready'
            : '⚠️ NearPayBootstrap: SDK not ready (will retry on payment)');
      }).catchError((Object e) {
        debugPrint('⚠️ NearPayBootstrap init failed: $e');
      });
    }

    setState(() {
      _isProfileNearPayEnabled = nearPayEnabledFromProfile;
      final nameCandidates = _useArabicUi
          ? <dynamic>[
              user['fullname_ar'],
              user['seller_name_ar'],
              user['name_ar'],
              user['fullname'],
              user['seller_name'],
              user['name'],
              user['username'],
              user['fullname_en'],
              user['seller_name_en'],
              user['name_en'],
            ]
          : <dynamic>[
              user['fullname_en'],
              user['seller_name_en'],
              user['name_en'],
              user['fullname'],
              user['seller_name'],
              user['name'],
              user['username'],
              user['fullname_ar'],
              user['seller_name_ar'],
              user['name_ar'],
            ];
      _userName =
          _readLocalizedText(nameCandidates) ?? _trUi('المستخدم', 'User');

      final roleCandidates = _useArabicUi
          ? <dynamic>[
              user['role_display_ar'],
              user['role_ar'],
              user['role_display'],
              user['role'],
              user['role_display_en'],
              user['role_en'],
            ]
          : <dynamic>[
              user['role_display_en'],
              user['role_en'],
              user['role_display'],
              user['role'],
              user['role_display_ar'],
              user['role_ar'],
            ];
      _userRole =
          _readLocalizedText(roleCandidates) ?? _trUi('كاشير', 'Cashier');

      if (_userName.isNotEmpty) {
        final parts = _userName.trim().split(' ');
        if (parts.length > 1) {
          _initials = (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
        } else {
          _initials = _userName
              .substring(0, _userName.length > 1 ? 2 : 1)
              .toUpperCase();
        }
      }
    });
  }


  void _onLanguageChanged() {
    if (mounted) {
      if (_lastUserData != null) {
        _updateUserUI(_lastUserData!);
      }
      if (_canCallBranchApis()) {
        _loadData();
      }
    }
  }

  Future<void> _handleLogout() async {
    final authService = AuthService();

    // Show confirmation dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(translationService.t('logout_confirm_title')),
        content: Text(translationService.t('logout_confirm_message')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(translationService.t('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(translationService.t('logout')),
          ),
        ],
      ),
    );

    if (confirm == true) {
      // Show loading
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) =>
              const Center(child: CircularProgressIndicator()),
        );
      }

      await authService.logout();

      if (mounted) {
        // Clear navigation and go to login
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (route) => false,
        );
      }
    }
  }

  Future<void> _handleSwitchBranch() async {
    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final authService = getIt<AuthService>();
      final branches = await authService.getBranches();

      if (mounted) Navigator.pop(context); // Close loading

      if (branches.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(
            SnackBar(
                content: Text(translationService.t('no_branches_available'))),
          );
        }
        return;
      }

      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => BranchSelectionScreen(branches: branches),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(
          SnackBar(
            content: Text(
              translationService.t('branch_fetch_error', args: {'error': e}),
            ),
          ),
        );
      }
    }
  }
}
