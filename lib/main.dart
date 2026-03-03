import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'dart:math';
import 'dart:io';
import 'package:google_fonts/google_fonts.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:app_links/app_links.dart';
import 'package:universal_html/html.dart' as html;
import 'package:roster_champ/home_screen.dart';
import 'providers.dart';
import 'screens/onboarding_screen.dart';
import 'screens/roster_sharing_screen.dart';
import 'screens/login_screen.dart';
import 'screens/paywall_screen.dart';
import 'aws_service.dart';
import 'ai_service.dart';
import 'models.dart' as models;
import 'theme/theme_manager.dart';
import 'utils/error_handler.dart';
import 'config/env_loader.dart';
import 'services/analytics_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: RosterChampApp()));
}

class RosterChampApp extends ConsumerStatefulWidget {
  const RosterChampApp({super.key});

  @override
  ConsumerState<RosterChampApp> createState() => _RosterChampAppState();
}

class _RosterChampAppState extends ConsumerState<RosterChampApp>
    with WidgetsBindingObserver {
  bool _isInitializing = true;
  bool _isAuthenticated = false;
  bool _hasRoster = false;
  bool _awsConfigured = false;
  bool _aiConfigured = false;
  bool _isGuestMode = false;
  bool _isOffline = false;
  bool _requiresUpdate = false;
  String? _updateUrl;
  String? _minVersion;
  String? _latestVersion;
  bool _isBillingLocked = false;
  bool _billingChecked = false;
  String? _subscriptionStatus;
  String? _subscriptionPlan;
  bool _trialActive = false;
  String? _trialEndsAt;
  String? _initWarning;
  String _initStage = 'startup';
  String? _initError;
  StreamSubscription<Uri>? _linkSubscription;
  Uri? _pendingAuthRedirect;
  Timer? _connectionTimer;
  models.ConnectionStatus? _lastAwsStatus;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!kIsWeb && Platform.isWindows) {
      _isInitializing = false;
      _initWarning = 'Windows startup bypassed initialization screen.';
    }
    _initializeApp();
    _startInitWatchdog();
    _forceDesktopInitExit();
    _setupAuthListener();
    _setupDeepLinks();
    _startConnectionMonitor();
  }

  void _logInit(String message) {
    try {
      final file = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}roster_init.log',
      );
      final stamp = DateTime.now().toIso8601String();
      file.writeAsStringSync('[$stamp] $message\n', mode: FileMode.append);
    } catch (_) {
      // Ignore logging failures.
    }
  }

  void _setInitStage(String stage, {String? error}) {
    if (mounted) {
      setState(() {
        _initStage = stage;
        if (error != null) _initError = error;
      });
    } else {
      _initStage = stage;
      if (error != null) _initError = error;
    }
    _logInit(error == null ? stage : '$stage | $error');
  }

  void _forceDesktopInitExit() {
    if (kIsWeb) return;
    if (!Platform.isWindows) return;
    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;
      if (_isInitializing) {
        setState(() {
          _isInitializing = false;
          _initWarning =
              'Startup timed out on Windows. You can sign in now.';
        });
      }
    });
  }

  void _startInitWatchdog() {
    Future.delayed(const Duration(seconds: 12), () {
      if (!mounted) return;
      if (_isInitializing) {
        setState(() {
          _isInitializing = false;
          _initWarning =
              'Startup is taking longer than expected. You can sign in now.';
        });
      }
    });
  }

  void _startConnectionMonitor() {
    _connectionTimer?.cancel();
    _connectionTimer = Timer.periodic(const Duration(seconds: 25), (_) async {
      await _checkConnections();
    });
  }

  void _setupAuthListener() {
    AwsService.instance.onAuthStateChanged = (isAuthenticated) {
      if (mounted) {
        setState(() {
          _isAuthenticated = isAuthenticated;
          _isGuestMode = false;
          _billingChecked = false;
        });
        ref.read(staffNameProvider).loadForUser(
              userId: AwsService.instance.userId,
              email: AwsService.instance.userEmail,
            );
        ref.read(settingsProvider.notifier).loadSettings();
        if (isAuthenticated) {
          _handlePostAuthLoad();
        }
      }
    };
  }

  void _setupDeepLinks() {
    try {
      if (kIsWeb) {
        final uri = Uri.base;
        if (uri.queryParameters.containsKey('code')) {
          _pendingAuthRedirect = uri;
          // Clean URL after handling auth redirect.
          final cleaned = uri.replace(queryParameters: {});
          html.window.history.replaceState(null, '', cleaned.toString());
        }
        return;
      }
      final appLinks = AppLinks();
      _linkSubscription = appLinks.uriLinkStream.listen(
        (uri) => AwsService.instance.handleAuthRedirect(uri),
        onError: (error) => debugPrint('App link error: $error'),
      );
      appLinks.getInitialLink().then((uri) {
        if (uri != null) {
          AwsService.instance.handleAuthRedirect(uri);
        }
      });
    } catch (e) {
      debugPrint('Deep link setup error: $e');
    }
  }

  void _enterGuestMode() {
    if (mounted) {
      setState(() {
        _isGuestMode = true;
        _isAuthenticated = false;
      });
      _loadRosterData();
    }
  }

  Future<void> _enterSharedRoster(String code) async {
    if (mounted) {
      setState(() {
        _isGuestMode = true;
        _isAuthenticated = false;
        _hasRoster = true;
      });
    }
    await ErrorHandler.wrapAsync(
      () => ref.read(rosterProvider).loadSharedRosterByCode(code),
      context: 'Loading shared roster',
    );
  }

  void _exitGuestMode() {
    if (mounted) {
      setState(() {
        _isGuestMode = false;
      });
    }
  }

  Future<void> _initializeApp() async {
    try {
      _setInitStage('services_init');
      await _initializeServices();
      if (_pendingAuthRedirect != null) {
        try {
          await AwsService.instance.handleAuthRedirect(_pendingAuthRedirect!);
        } catch (e) {
          debugPrint('Web auth redirect failed: $e');
        } finally {
          _pendingAuthRedirect = null;
        }
      }
      _setInitStage('connectivity');
      try {
        final connected = await AwsService.instance
            .checkConnection()
            .timeout(const Duration(seconds: 4));
        _isOffline = !connected;
        ref.read(awsStatusProvider.notifier).state = models.ServiceStatus(
          status: connected
              ? models.ConnectionStatus.connected
              : models.ConnectionStatus.disconnected,
          message: connected ? 'Connected to AWS' : 'Offline mode',
          lastChecked: DateTime.now(),
        );
      } catch (_) {
        _isOffline = true;
        ref.read(awsStatusProvider.notifier).state = models.ServiceStatus(
          status: models.ConnectionStatus.disconnected,
          message: 'Offline mode',
          lastChecked: DateTime.now(),
        );
      }
      _setInitStage('config_check');
      // Check service configurations
      _awsConfigured = AwsService.instance.isConfigured;
      _aiConfigured = AiService.instance.isConfigured;

      // Load settings
      _setInitStage('load_settings');
      await ref.read(settingsProvider.notifier).loadSettings();
      final settings = ref.read(settingsProvider);
      if (!settings.staySignedIn) {
        await AwsService.instance.signOutLocal();
        _isAuthenticated = false;
      }

      _setInitStage('check_version');
      await _checkAppVersion();

      // Check initial auth state
      _setInitStage('auth_state');
      _isAuthenticated = AwsService.instance.isAuthenticated;
      _hasRoster = AwsService.instance.currentRosterId != null;
      await ref.read(staffNameProvider).loadForUser(
            userId: AwsService.instance.userId,
            email: AwsService.instance.userEmail,
          );

      if (_isAuthenticated && !_isOffline) {
        _setInitStage('post_auth');
        await AwsService.instance.ensureCurrentRosterSelected();
        _hasRoster = AwsService.instance.currentRosterId != null;
        await _loadRosterData();
        await _refreshSubscriptionStatus();
      } else if (_isAuthenticated && _isOffline) {
        _setInitStage('offline_auth');
        final cached = await AwsService.instance.getCachedSubscription();
        _subscriptionStatus = cached['status']?.toString();
        _subscriptionPlan = cached['plan']?.toString();
        _trialActive = (_subscriptionStatus == 'trialing');
        final offlineAllowed =
            await AwsService.instance.isCachedSubscriptionActive(graceDays: 7);
        _isBillingLocked = !offlineAllowed;
        _billingChecked = true;
        await _loadRosterData();
      }

      // Set up real-time sync if authenticated and has roster
      if (_isAuthenticated && _hasRoster && !_isOffline) {
        _setInitStage('realtime_sync');
        ref.read(rosterProvider).setupRealtimeSync();
      }

      // Check connections
      if (!_isOffline) {
        _setInitStage('check_connections');
        await _checkConnections();
      }
      _setInitStage('ready');
    } catch (e) {
      debugPrint('App initialization error: $e');
      _setInitStage('error', error: e.toString());
      if (mounted) {
        _initWarning = 'Startup issue: $e';
      }
    } finally {
      if (mounted) {
        setState(() => _isInitializing = false);
      }
    }
  }

  Future<void> _initializeServices() async {
    await EnvLoader.instance.load();
    await _runWithTimeout(() => AwsService.instance.initialize(),
        const Duration(seconds: 8), 'AWS init timeout');
    await _runWithTimeout(() => AiService.instance.initialize(),
        const Duration(seconds: 6), 'AI init timeout');
    await _runWithTimeout(() => ThemeManager.instance.initialize(),
        const Duration(seconds: 4), 'Theme init timeout');
    await _runWithTimeout(() => AnalyticsService.instance.initialize(),
        const Duration(seconds: 4), 'Analytics init timeout');
    AnalyticsService.instance.trackEvent(
      'app_start',
      type: 'lifecycle',
    );
  }

  Future<void> _runWithTimeout(
    Future<void> Function() action,
    Duration timeout,
    String timeoutMessage,
  ) async {
    try {
      await action().timeout(timeout);
    } catch (e) {
      debugPrint(timeoutMessage);
    }
  }

  Future<void> _loadRosterData() async {
    try {
      if (_isOffline) {
        await ErrorHandler.wrapAsync(
          () => ref.read(rosterProvider).loadFromLocal(),
          context: 'Loading from local storage',
        );
        return;
      }

      if (_isAuthenticated && AwsService.instance.currentRosterId != null) {
        try {
          await ErrorHandler.wrapAsync(
            () => ref.read(rosterProvider).loadFromAWS(),
            context: 'Loading from AWS',
          );
        } catch (e) {
          await ErrorHandler.wrapAsync(
            () => ref.read(rosterProvider).loadFromLocal(),
            context: 'Loading from local storage',
          );
        }
      } else {
        await ErrorHandler.wrapAsync(
          () => ref.read(rosterProvider).loadFromLocal(),
          context: 'Loading from local storage',
        );
      }
    } catch (e) {
      debugPrint('Error loading roster data: $e');
    }
  }

  Future<void> _checkConnections() async {
    // Check AWS connection only if configured
    if (_awsConfigured) {
      try {
        final previous = ref.read(awsStatusProvider).status;
        ref.read(awsStatusProvider.notifier).state = models.ServiceStatus(
          status: models.ConnectionStatus.connecting,
          lastChecked: DateTime.now(),
        );

        final connected = await AwsService.instance.checkConnection();
        final nextStatus = connected
            ? models.ConnectionStatus.connected
            : models.ConnectionStatus.error;

        ref.read(awsStatusProvider.notifier).state = models.ServiceStatus(
          status: nextStatus,
          message: connected
              ? 'Connected to AWS'
              : 'AWS connection failed. Fix: Check internet - Verify API URL - Sign in',
          lastChecked: DateTime.now(),
        );
        _isOffline = !connected;
        if (previous != models.ConnectionStatus.connected &&
            nextStatus == models.ConnectionStatus.connected) {
          await ref.read(rosterProvider).tryProcessPendingSync();
        }
        _lastAwsStatus = nextStatus;
      } catch (e) {
        ref.read(awsStatusProvider.notifier).state = models.ServiceStatus(
          status: models.ConnectionStatus.error,
          message:
              'AWS error: $e. Fix: Check internet - Verify API URL - Sign in',
          lastChecked: DateTime.now(),
        );
        _isOffline = true;
      }
    } else {
      ref.read(awsStatusProvider.notifier).state = models.ServiceStatus(
        status: models.ConnectionStatus.disconnected,
        message: 'AWS not configured',
        lastChecked: DateTime.now(),
      );
      _isOffline = true;
    }

    // Check AI connection only if configured
    if (_aiConfigured) {
      try {
        ref.read(aiStatusProvider.notifier).state = models.ServiceStatus(
          status: models.ConnectionStatus.connecting,
          lastChecked: DateTime.now(),
        );

        final connected = await AiService.instance.checkConnection();

        ref.read(aiStatusProvider.notifier).state = models.ServiceStatus(
          status: connected
              ? models.ConnectionStatus.connected
              : models.ConnectionStatus.error,
          message: connected
              ? 'Connected to AI'
              : 'AI connection failed. Fix: Check internet - Retry',
          lastChecked: DateTime.now(),
        );
      } catch (e) {
        ref.read(aiStatusProvider.notifier).state = models.ServiceStatus(
          status: models.ConnectionStatus.error,
          message: 'AI error: $e. Fix: Check internet - Retry',
          lastChecked: DateTime.now(),
        );
      }
    } else {
      ref.read(aiStatusProvider.notifier).state = models.ServiceStatus(
        status: models.ConnectionStatus.disconnected,
        message: 'AI not configured',
        lastChecked: DateTime.now(),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _linkSubscription?.cancel();
    _connectionTimer?.cancel();
    super.dispose();
  }

  Future<void> _handlePostAuthLoad() async {
    await AwsService.instance.ensureCurrentRosterSelected();
    if (mounted) {
      setState(() {
        _hasRoster = AwsService.instance.currentRosterId != null;
      });
    }
    await _loadRosterData();
    await _refreshSubscriptionStatus();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final settings = ref.read(settingsProvider);
    if (state == AppLifecycleState.resumed) {
      _refreshSubscriptionStatus();
    } else if ((state == AppLifecycleState.paused ||
            state == AppLifecycleState.detached) &&
        settings.signOutOnExit) {
      AwsService.instance.signOutLocal();
      if (mounted) {
        setState(() {
          _isAuthenticated = false;
          _billingChecked = false;
          _isBillingLocked = false;
        });
      }
    }
    super.didChangeAppLifecycleState(state);
  }

  Future<void> _refreshSubscriptionStatus() async {
    if (!_isAuthenticated || _isGuestMode) return;
    try {
      try {
        await AwsService.instance.refreshBillingStatus();
      } catch (e) {
        debugPrint('Billing reconcile failed: $e');
      }
      final profile = await AwsService.instance.getProfile();
      final status = profile['subscriptionStatus']?.toString() ?? 'inactive';
      final plan = profile['subscriptionPlan']?.toString() ?? 'none';
      final periodEnd =
          profile['subscriptionPeriodEnd']?.toString();
      final trialEndsAt = profile['trialEndsAt']?.toString();
      final trialActive =
          profile['trialActive'] == true ||
          profile['subscriptionStatus']?.toString() == 'trialing' ||
          _isTrialStillValid(trialEndsAt);
      final normalizedPlan = plan.toLowerCase();
      final hasPaidPlan = normalizedPlan == 'starter' ||
          normalizedPlan == 'operations' ||
          normalizedPlan == 'enterprise';
      final active =
          trialActive ||
          (status == 'active' && hasPaidPlan) ||
          (status == 'trialing');
      await AwsService.instance.cacheSubscriptionStatus(
        status: status,
        plan: plan,
        periodEnd: periodEnd,
      );
      if (mounted) {
        setState(() {
          _subscriptionStatus = status;
          _subscriptionPlan = plan;
          _trialActive = trialActive;
          _trialEndsAt = trialEndsAt;
          _isBillingLocked = !active;
          _billingChecked = true;
        });
      }
    } catch (e) {
      debugPrint('Subscription status check failed: $e');
      final cachedActive =
          await AwsService.instance.isCachedSubscriptionActive();
      final cached = await AwsService.instance.getCachedSubscription();
      if (mounted) {
        setState(() {
          _subscriptionStatus =
              cached['status']?.toString() ?? 'inactive';
          _subscriptionPlan =
              cached['plan']?.toString() ?? 'none';
          _trialEndsAt = cached['trialEndsAt']?.toString();
          _trialActive =
              cached['status']?.toString() == 'trialing' ||
              _isTrialStillValid(_trialEndsAt);
          _isBillingLocked = !cachedActive;
          _billingChecked = true;
        });
      }
    }
  }

  Future<void> _checkAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final platform = _platformLabel();
      final versionInfo =
          await AwsService.instance.getAppUpdateInfo(platform: platform);
      final minVersion = versionInfo['minVersion']?.toString() ?? '';
      final latestVersion = versionInfo['latestVersion']?.toString() ?? '';
      final updateUrl = versionInfo['updateUrl']?.toString() ?? '';
      _minVersion = minVersion;
      _latestVersion = latestVersion;
      _updateUrl = updateUrl;
      if (_isVersionNewer(minVersion, info.version)) {
        _requiresUpdate = true;
      }
      // Soft update notification handled in UI, not blocking.
    } catch (e) {
      debugPrint('Version check failed: $e');
    }
  }

  bool _isTrialStillValid(String? trialEndsAt) {
    if (trialEndsAt == null || trialEndsAt.isEmpty) return false;
    final parsed = DateTime.tryParse(trialEndsAt);
    if (parsed == null) return false;
    return parsed.toUtc().isAfter(DateTime.now().toUtc());
  }

  String _platformLabel() {
    if (!kIsWeb && Platform.isWindows) {
      return 'windows';
    }
    if (!kIsWeb && Platform.isAndroid) {
      return 'android';
    }
    if (!kIsWeb && Platform.isIOS) {
      return 'ios';
    }
    return 'unknown';
  }

  bool _isVersionNewer(String required, String current) {
    if (required.isEmpty) return false;
    final reqParts = required.split('.');
    final curParts = current.split('.');
    final maxLen = reqParts.length > curParts.length
        ? reqParts.length
        : curParts.length;
    for (var i = 0; i < maxLen; i++) {
      final req = i < reqParts.length ? int.tryParse(reqParts[i]) ?? 0 : 0;
      final cur = i < curParts.length ? int.tryParse(curParts[i]) ?? 0 : 0;
      if (req > cur) return true;
      if (req < cur) return false;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    if (_requiresUpdate) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: UpdateRequiredScreen(
          minVersion: _minVersion ?? '',
          latestVersion: _latestVersion ?? '',
          updateUrl: _updateUrl,
        ),
        theme: ThemeManager.instance.getLightTheme(
          settings.colorScheme,
          settings.layoutStyle,
          true,
        ),
      );
    }
    final themeMode = ThemeManager.instance.getThemeMode(settings.themeMode);

    if (_isInitializing) {
      if (!kIsWeb && Platform.isWindows) {
        // Windows: never block on init spinner.
        return MaterialApp(
          locale: Locale(settings.languageCode),
          supportedLocales: const [
            Locale('en'),
            Locale('es'),
            Locale('fr'),
            Locale('de'),
            Locale('it'),
            Locale('pt'),
            Locale('zh'),
            Locale('ja'),
            Locale('ko'),
            Locale('ar'),
          ],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: ThemeManager.instance.getLightTheme(
            settings.colorScheme,
            settings.layoutStyle,
            true,
          ),
          darkTheme: ThemeManager.instance.getDarkTheme(
            settings.colorScheme,
            settings.layoutStyle,
            true,
          ),
          themeMode: themeMode,
          home: _buildHomeScreen(),
        );
      }
      return MaterialApp(
        locale: Locale(settings.languageCode),
        supportedLocales: const [
          Locale('en'),
          Locale('es'),
          Locale('fr'),
          Locale('de'),
          Locale('it'),
          Locale('pt'),
          Locale('zh'),
          Locale('ja'),
          Locale('ko'),
          Locale('ar'),
        ],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: AnimatedLaunchScreen(
          awsConfigured: _awsConfigured,
          aiConfigured: _aiConfigured,
        ),
      );
    }

    final app = MaterialApp(
      title: 'Roster Champion',
      debugShowCheckedModeBanner: false,
      locale: Locale(settings.languageCode),
      supportedLocales: const [
        Locale('en'),
        Locale('es'),
        Locale('fr'),
        Locale('de'),
        Locale('it'),
        Locale('pt'),
        Locale('zh'),
        Locale('ja'),
        Locale('ko'),
        Locale('ar'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeManager.instance.getLightTheme(
        settings.colorScheme,
        settings.layoutStyle,
        true,
      ),
      darkTheme: ThemeManager.instance.getDarkTheme(
        settings.colorScheme,
        settings.layoutStyle,
        true,
      ),
      themeMode: themeMode,
      home: _buildHomeScreen(),
    );
    if (!kIsWeb && Platform.isWindows) {
      return Stack(
        children: [
          app,
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: IgnorePointer(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: DefaultTextStyle(
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Init stage: $_initStage'),
                      Text('Init error: ${_initError ?? '-'}'),
                      Text('AWS configured: $_awsConfigured'),
                      Text('Authenticated: $_isAuthenticated'),
                      if (_initWarning != null)
                        Text('Warning: $_initWarning'),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }
    return app;
  }

  Widget _buildHomeScreen() {
    if (!_isAuthenticated && !_isGuestMode) {
      return LoginScreen(
        onAccessCode: _enterSharedRoster,
        initialMessage: _initWarning,
      );
    } else if (_isAuthenticated && !_billingChecked) {
      return const PaywallScreen.loading();
    } else if (_isAuthenticated && _isBillingLocked) {
      return PaywallScreen(
        subscriptionStatus: _subscriptionStatus ?? 'inactive',
        subscriptionPlan: _subscriptionPlan ?? 'none',
        trialActive: _trialActive,
        trialEndsAt: _trialEndsAt,
        onRefreshStatus: _refreshSubscriptionStatus,
      );
    } else if (!_hasRoster && ref.read(rosterProvider).staffMembers.isEmpty) {
      return OnboardingScreen(isGuestMode: _isGuestMode);
    } else if (_isAuthenticated && !_hasRoster) {
      return RosterSharingScreen();
    } else {
      return HomeScreen(
        isGuestMode: _isGuestMode,
        onExitGuestMode: _exitGuestMode,
      );
    }
  }
}

class UpdateRequiredScreen extends StatelessWidget {
  final String minVersion;
  final String latestVersion;
  final String? updateUrl;

  const UpdateRequiredScreen({
    super.key,
    required this.minVersion,
    required this.latestVersion,
    required this.updateUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.system_update,
                  size: 72, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 16),
              Text(
                'Update Required',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                'Please update to continue using Roster Champion.',
                textAlign: TextAlign.center,
              ),
              if (minVersion.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Minimum version: $minVersion'),
              ],
              if (latestVersion.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('Latest version: $latestVersion'),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: updateUrl == null || updateUrl!.isEmpty
                    ? null
                    : () => launchUrl(Uri.parse(updateUrl!),
                        mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Update Now'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AnimatedLaunchScreen extends StatefulWidget {
  final bool awsConfigured;
  final bool aiConfigured;

  const AnimatedLaunchScreen({
    super.key,
    required this.awsConfigured,
    required this.aiConfigured,
  });

  @override
  State<AnimatedLaunchScreen> createState() => _AnimatedLaunchScreenState();
}

class _AnimatedLaunchScreenState extends State<AnimatedLaunchScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: const Duration(seconds: 10))
          ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        final pulse = (sin(2 * pi * t) + 1) / 2;
        final pulse2 = (sin(2 * pi * (t + 0.35)) + 1) / 2;
        final gradient = LinearGradient(
          begin: Alignment.lerp(Alignment.topLeft, Alignment.centerRight, pulse)!,
          end: Alignment.lerp(Alignment.bottomRight, Alignment.centerLeft, pulse2)!,
          colors: [
            Color.lerp(const Color(0xFF0B132B), const Color(0xFF1F2F55), pulse)!,
            Color.lerp(const Color(0xFF2AA15F), const Color(0xFF0F4C5C), pulse2)!,
            Color.lerp(const Color(0xFF2AA1A1), const Color(0xFF4CC9F0), pulse)!,
          ],
        );

        return Scaffold(
          body: Stack(
            children: [
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(gradient: gradient),
                ),
              ),
              Positioned.fill(
                child: CustomPaint(
                  painter: _PatternPainter(progress: t),
                ),
              ),
              ..._buildOrbs(t),
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Roster Champion',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 34,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Plan. Align. Deliver.',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 15,
                        color: Colors.white.withOpacity(0.75),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Image.asset(
                      'assets/images/rc4eee.gif',
                      width: 340,
                      height: 340,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(height: 24),
                    const SizedBox(
                      width: 42,
                      height: 42,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Initializing...',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 14,
                        color: Colors.white70,
                      ),
                    ),
                    if (!widget.awsConfigured || !widget.aiConfigured) ...[
                      const SizedBox(height: 18),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: [
                          if (!widget.awsConfigured)
                            const _StatusChip(
                              label: 'AWS not configured',
                              color: Colors.orangeAccent,
                            ),
                          if (!widget.aiConfigured)
                            const _StatusChip(
                              label: 'AI not configured',
                              color: Colors.orangeAccent,
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _buildOrbs(double t) {
    return [
      _FloatingOrb(
        size: 160,
        color: const Color(0xFF4CC9F0),
        x: 40 + 30 * sin(2 * pi * t),
        y: 110 + 40 * cos(2 * pi * t),
        opacity: 0.25,
      ),
      _FloatingOrb(
        size: 220,
        color: const Color(0xFFF72585),
        x: 240 + 35 * cos(2 * pi * (t + 0.2)),
        y: 420 + 45 * sin(2 * pi * (t + 0.15)),
        opacity: 0.2,
      ),
      _FloatingOrb(
        size: 120,
        color: const Color(0xFF80FFDB),
        x: 280 + 28 * sin(2 * pi * (t + 0.4)),
        y: 180 + 30 * cos(2 * pi * (t + 0.35)),
        opacity: 0.18,
      ),
    ];
  }
}

class _FloatingOrb extends StatelessWidget {
  final double size;
  final Color color;
  final double x;
  final double y;
  final double opacity;

  const _FloatingOrb({
    required this.size,
    required this.color,
    required this.x,
    required this.y,
    required this.opacity,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: x,
      top: y,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withOpacity(opacity),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(opacity * 0.8),
              blurRadius: 40,
              spreadRadius: 6,
            ),
          ],
        ),
      ),
    );
  }
}

class _PatternPainter extends CustomPainter {
  final double progress;

  _PatternPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final baseOpacity = 0.05 + (0.03 * sin(2 * pi * progress));
    final paint = Paint()
      ..color = Colors.white.withOpacity(baseOpacity)
      ..strokeWidth = 1.0;
    final boldPaint = Paint()
      ..color = Colors.white.withOpacity(baseOpacity + 0.04)
      ..strokeWidth = 1.6;

    final spacing = 32.0;
    final offset = spacing * progress;
    for (double x = -spacing; x < size.width + spacing; x += spacing) {
      final isMajor = (x / spacing).round() % 4 == 0;
      final dx = x + offset;
      canvas.drawLine(
        Offset(dx % (size.width + spacing), 0),
        Offset(dx % (size.width + spacing), size.height),
        isMajor ? boldPaint : paint,
      );
    }
    for (double y = -spacing; y < size.height + spacing; y += spacing) {
      final isMajor = (y / spacing).round() % 4 == 0;
      final dy = y + offset * 0.6;
      canvas.drawLine(
        Offset(0, dy % (size.height + spacing)),
        Offset(size.width, dy % (size.height + spacing)),
        isMajor ? boldPaint : paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PatternPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusChip({
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withOpacity(0.6)),
      ),
      child: Text(
        label,
        style: GoogleFonts.spaceGrotesk(
          fontSize: 12,
          color: Colors.white,
        ),
      ),
    );
  }
}
