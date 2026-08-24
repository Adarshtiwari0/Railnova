import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'features/live/live_train_screen.dart';
import 'features/splash/splash_screen.dart';
import 'firebase_options.dart';
import 'theme/app_theme.dart';
import 'core/theme/skin_tokens.dart';
import 'core/widgets/connectivity_gate.dart';
import 'core/widgets/responsive_container.dart';

import 'package:provider/provider.dart';
import 'providers/theme_provider.dart';

/// Used to push a screen (e.g. opening a train's live status from a push
/// notification tap) without needing a BuildContext from inside main().
final navigatorKey = GlobalKey<NavigatorState>();

/// Must be a top-level function — this is what runs in a separate isolate
/// when a push notification arrives while the app is backgrounded/killed.
/// It doesn't need to do anything itself (no local DB to write to), it just
/// has to exist and be registered for background pushes to be delivered.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Draw edge-to-edge (status/nav bars transparent, content extends behind
  // them) rather than leaving it to whatever the OS defaults to — Android
  // 15+ enforces edge-to-edge for apps targeting SDK 35 regardless, so this
  // just makes it explicit instead of implicit. Icon colour is handled per-
  // frame below via AnnotatedRegion so it always contrasts with whatever
  // skin is active, instead of the status bar going invisible/blending in.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
    ),
  );

  // Firebase Initialize — wrapped because a missing/misconfigured
  // google-services.json (or GoogleService-Info.plist) throws here, which
  // would otherwise crash the app before a single frame renders. Search/PNR/
  // live status don't depend on Firebase at all, so the app keeps working
  // without it — only Crashlytics, Analytics, and push notifications are
  // skipped if init fails.
  bool firebaseReady = false;

  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    firebaseReady = true;
  } catch (e) {
    debugPrint("Firebase initialization failed, continuing without it: $e");
  }

  if (firebaseReady) {
    // Crashlytics has no web implementation — calling it on web throws
    // "pluginConstants['isCrashlyticsCollectionEnabled'] != null is not
    // true" on every single frame/pointer event, which was flooding the
    // console and disrupting rendering (e.g. the train results list).
    if (!kIsWeb) {
      FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
      PlatformDispatcher.instance.onError = (error, stack) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };
    }

    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  }

  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: RailNovaApp(firebaseReady: firebaseReady),
    ),
  );
}

class RailNovaApp extends StatefulWidget {
  final bool firebaseReady;

  const RailNovaApp({super.key, required this.firebaseReady});

  @override
  State<RailNovaApp> createState() => _RailNovaAppState();
}

class _RailNovaAppState extends State<RailNovaApp> {
  @override
  void initState() {
    super.initState();
    if (widget.firebaseReady) _wireNotificationTaps();
  }

  Future<void> _wireNotificationTaps() async {
    // App was opened directly (from a terminated state) by tapping a
    // notification.
    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) _openTrainFromMessage(initialMessage);

    // App was backgrounded and brought back to the foreground by a tap.
    FirebaseMessaging.onMessageOpenedApp.listen(_openTrainFromMessage);
  }

  void _openTrainFromMessage(RemoteMessage message) {
    final trainNumber = message.data["trainNumber"];
    if (trainNumber == null) return;

    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => LiveTrainScreen(initialTrainNumber: trainNumber),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Keep the native Material surfaces (date picker, dialogs, snackbars,
    // text selection) in step with the selected skin — otherwise a dark skin
    // like "Night Express" shows jarring white popups.
    final isDarkSkin =
        SkinTokens.of(context.watch<ThemeProvider>().skin).brightness ==
        Brightness.dark;

    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'RailNova',

      theme: AppTheme.lightTheme,

      darkTheme: AppTheme.darkTheme,

      themeMode: isDarkSkin ? ThemeMode.dark : ThemeMode.light,

      navigatorObservers: widget.firebaseReady
          ? [FirebaseAnalyticsObserver(analytics: FirebaseAnalytics.instance)]
          : [],

      builder: (context, child) {
        // Re-applied on every rebuild (e.g. switching skins from the
        // theme picker) so status/nav bar icons never end up the same
        // brightness as the bar behind them — that's what made the
        // battery/SIM/clock icons look "covered" on a real device: with
        // edge-to-edge, the status bar is transparent and shows whatever
        // is drawn behind it, so the icon colour has to be set explicitly
        // per skin rather than left at the OS default.
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: isDarkSkin
              ? SystemUiOverlayStyle.light.copyWith(
                  statusBarColor: Colors.transparent,
                  systemNavigationBarColor: Colors.transparent,
                  systemNavigationBarIconBrightness: Brightness.light,
                )
              : SystemUiOverlayStyle.dark.copyWith(
                  statusBarColor: Colors.transparent,
                  systemNavigationBarColor: Colors.transparent,
                  systemNavigationBarIconBrightness: Brightness.dark,
                ),
          child: ConnectivityGate(
            child: ResponsiveContainer(
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        );
      },

      home: const SplashScreen(),
    );
  }
}
