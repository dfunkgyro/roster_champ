import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/document_analyzer_service.dart';
import 'services/roster_service.dart';
import 'services/storage_service.dart';
import 'screens/home_screen.dart';
import 'utils/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize services
  final storageService = StorageService();
  await storageService.init();

  runApp(
    MultiProvider(
      providers: [
        Provider<StorageService>.value(value: storageService),
        Provider<DocumentAnalyzerService>(
          create: (_) => DocumentAnalyzerService(),
        ),
        ChangeNotifierProvider<RosterService>(
          create: (_) => RosterService(),
        ),
      ],
      child: const PicTabApp(),
    ),
  );
}

class PicTabApp extends StatelessWidget {
  const PicTabApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PicTab',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      home: const HomeScreen(),
    );
  }
}
