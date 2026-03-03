import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math' as math;
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import '../aws_service.dart';
import 'login_screen.dart';
import '../services/activity_log_service.dart';

class PaywallScreen extends StatefulWidget {
  final String subscriptionStatus;
  final String subscriptionPlan;
  final bool? trialActive;
  final String? trialEndsAt;
  final Future<void> Function()? onRefreshStatus;
  final bool isLoading;

  const PaywallScreen({
    super.key,
    required this.subscriptionStatus,
    required this.subscriptionPlan,
    this.trialActive,
    this.trialEndsAt,
    this.onRefreshStatus,
  }) : isLoading = false;

  const PaywallScreen.loading({super.key})
      : subscriptionStatus = 'loading',
        subscriptionPlan = 'none',
        trialActive = false,
        trialEndsAt = null,
        onRefreshStatus = null,
        isLoading = true;

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  bool _busy = false;
  bool _isOffline = false;
  bool _isRestoring = false;
  bool _showRestoreSuccess = false;
  bool _didAutoRestore = false;
  String _lastStatus = 'inactive';
  String? _lastCheckoutError;
  String? _paymentSuccessPlan;
  DateTime? _paymentSuccessAt;
  DateTime? _trialEndsAt;
  Map<String, double> _fxRates = {};
  String? _fxUpdatedAt;

  static const Set<String> _euroRegions = {
    'AT',
    'BE',
    'CY',
    'DE',
    'EE',
    'ES',
    'FI',
    'FR',
    'GR',
    'HR',
    'IE',
    'IT',
    'LT',
    'LU',
    'LV',
    'MT',
    'NL',
    'PT',
    'SI',
    'SK',
  };

  String _priceForPlan(String plan) {
    switch (plan) {
      case 'starter':
        return '\$9 / month';
      case 'operations':
        return '\$29 / month';
      case 'enterprise':
        return '\$79 / month';
      default:
        return '\$0 / month';
    }
  }

  String _currencyForLocale(Locale locale) {
    final region = (locale.countryCode ?? '').toUpperCase();
    if (region == 'GB' || region == 'UK') return 'GBP';
    if (region == 'JP') return 'JPY';
    if (region == 'CN') return 'CNY';
    if (region == 'IN') return 'INR';
    if (_euroRegions.contains(region)) return 'EUR';
    return 'USD';
  }

  double _usdForPlan(String plan) {
    switch (plan) {
      case 'starter':
        return 9;
      case 'operations':
        return 29;
      case 'enterprise':
        return 79;
      default:
        return 0;
    }
  }

  String? _localEstimate(String plan, Locale locale) {
    final currency = _currencyForLocale(locale);
    if (currency == 'USD') return null;
    final rate = _fxRates[currency];
    if (rate == null) return null;
    final usdAmount = _usdForPlan(plan);
    if (usdAmount == 0) return null;
    final estimate = usdAmount * rate;
    final formatter = NumberFormat.simpleCurrency(name: currency);
    return '≈ ${formatter.format(estimate)} (converted at checkout)';
  }

  Future<void> _loadFxRates() async {
    try {
      final data = await AwsService.instance.getFxRates();
      final rates = (data['rates'] as Map?)?.cast<String, dynamic>() ?? {};
      final parsed = <String, double>{};
      rates.forEach((key, value) {
        final numValue = value is num ? value.toDouble() : double.tryParse('$value');
        if (numValue != null) {
          parsed[key.toUpperCase()] = numValue;
        }
      });
      if (mounted) {
        setState(() {
          _fxRates = parsed;
          _fxUpdatedAt = data['updatedAt']?.toString();
        });
      }
    } catch (_) {
      // Ignore FX failures, USD remains primary display.
    }
  }

  @override
  void initState() {
    super.initState();
    _lastStatus = widget.subscriptionStatus;
    _trialEndsAt = _parseTrialDate(widget.trialEndsAt);
    _checkConnection();
    _loadFxRates();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _attemptAutoRestore();
    });
  }

  @override
  void didUpdateWidget(covariant PaywallScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _lastStatus = widget.subscriptionStatus;
    _trialEndsAt = _parseTrialDate(widget.trialEndsAt);
  }

  DateTime? _parseTrialDate(String? value) {
    if (value == null || value.isEmpty) return null;
    final parsed = DateTime.tryParse(value);
    return parsed;
  }

  int _trialDaysRemaining() {
    if (_trialEndsAt == null) return 0;
    final now = DateTime.now();
    final diff = _trialEndsAt!.difference(now);
    if (diff.isNegative) return 0;
    return diff.inDays + (diff.inHours % 24 > 0 ? 1 : 0);
  }

  Future<void> _checkConnection() async {
    final connected = await AwsService.instance.checkConnection();
    if (mounted) {
      setState(() {
        _isOffline = !connected;
      });
    }
  }

  Future<void> _attemptAutoRestore() async {
    if (_didAutoRestore) return;
    _didAutoRestore = true;
    await _restoreAccess(showSpinner: true);
  }

  Future<void> _restoreAccess({bool showSpinner = false}) async {
    if (_isOffline) {
      _showOfflineNotice();
      return;
    }
    if (showSpinner) {
      setState(() => _isRestoring = true);
    }
    if (widget.onRefreshStatus != null) {
      await widget.onRefreshStatus!();
    }
    final profile = await AwsService.instance.getProfile();
    final status = profile['subscriptionStatus']?.toString() ?? 'inactive';
    final becameActive = (status == 'active' || status == 'trialing') &&
        !(_lastStatus == 'active' || _lastStatus == 'trialing');
    _lastStatus = status;
    await _checkConnection();
    if (mounted) {
      setState(() {
        _isRestoring = false;
        _showRestoreSuccess = becameActive;
      });
      if (becameActive) {
        Future.delayed(const Duration(seconds: 4), () {
          if (mounted) {
            setState(() => _showRestoreSuccess = false);
          }
        });
      }
    }
  }

  Future<void> _openCheckout(String plan) async {
    if (_isOffline) {
      _showOfflineNotice();
      return;
    }
    setState(() => _busy = true);
    try {
      final url = await AwsService.instance.createCheckoutSession(plan: plan);
      if (url != null && url.isNotEmpty) {
        ActivityLogService.instance.addInfo(
          'Billing - Starting checkout for $plan',
        );
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        return;
      }
      _lastCheckoutError = 'Checkout URL missing for $plan';
      _showCheckoutError('Unable to start checkout. Please try again.');
      ActivityLogService.instance.addError(
        'Billing - Checkout URL missing for $plan',
        const ['Retry checkout', 'Check billing setup'],
      );
    } catch (error) {
      final details = error.toString();
      _lastCheckoutError = details;
      ActivityLogService.instance.addError(
        'Billing - Checkout failed',
        const ['Retry checkout', 'Check billing setup', 'Check connection'],
        details: details,
      );
      _showCheckoutError(
        _formatCheckoutError('Unable to start checkout', details),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openInAppCheckout(String plan) async {
    if (_isOffline) {
      _showOfflineNotice();
      return;
    }
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) {
      _showCheckoutError(
        'In-app checkout is available on Android and iOS. Use browser checkout on this device.',
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final payload = await AwsService.instance.createPaymentSheet(plan: plan);
      final publishableKey = payload['publishableKey'] as String?;
      final customerId = payload['customerId'] as String?;
      final customerEphemeralKeySecret = payload['ephemeralKey'] as String?;
      final paymentIntentClientSecret = payload['paymentIntent'] as String?;

      if (publishableKey == null ||
          customerId == null ||
          customerEphemeralKeySecret == null ||
          paymentIntentClientSecret == null) {
        _lastCheckoutError = 'Payment sheet payload missing fields';
        _showCheckoutError('Unable to start in-app checkout.');
        return;
      }

      Stripe.publishableKey = publishableKey;
      await Stripe.instance.applySettings();

      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: paymentIntentClientSecret,
          merchantDisplayName: 'Roster Champion',
          customerId: customerId,
          customerEphemeralKeySecret: customerEphemeralKeySecret,
          style: ThemeMode.system,
        ),
      );

      await Stripe.instance.presentPaymentSheet();
      ActivityLogService.instance.addInfo(
        'Billing - Payment sheet completed for $plan',
      );
      if (mounted) {
        setState(() {
          _paymentSuccessPlan = plan;
          _paymentSuccessAt = DateTime.now();
        });
      }
      await _restoreAccess(showSpinner: true);
      if (mounted && _paymentSuccessAt != null) {
        Future.delayed(const Duration(seconds: 6), () {
          if (!mounted) return;
          if (_paymentSuccessAt != null &&
              DateTime.now().difference(_paymentSuccessAt!) >
                  const Duration(seconds: 5)) {
            setState(() {
              _paymentSuccessPlan = null;
              _paymentSuccessAt = null;
            });
          }
        });
      }
    } on StripeException catch (e) {
      final details = e.error.message ?? e.toString();
      _lastCheckoutError = details;
      ActivityLogService.instance.addError(
        'Billing - Payment sheet failed',
        const ['Retry payment', 'Check billing setup'],
        details: details,
      );
      _showCheckoutError(
        _formatCheckoutError('In-app checkout failed', details),
      );
    } catch (error) {
      final details = error.toString();
      _lastCheckoutError = details;
      ActivityLogService.instance.addError(
        'Billing - Payment sheet failed',
        const ['Retry payment', 'Check billing setup', 'Check connection'],
        details: details,
      );
      _showCheckoutError(
        _formatCheckoutError('In-app checkout failed', details),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _isValidPlan(String plan) {
    switch (plan.toLowerCase()) {
      case 'starter':
      case 'operations':
      case 'enterprise':
        return true;
      default:
        return false;
    }
  }

  bool _canReturnToApp() {
    final status = widget.subscriptionStatus.toLowerCase();
    final plan = widget.subscriptionPlan.toLowerCase();
    final trialActiveNow = widget.trialActive == true && _trialDaysRemaining() > 0;
    final activeWithPlan =
        (status == 'active' || status == 'trialing') && _isValidPlan(plan);
    return trialActiveNow || activeWithPlan;
  }

  Future<void> _returnToApp() async {
    await _restoreAccess(showSpinner: true);
    if (!mounted) return;
    if (!_canReturnToApp()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Your subscription is not active yet.'),
        ),
      );
    }
  }

  Future<void> _openPortal() async {
    if (_isOffline) {
      _showOfflineNotice();
      return;
    }
    setState(() => _busy = true);
    try {
      final url = await AwsService.instance.createBillingPortal();
      if (url != null && url.isNotEmpty) {
        ActivityLogService.instance.addInfo(
          'Billing - Opening billing portal',
        );
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        return;
      }
      _lastCheckoutError = 'Portal URL missing';
      _showCheckoutError('Unable to open billing portal. Please try again.');
      ActivityLogService.instance.addError(
        'Billing - Portal URL missing',
        const ['Retry portal', 'Check billing setup'],
      );
    } catch (error) {
      final details = error.toString();
      _lastCheckoutError = details;
      ActivityLogService.instance.addError(
        'Billing - Portal failed',
        const ['Retry portal', 'Check billing setup', 'Check connection'],
        details: details,
      );
      _showCheckoutError(
        _formatCheckoutError('Unable to open billing portal', details),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showOfflineNotice() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Offline: connect to the internet to manage billing.',
        ),
      ),
    );
  }

  void _showCheckoutError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
    _showCheckoutErrorDialog(message);
  }

  String _formatCheckoutError(String prefix, String details) {
    final trimmed = details.replaceAll(RegExp(r'\\s+'), ' ').trim();
    if (trimmed.isEmpty) return '$prefix. Please try again.';
    final preview = trimmed.length > 140 ? '${trimmed.substring(0, 140)}...' : trimmed;
    return '$prefix: $preview';
  }

  void _showCheckoutErrorDialog(String headline) {
    final details = _lastCheckoutError;
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Checkout error'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(headline),
              if (details != null && details.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('Details'),
                const SizedBox(height: 6),
                SelectableText(details),
              ],
            ],
          ),
          actions: [
            if (details != null && details.isNotEmpty)
              TextButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: details));
                  Navigator.of(context).pop();
                },
                icon: const Icon(Icons.copy),
                label: const Text('Copy details'),
              ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _signOut() async {
    try {
      await AwsService.instance.signOut();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to sign out. Please try again.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final bg = theme.colorScheme.surface;
    final primary = theme.colorScheme.primary;
    final locale = Localizations.localeOf(context);
    final canReturnToApp = _canReturnToApp();

    return WillPopScope(
      onWillPop: () async => canReturnToApp,
      child: Scaffold(
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                bg,
                theme.colorScheme.primaryContainer.withOpacity(0.35),
                bg,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final contentWidth = math.max(
                  constraints.maxWidth.toDouble(),
                  980.0,
                );
                return InteractiveViewer(
                  panEnabled: true,
                  scaleEnabled: false,
                  constrained: false,
                  child: SizedBox(
                    width: contentWidth,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 980),
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                    if (_isOffline)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.wifi_off,
                                color: theme.colorScheme.onErrorContainer),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'You are offline. Billing requires an internet connection.',
                                style: textTheme.bodySmall?.copyWith(
                                  color:
                                      theme.colorScheme.onErrorContainer,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Retry',
                              onPressed: () async {
                                await _checkConnection();
                                await _restoreAccess(showSpinner: true);
                              },
                              icon: Icon(
                                Icons.refresh,
                                color: theme.colorScheme.onErrorContainer,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (_isOffline) const SizedBox(height: 16),
                    if (_isRestoring)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.secondaryContainer
                              .withOpacity(0.6),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Checking payment status...',
                                style: textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (_isRestoring) const SizedBox(height: 16),
                    if (_paymentSuccessPlan != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.tertiaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.verified_rounded,
                                color: theme.colorScheme.onTertiaryContainer),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Payment approved for ${_paymentSuccessPlan!}. Unlocking your workspace...',
                                style: textTheme.bodySmall?.copyWith(
                                  color:
                                      theme.colorScheme.onTertiaryContainer,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  _paymentSuccessPlan = null;
                                  _paymentSuccessAt = null;
                                });
                              },
                              child: Text(
                                'Hide',
                                style: TextStyle(
                                  color:
                                      theme.colorScheme.onTertiaryContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (_paymentSuccessPlan != null)
                      const SizedBox(height: 16),
                    if (widget.trialActive == true)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.secondaryContainer
                              .withOpacity(0.7),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.timer_outlined,
                                color: theme
                                    .colorScheme.onSecondaryContainer),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Trial ends in ${_trialDaysRemaining()} day${_trialDaysRemaining() == 1 ? '' : 's'}. Upgrade now to keep full access.',
                                style: textTheme.bodySmall?.copyWith(
                                  color: theme
                                      .colorScheme.onSecondaryContainer,
                                ),
                              ),
                            ),
                            FilledButton(
                              onPressed: _busy
                                  ? null
                                  : () => _openCheckout('operations'),
                              child: const Text('Upgrade now'),
                            ),
                          ],
                        ),
                      ),
                    if (widget.trialActive == true)
                      const SizedBox(height: 16),
                    if (_showRestoreSuccess)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.check_circle,
                                color: theme.colorScheme.onPrimaryContainer),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Payment confirmed. Restoring access...',
                                style: textTheme.bodySmall?.copyWith(
                                  color:
                                      theme.colorScheme.onPrimaryContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (_showRestoreSuccess) const SizedBox(height: 16),
                    Text(
                      'Unlock Roster Champion',
                      style: textTheme.headlineLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'You are signed in. Choose a plan to activate your roster workspace. After activation, you will go straight into your roster unless you upgrade later.',
                      style: textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        _PlanCard(
                          title: 'Starter',
                          price: _priceForPlan('starter'),
                          estimate: _localEstimate('starter', locale),
                          subtitle: 'Fast setup for small teams',
                          highlights: const [
                            'Smart roster tools',
                            'Holiday overlays',
                            'Essential insights',
                          ],
                          accent: primary,
                          onSelect: _busy ? null : () => _openCheckout('starter'),
                          buttonLabel: 'Start Starter',
                        ),
                        _PlanCard(
                          title: 'Operations',
                          price: _priceForPlan('operations'),
                          estimate: _localEstimate('operations', locale),
                          subtitle: 'Advanced coverage + AI workflows',
                          highlights: const [
                            'AI guidance + automation',
                            'Coverage intelligence',
                            'Shift swaps & approvals',
                          ],
                          accent: theme.colorScheme.secondary,
                          isFeatured: true,
                          onSelect:
                              _busy ? null : () => _openCheckout('operations'),
                          buttonLabel: 'Start Operations',
                        ),
                        _PlanCard(
                          title: 'Enterprise',
                          price: _priceForPlan('enterprise'),
                          estimate: _localEstimate('enterprise', locale),
                          subtitle: 'Best performance + enterprise control',
                          highlights: const [
                            'Org/team management',
                            'Advanced audit trails',
                            'Priority support',
                          ],
                          accent: theme.colorScheme.tertiary,
                          onSelect:
                              _busy ? null : () => _openCheckout('enterprise'),
                          buttonLabel: 'Start Enterprise',
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Local currency estimates (if available) are shown for reference. Final charge is converted by Stripe at checkout.',
                      style: textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.7),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (canReturnToApp) ...[
                          FilledButton.icon(
                            onPressed: _busy ? null : _returnToApp,
                            icon: const Icon(Icons.arrow_forward),
                            label: const Text('Return to App'),
                          ),
                          const SizedBox(width: 12),
                        ],
                        FilledButton.icon(
                          onPressed: _busy ? null : _openPortal,
                          icon: const Icon(Icons.manage_accounts),
                          label: const Text('Manage Billing'),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          onPressed: _busy
                              ? null
                              : () async {
                                  await _restoreAccess(showSpinner: true);
                                },
                          icon: const Icon(Icons.refresh),
                          label: const Text('Restore access'),
                        ),
                        const SizedBox(width: 12),
                        TextButton(
                          onPressed: _busy ? null : _signOut,
                          child: const Text('Sign out'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Status: ${widget.subscriptionStatus} - Plan: ${widget.subscriptionPlan}',
                      style: textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.7),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final String title;
  final String price;
  final String? estimate;
  final String subtitle;
  final List<String> highlights;
  final Color accent;
  final VoidCallback? onSelect;
  final bool isFeatured;
  final String? buttonLabel;

  const _PlanCard({
    required this.title,
    required this.price,
    this.estimate,
    required this.subtitle,
    required this.highlights,
    required this.accent,
    this.onSelect,
    this.isFeatured = false,
    this.buttonLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final border = isFeatured
        ? Border.all(color: accent, width: 2)
        : Border.all(color: theme.dividerColor);
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 240, maxWidth: 300),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: border,
          boxShadow: [
            BoxShadow(
              color: accent.withOpacity(0.12),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                if (isFeatured)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Popular',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: accent),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              price,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: accent,
              ),
            ),
            if (estimate != null) ...[
              const SizedBox(height: 4),
              Text(
                estimate!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.7),
                ),
              ),
            ],
            const SizedBox(height: 4),
            Text(subtitle, style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            ...highlights.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, size: 16, color: accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onSelect,
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                ),
                child: Text(buttonLabel ?? 'Choose plan'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
