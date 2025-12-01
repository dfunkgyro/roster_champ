import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'providers.dart';
import 'screens/onboarding_screen.dart';
import 'supabase_service.dart';
import 'openai_service.dart';
import 'models.dart' as models;
import 'theme/theme_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize services
  await SupabaseService.instance.initialize();
  await OpenAIService.instance.initialize();
  await ThemeManager.instance.initialize();

  runApp(const ProviderScope(child: RosterChampApp()));
}

class RosterChampApp extends ConsumerStatefulWidget {
  const RosterChampApp({super.key});

  @override
  ConsumerState<RosterChampApp> createState() => _RosterChampAppState();
}

class _RosterChampAppState extends ConsumerState<RosterChampApp> {
  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    // Load settings
    await ref.read(settingsProvider.notifier).loadSettings();

    // Load roster data
    await ref.read(rosterProvider).loadFromLocal();

    // Check Supabase connection
    try {
      ref.read(supabaseStatusProvider.notifier).state = models.ServiceStatus(
        status: models.ConnectionStatus.connecting,
        lastChecked: DateTime.now(),
      );

      final connected = await SupabaseService.instance.checkConnection();

      ref.read(supabaseStatusProvider.notifier).state = models.ServiceStatus(
        status: connected
            ? models.ConnectionStatus.connected
            : models.ConnectionStatus.error,
        message: connected ? 'Connected to Supabase' : 'Connection failed',
        lastChecked: DateTime.now(),
      );
    } catch (e) {
      ref.read(supabaseStatusProvider.notifier).state = models.ServiceStatus(
        status: models.ConnectionStatus.error,
        message: 'Error: $e',
        lastChecked: DateTime.now(),
      );
    }

    // Check OpenAI connection
    try {
      ref.read(openaiStatusProvider.notifier).state = models.ServiceStatus(
        status: models.ConnectionStatus.connecting,
        lastChecked: DateTime.now(),
      );

      final connected = await OpenAIService.instance.checkConnection();

      ref.read(openaiStatusProvider.notifier).state = models.ServiceStatus(
        status: connected
            ? models.ConnectionStatus.connected
            : models.ConnectionStatus.error,
        message: connected ? 'Connected to OpenAI' : 'Connection failed',
        lastChecked: DateTime.now(),
      );
    } catch (e) {
      ref.read(openaiStatusProvider.notifier).state = models.ServiceStatus(
        status: models.ConnectionStatus.error,
        message: 'Error: $e',
        lastChecked: DateTime.now(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final themeMode = ThemeManager.instance.getThemeMode(settings.themeMode);

    return MaterialApp(
      title: 'Roster Champ Pro',
      debugShowCheckedModeBanner: false,
      theme: ThemeManager.instance.getLightTheme(settings.colorScheme),
      darkTheme: ThemeManager.instance.getDarkTheme(settings.colorScheme),
      themeMode: themeMode,
      home: const OnboardingScreen(),
    );
  }
}
