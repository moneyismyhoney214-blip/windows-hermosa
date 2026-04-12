import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'Splash/splash_screen.dart';
import 'screens/login_screen.dart';
import 'services/api/auth_service.dart';
import 'services/api/base_client.dart';
import 'services/language_service.dart';
import 'services/cashier_sound_service.dart';
import 'services/presentation_service.dart';
import 'services/offline/offline_database_service.dart';
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

  // Primary display — run the full cashier app.
  var isAuthenticated = false;
  var locatorReady = false;

  try {
    setupLocator();
    locatorReady = true;

    // Initialize offline database FIRST (before any service needs it)
    await OfflineDatabaseService().initialize();
    debugPrint('Offline database initialized');

    // Initialize connectivity monitoring
    await ConnectivityService().initialize();
    debugPrint('Connectivity service initialized');

    // Initialize sync service
    await SyncService().initialize();
    debugPrint('Sync service initialized');

    await translationService.initialize();

    if (!getIt.isRegistered<CashierSoundService>()) {
      getIt.registerLazySingleton<CashierSoundService>(
        () => CashierSoundService(),
      );
    }
    await getIt<CashierSoundService>().initialize();

    final authService = getIt<AuthService>();
    await authService.initialize(force: true);
    isAuthenticated = await authService.isAuthenticated();

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
  } catch (e, stackTrace) {
    debugPrint('❌ Startup initialization failed: $e');
    debugPrintStack(stackTrace: stackTrace);
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
  }

  @override
  void dispose() {
    translationService.removeListener(_onLocaleChange);
    super.dispose();
  }

  void _onLocaleChange() {
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
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFF58220),
          primary: const Color(0xFFF58220),
          surface: const Color(0xFFF8FAFC),
        ),
        textTheme: isRTL
            ? GoogleFonts.tajawalTextTheme()
            : GoogleFonts.robotoTextTheme(),
        iconTheme: const IconThemeData(size: 20),
      ),
      builder: (context, child) {
        return PrintListener(child: child!);
      },
      home: SplashScreen(isAuthenticated: widget.isAuthenticated),
    );
  }
}
