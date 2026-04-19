import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'Splash/splash_screen.dart';
import 'screens/login_screen.dart';
import 'services/api/auth_service.dart';
import 'services/api/base_client.dart';
import 'services/language_service.dart';
import 'services/theme_service.dart';
import 'services/printer_language_settings_service.dart';
import 'services/app_themes.dart';
import 'services/cashier_sound_service.dart';
import 'services/presentation_service.dart';
import 'services/offline/offline_database_service.dart';
import 'services/offline/offline_pos_database.dart';
import 'services/offline/connectivity_service.dart';
import 'services/offline/sync_service.dart';
import 'widgets/print_listener.dart';
import 'customer_display/customer_display_main.dart';

import 'locator.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Check if this engine is running on the secondary display.
  // The native side sets this flag before launching the engine.
  final isSecondaryDisplay = await _checkIfSecondaryDisplay();

  if (isSecondaryDisplay) {
    // Run the lightweight customer display UI — no locator, no auth, no plugins.
    runApp(const CustomerDisplayApp());
    return;
  }

  // Initialize sqflite FFI for desktop platforms (Linux, Windows, macOS)
  if (!kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
    try {
      final sqfliteFfi = await _initSqfliteFfi();
      if (sqfliteFfi) debugPrint('✅ sqflite FFI initialized for desktop');
    } catch (e) {
      debugPrint('⚠️ sqflite FFI init failed (non-fatal): $e');
    }
  }

  // Primary display — run the full cashier app.
  var isAuthenticated = false;
  var locatorReady = false;

  try {
    setupLocator();
    locatorReady = true;
  } catch (e, stackTrace) {
    debugPrint('❌ Locator setup failed: $e');
    debugPrintStack(stackTrace: stackTrace);
  }

  // Initialize offline services (non-critical — may fail on Linux)
  try {
    await OfflineDatabaseService().initialize();
    debugPrint('Offline database initialized');
  } catch (e) {
    debugPrint('⚠️ Offline database init (non-fatal): $e');
  }

  // Initialize the bundled POS database (copies from assets on first run)
  try {
    await OfflinePosDatabase().initialize();
    debugPrint('Offline POS database initialized');
  } catch (e) {
    debugPrint('⚠️ Offline POS database init (non-fatal): $e');
  }

  try {
    await ConnectivityService().initialize();
    debugPrint('Connectivity service initialized');
  } catch (e) {
    debugPrint('⚠️ Connectivity service init (non-fatal): $e');
  }

  try {
    await SyncService().initialize();
    debugPrint('Sync service initialized');
  } catch (e) {
    debugPrint('⚠️ Sync service init (non-fatal): $e');
  }

  // Critical: language must always load
  try {
    await translationService.initialize();
  } catch (e) {
    debugPrint('⚠️ Translation init failed: $e');
  }

  // Load persisted theme preference (non-critical — defaults to light)
  try {
    await themeService.initialize();
  } catch (e) {
    debugPrint('⚠️ Theme init (non-fatal): $e');
  }

  // Load persisted printer language preference (non-critical — defaults to ar/en)
  try {
    await printerLanguageSettings.initialize();
  } catch (e) {
    debugPrint('⚠️ Printer language init (non-fatal): $e');
  }

  // Critical: auth must always load to restore login state
  try {
    if (locatorReady) {
      if (!getIt.isRegistered<CashierSoundService>()) {
        getIt.registerLazySingleton<CashierSoundService>(
          () => CashierSoundService(),
        );
      }
      await getIt<CashierSoundService>().initialize();
    }
  } catch (e) {
    debugPrint('⚠️ Sound service init (non-fatal): $e');
  }

  try {
    if (locatorReady) {
      final authService = getIt<AuthService>();
      await authService.initialize(force: true);
      isAuthenticated = await authService.isAuthenticated();
    }
  } catch (e) {
    debugPrint('⚠️ Auth service init failed: $e');
  }

  // Initialize Presentation API for dual-screen devices (e.g. Sunmi D2s).
  try {
    final presentationService = PresentationService();
    await presentationService.initialize();
    if (presentationService.hasSecondaryDisplay) {
      debugPrint(
          '🖥️ Dual-screen device detected — launching customer display');
      await presentationService.showPresentation();
    }
  } catch (e) {
    debugPrint('⚠️ Presentation init (non-fatal): $e');
  }

  BaseClient.onUnauthorized = () async {
    print('🚫 onUnauthorized callback triggered - logging out');
    try {
      if (!locatorReady || !getIt.isRegistered<AuthService>()) return;
      final authService = getIt<AuthService>();
      await authService.logout();
      if (navigatorKey.currentState != null) {
        navigatorKey.currentState!.pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      debugPrint('⚠️ onUnauthorized handling failed: $e');
    }
  };

  runApp(HermosaPosApp(isAuthenticated: isAuthenticated));
}

/// Ask the native side if we are running on a secondary display.
/// The native side responds true for the secondary engine.
Future<bool> _initSqfliteFfi() async {
  try {
    // ignore: depend_on_referenced_packages
    // ignore: unused_import
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    return true;
  } catch (e) {
    debugPrint('⚠️ sqflite FFI setup error: $e');
    return false;
  }
}

Future<bool> _checkIfSecondaryDisplay() async {
  try {
    const channel = MethodChannel('com.hermosaapp.presentation');
    final result = await channel.invokeMethod<bool>('isSecondaryEngine');
    return result ?? false;
  } catch (_) {
    // Channel not set up = primary engine
    return false;
  }
}

class HermosaPosApp extends StatefulWidget {
  final bool isAuthenticated;
  const HermosaPosApp({super.key, required this.isAuthenticated});

  @override
  State<HermosaPosApp> createState() => _HermosaPosAppState();
}

class _HermosaPosAppState extends State<HermosaPosApp> {
  @override
  void initState() {
    super.initState();
    translationService.addListener(_onLocaleChange);
    themeService.addListener(_onThemeChange);
  }

  @override
  void dispose() {
    translationService.removeListener(_onLocaleChange);
    themeService.removeListener(_onThemeChange);
    super.dispose();
  }

  void _onLocaleChange() {
    setState(() {});
  }

  void _onThemeChange() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final currentLocale = translationService.currentLocale;
    final isRTL = translationService.isRTL;

    return MaterialApp(
      navigatorKey: navigatorKey,
      title: translationService.t('app_name'),
      debugShowCheckedModeBanner: false,
      locale: currentLocale,
      supportedLocales: SupportedLanguages.all.map((l) => l.locale).toList(),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      themeMode: themeService.themeMode,
      theme: AppThemes.light(isRTL: isRTL),
      darkTheme: AppThemes.dark(isRTL: isRTL),
      builder: (context, child) {
        return PrintListener(child: child!);
      },
      home: SplashScreen(isAuthenticated: widget.isAuthenticated),
    );
  }
}
