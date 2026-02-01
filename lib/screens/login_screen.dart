import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../aws_service.dart';
import '../utils/error_handler.dart';
import '../home_screen.dart';
import '../providers.dart';
import 'roster_sharing_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  final VoidCallback? onGuestMode;
  final Future<void> Function(String code)? onAccessCode;

  const LoginScreen({
    super.key,
    this.onGuestMode,
    this.onAccessCode,
  });

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _displayNameController = TextEditingController();
  bool _isLoading = false;
  bool _isSignUp = false;
  bool _obscurePassword = true;

  bool _isValidEmail(String value) {
    return value.contains('@') && value.contains('.');
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  Future<void> _authenticate() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      ErrorHandler.showErrorSnackBar(context, 'Please fill in all fields');
      return;
    }

    if (!_isValidEmail(_emailController.text.trim())) {
      ErrorHandler.showErrorSnackBar(context, 'Enter a valid email address');
      return;
    }

    if (_isSignUp && _displayNameController.text.isEmpty) {
      ErrorHandler.showErrorSnackBar(context, 'Please enter a display name');
      return;
    }

    setState(() => _isLoading = true);

    try {
      bool signedIn = false;
      if (_isSignUp) {
        final needsConfirm = await AwsService.instance.signUp(
          _emailController.text.trim(),
          _passwordController.text,
          _displayNameController.text.trim(),
        );
        if (needsConfirm && mounted) {
          signedIn = await _showConfirmDialog(
            _emailController.text.trim(),
            password: _passwordController.text,
          );
        } else {
          await AwsService.instance.signIn(
            _emailController.text.trim(),
            _passwordController.text,
          );
          signedIn = true;
        }
      } else {
        await AwsService.instance.signIn(
          _emailController.text.trim(),
          _passwordController.text,
        );
        signedIn = true;
      }

      // Success - navigation will be handled by auth state listener
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isSignUp
                ? 'Account created successfully!'
                : 'Signed in successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        if (signedIn) {
          _handleAuthNavigation();
        }
      }
    } catch (e) {
      if (mounted) {
        final message = e.toString();
        final lower = message.toLowerCase();
        final offlineEligible = lower.contains('socketexception') ||
            lower.contains('failed host lookup') ||
            lower.contains('timed out') ||
            lower.contains('connection refused') ||
            lower.contains('network');
        if (!_isSignUp && offlineEligible) {
          final offlineSignedIn = await AwsService.instance.signInOffline(
            _emailController.text.trim(),
            _passwordController.text,
          );
          if (offlineSignedIn) {
            await ref.read(rosterProvider).loadFromLocal();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Offline mode enabled. Using cached roster.'),
                  backgroundColor: Colors.orange,
                ),
              );
              _handleAuthNavigation();
              return;
            }
          }
        }
        if (!_isSignUp && message.contains('Account not confirmed')) {
          final signedIn = await _showConfirmDialog(
            _emailController.text.trim(),
            password: _passwordController.text,
          );
          if (signedIn && mounted) {
            _handleAuthNavigation();
          }
        } else {
          ErrorHandler.showErrorSnackBar(context, e);
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _resetPassword() async {
    if (_emailController.text.trim().isEmpty) {
      ErrorHandler.showErrorSnackBar(context, 'Enter your email first');
      return;
    }
    setState(() => _isLoading = true);
    try {
      await AwsService.instance.resetPassword(_emailController.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password reset email sent')),
        );
      }
    } catch (e) {
      if (mounted) {
        final message = e.toString();
        if (!_isSignUp && message.contains('Account not confirmed')) {
          await _showConfirmDialog(_emailController.text.trim());
        } else {
          ErrorHandler.showErrorSnackBar(context, e);
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<bool> _showConfirmDialog(String email, {String? password}) async {
    final codeController = TextEditingController();
    bool signedIn = false;
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm your account'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Enter the confirmation code sent to $email.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: codeController,
              decoration: const InputDecoration(
                labelText: 'Confirmation code',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await AwsService.instance.resendConfirmationCode(email);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Code resent')),
                );
              }
            },
            child: const Text('Resend'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final code = codeController.text.trim();
              if (code.isEmpty) return;
              try {
                await AwsService.instance.confirmSignUp(email, code);
                if (password != null) {
                  await AwsService.instance.signIn(email, password);
                  signedIn = true;
                }
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(password != null
                          ? 'Account confirmed. Signed in.'
                          : 'Account confirmed. Sign in.'),
                    ),
                  );
                }
                if (context.mounted) {
                  Navigator.pop(context);
                }
              } catch (e) {
                if (context.mounted) {
                  ErrorHandler.showErrorSnackBar(context, e);
                }
              }
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    codeController.dispose();
    return signedIn;
  }

  void _handleAuthNavigation() {
    final hasRoster = AwsService.instance.currentRosterId != null;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (context) =>
            hasRoster ? const HomeScreen() : const RosterSharingScreen(),
      ),
      (route) => false,
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
              if (widget.onAccessCode != null) {
                setState(() => _isLoading = true);
                try {
                  await widget.onAccessCode!(code);
                } catch (e) {
                  if (mounted) {
                    ErrorHandler.showErrorSnackBar(context, e);
                  }
                } finally {
                  if (mounted) {
                    setState(() => _isLoading = false);
                  }
                }
              }
            },
            child: const Text('Open'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 24),
              Icon(
                Icons.calendar_today_rounded,
                size: 64,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 12),
              Text(
                'Roster Champion',
                style: GoogleFonts.inter(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color:
                      Theme.of(context).colorScheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: false,
                      label: Text('Sign In'),
                      icon: Icon(Icons.login),
                    ),
                    ButtonSegment(
                      value: true,
                      label: Text('Sign Up'),
                      icon: Icon(Icons.person_add),
                    ),
                  ],
                  selected: {_isSignUp},
                  onSelectionChanged: _isLoading
                      ? null
                      : (selection) {
                          setState(() => _isSignUp = selection.first);
                        },
                ),
              ),
              const SizedBox(height: 24),
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: Theme.of(context).dividerColor,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        _isSignUp
                            ? 'Create your account'
                            : 'Welcome back',
                        style: GoogleFonts.inter(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _emailController,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          prefixIcon: Icon(Icons.email_outlined),
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.emailAddress,
                        enabled: !_isLoading,
                      ),
                      const SizedBox(height: 12),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: _isSignUp
                            ? Column(
                                key: const ValueKey('signup-name'),
                                children: [
                                  TextField(
                                    controller: _displayNameController,
                                    decoration: const InputDecoration(
                                      labelText: 'Display Name',
                                      prefixIcon:
                                          Icon(Icons.person_outline),
                                      border: OutlineInputBorder(),
                                    ),
                                    enabled: !_isLoading,
                                  ),
                                  const SizedBox(height: 12),
                                ],
                              )
                            : const SizedBox.shrink(
                                key: ValueKey('signin-name'),
                              ),
                      ),
                      TextField(
                        controller: _passwordController,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline),
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                            ),
                            onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                          ),
                        ),
                        obscureText: _obscurePassword,
                        enabled: !_isLoading,
                      ),
                      const SizedBox(height: 16),
                      if (!_isSignUp)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _isLoading ? null : _resetPassword,
                            child: const Text('Forgot password?'),
                          ),
                        ),
                      const SizedBox(height: 8),
                      FilledButton(
                        onPressed: _isLoading ? null : _authenticate,
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(_isSignUp ? 'Create Account' : 'Sign In'),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed:
                            _isLoading ? null : _openAccessCodeDialog,
                        icon: const Icon(Icons.key),
                        label: const Text('View roster with access code'),
                      ),
                      if (widget.onGuestMode != null) ...[
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed:
                              _isLoading ? null : widget.onGuestMode,
                          child: const Text('Continue as guest'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _isSignUp
                    ? 'By creating an account you agree to the Terms.'
                    : 'Secure sign-in for your organization.',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
