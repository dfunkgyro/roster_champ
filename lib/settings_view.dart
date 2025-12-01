import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers.dart';
import 'models.dart' as models;

class SettingsView extends ConsumerWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildAppearanceSection(context, ref, settings),
        const SizedBox(height: 16),
        _buildNotificationsSection(context, ref, settings),
        const SizedBox(height: 16),
        _buildSyncSection(context, ref, settings),
        const SizedBox(height: 16),
        _buildDisplaySection(context, ref, settings),
        const SizedBox(height: 16),
        _buildAboutSection(context),
      ],
    );
  }

  Widget _buildAppearanceSection(
    BuildContext context,
    WidgetRef ref,
    models.AppSettings settings,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.palette,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Appearance',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Dark Mode'),
              subtitle: const Text('Use dark theme'),
              value: settings.darkMode,
              onChanged: (value) {
                ref.read(settingsProvider.notifier).updateSettings(
                      settings.copyWith(darkMode: value),
                    );
              },
              secondary: Icon(
                settings.darkMode ? Icons.dark_mode : Icons.light_mode,
              ),
            ),
            SwitchListTile(
              title: const Text('Compact View'),
              subtitle: const Text('Reduce spacing in lists'),
              value: settings.compactView,
              onChanged: (value) {
                ref.read(settingsProvider.notifier).updateSettings(
                      settings.copyWith(compactView: value),
                    );
              },
              secondary: const Icon(Icons.view_compact),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationsSection(
    BuildContext context,
    WidgetRef ref,
    models.AppSettings settings,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.notifications,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Notifications',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Enable Notifications'),
              subtitle: const Text('Receive alerts for roster changes'),
              value: settings.notifications,
              onChanged: (value) {
                ref.read(settingsProvider.notifier).updateSettings(
                      settings.copyWith(notifications: value),
                    );
              },
              secondary: const Icon(Icons.notifications_active),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSyncSection(
    BuildContext context,
    WidgetRef ref,
    models.AppSettings settings,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.sync,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Synchronization',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Auto Sync'),
              subtitle: const Text('Automatically sync with cloud'),
              value: settings.autoSync,
              onChanged: (value) {
                ref.read(settingsProvider.notifier).updateSettings(
                      settings.copyWith(autoSync: value),
                    );
              },
              secondary: const Icon(Icons.cloud_sync),
            ),
            ListTile(
              leading: const Icon(Icons.timer),
              title: const Text('Sync Interval'),
              subtitle: Text('${settings.syncInterval} minutes'),
              trailing: DropdownButton<int>(
                value: settings.syncInterval,
                items: [5, 15, 30, 60].map((minutes) {
                  return DropdownMenuItem(
                    value: minutes,
                    child: Text('$minutes min'),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    ref.read(settingsProvider.notifier).updateSettings(
                          settings.copyWith(syncInterval: value),
                        );
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDisplaySection(
    BuildContext context,
    WidgetRef ref,
    models.AppSettings settings,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.display_settings,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Display',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Show Week Numbers'),
              subtitle: const Text('Display week numbers in roster'),
              value: settings.showWeekNumbers,
              onChanged: (value) {
                ref.read(settingsProvider.notifier).updateSettings(
                      settings.copyWith(showWeekNumbers: value),
                    );
              },
              secondary: const Icon(Icons.calendar_view_week),
            ),
            ListTile(
              leading: const Icon(Icons.date_range),
              title: const Text('Date Format'),
              subtitle: Text(settings.dateFormat),
              trailing: DropdownButton<String>(
                value: settings.dateFormat,
                items: ['dd/MM/yyyy', 'MM/dd/yyyy', 'yyyy-MM-dd'].map((format) {
                  return DropdownMenuItem(
                    value: format,
                    child: Text(format),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    ref.read(settingsProvider.notifier).updateSettings(
                          settings.copyWith(dateFormat: value),
                        );
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAboutSection(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.info,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'About',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 16),
            const ListTile(
              leading: Icon(Icons.app_settings_alt),
              title: Text('App Version'),
              subtitle: Text('2.0.0'),
            ),
            const ListTile(
              leading: Icon(Icons.code),
              title: Text('Build'),
              subtitle: Text('Production'),
            ),
            ListTile(
              leading: const Icon(Icons.privacy_tip),
              title: const Text('Privacy Policy'),
              trailing: const Icon(Icons.open_in_new),
              onTap: () {
                // TODO: Open privacy policy
              },
            ),
            ListTile(
              leading: const Icon(Icons.description),
              title: const Text('Terms of Service'),
              trailing: const Icon(Icons.open_in_new),
              onTap: () {
                // TODO: Open terms of service
              },
            ),
            ListTile(
              leading: const Icon(Icons.bug_report),
              title: const Text('Report an Issue'),
              trailing: const Icon(Icons.open_in_new),
              onTap: () {
                // TODO: Open issue tracker
              },
            ),
          ],
        ),
      ),
    );
  }
}
