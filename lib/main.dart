import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables first
  await EnvLoader.instance.load();

  // Initialize services
  await AwsService.instance.initialize();
  await AiService.instance.initialize();
  await ThemeManager.instance.initialize();

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

  @override
  void initState() {
    super.initState();
    _initializeApp();
    _setupAuthListener();
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
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final themeMode = ThemeManager.instance.getThemeMode(settings.themeMode);

    if (_isInitializing) {
      return MaterialApp(
        home: Scaffold(
          backgroundColor: Theme.of(context).colorScheme.background,
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.calendar_today_rounded,
                  size: 80,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 20),
                Text(
                  'Roster Champ Pro',
                  style: GoogleFonts.inter(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),
                const CircularProgressIndicator(),
                const SizedBox(height: 10),
                Text(
                  'Initializing...',
                  style: GoogleFonts.inter(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                if (!_awsConfigured) ...[
                  const SizedBox(height: 10),
                  Text(
                    'AWS: Not configured',
                    style: GoogleFonts.inter(
                      color: Colors.orange,
                      fontSize: 12,
                    ),
                  ),
                ],
                if (!_aiConfigured) ...[
                  Text(
                    'AI: Not configured',
                    style: GoogleFonts.inter(
                      color: Colors.orange,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return MaterialApp(
      title: 'Roster Champ Pro',
      debugShowCheckedModeBanner: false,
      theme: ThemeManager.instance.getLightTheme(settings.colorScheme),
      darkTheme: ThemeManager.instance.getDarkTheme(settings.colorScheme),
      themeMode: themeMode,
      home: _buildHomeScreen(),
    );
  }

  Widget _buildHomeScreen() {
    if (!_isAuthenticated && !_isGuestMode) {
      return LoginScreen(
        onGuestMode: _enterGuestMode,
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
