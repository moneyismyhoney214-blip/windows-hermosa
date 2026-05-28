import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'Splash/splash_screen.dart';
// Keeps customer_display_main.dart in the kernel snapshot — MainActivity.kt boots it on a secondary engine.
// ignore: unused_import
import 'customer_display/customer_display_main.dart';
import 'locator.dart';
import 'screens/login_screen.dart';
import 'services/api/auth_service.dart';
import 'services/api/base_client.dart';
import 'services/api/device_service.dart';
import 'services/api/product_service.dart';
import 'services/app_themes.dart';
import 'services/cashier_sound_service.dart';
import 'services/language_service.dart';
import 'services/logger_service.dart';
import 'services/observability/crash_reporter.dart';
import 'services/observability/sentry_crash_reporter.dart';
import 'services/offline/connectivity_service.dart';
import 'services/offline/offline_database_service.dart';
import 'services/offline/offline_pos_database.dart';
import 'services/offline/sync_service.dart';
import 'services/presentation_service.dart';
import 'services/printer_language_settings_service.dart';
import 'services/theme_service.dart';
import 'widgets/print_listener.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// `main` here runs on primary cashier engine only; secondary display boots customerDisplayMain.
void main() {
  // Guarded zone funnels uncaught async exceptions through the logger.
  runZonedGuarded<Future<void>>(_bootstrap, (error, stackTrace) {
    Log.e('zone', 'uncaught async exception', error: error, stackTrace: stackTrace);
  });
}

Future<void> _bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  // File reporter by default; Sentry fans out when --dart-define=SENTRY_DSN was set at build.
  if (SentryCrashReporter.isEnabled) {
    await SentryCrashReporter.bootstrap(existing: FileCrashReporter());
  } else {
    CrashReporter.wireUp();
  }

  FlutterError.onError = (FlutterErrorDetails details) {
    Log.e('flutter',
        details.exceptionAsString(),
        error: details.exception, stackTrace: details.stack);
    FlutterError.presentError(details);
  };

  // Engine/platform errors — returning true tells engine we handled it.
  WidgetsBinding.instance.platformDispatcher.onError = (error, stackTrace) {
    Log.e('platform', 'unhandled platform error',
        error: error, stackTrace: stackTrace);
    return true;
  };

  if (!kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
    try {
      final sqfliteFfi = await _initSqfliteFfi();
      if (sqfliteFfi) Log.i('boot', 'sqflite FFI initialized for desktop');
    } catch (e, st) {
      Log.w('boot', 'sqflite FFI init failed (non-fatal)', error: e);
      Log.e('boot', 'sqflite FFI init stack', error: e, stackTrace: st);
    }
  }

  var isAuthenticated = false;
  var locatorReady = false;

  try {
    setupLocator();
    locatorReady = true;
  } catch (e, stackTrace) {
    Log.e('boot', 'locator setup failed', error: e, stackTrace: stackTrace);
  }

  // Run independent inits in parallel; connectivity→sync stays sequential.
  Future<void> guarded(String tag, Future<void> Function() init) async {
    try {
      await init();
    } catch (e, st) {
      Log.w('boot', '$tag init failed (non-fatal)', error: e);
      if (kDebugMode) {
        Log.e('boot', '$tag init stack', error: e, stackTrace: st);
      }
    }
  }

  await Future.wait<void>([
    guarded('offline-db', () => OfflineDatabaseService().initialize()),
    guarded('offline-pos-db', () => OfflinePosDatabase().initialize()),
    guarded('translation', () => translationService.initialize()),
    guarded('theme', () => themeService.initialize()),
    // Sync depends on connectivity — run in order, rest runs alongside.
    () async {
      await guarded(
          'connectivity', () => ConnectivityService().initialize());
      await guarded('sync', () => SyncService().initialize());
    }(),
  ]);

  try {
    await printerLanguageSettings.initialize();
    // Wipe stale translation cache from previous build — static state survives hot-restart.
    ProductService().invalidateTranslationsCache();

    void syncPrinterLangsToProducts() {
      try {
        ProductService().primeLanguages([
          printerLanguageSettings.primary,
          if (printerLanguageSettings.allowSecondary)
            printerLanguageSettings.secondary,
        ]);
      } catch (e) {
        Log.d('Bootstrap', 'primeLanguages on printer-lang change failed (non-fatal): $e');
      }
    }

    syncPrinterLangsToProducts();
    printerLanguageSettings.addListener(syncPrinterLangsToProducts);
  } catch (e) {
    debugPrint('⚠️ Printer language init (non-fatal): $e');
  }

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

  // Auto-register Q7 built-in printer (cashier-receipt role only). No-op on non-Q7 devices.
  try {
    if (locatorReady) {
      final device = await getIt<DeviceService>()
          .autoRegisterQ7BuiltInPrinterIfPresent();
      if (device != null) {
        debugPrint('✅ Q7 built-in printer auto-registered: ${device.name}');
      }
    }
  } catch (e) {
    debugPrint('⚠️ Q7 auto-register (non-fatal): $e');
  }

  // Initialize Presentation API for dual-screen devices (e.g. Sunmi D2s).
  try {
    await PresentationService.logSunmi('=== primary app main() — Presentation bring-up START ===');
    final logPath = await PresentationService.sunmiLogPath();
    await PresentationService.logSunmi('sunmi log file path = $logPath');
    final presentationService = PresentationService();
    await presentationService.initialize();
    if (presentationService.hasSecondaryDisplay) {
      await PresentationService.logSunmi(
        'dual-screen device detected — calling showPresentation() from main()',
      );
      await presentationService.showPresentation();
    } else {
      await PresentationService.logSunmi(
        'no secondary display at boot — will retry on onDisplayAdded',
        level: 'W',
      );
    }
    await PresentationService.logSunmi('=== Presentation bring-up END ===');
  } catch (e, st) {
    await PresentationService.logSunmi(
      'Presentation init threw: $e\n$st',
      level: 'E',
    );
  }

  BaseClient.onUnauthorized = () async {
    Log.w('auth', '401 received — invalidating session and routing to login');
    try {
      if (!locatorReady || !getIt.isRegistered<AuthService>()) return;
      final authService = getIt<AuthService>();
      await authService.logout();
      if (navigatorKey.currentState != null) {
        unawaited(navigatorKey.currentState!.pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (route) => false,
        ));
      }
    } catch (e, st) {
      Log.e('auth', 'onUnauthorized handling failed', error: e, stackTrace: st);
    }
  };

  runApp(HermosaPosApp(isAuthenticated: isAuthenticated));
}

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
