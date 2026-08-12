import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'screens/main_nav_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/permission_consent_screen.dart';
import 'screens/splash_screen.dart';
import 'services/permission_consent_service.dart';
import 'services/revenuecat_service.dart';
import 'services/settings_service.dart';
import 'theme/app_theme.dart';
import 'widgets/app_lock_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: FreelancerApp()));
}

class FreelancerApp extends StatelessWidget {
  const FreelancerApp({super.key, this.showOnboarding});

  /// A non-null value is kept for the widget smoke test and for embedding the
  /// app in a host that has already completed startup initialization. Normal
  /// production startup leaves this null and uses [AppBootstrap].
  final bool? showOnboarding;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Centsio AI: Invoice Maker',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: showOnboarding == null
          ? const AppBootstrap()
          : showOnboarding!
          ? const OnboardingScreen()
          : const AppLockGate(child: MainNavScreen()),
    );
  }
}

/// Performs startup work behind a branded splash instead of blocking before
/// the first Flutter frame. This gives the user visible progress and ensures
/// the lock screen is reached only after local settings have been loaded.
class AppBootstrap extends StatefulWidget {
  const AppBootstrap({super.key});

  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap> {
  static const _splashDuration = Duration(seconds: 5);

  double _progress = 0;
  String _status = 'Starting securely…';
  String? _error;
  bool _ready = false;
  bool _showOnboarding = false;
  bool _showPermissionConsent = false;
  Timer? _progressTimer;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    super.dispose();
  }

  Future<void> _initialize() async {
    _progressTimer?.cancel();
    final startedAt = DateTime.now();
    _progressTimer = Timer.periodic(const Duration(milliseconds: 40), (_) {
      if (!mounted) return;
      final elapsed = DateTime.now().difference(startedAt);
      final progress = (elapsed.inMilliseconds / _splashDuration.inMilliseconds)
          .clamp(0.0, 0.98)
          .toDouble();
      setState(() => _progress = progress);
    });

    setState(() {
      _progress = 0;
      _status = 'Loading app configuration…';
      _error = null;
      _ready = false;
    });

    try {
      await dotenv.load(fileName: '.env');
      if (!mounted) return;
      setState(() => _status = 'Preparing secure services…');

      await RevenueCatService.init();
      if (!mounted) return;
      setState(() => _status = 'Loading your workspace…');

      final showOnboarding = !await SettingsService.hasCompletedOnboarding();
      final showPermissionConsent =
          !await PermissionConsentService.hasReviewed();
      if (!mounted) return;
      setState(() {
        _showOnboarding = showOnboarding;
        _showPermissionConsent = showPermissionConsent;
        _status = 'Finishing secure setup…';
      });

      final remaining = _splashDuration - DateTime.now().difference(startedAt);
      if (!remaining.isNegative && remaining > Duration.zero) {
        await Future<void>.delayed(remaining);
      }
      if (!mounted) return;
      _progressTimer?.cancel();
      setState(() {
        _progress = 1;
        _status = 'Ready';
      });
      await Future<void>.delayed(const Duration(milliseconds: 80));
      if (mounted) setState(() => _ready = true);
    } catch (error, stackTrace) {
      _progressTimer?.cancel();
      debugPrint('App startup failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() {
        _error = 'Please check your connection and try again.';
        _status = 'Startup failed';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return SplashScreen(
        progress: _progress,
        status: _status,
        error: _error,
        onRetry: _initialize,
      );
    }
    if (!_ready) {
      return SplashScreen(progress: _progress, status: _status);
    }
    if (_showPermissionConsent) {
      return PermissionConsentScreen(
        onComplete: () async {
          if (mounted) setState(() => _showPermissionConsent = false);
        },
      );
    }
    return _showOnboarding
        ? const OnboardingScreen()
        : const AppLockGate(child: MainNavScreen());
  }
}
