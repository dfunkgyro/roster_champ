import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'aws_service.dart';

class AdminDashboardView extends ConsumerStatefulWidget {
  const AdminDashboardView({super.key});

  @override
  ConsumerState<AdminDashboardView> createState() =>
      _AdminDashboardViewState();
}

class _AdminDashboardViewState extends ConsumerState<AdminDashboardView> {
  Map<String, dynamic>? _metrics;
  bool _loading = true;
  String? _error;
  bool _billingBusy = false;
  String? _billingNotice;
  final TextEditingController _trialEmailController = TextEditingController();
  Map<String, dynamic>? _trialHistoryResult;
  String? _trialHistoryNotice;
  bool _trialHistoryBusy = false;
  bool _shareRevokeBusy = false;
  String? _shareRevokeNotice;
  final TextEditingController _usageEmailController = TextEditingController();
  final TextEditingController _usageLimitController = TextEditingController();
  Map<String, dynamic>? _usageUser;
  String _usageKey = 'ai';
  bool _usageBusy = false;
  String? _usageNotice;

  @override
  void initState() {
    super.initState();
    _loadMetrics();
  }

  @override
  void dispose() {
    _trialEmailController.dispose();
    _usageEmailController.dispose();
    _usageLimitController.dispose();
    super.dispose();
  }

  Future<void> _loadUsageUser() async {
    final email = _usageEmailController.text.trim();
    if (email.isEmpty) return;
    setState(() {
      _usageBusy = true;
      _usageNotice = null;
    });
    try {
      final data = await AwsService.instance.getAdminUsageUser(email: email);
      if (mounted) {
        setState(() {
          _usageUser = data;
          _usageBusy = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _usageNotice = e.toString();
          _usageBusy = false;
        });
      }
    }
  }

  Future<void> _applyUsageLimit() async {
    final email = _usageEmailController.text.trim();
    if (email.isEmpty) return;
    final raw = _usageLimitController.text.trim();
    final parsed = raw.isEmpty ? null : int.tryParse(raw);
    setState(() {
      _usageBusy = true;
      _usageNotice = null;
    });
    try {
      final limits = Map<String, dynamic>.from(
        (_usageUser?['usageLimits'] as Map?) ?? {},
      );
      if (parsed == null) {
        limits.remove(_usageKey);
      } else {
        limits[_usageKey] = parsed;
      }
      final updated = await AwsService.instance.setAdminUsageLimits(
        email: email,
        limits: limits,
      );
      if (mounted) {
        setState(() {
          _usageUser = updated;
          _usageBusy = false;
          _usageNotice = 'Updated usage limits';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _usageNotice = e.toString();
          _usageBusy = false;
        });
      }
    }
  }

  Future<void> _loadMetrics() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await AwsService.instance.getAdminMetrics();
      if (mounted) {
        setState(() {
          _metrics = data;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.warning, size: 48),
            const SizedBox(height: 8),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _loadMetrics,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final totals = _metrics?['totals'] as Map<String, dynamic>? ?? {};
    final plans = _metrics?['plans'] as Map<String, dynamic>? ?? {};
    final recent = _metrics?['recentActivity'] as List<dynamic>? ?? [];
    final trends = _metrics?['registrationTrends'] as List<dynamic>? ?? [];
    final users = _metrics?['users'] as List<dynamic>? ?? [];
    final admins = _metrics?['admins'] as List<dynamic>? ?? [];
    final trialEndingSoon =
        _metrics?['trialEndingSoon'] as List<dynamic>? ?? [];
    final shareSummary =
        _metrics?['shareSummary'] as Map<String, dynamic>? ?? {};
    final serviceHealth =
        _metrics?['serviceHealth'] as Map<String, dynamic>? ?? {};
    final authFunnel =
        _metrics?['authFunnel'] as Map<String, dynamic>? ?? {};
    final securityAlerts =
        _metrics?['securityAlerts'] as Map<String, dynamic>? ?? {};
    final websiteMetrics =
        _metrics?['websiteMetrics'] as Map<String, dynamic>? ?? {};
    final billingHealth =
        _metrics?['billingHealth'] as Map<String, dynamic>? ?? {};
    final billingStatus =
        _metrics?['billingStatus'] as Map<String, dynamic>? ?? {};
    final billingAlerts =
        _metrics?['billingAlerts'] as Map<String, dynamic>? ?? {};
    final billingIssues =
        _metrics?['billingIssues'] as List<dynamic>? ?? [];
    final usageSummary =
        _metrics?['usageSummary'] as Map<String, dynamic>? ?? {};
    final usageTotals =
        usageSummary['totals'] as Map<String, dynamic>? ?? {};
    final usageCosts =
        usageSummary['costs'] as Map<String, dynamic>? ?? {};
    final usageCostTotal = usageSummary['costTotal'] ?? 0;
    final costAlerts =
        _metrics?['costAlerts'] as List<dynamic>? ?? [];
    final billingAudit =
        _metrics?['billingAudit'] as List<dynamic>? ?? [];
    final topUsers = users
        .map((item) => Map<String, dynamic>.from(item as Map))
        .where((item) => (item['eventCount'] ?? 0) != 0)
        .toList()
      ..sort((a, b) => (b['eventCount'] ?? 0).compareTo(a['eventCount'] ?? 0));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Admin Dashboard',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        Text(
          'Service Health',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildHealthChip(
              context,
              'API',
              serviceHealth['api']?.toString() ?? 'unknown',
            ),
            _buildHealthChip(
              context,
              'Cognito',
              serviceHealth['cognito']?.toString() ?? 'unknown',
            ),
            _buildHealthChip(
              context,
              'Stripe',
              serviceHealth['stripe']?.toString() ?? 'unknown',
            ),
          ],
        ),
        if ((serviceHealth['secretsError'] ?? '').toString().isNotEmpty &&
            serviceHealth['secretsError'] != null) ...[
          const SizedBox(height: 6),
          Text(
            'Secrets: ${serviceHealth['secretsError']}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 16),
        Text(
          'Auth Funnel (last 500 events)',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildMetricChip('Attempts', authFunnel['attempts']),
            _buildMetricChip('Success', authFunnel['success']),
            _buildMetricChip('Failed', authFunnel['failed']),
            _buildMetricChip('Google Start', authFunnel['googleStart']),
            _buildMetricChip('Google Success', authFunnel['googleSuccess']),
            _buildMetricChip('Google Failed', authFunnel['googleFailed']),
            _buildMetricChip('Offline Success', authFunnel['offlineSuccess']),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'Security Alerts',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildMetricChip('Failed 24h', securityAlerts['failedLogins24h']),
            _buildMetricChip('Failed 7d', securityAlerts['failedLogins7d']),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Admin Actions',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: _billingBusy ? null : _reconcileSingleUser,
              icon: const Icon(Icons.sync_alt_rounded),
              label: const Text('Reconcile User Billing'),
            ),
            OutlinedButton.icon(
              onPressed: _billingBusy ? null : _reconcileAllBilling,
              icon: const Icon(Icons.sync_rounded),
              label: const Text('Reconcile All Billing'),
            ),
            OutlinedButton.icon(
              onPressed: _shareRevokeBusy ? null : _revokeAllShareCodes,
              icon: const Icon(Icons.link_off),
              label: const Text('Revoke All Share Codes'),
            ),
            if (_billingBusy)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            if (_shareRevokeBusy)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
          ],
        ),
        if (_billingNotice != null) ...[
          const SizedBox(height: 8),
          Text(
            _billingNotice!,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        if (_shareRevokeNotice != null) ...[
          const SizedBox(height: 8),
          Text(
            _shareRevokeNotice!,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 12),
        Text(
          'Trial History',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _trialEmailController,
          decoration: const InputDecoration(
            labelText: 'User email',
            hintText: 'name@company.com',
          ),
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: _trialHistoryBusy ? null : _lookupTrialHistory,
              icon: const Icon(Icons.search),
              label: const Text('Lookup Trial History'),
            ),
            OutlinedButton.icon(
              onPressed: _trialHistoryBusy ? null : _resetTrialHistory,
              icon: const Icon(Icons.refresh),
              label: const Text('Reset Trial History'),
            ),
            if (_trialHistoryBusy)
              const SizedBox(
                height: 16,
                width: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
        if (_trialHistoryNotice != null) ...[
          const SizedBox(height: 8),
          Text(
            _trialHistoryNotice!,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        if (_trialHistoryResult != null) ...[
          const SizedBox(height: 8),
          _buildTrialHistoryResult(_trialHistoryResult!),
        ],
        const SizedBox(height: 12),
        Text(
          'Billing Status',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _metricCard('Active', billingStatus['active'] ?? 0),
            _metricCard('Trialing', billingStatus['trialing'] ?? 0),
            _metricCard('Inactive', billingStatus['inactive'] ?? 0),
            _metricCard('Total users', billingStatus['totalUsers'] ?? 0),
            _metricCard(
              'Webhook (last)',
              billingStatus['lastWebhookAt'] ?? 'unknown',
            ),
            _metricCard(
              'Reconcile (last)',
              billingStatus['lastReconcileAt'] ?? 'unknown',
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Billing Health',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _metricCard(
              'Last webhook',
              billingHealth['lastWebhookAt'] ?? 'unknown',
            ),
            _metricCard(
              'Webhook type',
              billingHealth['lastWebhookType'] ?? 'unknown',
            ),
            _metricCard(
              'Last reconcile',
              billingHealth['lastReconcileAt'] ?? 'unknown',
            ),
            _metricCard(
              'Reconcile status',
              billingHealth['lastReconcileStatus'] ?? 'unknown',
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Billing Alerts',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _metricCard(
              'Missing Stripe IDs',
              billingAlerts['missingStripeIds'] ?? 0,
            ),
            _metricCard(
              'Expired active',
              billingAlerts['expiredActive'] ?? 0,
            ),
            _metricCard(
              'Trial expired',
              billingAlerts['trialExpired'] ?? 0,
            ),
            _metricCard(
              'Inactive w/ period',
              billingAlerts['inactiveWithFuturePeriod'] ?? 0,
            ),
          ],
        ),
        if (costAlerts.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.withOpacity(0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cost Alerts',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 6),
                ...costAlerts.map((alert) {
                  final map = Map<String, dynamic>.from(alert as Map);
                  return Text(
                    map['message']?.toString() ?? 'Cost threshold exceeded.',
                    style: Theme.of(context).textTheme.bodySmall,
                  );
                }).toList(),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        Text(
          'Cost Control',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _metricCard(
              'Usage period',
              usageSummary['period'] ?? 'unknown',
            ),
            _metricCard('Est cost (MTD)', usageCostTotal),
            _metricCard('AI calls', usageTotals['ai'] ?? 0),
            _metricCard('Analytics', usageTotals['analytics'] ?? 0),
            _metricCard('Exports', usageTotals['exports'] ?? 0),
            _metricCard('Timeclock', usageTotals['timeclock'] ?? 0),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _metricCard('Share create', usageTotals['share_create'] ?? 0),
            _metricCard('Share access', usageTotals['share_access'] ?? 0),
            _metricCard('Share leave', usageTotals['share_leave'] ?? 0),
            _metricCard(
              'AI cost',
              usageCosts['ai'] ?? 0,
            ),
            _metricCard(
              'Analytics cost',
              usageCosts['analytics'] ?? 0,
            ),
            _metricCard(
              'Exports cost',
              usageCosts['exports'] ?? 0,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'User Usage Limits',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _usageEmailController,
          decoration: const InputDecoration(
            labelText: 'User email',
            hintText: 'name@company.com',
          ),
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            DropdownButton<String>(
              value: _usageKey,
              items: const [
                DropdownMenuItem(value: 'ai', child: Text('AI')),
                DropdownMenuItem(value: 'analytics', child: Text('Analytics')),
                DropdownMenuItem(value: 'exports', child: Text('Exports')),
                DropdownMenuItem(value: 'timeclock', child: Text('Timeclock')),
                DropdownMenuItem(value: 'share_create', child: Text('Share create')),
                DropdownMenuItem(value: 'share_access', child: Text('Share access')),
                DropdownMenuItem(value: 'share_leave', child: Text('Share leave')),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _usageKey = value);
              },
            ),
            SizedBox(
              width: 140,
              child: TextField(
                controller: _usageLimitController,
                decoration: const InputDecoration(
                  labelText: 'Limit',
                  hintText: 'e.g. 1000',
                ),
                keyboardType: TextInputType.number,
              ),
            ),
            FilledButton.icon(
              onPressed: _usageBusy ? null : _loadUsageUser,
              icon: const Icon(Icons.search),
              label: const Text('Lookup'),
            ),
            OutlinedButton.icon(
              onPressed: _usageBusy ? null : _applyUsageLimit,
              icon: const Icon(Icons.tune_rounded),
              label: const Text('Apply'),
            ),
            if (_usageBusy)
              const SizedBox(
                height: 16,
                width: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
        if (_usageNotice != null) ...[
          const SizedBox(height: 8),
          Text(_usageNotice!, style: Theme.of(context).textTheme.bodySmall),
        ],
        if (_usageUser != null) ...[
          const SizedBox(height: 8),
          _buildUsageUserCard(_usageUser!),
        ],
        const SizedBox(height: 12),
        Text(
          'Billing Issues',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (billingIssues.isEmpty)
          const Text('No billing issues detected.')
        else
          ...billingIssues.take(8).map((item) {
            final map = Map<String, dynamic>.from(item as Map);
            final email = map['email']?.toString() ?? 'user';
            final reason = map['reason']?.toString() ?? 'issue';
            final userId = map['userId']?.toString() ?? '';
            return ListTile(
              leading: const Icon(Icons.report_gmailerrorred),
              title: Text(email),
              subtitle: Text(reason),
              trailing: IconButton(
                icon: const Icon(Icons.sync_rounded),
                tooltip: 'Reconcile user',
                onPressed: _billingBusy || userId.isEmpty
                    ? null
                    : () => _reconcileUserById(userId, email),
              ),
            );
          }).toList(),
        const SizedBox(height: 12),
        Text(
          'Billing Audit Log',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (billingAudit.isEmpty)
          const Text('No billing audit events yet.')
        else
          ...billingAudit.take(12).map((item) {
            final map = Map<String, dynamic>.from(item as Map);
            final action = map['action']?.toString() ?? 'billing_event';
            final timestamp = map['timestamp']?.toString() ?? '';
            final userId = map['userId']?.toString() ?? 'system';
            final status = map['status']?.toString() ?? '';
            final plan = map['plan']?.toString() ?? '';
            final detail = map['detail']?.toString() ?? '';
            final subtitleBits = <String>[
              if (status.isNotEmpty) 'Status: $status',
              if (plan.isNotEmpty) 'Plan: $plan',
              if (detail.isNotEmpty) detail,
            ];
            return ListTile(
              leading: const Icon(Icons.receipt_long),
              title: Text(action),
              subtitle: Text(
                [
                  if (timestamp.isNotEmpty) timestamp,
                  if (subtitleBits.isNotEmpty) subtitleBits.join(' - '),
                ].where((value) => value.isNotEmpty).join('\n'),
              ),
              trailing: Text(userId),
            );
          }).toList(),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _metricCard('Total users', totals['users'] ?? 0),
            _metricCard('Active subs', totals['activeSubs'] ?? 0),
            _metricCard('Trialing', totals['trialing'] ?? 0),
            _metricCard('Churned', totals['inactive'] ?? 0),
            _metricCard('Active 7d', totals['active7'] ?? 0),
            _metricCard('Active 30d', totals['active30'] ?? 0),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'Plans',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _metricCard('Starter', plans['starter'] ?? 0),
            _metricCard('Operations', plans['operations'] ?? 0),
            _metricCard('Enterprise', plans['enterprise'] ?? 0),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'Share Codes',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _metricCard('Active', shareSummary['active'] ?? 0),
            _metricCard('Revoked', shareSummary['revoked'] ?? 0),
            _metricCard('Expired', shareSummary['expired'] ?? 0),
            _metricCard('Total', shareSummary['total'] ?? 0),
          ],
        ),
        const SizedBox(height: 8),
        _buildCategoryChart({
          'Active': shareSummary['active'] ?? 0,
          'Revoked': shareSummary['revoked'] ?? 0,
          'Expired': shareSummary['expired'] ?? 0,
        }),
        const SizedBox(height: 16),
        Text(
          'Website Activity',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _metricCard('Page views 7d', websiteMetrics['pageViews7'] ?? 0),
            _metricCard('Page views 30d', websiteMetrics['pageViews30'] ?? 0),
            _metricCard(
              'Visitors 7d',
              websiteMetrics['uniqueVisitors7'] ?? 0,
            ),
            _metricCard(
              'Visitors 30d',
              websiteMetrics['uniqueVisitors30'] ?? 0,
            ),
          ],
        ),
        const SizedBox(height: 8),
        _buildRegistrationChart(
          websiteMetrics['dailyPageViews'] as List<dynamic>? ?? [],
        ),
        const SizedBox(height: 12),
        Text(
          'Top pages',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        ...((websiteMetrics['topPages'] as List<dynamic>? ?? [])
            .take(6)
            .map((item) {
          final map = Map<String, dynamic>.from(item as Map);
          return ListTile(
            leading: const Icon(Icons.public),
            title: Text(map['path']?.toString() ?? 'page'),
            trailing: Text(map['count']?.toString() ?? '0'),
          );
        }).toList()),
        const SizedBox(height: 12),
        Text(
          'Top CTAs',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        ...((websiteMetrics['topCtas'] as List<dynamic>? ?? [])
            .take(6)
            .map((item) {
          final map = Map<String, dynamic>.from(item as Map);
          return ListTile(
            leading: const Icon(Icons.ads_click),
            title: Text(map['label']?.toString() ?? 'cta'),
            trailing: Text(map['count']?.toString() ?? '0'),
          );
        }).toList()),
        const SizedBox(height: 12),
        Text(
          'Top downloads',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        ...((websiteMetrics['topDownloads'] as List<dynamic>? ?? [])
            .take(6)
            .map((item) {
          final map = Map<String, dynamic>.from(item as Map);
          return ListTile(
            leading: const Icon(Icons.download),
            title: Text(map['label']?.toString() ?? 'download'),
            trailing: Text(map['count']?.toString() ?? '0'),
          );
        }).toList()),
        const SizedBox(height: 12),
        Text(
          'Recent website events',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        ...((websiteMetrics['recentEvents'] as List<dynamic>? ?? [])
            .take(8)
            .map((item) {
          final map = Map<String, dynamic>.from(item as Map);
          final detail = map['detail']?.toString() ?? '';
          return ListTile(
            leading: const Icon(Icons.timeline),
            title: Text(map['name']?.toString() ?? 'event'),
            subtitle: Text(
              [
                map['timestamp']?.toString() ?? '',
                if (detail.isNotEmpty) detail,
              ].where((value) => value.isNotEmpty).join(' - '),
            ),
          );
        }).toList()),
        const SizedBox(height: 16),
        Text(
          'Registrations (last 30 days)',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        _buildRegistrationChart(trends),
        const SizedBox(height: 16),
        Text(
          'Top Users (Activity)',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (topUsers.isEmpty)
          const Text('No user activity yet.')
        else
          ...topUsers.take(5).map((map) {
            final email = map['email']?.toString() ?? 'user';
            final events = map['eventCount'] ?? 0;
            final lastActive = map['lastActiveAt']?.toString() ?? '';
            return ListTile(
              leading: const Icon(Icons.trending_up),
              title: Text(email),
              subtitle: Text(
                'Events: $events${lastActive.isNotEmpty ? ' - Last active: $lastActive' : ''}',
              ),
            );
          }).toList(),
        const SizedBox(height: 16),
        Text(
          'Admins',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (admins.isEmpty)
          const Text('No admins listed.'),
        ...admins.map((item) {
          final map = Map<String, dynamic>.from(item as Map);
          final username = map['username']?.toString() ?? '';
          return ListTile(
            leading: const Icon(Icons.verified_user),
            title: Text(map['email']?.toString() ?? 'admin'),
            subtitle: Text(username.isEmpty ? '' : 'User: $username'),
          );
        }).toList(),
        const SizedBox(height: 16),
        Text(
          'Trial ending soon',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (trialEndingSoon.isEmpty)
          const Text('No trials ending soon.'),
        ...trialEndingSoon.map((item) {
          final map = Map<String, dynamic>.from(item as Map);
          return ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: Text(map['email']?.toString() ?? 'trial'),
            subtitle:
                Text('Ends: ${map['trialExpiresAt']?.toString() ?? ''}'),
          );
        }).toList(),
        const SizedBox(height: 16),
        Text(
          'Users',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (users.isEmpty)
          const Text('No users available.'),
        ...users.map((item) {
          final map = Map<String, dynamic>.from(item as Map);
          final plan = map['plan']?.toString() ?? 'starter';
          final status = map['status']?.toString() ?? 'unknown';
          final lastActive = map['lastActiveAt']?.toString() ?? '';
          final eventCount = map['eventCount']?.toString() ?? '';
          final platforms = (map['platforms'] as List?)
                  ?.map((p) => p.toString())
                  .toList() ??
              [];
          final createdAt = map['createdAt']?.toString() ?? '';
          String createdLabel = '';
          if (createdAt.isNotEmpty) {
            final parsed = DateTime.tryParse(createdAt);
            if (parsed != null) {
              final days = DateTime.now().difference(parsed).inDays;
              createdLabel = 'Since: $createdAt ($days days)';
            } else {
              createdLabel = 'Since: $createdAt';
            }
          }
          final activityBits = <String>[];
          if (createdLabel.isNotEmpty) {
            activityBits.add(createdLabel);
          }
          if (lastActive.isNotEmpty) {
            activityBits.add('Last active: $lastActive');
          }
          if (eventCount.isNotEmpty) {
            activityBits.add('Events: $eventCount');
          }
          final shareActive = map['shareCodesActive'];
          final shareRevoked = map['shareCodesRevoked'];
          final shareExpired = map['shareCodesExpired'];
          if (shareActive != null || shareRevoked != null || shareExpired != null) {
            activityBits.add(
              'Share codes: ${(shareActive ?? 0)} active / ${(shareRevoked ?? 0)} revoked / ${(shareExpired ?? 0)} expired',
            );
          }
          if (platforms.isNotEmpty) {
            activityBits.add('Platforms: ${platforms.join(', ')}');
          }
          final userId = map['userId']?.toString() ?? '';
          return ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(map['email']?.toString() ?? 'user'),
            subtitle: Text(
              [
                'Plan: $plan - Status: $status',
                if (activityBits.isNotEmpty) activityBits.join(' - '),
              ].join('\n'),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(userId),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.sync_rounded),
                  tooltip: 'Reconcile user',
                  onPressed: _billingBusy || userId.isEmpty
                      ? null
                      : () =>
                          _reconcileUserById(userId, map['email']?.toString() ?? ''),
                ),
              ],
            ),
          );
        }).toList(),
        const SizedBox(height: 16),
        Text(
          'Recent activity',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (recent.isEmpty)
          const Text('No recent activity logged.'),
        ...recent.map((item) {
          final map = Map<String, dynamic>.from(item as Map);
          return ListTile(
            leading: const Icon(Icons.timeline),
            title: Text(map['name']?.toString() ?? 'event'),
            subtitle: Text(map['timestamp']?.toString() ?? ''),
            trailing: Text(map['userId']?.toString() ?? ''),
          );
        }).toList(),
      ],
    );
  }

  Widget _metricCard(String label, Object value) {
    return Container(
      width: 160,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blueGrey.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blueGrey.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 6),
          Text(
            value.toString(),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUsageUserCard(Map<String, dynamic> user) {
    final email = user['email']?.toString() ?? 'user';
    final plan = user['plan']?.toString() ?? 'none';
    final status = user['status']?.toString() ?? 'inactive';
    final limits = Map<String, dynamic>.from(
      user['usageLimits'] as Map? ?? {},
    );
    final snapshot =
        Map<String, dynamic>.from(user['usageSnapshot'] as Map? ?? {});
    final counts = Map<String, dynamic>.from(
      snapshot['counts'] as Map? ?? {},
    );
    final remaining = Map<String, dynamic>.from(
      snapshot['remaining'] as Map? ?? {},
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blueGrey.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blueGrey.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$email · $plan · $status',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _metricCard('AI used', counts['ai'] ?? 0),
              _metricCard('AI remaining', remaining['ai'] ?? '-'),
              _metricCard('Exports used', counts['exports'] ?? 0),
              _metricCard('Exports remaining', remaining['exports'] ?? '-'),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Overrides: ${limits.isEmpty ? 'None' : limits.entries.map((e) => '${e.key}:${e.value}').join(', ')}',
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildRegistrationChart(List<dynamic> raw) {
    if (raw.isEmpty) {
      return const Text('No registration data yet.');
    }
    final items = raw
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    final maxCount = items
        .map((item) => (item['count'] as num?) ?? 0)
        .fold<num>(0, (prev, value) => value > prev ? value : prev);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blueGrey.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blueGrey.withOpacity(0.2)),
      ),
      child: SizedBox(
        height: 140,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: items.map((item) {
            final count = (item['count'] as num?) ?? 0;
            final ratio = maxCount == 0 ? 0.0 : (count / maxCount);
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Tooltip(
                  message: '${item['date']}: $count',
                  child: Container(
                    height: 20 + (100 * ratio),
                    decoration: BoxDecoration(
                      color: Colors.indigo.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Future<void> _revokeAllShareCodes() async {
    setState(() {
      _shareRevokeBusy = true;
      _shareRevokeNotice = null;
    });
    try {
      final result = await AwsService.instance.revokeAllShareCodes();
      if (mounted) {
        setState(() {
          _shareRevokeNotice =
              'Revoked ${result['revoked'] ?? 0} of ${result['scanned'] ?? 0} share codes.';
        });
        await _loadMetrics();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _shareRevokeNotice = 'Revoke failed: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _shareRevokeBusy = false);
      }
    }
  }

  Widget _buildTrialHistoryResult(Map<String, dynamic> result) {
    final hasHistory = result['hasTrialHistory'] == true;
    final history = result['trialHistory'] as Map<String, dynamic>?;
    final profile = result['profile'] as Map<String, dynamic>?;
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            hasHistory ? 'Trial history: FOUND' : 'Trial history: NOT FOUND',
            style: theme.textTheme.titleSmall,
          ),
          if (history != null) ...[
            const SizedBox(height: 6),
            Text('First trial: ${history['firstTrialAt'] ?? ''}'),
            Text('Source: ${history['source'] ?? ''}'),
          ],
          if (profile != null) ...[
            const SizedBox(height: 6),
            Text('Profile userId: ${profile['userId'] ?? ''}'),
            Text('Status: ${profile['subscriptionStatus'] ?? ''}'),
            Text('Plan: ${profile['subscriptionPlan'] ?? ''}'),
            if ((profile['trialStartAt'] ?? '').toString().isNotEmpty)
              Text('Trial start: ${profile['trialStartAt']}'),
            if ((profile['trialExpiresAt'] ?? '').toString().isNotEmpty)
              Text('Trial ends: ${profile['trialExpiresAt']}'),
          ],
        ],
      ),
    );
  }

  Future<void> _reconcileAllBilling() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reconcile All Billing'),
        content: const Text(
          'This will sync subscription status for all users. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Run'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() {
      _billingBusy = true;
      _billingNotice = null;
    });
    try {
      final result = await AwsService.instance.reconcileBillingAll();
      final summary = result['results'] ?? {};
      setState(() {
        _billingNotice =
            'Reconcile complete: ${summary['updated'] ?? 0} updated, ${summary['skipped'] ?? 0} skipped, ${summary['errors'] ?? 0} errors.';
      });
    } catch (e) {
      setState(() {
        _billingNotice = 'Reconcile failed: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _billingBusy = false;
        });
      }
      _loadMetrics();
    }
  }

  Future<void> _reconcileSingleUser() async {
    final emailController = TextEditingController();
    final idController = TextEditingController();
    final run = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reconcile User Billing'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: emailController,
              decoration: const InputDecoration(
                labelText: 'Email (optional)',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: idController,
              decoration: const InputDecoration(
                labelText: 'User ID (optional)',
              ),
            ),
            const SizedBox(height: 8),
            const Text('Provide email or user ID.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reconcile'),
          ),
        ],
      ),
    );
    if (run != true) return;
    setState(() {
      _billingBusy = true;
      _billingNotice = null;
    });
    try {
      final result = await AwsService.instance.reconcileBillingUser(
        email: emailController.text,
        userId: idController.text,
      );
      final status = result['status']?.toString() ?? 'unknown';
      final plan = result['plan']?.toString() ?? 'unknown';
      final updated = result['updated'] == true;
      setState(() {
        _billingNotice = updated
            ? 'User reconciled. Status: $status, Plan: $plan'
            : 'No active subscription found for this user.';
      });
    } catch (e) {
      setState(() {
        _billingNotice = 'Reconcile failed: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _billingBusy = false;
        });
      }
      _loadMetrics();
    }
  }

  Future<void> _reconcileUserById(String userId, String email) async {
    setState(() {
      _billingBusy = true;
      _billingNotice = null;
    });
    try {
      final result = await AwsService.instance.reconcileBillingUser(
        userId: userId,
        email: email,
      );
      final status = result['status']?.toString() ?? 'unknown';
      final plan = result['plan']?.toString() ?? 'unknown';
      final updated = result['updated'] == true;
      setState(() {
        _billingNotice = updated
            ? 'User reconciled. Status: $status, Plan: $plan'
            : 'No active subscription found for $email.';
      });
    } catch (e) {
      setState(() {
        _billingNotice = 'Reconcile failed: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _billingBusy = false;
        });
      }
      _loadMetrics();
    }
  }

  Future<void> _lookupTrialHistory() async {
    final email = _trialEmailController.text.trim();
    if (email.isEmpty) {
      setState(() {
        _trialHistoryNotice = 'Enter an email address.';
        _trialHistoryResult = null;
      });
      return;
    }
    setState(() {
      _trialHistoryBusy = true;
      _trialHistoryNotice = null;
      _trialHistoryResult = null;
    });
    try {
      final result = await AwsService.instance.getAdminTrialHistory(email);
      setState(() {
        _trialHistoryResult = result;
        _trialHistoryNotice =
            result['hasTrialHistory'] == true ? 'Trial history found.' : 'No trial history found.';
      });
    } catch (e) {
      setState(() {
        _trialHistoryNotice = 'Lookup failed: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _trialHistoryBusy = false;
        });
      }
    }
  }

  Future<void> _resetTrialHistory() async {
    final email = _trialEmailController.text.trim();
    if (email.isEmpty) {
      setState(() {
        _trialHistoryNotice = 'Enter an email address.';
      });
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset Trial History'),
        content: Text(
          'This will allow a new trial for $email if no other trial record exists. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() {
      _trialHistoryBusy = true;
      _trialHistoryNotice = null;
    });
    try {
      final result = await AwsService.instance.resetAdminTrialHistory(email);
      final deleted = result['deleted'] == true;
      setState(() {
        _trialHistoryNotice =
            deleted ? 'Trial history reset.' : 'No trial record to delete.';
        _trialHistoryResult = null;
      });
    } catch (e) {
      setState(() {
        _trialHistoryNotice = 'Reset failed: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _trialHistoryBusy = false;
        });
      }
    }
  }

  Widget _buildHealthChip(BuildContext context, String label, String status) {
    final normalized = status.toLowerCase();
    Color color;
    if (normalized == 'ok') {
      color = Colors.green;
    } else if (normalized == 'missing') {
      color = Colors.orange;
    } else if (normalized == 'error') {
      color = Colors.red;
    } else {
      color = Colors.blueGrey;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 10, color: color),
          const SizedBox(width: 6),
          Text('$label: ${status.toUpperCase()}'),
        ],
      ),
    );
  }

  Widget _buildMetricChip(String label, dynamic value) {
    final display = value == null ? '0' : value.toString();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.blueGrey.withOpacity(0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.blueGrey.withOpacity(0.4)),
      ),
      child: Text('$label: $display'),
    );
  }

  Widget _buildCategoryChart(Map<String, dynamic> data) {
    if (data.isEmpty) {
      return const Text('No data available.');
    }
    final entries = data.entries.toList();
    final maxCount = entries
        .map((entry) => (entry.value as num?) ?? 0)
        .fold<num>(0, (prev, value) => value > prev ? value : prev);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blueGrey.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blueGrey.withOpacity(0.2)),
      ),
      child: SizedBox(
        height: 140,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: entries.map((entry) {
            final count = (entry.value as num?) ?? 0;
            final ratio = maxCount == 0 ? 0.0 : (count / maxCount);
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(count.toString()),
                    const SizedBox(height: 6),
                    Container(
                      height: 20 + (80 * ratio),
                      decoration: BoxDecoration(
                        color: Colors.teal.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      entry.key,
                      style: const TextStyle(fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
