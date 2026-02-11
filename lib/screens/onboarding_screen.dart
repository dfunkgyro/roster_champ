import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../home_screen.dart';
import '../providers.dart';
import '../dialogs.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  final bool isGuestMode;

  const OnboardingScreen({
    super.key,
    this.isGuestMode = false,
  });

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  int _currentStep = 0;
  final PageController _pageController = PageController();

  @override
  Widget build(BuildContext context) {
    final roster = ref.watch(rosterProvider);

    // Skip onboarding if roster is already initialized
    if (roster.staffMembers.isNotEmpty && roster.masterPattern.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => HomeScreen(
              isGuestMode: widget.isGuestMode,
              onExitGuestMode: () {}, // Empty callback for onboarding
            ),
          ),
        );
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      body: SafeArea(
        child: Column(
          children: [
            // Progress indicator
            LinearProgressIndicator(
              value: (_currentStep + 1) / 3,
              backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
              color: Theme.of(context).colorScheme.primary,
            ),

            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (index) => setState(() => _currentStep = index),
                children: [
                  _buildWelcomeStep(),
                  _buildSetupStep(),
                  _buildCompleteStep(),
                ],
              ),
            ),

            // Navigation buttons
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (_currentStep > 0)
                    TextButton(
                      onPressed: () => _pageController.previousPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      ),
                      child: const Text('Back'),
                    )
                  else
                    const SizedBox(width: 80),
                  if (_currentStep < 2)
                    FilledButton(
                      onPressed: () => _pageController.nextPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      ),
                      child: const Text('Next'),
                    )
                  else
                    FilledButton(
                      onPressed: _completeOnboarding,
                      child: const Text('Get Started'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomeStep() {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.calendar_today_rounded,
            size: 80,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 32),
          Text(
            'Welcome to Roster Champion',
            style: GoogleFonts.inter(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onBackground,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            widget.isGuestMode
                ? 'You\'re using the app in guest mode. All data will be stored locally on this device.'
                : 'The most powerful roster management app with AI-powered insights and seamless team coordination.',
            style: GoogleFonts.inter(
              fontSize: 16,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 48),
          _buildFeatureRow(Icons.psychology, 'AI-Powered Suggestions'),
          _buildFeatureRow(Icons.cloud_sync,
              widget.isGuestMode ? 'Local Storage' : 'Real-time Sync'),
          _buildFeatureRow(Icons.analytics, 'Advanced Analytics'),
          _buildFeatureRow(Icons.group, 'Team Management'),
          if (widget.isGuestMode) ...[
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange),
              ),
              child: Row(
                children: [
                  Icon(Icons.info, color: Colors.orange, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Guest Mode: Data stored locally only',
                      style: GoogleFonts.inter(
                        color: Colors.orange[800],
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSetupStep() {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.settings,
            size: 60,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 32),
          Text(
            'Setup Your Roster',
            style: GoogleFonts.inter(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Let\'s configure your roster with the right number of staff and rotation cycle.',
            style: GoogleFonts.inter(
              fontSize: 16,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: _showInitializeDialog,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Configure Roster'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompleteStep() {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.check_circle_rounded,
            size: 80,
            color: Colors.green,
          ),
          const SizedBox(height: 32),
          Text(
            'Ready to Go!',
            style: GoogleFonts.inter(
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            widget.isGuestMode
                ? 'Your roster is all set up and ready to use in guest mode. '
                    'You can sign up anytime to sync your data across devices.'
                : 'Your roster is all set up and ready to use. Start managing your team efficiently with powerful features.',
            style: GoogleFonts.inter(
              fontSize: 16,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 48),
          _buildFeatureRow(Icons.edit_calendar, 'Manage Shifts & Changes'),
          _buildFeatureRow(Icons.event, 'Track Events & Holidays'),
          _buildFeatureRow(Icons.insights, 'View Analytics & Reports'),
          _buildFeatureRow(Icons.sync,
              widget.isGuestMode ? 'Local Data Only' : 'Sync Across Devices'),
        ],
      ),
    );
  }

  Widget _buildFeatureRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Text(
            text,
            style: GoogleFonts.inter(fontSize: 16),
          ),
        ],
      ),
    );
  }

  Future<void> _showInitializeDialog() async {
    await showDialog(
      context: context,
      builder: (context) => InitializeRosterDialog(
        onInitialize: (cycle, people) {
          ref.read(rosterProvider).initializeRoster(cycle, people);
          _pageController.nextPage(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        },
      ),
    );
  }

  void _completeOnboarding() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => HomeScreen(
          isGuestMode: widget.isGuestMode,
          onExitGuestMode: () {}, // Empty callback for onboarding
        ),
      ),
    );
  }
}
