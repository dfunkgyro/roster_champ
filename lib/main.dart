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
import 'package:roster_champ/home_screen.dart';
import 'providers.dart';
import 'screens/onboarding_screen.dart';
import 'screens/roster_sharing_screen.dart';
import 'screens/login_screen.dart';
import 'aws_service.dart';
import 'ai_service.dart';
import 'models.dart' as models;
import 'theme/theme_manager.dart';
import 'utils/error_handler.dart';
import 'config/env_loader.dart';
import 'services/analytics_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables first
  await EnvLoader.instance.load();

  // Initialize services
  await AwsService.instance.initialize();
  await AiService.instance.initialize();
  await ThemeManager.instance.initialize();
  await AnalyticsService.instance.initialize();
  AnalyticsService.instance.trackEvent(
    'app_start',
    type: 'lifecycle',
  );

  runApp(const ProviderScope(child: RosterChampApp()));
}

class RosterChampApp extends ConsumerStatefulWidget {
  const RosterChampApp({super.key});

  @override
  ConsumerState<RosterChampApp> createState() => _RosterChampAppState();
}

class _RosterChampAppState extends ConsumerState<RosterChampApp> {
  bool _isInitializing = true;
  bool _isAuthenticated = false;
  bool _hasRoster = false;
  bool _awsConfigured = false;
  bool _aiConfigured = false;
  bool _isGuestMode = false;
  bool _requiresUpdate = false;
  String? _updateUrl;
  String? _minVersion;
  String? _latestVersion;
  StreamSubscription<Uri>? _linkSubscription;

  @override
  void initState() {
    super.initState();
    _initializeApp();
    _setupAuthListener();
    _setupDeepLinks();
  }

  void _setupAuthListener() {
    AwsService.instance.onAuthStateChanged = (isAuthenticated) {
      if (mounted) {
        setState(() {
          _isAuthenticated = isAuthenticated;
          _isGuestMode = false;
          _hasRoster = AwsService.instance.currentRosterId != null;
        });
        ref.read(staffNameProvider).loadForUser(
              userId: AwsService.instance.userId,
              email: AwsService.instance.userEmail,
            );
        ref.read(settingsProvider.notifier).loadSettings();
        if (isAuthenticated) {
          _loadRosterData();
        }
      }
    };
  }

  void _setupDeepLinks() {
    try {
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
      // Check service configurations
      _awsConfigured = AwsService.instance.isConfigured;
      _aiConfigured = AiService.instance.isConfigured;

      // Load settings
      await ref.read(settingsProvider.notifier).loadSettings();

      await _checkAppVersion();

      // Check initial auth state
      _isAuthenticated = AwsService.instance.isAuthenticated;
      _hasRoster = AwsService.instance.currentRosterId != null;
      await ref.read(staffNameProvider).loadForUser(
            userId: AwsService.instance.userId,
            email: AwsService.instance.userEmail,
          );

      if (_isAuthenticated) {
        await _loadRosterData();
      }

      // Set up real-time sync if authenticated and has roster
      if (_isAuthenticated && _hasRoster) {
        ref.read(rosterProvider).setupRealtimeSync();
      }

      // Check connections
      await _checkConnections();
    } catch (e) {
      debugPrint('App initialization error: $e');
    } finally {
      if (mounted) {
        setState(() => _isInitializing = false);
      }
    }
  }

  Future<void> _loadRosterData() async {
    try {
      if (_isAuthenticated && AwsService.instance.currentRosterId != null) {
        await ErrorHandler.wrapAsync(
          () => ref.read(rosterProvider).loadFromAWS(),
          context: 'Loading from AWS',
        );
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
        ref.read(awsStatusProvider.notifier).state = models.ServiceStatus(
          status: models.ConnectionStatus.connecting,
          lastChecked: DateTime.now(),
        );

        final connected = await AwsService.instance.checkConnection();

        ref.read(awsStatusProvider.notifier).state = models.ServiceStatus(
          status: connected
              ? models.ConnectionStatus.connected
              : models.ConnectionStatus.error,
          message: connected
              ? 'Connected to AWS'
              : 'AWS connection failed. Fix: Check internet - Verify API URL - Sign in',
          lastChecked: DateTime.now(),
        );
      } catch (e) {
        ref.read(awsStatusProvider.notifier).state = models.ServiceStatus(
          status: models.ConnectionStatus.error,
          message:
              'AWS error: $e. Fix: Check internet - Verify API URL - Sign in',
          lastChecked: DateTime.now(),
        );
      }
    } else {
      ref.read(awsStatusProvider.notifier).state = models.ServiceStatus(
        status: models.ConnectionStatus.disconnected,
        message: 'AWS not configured',
        lastChecked: DateTime.now(),
      );
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
    _linkSubscription?.cancel();
    super.dispose();
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
      // Soft update notification handled in UI, not blocking.
    } catch (e) {
      debugPrint('Version check failed: $e');
    }
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
    if (_requiresUpdate) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: UpdateRequiredScreen(
          minVersion: _minVersion ?? '',
          latestVersion: _latestVersion ?? '',
          updateUrl: _updateUrl,
        ),
        theme: ThemeManager.instance.currentTheme,
      );
    }
    final settings = ref.watch(settingsProvider);
    final themeMode = ThemeManager.instance.getThemeMode(settings.themeMode);

    if (_isInitializing) {
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

    return MaterialApp(
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
  }

  Widget _buildHomeScreen() {
    if (!_isAuthenticated && !_isGuestMode) {
      return LoginScreen(
        onAccessCode: _enterSharedRoster,
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
            Color.lerp(const Color(0xFF5A189A), const Color(0xFF0F4C5C), pulse2)!,
            Color.lerp(const Color(0xFFF72585), const Color(0xFF4CC9F0), pulse)!,
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
                    Container(
                      width: 82,
                      height: 82,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.15),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.white.withOpacity(0.2),
                            blurRadius: 20,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.calendar_today_rounded,
                        size: 38,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 24),
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
                    const SizedBox(height: 30),
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
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.08)
      ..strokeWidth = 1.2;

    final spacing = 28.0;
    final offset = spacing * progress;
    for (double x = -size.height; x < size.width + size.height; x += spacing) {
      final start = Offset(x + offset, 0);
      final end = Offset(x - size.height + offset, size.height);
      canvas.drawLine(start, end, paint);
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
