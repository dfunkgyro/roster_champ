import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../aws_service.dart';
import '../utils/error_handler.dart';
import '../home_screen.dart';
import '../providers.dart';
import 'roster_sharing_screen.dart';
import '../import_roster_screen.dart';
import 'package:roster_champ/safe_text_field.dart';
import '../services/analytics_service.dart';

class LoginScreen extends ConsumerStatefulWidget {
  final VoidCallback? onGuestMode;
  final Future<void> Function(String code)? onAccessCode;
  final String? initialMessage;

  const LoginScreen({
    super.key,
    this.onGuestMode,
    this.onAccessCode,
    this.initialMessage,
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
  late final bool _safeInputMode = !kIsWeb && Platform.isAndroid;
  bool _isOffline = false;
  bool _canUseBiometrics = false;
  String? _formMessage;
  bool _formMessageIsError = false;
  bool _staySignedIn = true;

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

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    _staySignedIn = settings.staySignedIn;
    _checkConnectivity();
    _checkBiometrics();
    if (widget.initialMessage != null &&
        widget.initialMessage!.trim().isNotEmpty) {
      _formMessage = widget.initialMessage!.trim();
      _formMessageIsError = false;
    }
  }

  Future<void> _checkConnectivity() async {
    final connected = await AwsService.instance.checkConnection();
    if (mounted) {
      setState(() => _isOffline = !connected);
    }
  }

  Future<void> _checkBiometrics() async {
    if (kIsWeb) return;
    final auth = LocalAuthentication();
    try {
      final supported =
          await auth.isDeviceSupported() || await auth.canCheckBiometrics;
      if (mounted) {
        setState(() => _canUseBiometrics = supported);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _canUseBiometrics = false);
      }
    }
  }

  Future<void> _authenticate() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      _setFormMessage('Please fill in all fields', isError: true);
      ErrorHandler.showErrorSnackBar(context, 'Please fill in all fields');
      return;
    }

    if (!_isValidEmail(_emailController.text.trim())) {
      _setFormMessage('Enter a valid email address', isError: true);
      ErrorHandler.showErrorSnackBar(context, 'Enter a valid email address');
      return;
    }

    if (_isSignUp && _displayNameController.text.isEmpty) {
      _setFormMessage('Please enter a display name', isError: true);
      ErrorHandler.showErrorSnackBar(context, 'Please enter a display name');
      return;
    }

    setState(() => _isLoading = true);

    try {
      AnalyticsService.instance.trackEvent(
        'auth_attempt',
        type: 'auth',
        properties: {
          'method': _isSignUp ? 'signup' : 'password',
          'offline': _isOffline,
        },
      );
      ref.read(settingsProvider.notifier).updateSettings(
            ref.read(settingsProvider).copyWith(
                  staySignedIn: _staySignedIn,
                  signOutOnExit:
                      _staySignedIn ? false : ref.read(settingsProvider).signOutOnExit,
                ),
          );
      bool signedIn = false;
      if (_isSignUp) {
        final needsConfirm = await AwsService.instance.signUp(
          _emailController.text.trim(),
          _passwordController.text,
          _displayNameController.text.trim(),
        );
        if (needsConfirm && mounted) {
          _setFormMessage(
            'We sent a verification code to your email. Enter it to finish sign up.',
          );
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
        _setFormMessage(
          _isSignUp ? 'Account created successfully!' : 'Signed in successfully!',
          isError: false,
        );
        // Removed success banner to avoid intrusive popup on sign-in.
        if (signedIn) {
          AnalyticsService.instance.trackEvent(
            'auth_success',
            type: 'auth',
            properties: {
              'method': _isSignUp ? 'signup' : 'password',
            },
          );
          await AwsService.instance.ensureCurrentRosterSelected();
          if (AwsService.instance.currentRosterId == null) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool('show_template_prompt', true);
          }
          await _handleAuthNavigation();
        }
      }
    } catch (e) {
      if (mounted) {
        final message = e.toString();
        _setFormMessage(message, isError: true);
        final lower = message.toLowerCase();
        final offlineEligible = lower.contains('socketexception') ||
            lower.contains('failed host lookup') ||
            lower.contains('timed out') ||
            lower.contains('connection refused') ||
            lower.contains('network');
        if (!_isSignUp && offlineEligible) {
          setState(() => _isOffline = true);
          final offlineSignedIn = await AwsService.instance.signInOffline(
            _emailController.text.trim(),
            _passwordController.text,
          );
          if (offlineSignedIn) {
            AnalyticsService.instance.trackEvent(
              'auth_offline_success',
              type: 'auth',
              properties: {'method': 'password'},
            );
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
        if (!_isSignUp &&
            (message.contains('Account not confirmed') ||
                message.contains('User Confirmation Necessary'))) {
          _setFormMessage(
            'Account not confirmed. We sent a verification code to your email.',
            isError: false,
          );
          final signedIn = await _showConfirmDialog(
            _emailController.text.trim(),
            password: _passwordController.text,
          );
          if (signedIn && mounted) {
            _handleAuthNavigation();
          }
        } else {
          AnalyticsService.instance.trackEvent(
            'auth_failed',
            type: 'auth',
            properties: {
              'method': _isSignUp ? 'signup' : 'password',
              'reason': message,
            },
          );
          ErrorHandler.showErrorSnackBar(context, e);
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _signInOffline() async {
    if (_isLoading) return;
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      _setFormMessage(
        'Enter your email and password to unlock offline mode.',
        isError: true,
      );
      return;
    }
    setState(() => _isLoading = true);
    final ok = await AwsService.instance.signInOffline(email, password);
    if (!ok) {
      _setFormMessage(
        'Offline sign-in failed. Use the last saved email and password.',
        isError: true,
      );
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    AnalyticsService.instance.trackEvent(
      'auth_offline_success',
      type: 'auth',
      properties: {'method': 'password'},
    );
    await ref.read(rosterProvider).loadFromLocal();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Offline mode enabled. Using cached roster.'),
          backgroundColor: Colors.orange,
        ),
      );
      _handleAuthNavigation();
      setState(() => _isLoading = false);
    }
  }

  Future<void> _signInOfflineWithBiometrics() async {
    if (_isLoading) return;
    if (!AwsService.instance.hasOfflineCredentials) {
      _setFormMessage(
        'Offline biometrics requires a prior online sign-in on this device.',
        isError: true,
      );
      return;
    }
    final auth = LocalAuthentication();
    try {
      final ok = await auth.authenticate(
        localizedReason: 'Unlock your roster with biometrics.',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
      if (!ok) return;
    } catch (e) {
      _setFormMessage('Biometric unlock failed: $e', isError: true);
      return;
    }
    final signedIn = await AwsService.instance.signInOfflineWithBiometrics();
    if (!signedIn) {
      _setFormMessage('Offline unlock not available on this device.',
          isError: true);
      return;
    }
    await ref.read(rosterProvider).loadFromLocal();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Offline mode unlocked with biometrics.'),
          backgroundColor: Colors.orange,
        ),
      );
      _handleAuthNavigation();
    }
  }

  Future<void> _signInWithGoogle({bool forceAccountPicker = false}) async {
    setState(() => _isLoading = true);
    bool cancelled = false;
    AnalyticsService.instance.trackEvent(
      'auth_google_start',
      type: 'auth',
      properties: {'forcedPicker': forceAccountPicker},
    );
    if (mounted && !kIsWeb) {
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
        AnalyticsService.instance.trackEvent(
          'auth_google_success',
          type: 'auth',
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Signed in with Google.')),
        );
        _handleAuthNavigation();
      }
    } catch (e) {
      if (mounted && !cancelled) {
        AnalyticsService.instance.trackEvent(
          'auth_google_failed',
          type: 'auth',
          properties: {'reason': e.toString()},
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Google sign-in failed: $e')),
        );
      }
    } finally {
      if (mounted) {
        if (!kIsWeb) {
          Navigator.of(context, rootNavigator: true).maybePop();
        }
        setState(() => _isLoading = false);
      }
    }
  }

  void _setFormMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    setState(() {
      _formMessage = message;
      _formMessageIsError = isError;
    });
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
    bool isSending = false;
    bool isConfirming = false;
    DateTime? lastSentAt;
    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
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
              onPressed: isSending
                  ? null
                  : () async {
                      final now = DateTime.now();
                      if (lastSentAt != null &&
                          now.difference(lastSentAt!).inSeconds < 10) {
                        return;
                      }
                      setStateDialog(() => isSending = true);
                      try {
                        await AwsService.instance.resendConfirmationCode(email);
                        lastSentAt = DateTime.now();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Code resent')),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ErrorHandler.showErrorSnackBar(context, e);
                        }
                      } finally {
                        if (context.mounted) {
                          setStateDialog(() => isSending = false);
                        }
                      }
                    },
              child: Text(isSending ? 'Sending...' : 'Resend'),
            ),
            TextButton(
              onPressed: isConfirming ? null : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: isConfirming
                  ? null
                  : () async {
                      final code = codeController.text.trim();
                      if (code.isEmpty) return;
                      setStateDialog(() => isConfirming = true);
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
                      } finally {
                        if (context.mounted) {
                          setStateDialog(() => isConfirming = false);
                        }
                      }
                    },
              child: Text(isConfirming ? 'Confirming...' : 'Confirm'),
            ),
          ],
        ),
      ),
    );
    codeController.dispose();
    return signedIn;
  }

  Future<void> _handleAuthNavigation() async {
    final hasRoster = AwsService.instance.currentRosterId != null;
    if (!context.mounted) return;
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
                      if (_formMessage != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _formMessageIsError
                                ? Theme.of(context).colorScheme.errorContainer
                                : Theme.of(context)
                                    .colorScheme
                                    .secondaryContainer
                                    .withOpacity(0.6),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _formMessageIsError
                                    ? Icons.error_outline
                                    : Icons.info_outline,
                                size: 18,
                                color: _formMessageIsError
                                    ? Theme.of(context)
                                        .colorScheme
                                        .onErrorContainer
                                    : Theme.of(context)
                                        .colorScheme
                                        .onSecondaryContainer,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _formMessage!,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: _formMessageIsError
                                            ? Theme.of(context)
                                                .colorScheme
                                                .onErrorContainer
                                            : Theme.of(context)
                                                .colorScheme
                                                .onSecondaryContainer,
                                      ),
                                ),
                              ),
                              if (_formMessageIsError &&
                                  _formMessage!
                                      .toLowerCase()
                                      .contains('already exists'))
                                TextButton(
                                  onPressed: () {
                                    setState(() {
                                      _isSignUp = false;
                                    });
                                  },
                                  child: const Text('Sign in'),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (_formMessage != null &&
                          _formMessage!
                              .toLowerCase()
                              .contains('account not confirmed')) ...[
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: _isLoading ? null : _resetPassword,
                            icon: const Icon(Icons.mark_email_read_outlined),
                            label: const Text('Resend code'),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Stay signed in on this device'),
                        subtitle: const Text(
                          'Turn off to sign out when the app closes.',
                        ),
                        value: _staySignedIn,
                        onChanged: _isLoading
                            ? null
                            : (value) {
                                setState(() => _staySignedIn = value);
                              },
                      ),
                      const SizedBox(height: 8),
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
                      if (_isOffline) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.orange),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.wifi_off, color: Colors.orange),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  'You are offline. Sign in with cached credentials.',
                                ),
                              ),
                              IconButton(
                                tooltip: 'Retry connection',
                                onPressed: _isLoading ? null : _checkConnectivity,
                                icon: const Icon(Icons.refresh),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (!_isSignUp &&
                            AwsService.instance.hasOfflineCredentials)
                          OutlinedButton.icon(
                            onPressed: _isLoading ? null : _signInOffline,
                            icon: const Icon(Icons.lock_open),
                            label: const Text('Sign in offline'),
                          ),
                        if (!_isSignUp &&
                            _canUseBiometrics &&
                            AwsService.instance.hasOfflineCredentials) ...[
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed:
                                _isLoading ? null : _signInOfflineWithBiometrics,
                            icon: const Icon(Icons.fingerprint),
                            label: const Text('Unlock with biometrics'),
                          ),
                        ],
                      ],
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _isLoading ? null : _signInWithGoogle,
                        icon: const Icon(Icons.g_mobiledata),
                        label: const Text('Sign in with Google'),
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
    final isAndroid = !kIsWeb && Platform.isAndroid;
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
