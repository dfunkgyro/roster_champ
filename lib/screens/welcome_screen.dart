import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'login_screen.dart';
import '../utils/error_handler.dart';
import 'package:roster_champ/safe_text_field.dart';

class WelcomeScreen extends StatefulWidget {
  final Future<void> Function(String code) onAccessCode;

  const WelcomeScreen({
    super.key,
    required this.onAccessCode,
  });

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with SingleTickerProviderStateMixin {
  bool _isLoading = false;
  late final AnimationController _controller;
  late final Animation<double> _fadeIn;
  late final Animation<double> _float;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _fadeIn = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _float = Tween<double>(begin: 0, end: 8).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colorScheme.background,
      body: SafeArea(
        child: Stack(
          children: [
            _buildBackground(context),
            Padding(
              padding: const EdgeInsets.all(24),
              child: FadeTransition(
                opacity: _fadeIn,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Spacer(flex: 2),
                    Transform.translate(
                      offset: Offset(0, -_float.value),
                      child: _buildHeroHeader(context),
                    ),
                    const SizedBox(height: 24),
                    _buildFeatureGrid(context),
                    const Spacer(flex: 2),
                    _buildActions(context),
                    const SizedBox(height: 20),
                    const SizedBox.shrink(),
                    const Spacer(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackground(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF0E1018),
            Theme.of(context).colorScheme.primary.withOpacity(0.25),
            const Color(0xFF131B2B),
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -80,
            right: -60,
            child: _buildBlob(const Color(0xFF5BC0EB), 220),
          ),
          Positioned(
            bottom: -100,
            left: -80,
            child: _buildBlob(const Color(0xFFFDE74C), 240),
          ),
          Positioned(
            top: 180,
            left: -40,
            child: _buildBlob(const Color(0xFF9BC53D), 140),
          ),
        ],
      ),
    );
  }

  Widget _buildBlob(Color color, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withOpacity(0.2),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.2),
            blurRadius: 40,
            spreadRadius: 10,
          ),
        ],
      ),
    );
  }

  Widget _buildHeroHeader(BuildContext context) {
    final textColor = Theme.of(context).colorScheme.onPrimaryContainer;
    return Column(
      children: [
        Container(
          width: 112,
          height: 112,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Theme.of(context).colorScheme.primaryContainer,
            boxShadow: [
              BoxShadow(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.35),
                blurRadius: 24,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Icon(
            Icons.calendar_month_rounded,
            size: 56,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'Roster Champ',
          style: GoogleFonts.spaceGrotesk(
            fontSize: 34,
            fontWeight: FontWeight.w700,
            color: textColor,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Design rosters that feel fair, fast, and future-proof.',
          style: GoogleFonts.spaceGrotesk(
            fontSize: 15,
            color: textColor.withOpacity(0.7),
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildFeatureGrid(BuildContext context) {
    final features = [
      const _FeatureTile(
        icon: Icons.psychology,
        title: 'AI insights',
        subtitle: 'Explainable roster suggestions.',
      ),
      const _FeatureTile(
        icon: Icons.sync_alt,
        title: 'Instant sync',
        subtitle: 'Pick up where you left off.',
      ),
      const _FeatureTile(
        icon: Icons.groups_rounded,
        title: 'Team ready',
        subtitle: 'Shared access and controls.',
      ),
      const _FeatureTile(
        icon: Icons.auto_graph,
        title: 'Live KPIs',
        subtitle: 'Coverage, leave, and risk.',
      ),
    ];

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      physics: const NeverScrollableScrollPhysics(),
      children:
          features.map((feature) => _buildFeatureCard(context, feature)).toList(),
    );
  }

  Widget _buildFeatureCard(BuildContext context, _FeatureTile feature) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withOpacity(0.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withOpacity(0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            feature.icon,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 10),
          Text(
            feature.title,
            style: GoogleFonts.spaceGrotesk(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            feature.subtitle,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _isLoading ? null : _openEmailLogin,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
            ),
            child: const Text(
              'Sign In / Create Account',
              style: TextStyle(fontSize: 16),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: const SizedBox.shrink(),
        ),
        const SizedBox(height: 0),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _isLoading ? null : _openAccessCodeDialog,
            icon: const Icon(Icons.key),
            label: const Text(
              'View Roster with Access Code',
              style: TextStyle(fontSize: 16),
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              foregroundColor: Theme.of(context).colorScheme.onSurface,
              side: BorderSide(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGuestInfo(BuildContext context) {
    return const SizedBox.shrink();
  }

  Future<void> _openEmailLogin() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
    );
  }

  Future<void> _openAccessCodeDialog() async {
    final controller = TextEditingController();
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enter Access Code'),
        content: SafeTextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Access code',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final code = controller.text.trim();
              if (code.isEmpty) return;
              Navigator.pop(context);
              setState(() => _isLoading = true);
              try {
                await widget.onAccessCode(code);
              } catch (e) {
                if (mounted) {
                  ErrorHandler.showErrorSnackBar(context, e);
                }
              } finally {
                if (mounted) {
                  setState(() => _isLoading = false);
                }
              }
            },
            child: const Text('Open'),
          ),
        ],
      ),
    );
  }
}

class _FeatureTile {
  final IconData icon;
  final String title;
  final String subtitle;

  const _FeatureTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
}
