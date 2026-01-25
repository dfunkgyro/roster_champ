import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'notification_service.dart';
import 'auth_gate.dart';
import 'providers.dart';
import 'utils.dart';
import 'connection_status_widgets.dart';
import 'openai_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: "assets/.env");
  final supabaseUrl = dotenv.env['SUPABASE_URL'];
  final supabaseKey = dotenv.env['SUPABASE_ANON_KEY'];
  if (supabaseUrl != null && supabaseKey != null) {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseKey,
    );
  }
  await NotificationService.instance.initialize();
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> with WidgetsBindingObserver {
  Timer? _aiRetryTimer;
  int _aiRetryAttempt = 0;
  bool _aiInitInProgress = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // Load settings on startup
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await loadSettings(ref.read(settingsProvider.notifier));
      await _initializeServices();
    });
  }

  Future<void> _initializeServices() async {
    try {
      // Initialize connection status
      ref.read(supabaseStatusProvider.notifier).state =
          const ServiceStatus(status: ConnectionStatus.connecting);

      // Simulate connection (replace with actual Supabase init in production)
      await Future.delayed(const Duration(seconds: 1));

      ref.read(supabaseStatusProvider.notifier).state = ServiceStatus(
        status: ConnectionStatus.connected,
        lastSync: DateTime.now(),
      );
    } catch (e) {
      ref.read(supabaseStatusProvider.notifier).state = ServiceStatus(
        status: ConnectionStatus.error,
        errorMessage: e.toString(),
      );
    }

    final settings = ref.read(settingsProvider);
    if (settings.enableAiSuggestions) {
      _startAiInit();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _aiRetryTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    final rosterNotifier = ref.read(rosterProvider.notifier);

    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        rosterNotifier.onAppPaused();
        break;
      case AppLifecycleState.resumed:
        rosterNotifier.onAppResumed();
        if (ref.read(settingsProvider).enableAiSuggestions) {
          _startAiInit();
        }
        break;
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);

    return MaterialApp(
      title: 'Work Roster App Enhanced v2.0',
      theme: ThemeData(
        brightness: Brightness.light,
        useMaterial3: true,
        colorSchemeSeed: Colors.deepOrange,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        colorSchemeSeed: Colors.deepOrange,
        scaffoldBackgroundColor: Colors.grey[900],
        cardColor: Colors.grey[850],
      ),
      themeMode: settings.darkMode ? ThemeMode.dark : ThemeMode.light,
      home: const AuthGate(),
    );
  }

  void _startAiInit() {
    if (_aiInitInProgress) return;
    final status = ref.read(openaiStatusProvider);
    if (status.status == ConnectionStatus.connected) return;

    _aiInitInProgress = true;
    ref.read(openaiStatusProvider.notifier).state =
        const ServiceStatus(status: ConnectionStatus.connecting);

    Future(() async {
      try {
        await OpenAIService().initialize();
        if (!mounted) return;
        _aiRetryAttempt = 0;
        _aiRetryTimer?.cancel();
        ref.read(openaiStatusProvider.notifier).state = ServiceStatus(
          status: ConnectionStatus.connected,
          lastSync: DateTime.now(),
        );
      } catch (_) {
        if (!mounted) return;
        ref.read(openaiStatusProvider.notifier).state = ServiceStatus(
          status: ConnectionStatus.error,
          errorMessage: 'OpenAI init failed',
        );
        _scheduleAiRetry();
      } finally {
        _aiInitInProgress = false;
      }
    });
  }

  void _scheduleAiRetry() {
    if (_aiRetryTimer?.isActive ?? false) return;
    const delays = [
      Duration(seconds: 30),
      Duration(minutes: 2),
      Duration(minutes: 5),
      Duration(minutes: 10),
    ];
    final delay =
        delays[_aiRetryAttempt.clamp(0, delays.length - 1)];
    _aiRetryAttempt = (_aiRetryAttempt + 1).clamp(0, delays.length);
    _aiRetryTimer = Timer(delay, () {
      if (ref.read(settingsProvider).enableAiSuggestions) {
        _startAiInit();
      }
    });
  }
}
