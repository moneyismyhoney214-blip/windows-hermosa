// ignore_for_file: invalid_use_of_protected_member, unused_element, unused_element_parameter, dead_code, dead_null_aware_expression, library_private_types_in_public_api
part of '../main_screen.dart';

extension MainScreenSession on _MainScreenState {
  bool _canCallBranchApis() {
    final token = BaseClient().getToken();
    return token != null && token.isNotEmpty && ApiConstants.branchId > 0;
  }

  /// Join the waiter LAN mesh as a viewer so the cashier can broadcast
  /// printer + KDS config to waiters. Safe to call repeatedly — the
  /// bootstrap is idempotent and the controller restarts on branch
  /// change internally.
  void _startCashierMesh() {
    if (ApiConstants.branchId <= 0) return;
    final CashierMeshBootstrap bootstrap;
    try {
      bootstrap = getIt<CashierMeshBootstrap>();
    } catch (e) {
      Log.d('catch', 'non-fatal: $e');
      return;
    }
    bootstrap.setDevicesProvider(() => _devices);
    final user = getIt<AuthService>().getUser();
    final rawName = user?['name']?.toString().trim() ?? '';
    final name = rawName.isNotEmpty ? rawName : 'Cashier';
    unawaited(bootstrap.start(
      name: name,
      branchId: ApiConstants.branchId.toString(),
    ));
  }

  /// Notify every waiter that the cashier's printer config just
  /// changed. Called from the add/edit/remove callsites in
  /// [MainScreenDevices] and the printers tab view.
  void _broadcastCashierPrintersConfig() {
    try {
      final bootstrap = getIt<CashierMeshBootstrap>();
      if (!bootstrap.isStarted) return;
      unawaited(bootstrap.broadcastKitchenPrintersConfig());
    } catch (e) {
      Log.d('MainScreenSession', 'broadcast cashier printers config failed (non-fatal): $e');
    }
  }

  Future<void> _redirectToLogin() async {
    if (!mounted) return;
    unawaited(Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const LoginScreen()),
      (route) => false,
    ));
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

        unawaited(Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => BranchSelectionScreen(branches: branches),
          ),
        ));
        return;
      }

      // Refresh branchModule + haveWaiters from /seller/branches — login response lacks these keys.
      try {
        final authService = getIt<AuthService>();
        final branches = await authService.getBranches();
        final match = branches.where((b) => b.id == ApiConstants.branchId);
        if (match.isNotEmpty) {
          final active = match.first;
          if (active.module.isNotEmpty) {
            ApiConstants.branchModule = active.module;
          }
          await authService.persistHaveWaiters(active.haveWaiters);
          await authService.persistWhatsappEnabled(active.whatsappStatus);
        }
      } catch (e) {
        Log.d('MainScreenSession', 'refresh branchModule/haveWaiters failed (non-fatal): $e');
      }

      // Mesh viewer runs in parallel with bootstrap; printer snapshot via provider keeps device list live.
      _startCashierMesh();

      // PERF: parallelise bootstrap (no inter-deps between these calls).
      final branchService = getIt<BranchService>();
      unawaited(branchService.getBranchSettings());
      // Tax refresh wins over login-payload values when VAT settings change between sessions.
      unawaited(branchService.refreshTaxConfig());
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
      if (seller is Map && (seller).isNotEmpty) {
        _cachedSellerInfo ??= Map<String, dynamic>.from(seller);
      } else if (originalSeller is Map && (originalSeller).isNotEmpty) {
        _cachedSellerInfo ??= Map<String, dynamic>.from(originalSeller);
      }
    }
    _cachedBranchAddressEn = receiptInfo['branch_address_en']?.toString();
    _cachedSellerNameEn = receiptInfo['seller_name_en']?.toString();
    debugPrint('✅ Receipt cache prewarmed (seller=${_cachedSellerInfo != null}, branch=${_cachedBranchMap != null})');
  }

  Future<void> _loadUserData() async {
    final authService = getIt<AuthService>();

    final cachedUser = authService.getUser();
    if (cachedUser != null) {
      _updateUserUI(cachedUser);
    }

    try {
      final profile = await authService.getProfile();
      if (profile['data'] != null) {
        _updateUserUI(profile['data']);
      }
    } catch (e) {
      Log.w('session', 'failed to fetch fresh profile', error: e);
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
    // Gate local SDK on the profile flag — mirrors Display App's NEARPAY_INIT handler.
    NearPayConfigService().setNearPayEnabled(nearPayEnabledFromProfile);
    debugPrint(
      '🔷 Profile options: nearpay=$nearPayEnabledFromProfile '
      '(raw options keys: ${optionsMap.keys.join(',')})',
    );
    // Pre-warm JWT cache so AUTH_CHALLENGE gets a JWT immediately.
    if (nearPayEnabledFromProfile) {
      NearPayService().generateJwt().then((_) {}).catchError((Object e) {
        debugPrint('⚠️ NearPay JWT pre-warm failed: $e');
      });
      // Bootstrap local NearPay SDK (matches Display App's NEARPAY_INIT flow).
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
      if (mounted) {
        unawaited(showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) =>
              const Center(child: CircularProgressIndicator()),
        ));
      }

      await authService.logout();

      if (mounted) {
        unawaited(Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (route) => false,
        ));
      }
    }
  }

  Future<void> _handleSwitchBranch() async {
    unawaited(showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    ));

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
                duration: const Duration(seconds: 3),
                content: Text(translationService.t('no_branches_available'))),
          );
        }
        return;
      }

      if (mounted) {
        unawaited(Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => BranchSelectionScreen(branches: branches),
          ),
        ));
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 3),
            content: Text(
              translationService.t('branch_fetch_error', args: {'error': e}),
            ),
          ),
        );
      }
    }
  }
}
