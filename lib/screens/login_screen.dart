import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../aws_service.dart';
import '../utils/error_handler.dart';
import '../home_screen.dart';
import '../providers.dart';
import 'roster_sharing_screen.dart';
import 'package:roster_champ/safe_text_field.dart';

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
  static const String _privacyUrl = 'https://rosterchampion.com/privacy';
  static const String _termsUrl = 'https://rosterchampion.com/terms';
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _emailFocus = FocusNode();
  final _displayFocus = FocusNode();
  final _passwordFocus = FocusNode();
  bool _isLoading = false;
  bool _isSignUp = false;
  bool _obscurePassword = true;
  late final bool _safeInputMode = Platform.isAndroid;

  bool _isValidEmail(String value) {
    return value.contains('@') && value.contains('.');
  }

  Future<void> _openExternal(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to open $url')),
        );
      }
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _displayNameController.dispose();
    _emailFocus.dispose();
    _displayFocus.dispose();
    _passwordFocus.dispose();
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

  Future<void> _signInWithGoogle({bool forceAccountPicker = false}) async {
    setState(() => _isLoading = true);
    bool cancelled = false;
    if (mounted) {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return AlertDialog(
            title: const Text('Waiting for Google'),
            content: const Text(
              'Complete sign-in in the browser. You can cancel if you changed your mind.',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  cancelled = true;
                  AwsService.instance.cancelGoogleSignIn();
                  Navigator.of(context).pop();
                },
                child: const Text('Cancel'),
              ),
            ],
          );
        },
      );
    }

    try {
      await AwsService.instance
          .signInWithGoogle(forceAccountPicker: forceAccountPicker);
      if (mounted && !cancelled) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Signed in with Google.')),
        );
      }
    } catch (e) {
      if (mounted && !cancelled) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Google sign-in failed: $e')),
        );
      }
    } finally {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).maybePop();
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
            SafeTextField(
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
    final authProvider = AwsService.instance.authProvider;
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
                      _buildEmailField(),
                      const SizedBox(height: 12),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: _isSignUp
                            ? Column(
                                key: const ValueKey('signup-name'),
                                children: [
                                  _buildDisplayNameField(),
                                  const SizedBox(height: 12),
                                ],
                              )
                            : const SizedBox.shrink(
                                key: ValueKey('signin-name'),
                              ),
                      ),
                      _buildPasswordField(),
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
                        onPressed: _isLoading ? null : _signInWithGoogle,
                        icon: const Icon(Icons.g_mobiledata),
                        label: const Text('Sign in with Google'),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _isLoading
                            ? null
                            : () => _signInWithGoogle(
                                  forceAccountPicker: true,
                                ),
                        icon: const Icon(Icons.switch_account),
                        label: const Text('Switch Google account'),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed:
                            _isLoading ? null : _openAccessCodeDialog,
                        icon: const Icon(Icons.key),
                        label: const Text('View roster with access code'),
                      ),
                      const SizedBox(height: 12),
                      if (authProvider != null)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceVariant,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.verified_user, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Signed in last time with ${authProvider == 'google' ? 'Google' : 'Email'}',
                                ),
                              ),
                            ],
                          ),
                        ),
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
              const SizedBox(height: 6),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: () => _openExternal(_termsUrl),
                    child: const Text('Terms'),
                  ),
                  TextButton(
                    onPressed: () => _openExternal(_privacyUrl),
                    child: const Text('Privacy'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmailField() {
    return _buildSafeField(
      controller: _emailController,
      focusNode: _emailFocus,
      label: 'Email',
      icon: Icons.email_outlined,
      keyboardType:
          _safeInputMode ? TextInputType.text : TextInputType.emailAddress,
      textInputAction: TextInputAction.next,
      onSubmitted: (_) => _displayFocus.requestFocus(),
    );
  }

  Widget _buildDisplayNameField() {
    return _buildSafeField(
      controller: _displayNameController,
      focusNode: _displayFocus,
      label: 'Display Name',
      icon: Icons.person_outline,
      keyboardType: TextInputType.text,
      textInputAction: TextInputAction.next,
      onSubmitted: (_) => _passwordFocus.requestFocus(),
    );
  }

  Widget _buildPasswordField() {
    return _buildSafeField(
      controller: _passwordController,
      focusNode: _passwordFocus,
      label: 'Password',
      icon: Icons.lock_outline,
      keyboardType:
          _safeInputMode ? TextInputType.text : TextInputType.visiblePassword,
      textInputAction: TextInputAction.done,
      obscureText: _obscurePassword,
      suffix: IconButton(
        icon: Icon(
          _obscurePassword ? Icons.visibility : Icons.visibility_off,
        ),
        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
      ),
      onSubmitted: (_) => _authenticate(),
    );
  }

  Widget _buildSafeField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String label,
    required IconData icon,
    required TextInputType keyboardType,
    required TextInputAction textInputAction,
    bool obscureText = false,
    Widget? suffix,
    ValueChanged<String>? onSubmitted,
  }) {
    final isAndroid = Platform.isAndroid;
    return SafeTextField(
      controller: controller,
      focusNode: focusNode,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: const OutlineInputBorder(),
        suffixIcon: suffix,
      ),
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      obscureText: obscureText,
      textCapitalization: TextCapitalization.none,
      inputFormatters: [FilteringTextInputFormatter.singleLineFormatter],
      autofillHints: null,
      autocorrect: !isAndroid,
      enableSuggestions: !isAndroid,
      enableIMEPersonalizedLearning: false,
      enabled: !_isLoading,
    );
  }
}
