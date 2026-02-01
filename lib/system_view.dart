import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers.dart';
import 'models.dart' as models;
import 'aws_service.dart';
import 'services/diagnostic_service.dart';
import 'services/time_service.dart';

class SystemView extends ConsumerWidget {
  const SystemView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final awsStatus = ref.watch(awsStatusProvider);
    final aiStatus = ref.watch(aiStatusProvider);
    final awsConfigured = AwsService.instance.isConfigured;
    final awsAuthenticated = AwsService.instance.isAuthenticated;
    final settings = ref.watch(settingsProvider);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SectionCard(
          title: 'Backend Status',
          child: Column(
            children: [
              _StatusRow(
                label: 'AWS API',
                status: awsStatus.status,
                detail: awsStatus.message ?? '',
              ),
              ListTile(
                leading: const Icon(Icons.link),
                title: const Text('API URL'),
                subtitle: Text(AwsService.instance.apiUrl ?? 'Not set'),
              ),
              _StatusRow(
                label: 'AI Service',
                status: aiStatus.status,
                detail: aiStatus.message ?? '',
              ),
              _StatusRow(
                label: 'Auth',
                status: awsAuthenticated
                    ? models.ConnectionStatus.connected
                    : models.ConnectionStatus.disconnected,
                detail: awsAuthenticated ? 'Signed in' : 'Signed out',
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _SectionCard(
          title: 'AWS Services',
          child: Column(
            children: _awsServices(awsConfigured)
                .map(
                  (service) => ListTile(
                    leading: Icon(
                      service.enabled
                          ? Icons.check_circle_outline
                          : Icons.error_outline,
                      color: service.enabled ? Colors.green : Colors.grey,
                    ),
                    title: Text(service.name),
                    subtitle: Text(service.detail),
                  ),
                )
                .toList(),
          ),
        ),
        const SizedBox(height: 12),
        _SectionCard(
          title: 'Diagnostics',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Copy a diagnostic report to share with support.',
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () async {
                  final report =
                      await DiagnosticService.instance.buildReport();
                  await Clipboard.setData(ClipboardData(text: report));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Diagnostic report copied'),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.copy),
                label: const Text('Copy Diagnostic Report'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _SectionCard(
          title: 'Locale & Location',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Timezone: ${settings.timeZone}'),
              const SizedBox(height: 8),
              if (settings.siteLat != null && settings.siteLon != null)
                Text(
                  'Location: ${settings.siteName.isEmpty ? 'Selected site' : settings.siteName}',
                ),
              if (settings.siteLat != null && settings.siteLon != null)
                Text(
                  'Coordinates: ${settings.siteLat!.toStringAsFixed(4)}, ${settings.siteLon!.toStringAsFixed(4)}',
                ),
              const SizedBox(height: 8),
              FutureBuilder<TimeInfo>(
                future: TimeService.instance.getTime(settings.timeZone),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const SizedBox.shrink();
                  }
                  final time = snapshot.data!;
                  return Text(
                    'Local time: ${time.dateTime.toLocal().toString().substring(0, 16)}',
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<_AwsServiceInfo> _awsServices(bool awsConfigured) {
    return [
      _AwsServiceInfo(
        name: 'API Gateway + Lambda',
        detail: awsConfigured
            ? 'HTTP API routing to serverless functions'
            : 'Not configured',
        enabled: awsConfigured,
      ),
      _AwsServiceInfo(
        name: 'DynamoDB',
        detail: awsConfigured
            ? 'Roster data, logs, and workflows'
            : 'Not configured',
        enabled: awsConfigured,
      ),
      _AwsServiceInfo(
        name: 'Analytics (DynamoDB)',
        detail: awsConfigured
            ? 'Usage analytics and event telemetry'
            : 'Not configured',
        enabled: awsConfigured,
      ),
      _AwsServiceInfo(
        name: 'Cognito User Pool',
        detail: awsConfigured ? 'Email/password auth' : 'Not configured',
        enabled: awsConfigured,
      ),
      _AwsServiceInfo(
        name: 'Cognito Identity Pool',
        detail: awsConfigured ? 'IAM-backed API access' : 'Not configured',
        enabled: awsConfigured,
      ),
      _AwsServiceInfo(
        name: 'S3 Exports',
        detail: awsConfigured ? 'Roster exports and files' : 'Not configured',
        enabled: awsConfigured,
      ),
      _AwsServiceInfo(
        name: 'CloudFront CDN',
        detail: awsConfigured ? 'Export delivery' : 'Not configured',
        enabled: awsConfigured,
      ),
      _AwsServiceInfo(
        name: 'SNS Notifications',
        detail: awsConfigured ? 'Approval alerts' : 'Not configured',
        enabled: awsConfigured,
      ),
      _AwsServiceInfo(
        name: 'EventBridge Scheduler',
        detail: awsConfigured ? 'Daily summaries' : 'Not configured',
        enabled: awsConfigured,
      ),
      _AwsServiceInfo(
        name: 'Bedrock AI',
        detail: awsConfigured ? 'AI suggestions' : 'Not configured',
        enabled: awsConfigured,
      ),
      _AwsServiceInfo(
        name: 'SES Email',
        detail: awsConfigured ? 'Email delivery' : 'Not configured',
        enabled: awsConfigured,
      ),
    ];
  }
}

class _AwsServiceInfo {
  final String name;
  final String detail;
  final bool enabled;

  const _AwsServiceInfo({
    required this.name,
    required this.detail,
    required this.enabled,
  });
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  final String label;
  final models.ConnectionStatus status;
  final String detail;

  const _StatusRow({
    required this.label,
    required this.status,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);
    return ListTile(
      dense: true,
      leading: Icon(Icons.circle, size: 10, color: color),
      title: Text(label),
      subtitle: detail.isEmpty ? null : Text(detail),
      trailing: Text(
        _statusText(status),
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }

  Color _statusColor(models.ConnectionStatus status) {
    switch (status) {
      case models.ConnectionStatus.connected:
        return Colors.green;
      case models.ConnectionStatus.connecting:
        return Colors.orange;
      case models.ConnectionStatus.error:
        return Colors.red;
      case models.ConnectionStatus.disconnected:
        return Colors.grey;
    }
  }

  String _statusText(models.ConnectionStatus status) {
    switch (status) {
      case models.ConnectionStatus.connected:
        return 'Connected';
      case models.ConnectionStatus.connecting:
        return 'Connecting';
      case models.ConnectionStatus.error:
        return 'Error';
      case models.ConnectionStatus.disconnected:
        return 'Offline';
    }
  }
}
