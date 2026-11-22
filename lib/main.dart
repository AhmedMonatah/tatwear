import 'dart:async';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tatweer/utils/app_colors.dart';
import 'services/sync_service.dart';
import 'services/local_db_service.dart';
import 'login_screen.dart';
import 'home_screen.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

Future<void> _initSharedPreferencesWithRetry() async {
  int retries = 5;
  while (retries > 0) {
    try {
      await SharedPreferences.getInstance();
      return;
    } catch (e) {
      debugPrint('SharedPreferences init failed: $e');
      retries--;
      if (retries == 0) {
        debugPrint(
          'Failed to initialize SharedPreferences after multiple attempts.',
        );
      }
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Retry SharedPreferences initialization to avoid channel errors on release mode
  await _initSharedPreferencesWithRetry();

  await EasyLocalization.ensureInitialized();
  await LocalDbService.instance.init();

  runApp(
    EasyLocalization(
      supportedLocales: const [Locale("ar")],
      fallbackLocale: const Locale('ar'),
      startLocale: const Locale('ar'),
      path: 'assets/translations',
      child: const TatweerApp(),
    ),
  );
}

class TatweerApp extends StatefulWidget {
  const TatweerApp({super.key});

  @override
  State<TatweerApp> createState() => _TatweerAppState();
}

class _TatweerAppState extends State<TatweerApp> {
  final Connectivity _connectivity = Connectivity();
  late final StreamSubscription<List<ConnectivityResult>> _connSub;

  Timer? _sessionTimer;

  bool _internetAvailable = false;
  bool _initialized = false;
  bool _loggedIn = false;

  @override
  void initState() {
    super.initState();
    _initConnectivity();
    _checkLoginStatus();

    _connSub = _connectivity.onConnectivityChanged.listen(
      _onConnectivityChanged,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startSessionChecker();
    });
  }

  Future<void> _checkLoginStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('user_id');

    setState(() {
      _loggedIn = userId != null;
      _initialized = true;
    });
  }

  Future<void> _initConnectivity() async {
    List<ConnectivityResult> results = [];

    try {
      results = await _connectivity.checkConnectivity();
    } on PlatformException catch (e) {
      debugPrint('Connectivity error: $e');
    }

    if (results.isNotEmpty) {
      _onConnectivityChanged(results);
    } else {
      _onConnectivityChanged([ConnectivityResult.none]);
    }
  }

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    final hasInternet =
        results.isNotEmpty && !results.contains(ConnectivityResult.none);

    setState(() => _internetAvailable = hasInternet);
  }

  void _startSessionChecker() {
    // First session check only AFTER the first UI frame is complete
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 250), () {
        _checkSessionExpiration();
      });
    });

    // Then check once per minute
    _sessionTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _checkSessionExpiration();
    });
  }

  Future<void> _checkSessionExpiration() async {
    final prefs = await SharedPreferences.getInstance();
    final lastActionStr = prefs.getString('last_action');

    if (lastActionStr == null) return;
    if (!_internetAvailable) return;
    final lastAction = DateTime.tryParse(lastActionStr);
    if (lastAction == null) return;

    final diffMinutes = DateTime.now().difference(lastAction).inMinutes;
    // if last action passed 2 hours
    if (diffMinutes >= 120) {
      debugPrint("🔔 Session expired triggered");

      try {
        await SyncService.instance.syncPendingToServer();
        await prefs.clear();
        await LocalDbService.instance.clearAllTables();
        // use global navigator key
        final navigator = appNavigatorKey.currentState;
        if (navigator == null) return;

        navigator.pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => LoginScreen(internetAvailable: _internetAvailable),
          ),
          (_) => false,
        );

        WidgetsBinding.instance.addPostFrameCallback((_) {
          showGeneralDialog(
            context: navigator.context,
            barrierDismissible: false,
            barrierColor: Colors.black.withValues(alpha: 0.5),
            transitionDuration: const Duration(milliseconds: 300),
            pageBuilder: (_, __, ___) => const SizedBox(),
            transitionBuilder: (_, anim, __, ___) {
              return Opacity(
                opacity: anim.value,
                child: buildSessionExpiredDialog(),
              );
            },
          );
        });
      } catch (e) {
        debugPrint("❌ Session expiration error: $e");
      }
    }
  }

  @override
  void dispose() {
    _connSub.cancel();
    _sessionTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return MaterialApp(
        navigatorKey: appNavigatorKey,
        debugShowCheckedModeBanner: false,
        localizationsDelegates: context.localizationDelegates,
        supportedLocales: context.supportedLocales,
        locale: context.locale,
        home: const Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    return MaterialApp(
      navigatorKey: appNavigatorKey,
      debugShowCheckedModeBanner: false,
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      home: _loggedIn
          ? HomeScreen(internetAvailable: _internetAvailable)
          : LoginScreen(internetAvailable: _internetAvailable),
    );
  }
}

Widget buildSessionExpiredDialog() {
  return Center(
    child: TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutBack,
      builder: (context, value, child) {
        return Opacity(
          opacity: value.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: (0.85 + (value * 0.15)).clamp(0.85, 1.0),
            child: child,
          ),
        );
      },
      child: Dialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 4,
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.warning_rounded, size: 60, color: AppColors.warning),
              const SizedBox(height: 16),

              Text(
                "انتهت الجلسة",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.onSurface,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 12),

              Text(
                "لقد انتهت مدة التسجيل\nيرجى تسجيل الدخول مرة أخرى",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.secondary,
                  fontSize: 16,
                  height: 1.5,
                ),
              ),

              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () {
                    Navigator.pop(appNavigatorKey.currentContext!);
                  },
                  child: const Text("حسناً", style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
