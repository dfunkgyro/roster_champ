import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'login_screen.dart';
import '../aws_service.dart';
import '../utils/error_handler.dart';

class WelcomeScreen extends StatefulWidget {
  final VoidCallback onGuestMode;
  final Future<void> Function(String code) onAccessCode;

  const WelcomeScreen({
    super.key,
    required this.onGuestMode,
    required this.onAccessCode,
  });

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Spacer(flex: 2),
              // App Icon and Title
              Icon(
                Icons.calendar_today_rounded,
                size: 100,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(
                'Roster Champ Pro',
                style: GoogleFonts.inter(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Smart roster management with AI insights',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const Spacer(flex: 1),

              // Feature Highlights
              _buildFeatureRow(Icons.psychology, 'AI-Powered Suggestions'),
              _buildFeatureRow(Icons.cloud_sync, 'Multi-Device Sync'),
              _buildFeatureRow(Icons.group, 'Team Collaboration'),
              _buildFeatureRow(Icons.analytics, 'Advanced Analytics'),

              const Spacer(flex: 2),

              // Action Buttons
              Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _isLoading ? null : _openEmailLogin,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
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
                    child: OutlinedButton(
                      onPressed: _isLoading ? null : widget.onGuestMode,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text(
                        'Continue as Guest',
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
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
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Guest Mode Info
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info, size: 20, color: Colors.blue[700]),
                        const SizedBox(width: 8),
                        Text(
                          'Guest Mode',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue[800],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '• Use the app immediately without an account\n'
                      '• All data is stored locally on this device\n'
                      '• Perfect for trying out features\n'
                      '• Sign up later to sync across devices and access cloud features',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: Colors.blue[700],
                      ),
                    ),
                  ],
                ),
              ),

              const Spacer(flex: 1),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 20, color: Colors.green),
          const SizedBox(width: 12),
          Text(
            text,
            style: GoogleFonts.inter(fontSize: 14),
          ),
        ],
      ),
    );
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
        content: TextField(
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
