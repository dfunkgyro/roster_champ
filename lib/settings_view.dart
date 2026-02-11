import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'providers.dart';
import 'models.dart' as models;
import 'aws_service.dart';
import 'services/holiday_service.dart';
import 'services/country_service.dart';
import 'services/location_service.dart';
import 'services/analytics_service.dart';
import 'services/voice_service.dart';
import 'services/adaptive_learning_service.dart';
import 'package:roster_champ/safe_text_field.dart';

class SettingsView extends ConsumerWidget {
  const SettingsView({super.key});

  static const String _privacyUrl = 'https://rosterchampion.com/privacy';
  static const String _termsUrl = 'https://rosterchampion.com/terms';
  static const String _issuesUrl =
      'https://github.com/dfunkgyro/roster_champ/issues';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final roster = ref.watch(rosterProvider);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildAppearanceSection(context, ref, settings),
        const SizedBox(height: 16),
        _buildNotificationsSection(context, ref, settings),
        const SizedBox(height: 16),
        _buildOptimizationSection(context, ref, roster),
        const SizedBox(height: 16),
        _buildShiftHoursSection(context, ref, settings),
        const SizedBox(height: 16),
        _buildSyncSection(context, ref, settings),
        const SizedBox(height: 16),
        _buildAnalyticsSection(context, ref, settings),
        const SizedBox(height: 16),
        _buildAdaptiveLearningSection(context, ref, settings),
        const SizedBox(height: 16),
        _buildDisplaySection(context, ref, settings),
        const SizedBox(height: 16),
        _buildVoiceSection(context, ref, settings),
        const SizedBox(height: 16),
        _buildHolidaySection(context, ref, settings, roster),
        const SizedBox(height: 16),
        _buildMultiCountryHolidaySection(context, ref, settings),
        const SizedBox(height: 16),
        _buildAccountSection(context),
        const SizedBox(height: 16),
        _buildRoleTemplatesSection(context),
        const SizedBox(height: 16),
        _buildAboutSection(context),
      ],
    );
  }

  Widget _buildMultiCountryHolidaySection(
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
                  Icons.public,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Additional Holiday Countries',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Overlay holidays from multiple countries.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (settings.additionalHolidayCountries.isEmpty)
              const Text('No additional countries selected.'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: settings.additionalHolidayCountries
                  .map(
                    (code) => Chip(
                      label: Text(code),
                      onDeleted: () {
                        final updated =
                            List<String>.from(settings.additionalHolidayCountries)
                              ..remove(code);
                        ref.read(settingsProvider.notifier).updateSettings(
                              settings.copyWith(
                                additionalHolidayCountries: updated,
                              ),
                            );
                      },
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => _showAddHolidayCountryDialog(
                  context,
                  ref,
                  settings,
                ),
                icon: const Icon(Icons.add),
                label: const Text('Add Country'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddHolidayCountryDialog(
    BuildContext context,
    WidgetRef ref,
    models.AppSettings settings,
  ) async {
    final countries = await HolidayService.instance.getCountries();
    String? selectedCode;
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Holiday Country'),
        content: DropdownButtonFormField<String>(
          value: selectedCode,
          items: countries
              .map(
                (c) => DropdownMenuItem(
                  value: c.code,
                  child: Text('${c.name} (${c.code})'),
                ),
              )
              .toList(),
          onChanged: (value) => selectedCode = value,
          decoration: const InputDecoration(labelText: 'Country'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (selectedCode == null) return;
              final updated =
                  List<String>.from(settings.additionalHolidayCountries);
              if (!updated.contains(selectedCode)) {
                updated.add(selectedCode!);
              }
              ref.read(settingsProvider.notifier).updateSettings(
                    settings.copyWith(
                      additionalHolidayCountries: updated,
                    ),
                  );
              Navigator.pop(context);
            },
            child: const Text('Add'),
          ),
        ],
      ),
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
            const SizedBox(height: 12),
            DropdownButtonFormField<models.AppLayoutStyle>(
              value: settings.layoutStyle,
              decoration: const InputDecoration(
                labelText: 'Layout Style',
                border: OutlineInputBorder(),
              ),
              items: models.AppLayoutStyle.values
                  .map(
                    (style) => DropdownMenuItem(
                      value: style,
                      child: Text(style.name),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value == null) return;
                ref.read(settingsProvider.notifier).updateSettings(
                      settings.copyWith(layoutStyle: value),
                    );
              },
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
            const SizedBox(height: 12),
            SwitchListTile(
              title: const Text('Enable notifications'),
              subtitle: const Text('Roster reminders and alerts'),
              value: settings.notifications,
              onChanged: (value) {
                ref.read(settingsProvider.notifier).updateSettings(
                      settings.copyWith(notifications: value),
                    );
              },
              secondary: const Icon(Icons.notifications_active_outlined),
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
                  'Sync',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              title: const Text('Auto sync'),
              subtitle: const Text('Keep roster in sync automatically'),
              value: settings.autoSync,
              onChanged: (value) {
                ref.read(settingsProvider.notifier).updateSettings(
                      settings.copyWith(autoSync: value),
                    );
              },
              secondary: const Icon(Icons.cloud_sync),
            ),
            const SizedBox(height: 8),
            _buildSliderRow(
              context,
              label: 'Sync interval (minutes)',
              value: settings.syncInterval.toDouble(),
              min: 5,
              max: 60,
              onChanged: (value) {
                if (!settings.autoSync) return;
                ref.read(settingsProvider.notifier).updateSettings(
                      settings.copyWith(syncInterval: value.round()),
                    );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnalyticsSection(
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
                  Icons.bar_chart,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Analytics',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              title: const Text('Enable analytics'),
              subtitle: const Text('Collect performance metrics'),
              value: settings.analyticsEnabled,
              onChanged: (value) {
                ref.read(settingsProvider.notifier).updateSettings(
                      settings.copyWith(analyticsEnabled: value),
                    );
              },
              secondary: const Icon(Icons.insights_rounded),
            ),
            SwitchListTile(
              title: const Text('Cloud analytics'),
              subtitle: const Text('Sync analytics to AWS'),
              value: settings.analyticsCloudEnabled,
              onChanged: settings.analyticsEnabled
                  ? (value) {
                      ref.read(settingsProvider.notifier).updateSettings(
                            settings.copyWith(analyticsCloudEnabled: value),
                          );
                    }
                  : null,
              secondary: const Icon(Icons.cloud_outlined),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdaptiveLearningSection(
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
                  Icons.memory,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Adaptive Learning',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              title: const Text('Enable adaptive learning'),
              subtitle: const Text('Improve suggestions from your edits'),
              value: settings.adaptiveLearningEnabled,
              onChanged: (value) {
                ref.read(settingsProvider.notifier).updateSettings(
                      settings.copyWith(adaptiveLearningEnabled: value),
                    );
              },
              secondary: const Icon(Icons.memory),
            ),
            SwitchListTile(
              title: const Text('Global learning (opt-in)'),
              subtitle: const Text(
                'Share anonymous corrections to improve all users',
              ),
              value: settings.adaptiveLearningGlobalOptIn,
              onChanged: settings.adaptiveLearningEnabled
                  ? (value) {
                      ref.read(settingsProvider.notifier).updateSettings(
                            settings.copyWith(
                              adaptiveLearningGlobalOptIn: value,
                            ),
                          );
                    }
                  : null,
              secondary: const Icon(Icons.public),
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('What is shared?'),
              subtitle: const Text(
                'Only shift-code corrections and layout signatures. No names or roster data.',
              ),
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Global learning shares only anonymized correction metadata.',
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.cleaning_services),
              title: const Text('Clear local learning'),
              subtitle: const Text('Remove local adaptive learning cache'),
              onTap: () async {
                await AdaptiveLearningService.instance.clearLocalLearning();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Local adaptive learning cache cleared'),
                    ),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOptimizationSection(
    BuildContext context,
    WidgetRef ref,
    dynamic roster,
  ) {
    final constraints = roster.constraints as models.RosterConstraints;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.tune,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Roster Optimization',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildSliderRow(
              context,
              label: 'Min Staff Per Day',
              value: constraints.minStaffPerDay.toDouble(),
              min: 1,
              max: 10,
              onChanged: (value) {
                ref.read(rosterProvider).updateConstraints(
                      constraints.copyWith(minStaffPerDay: value.round()),
                    );
              },
            ),
            _buildSliderRow(
              context,
              label: 'Min Staff Weekend',
              value: constraints.minStaffWeekend.toDouble(),
              min: 1,
              max: 10,
              onChanged: (value) {
                ref.read(rosterProvider).updateConstraints(
                      constraints.copyWith(minStaffWeekend: value.round()),
                    );
              },
            ),
            _buildSliderRow(
              context,
              label: 'Max Consecutive Days',
              value: constraints.maxConsecutiveDays.toDouble(),
              min: 2,
              max: 14,
              onChanged: (value) {
                ref.read(rosterProvider).updateConstraints(
                      constraints.copyWith(maxConsecutiveDays: value.round()),
                    );
              },
            ),
            _buildSliderRow(
              context,
              label: 'Max Shifts Per Week',
              value: constraints.maxShiftsPerWeek.toDouble(),
              min: 2,
              max: 7,
              onChanged: (value) {
                ref.read(rosterProvider).updateConstraints(
                      constraints.copyWith(maxShiftsPerWeek: value.round()),
                    );
              },
            ),
            _buildSliderRow(
              context,
              label: 'Min Rest Days',
              value: constraints.minRestDaysBetweenShifts.toDouble(),
              min: 0,
              max: 3,
              onChanged: (value) {
                ref.read(rosterProvider).updateConstraints(
                      constraints.copyWith(
                        minRestDaysBetweenShifts: value.round(),
                      ),
                    );
              },
            ),
            _buildSliderRow(
              context,
              label: 'Fairness Weight',
              value: constraints.fairnessWeight,
              min: 0,
              max: 1,
              divisions: 10,
              onChanged: (value) {
                ref.read(rosterProvider).updateConstraints(
                      constraints.copyWith(fairnessWeight: value),
                    );
              },
              valueLabel: constraints.fairnessWeight.toStringAsFixed(2),
            ),
            _buildSliderRow(
              context,
              label: 'Min Leave Balance',
              value: constraints.minLeaveBalance,
              min: 0,
              max: 10,
              divisions: 20,
              onChanged: (value) {
                ref.read(rosterProvider).updateConstraints(
                      constraints.copyWith(minLeaveBalance: value),
                    );
              },
              valueLabel: constraints.minLeaveBalance.toStringAsFixed(1),
            ),
            SwitchListTile(
              title: const Text('Balance Weekends'),
              subtitle: const Text('Rotate weekend shifts more evenly'),
              value: constraints.balanceWeekends,
              onChanged: (value) {
                ref.read(rosterProvider).updateConstraints(
                      constraints.copyWith(balanceWeekends: value),
                    );
              },
              secondary: const Icon(Icons.weekend),
            ),
            SwitchListTile(
              title: const Text('Allow AI Changes'),
              subtitle: const Text('Let AI propose change actions'),
              value: constraints.allowAiOverrides,
              onChanged: (value) {
                ref.read(rosterProvider).updateConstraints(
                      constraints.copyWith(allowAiOverrides: value),
                    );
              },
              secondary: const Icon(Icons.auto_fix_high),
            ),
            ListTile(
              leading: const Icon(Icons.rule),
              title: const Text('Shift Coverage Targets'),
              subtitle: Text(_formatShiftTargets(constraints)),
              trailing: const Icon(Icons.edit),
              onTap: () => _showShiftTargetsDialog(context, ref, roster),
            ),
            ListTile(
              leading: const Icon(Icons.today),
              title: const Text('Daily Coverage Targets'),
              subtitle: Text(_formatDailyTargets(constraints)),
              trailing: const Icon(Icons.edit),
              onTap: () => _showDailyTargetsDialog(context, ref, roster),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShiftHoursSection(
    BuildContext context,
    WidgetRef ref,
    models.AppSettings settings,
  ) {
    final hours = Map<String, double>.from(settings.shiftHourMap);
    const shiftKeys = [
      'D',
      'E',
      'L',
      'N',
      'D12',
      'N12',
      'C',
      'C1',
      'C2',
      'C3',
      'C4',
      'R',
      'OFF',
      'AL',
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.timer_rounded,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Shift Hours',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Used for RC math and roster analytics.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            ...shiftKeys.map((code) {
              final value = hours[code] ?? 0.0;
              return _buildSliderRow(
                context,
                label: '$code hours',
                value: value,
                min: 0,
                max: 24,
                onChanged: (v) {
                  hours[code] = v;
                  ref.read(settingsProvider.notifier).updateSettings(
                        settings.copyWith(shiftHourMap: hours),
                      );
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  String _formatShiftTargets(models.RosterConstraints constraints) {
    if (constraints.shiftCoverageTargets.isEmpty) {
      return 'Not set';
    }
    return constraints.shiftCoverageTargets.entries
        .map((e) => '${e.key}: ${e.value}')
        .join(', ');
  }

  String _formatDailyTargets(models.RosterConstraints constraints) {
    if (constraints.shiftCoverageTargetsByDay.isEmpty) {
      return 'Not set';
    }
    final days = constraints.shiftCoverageTargetsByDay.keys.length;
    return '$days day(s) configured';
  }

  void _showShiftTargetsDialog(
    BuildContext context,
    WidgetRef ref,
    dynamic roster,
  ) {
    final constraints = roster.constraints as models.RosterConstraints;
    final shiftTypes = roster.getShiftTypes() as List<String>;
    final targets = Map<String, int>.from(constraints.shiftCoverageTargets);
    final controllers = <String, TextEditingController>{
      for (final shift in shiftTypes)
        shift: TextEditingController(
          text: (targets[shift] ?? 0).toString(),
        )
    };

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Shift Coverage Targets'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: shiftTypes.map((shift) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: SafeTextField(
                  controller: controllers[shift],
                  decoration: InputDecoration(
                    labelText: '$shift minimum',
                    hintText: 'e.g., 1',
                  ),
                  keyboardType: TextInputType.number,
                ),
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final updated = <String, int>{};
              controllers.forEach((shift, controller) {
                final value = int.tryParse(controller.text.trim()) ?? 0;
                if (value > 0) {
                  updated[shift] = value;
                }
              });
              ref.read(rosterProvider).updateConstraints(
                    constraints.copyWith(shiftCoverageTargets: updated),
                  );
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showDailyTargetsDialog(
    BuildContext context,
    WidgetRef ref,
    dynamic roster,
  ) {
    final constraints = roster.constraints as models.RosterConstraints;
    final shiftTypes = roster.getShiftTypes() as List<String>;
    final dayTargets = Map<String, Map<String, int>>.from(
      constraints.shiftCoverageTargetsByDay,
    );
    int selectedDay = 1;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final dayKey = selectedDay.toString();
          final current =
              Map<String, int>.from(dayTargets[dayKey] ?? {});
          final controllers = <String, TextEditingController>{
            for (final shift in shiftTypes)
              shift: TextEditingController(
                text: (current[shift] ?? 0).toString(),
              )
          };

          return AlertDialog(
            title: const Text('Daily Coverage Targets'),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView(
                shrinkWrap: true,
                children: [
                  DropdownButtonFormField<int>(
                    value: selectedDay,
                    items: List.generate(7, (index) {
                      final day = index + 1;
                      return DropdownMenuItem(
                        value: day,
                        child: Text(_dayLabel(day)),
                      );
                    }),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => selectedDay = value);
                      }
                    },
                    decoration: const InputDecoration(labelText: 'Day'),
                  ),
                  const SizedBox(height: 8),
                  ...shiftTypes.map((shift) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: SafeTextField(
                        controller: controllers[shift],
                        decoration: InputDecoration(
                          labelText: '$shift minimum',
                          hintText: 'e.g., 1',
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    );
                  }).toList(),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final updated = <String, int>{};
                  controllers.forEach((shift, controller) {
                    final value = int.tryParse(controller.text.trim()) ?? 0;
                    if (value > 0) {
                      updated[shift] = value;
                    }
                  });
                  if (updated.isEmpty) {
                    dayTargets.remove(dayKey);
                  } else {
                    dayTargets[dayKey] = updated;
                  }
                  ref.read(rosterProvider).updateConstraints(
                        constraints.copyWith(
                          shiftCoverageTargetsByDay: dayTargets,
                        ),
                      );
                  Navigator.pop(context);
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  String _dayLabel(int weekday) {
    switch (weekday) {
      case 1:
        return 'Mon';
      case 2:
        return 'Tue';
      case 3:
        return 'Wed';
      case 4:
        return 'Thu';
      case 5:
        return 'Fri';
      case 6:
        return 'Sat';
      case 7:
        return 'Sun';
      default:
        return 'Day $weekday';
    }
  }

  Widget _buildSliderRow(
    BuildContext context, {
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
    String? valueLabel,
    int? divisions,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        Row(
          children: [
            Expanded(
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                divisions: divisions ?? (max - min).round(),
                label: valueLabel ?? value.round().toString(),
                onChanged: onChanged,
              ),
            ),
            SizedBox(
              width: 48,
              child: Text(
                valueLabel ?? value.round().toString(),
                textAlign: TextAlign.end,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
      ],
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
            SwitchListTile(
              title: const Text('Holiday Overlay'),
              subtitle: const Text('Show holidays on the roster grid'),
              value: settings.showHolidayOverlay,
              onChanged: (value) {
                ref.read(settingsProvider.notifier).updateSettings(
                      settings.copyWith(showHolidayOverlay: value),
                    );
              },
              secondary: const Icon(Icons.event_available),
            ),
            ListTile(
              leading: const Icon(Icons.align_horizontal_left),
              title: const Text('Month snap offset'),
              subtitle: Text(
                '${settings.monthSnapOffsetPx.toStringAsFixed(0)} px',
              ),
            ),
            Slider(
              value: settings.monthSnapOffsetPx,
              min: -2000,
              max: 2000,
              divisions: 400,
              label: '${settings.monthSnapOffsetPx.toStringAsFixed(0)} px',
              onChanged: (value) {
                ref.read(settingsProvider.notifier).updateSettings(
                      settings.copyWith(monthSnapOffsetPx: value),
                    );
              },
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.history_rounded),
              title: const Text('Past months limit'),
              subtitle: Text('${settings.monthsBackLimit} month(s)'),
            ),
            Slider(
              value: settings.monthsBackLimit.toDouble(),
              min: 1,
              max: 96,
              divisions: 95,
              label: '${settings.monthsBackLimit} months',
              onChanged: (value) {
                ref.read(settingsProvider.notifier).updateSettings(
                      settings.copyWith(monthsBackLimit: value.round()),
                    );
              },
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.forward_rounded),
              title: const Text('Future months limit'),
              subtitle: Text('${settings.monthsForwardLimit} month(s)'),
            ),
            Slider(
              value: settings.monthsForwardLimit.toDouble(),
              min: 1,
              max: 96,
              divisions: 95,
              label: '${settings.monthsForwardLimit} months',
              onChanged: (value) {
                ref.read(settingsProvider.notifier).updateSettings(
                      settings.copyWith(monthsForwardLimit: value.round()),
                    );
              },
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
            ListTile(
              leading: const Icon(Icons.language),
              title: const Text('Language'),
              subtitle: const Text('Change app language'),
              trailing: DropdownButton<String>(
                value: settings.languageCode,
                items: const {
                  'en': 'English',
                  'es': 'Spanish',
                  'fr': 'French',
                  'de': 'German',
                  'it': 'Italian',
                  'pt': 'Portuguese',
                  'zh': 'Chinese',
                  'ja': 'Japanese',
                  'ko': 'Korean',
                  'ar': 'Arabic',
                }.entries.map((entry) {
                  return DropdownMenuItem(
                    value: entry.key,
                    child: Text(entry.value),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    ref.read(settingsProvider.notifier).updateSettings(
                          settings.copyWith(languageCode: value),
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

  Widget _buildVoiceSection(
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
                  Icons.record_voice_over_rounded,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Voice Assistant',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              title: const Text('Enable voice'),
              subtitle: const Text('Let RC listen and respond with speech'),
              value: settings.voiceEnabled,
              onChanged: (value) {
                ref.read(settingsProvider.notifier).updateSettings(
                      settings.copyWith(voiceEnabled: value),
                    );
              },
              secondary: const Icon(Icons.mic_rounded),
            ),
            SwitchListTile(
              title: const Text('Always listening'),
              subtitle: const Text(
                'Wake word: "RC", "Roster Champ", or "Roster Champion"',
              ),
              value: settings.voiceAlwaysListening,
              onChanged: settings.voiceEnabled
                  ? (value) {
                      ref.read(settingsProvider.notifier).updateSettings(
                            settings.copyWith(voiceAlwaysListening: value),
                          );
                    }
                  : null,
              secondary: const Icon(Icons.hearing_rounded),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: settings.voiceInputEngine,
              decoration: const InputDecoration(
                labelText: 'Input engine',
              ),
              items: const [
                DropdownMenuItem(
                  value: 'onDevice',
                  child: Text('On-device (offline)'),
                ),
                DropdownMenuItem(
                  value: 'aws',
                  child: Text('Online (system)'),
                ),
              ],
              onChanged: settings.voiceEnabled
                  ? (value) {
                      if (value != null) {
                        ref.read(settingsProvider.notifier).updateSettings(
                              settings.copyWith(voiceInputEngine: value),
                            );
                      }
                    }
                  : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: settings.voiceOutputEngine,
              decoration: const InputDecoration(
                labelText: 'Voice response engine',
              ),
              items: const [
                DropdownMenuItem(
                  value: 'aws',
                  child: Text('AWS Polly (online)'),
                ),
                DropdownMenuItem(
                  value: 'onDevice',
                  child: Text('On-device TTS'),
                ),
              ],
              onChanged: settings.voiceEnabled
                  ? (value) {
                      if (value != null) {
                        ref.read(settingsProvider.notifier).updateSettings(
                              settings.copyWith(voiceOutputEngine: value),
                            );
                      }
                    }
                  : null,
            ),
            const SizedBox(height: 12),
            if (settings.voiceOutputEngine == 'aws')
              DropdownButtonFormField<String>(
                value: settings.voiceOutputVoice,
                decoration: const InputDecoration(
                  labelText: 'Voice (AWS Polly)',
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'aws:Joanna',
                    child: Text('Joanna (US, Female)'),
                  ),
                  DropdownMenuItem(
                    value: 'aws:Amy',
                    child: Text('Amy (UK, Female)'),
                  ),
                  DropdownMenuItem(
                    value: 'aws:Emma',
                    child: Text('Emma (UK, Female)'),
                  ),
                  DropdownMenuItem(
                    value: 'aws:Olivia',
                    child: Text('Olivia (UK, Female)'),
                  ),
                  DropdownMenuItem(
                    value: 'aws:Salli',
                    child: Text('Salli (US, Female)'),
                  ),
                  DropdownMenuItem(
                    value: 'aws:Ivy',
                    child: Text('Ivy (US, Female)'),
                  ),
                  DropdownMenuItem(
                    value: 'aws:Kendra',
                    child: Text('Kendra (US, Female)'),
                  ),
                  DropdownMenuItem(
                    value: 'aws:Kimberly',
                    child: Text('Kimberly (US, Female)'),
                  ),
                  DropdownMenuItem(
                    value: 'aws:Matthew',
                    child: Text('Matthew (US, Male)'),
                  ),
                  DropdownMenuItem(
                    value: 'aws:Brian',
                    child: Text('Brian (UK, Male)'),
                  ),
                  DropdownMenuItem(
                    value: 'aws:Justin',
                    child: Text('Justin (US, Male)'),
                  ),
                  DropdownMenuItem(
                    value: 'aws:Joey',
                    child: Text('Joey (US, Male)'),
                  ),
                ],
                onChanged: settings.voiceEnabled
                    ? (value) {
                        if (value != null) {
                          ref.read(settingsProvider.notifier).updateSettings(
                                settings.copyWith(voiceOutputVoice: value),
                              );
                        }
                      }
                    : null,
              )
            else
              FutureBuilder<List<Map<String, String>>>(
                future: VoiceService.instance.getDeviceVoices(),
                builder: (context, snapshot) {
                  final voices = snapshot.data ?? [];
                  final items = <DropdownMenuItem<String>>[
                    const DropdownMenuItem(
                      value: 'device:default',
                      child: Text('Device default'),
                    ),
                  ];
                  for (final voice in voices) {
                    final name = voice['name'] ?? '';
                    final locale = voice['locale'] ?? '';
                    if (name.isEmpty) continue;
                    items.add(
                      DropdownMenuItem(
                        value: 'device:$name|$locale',
                        child: Text(
                          locale.isEmpty ? name : '$name ($locale)',
                        ),
                      ),
                    );
                  }
                  return DropdownButtonFormField<String>(
                    value: settings.voiceOutputVoice.startsWith('device:')
                        ? settings.voiceOutputVoice
                        : 'device:default',
                    decoration: const InputDecoration(
                      labelText: 'Voice (Device)',
                    ),
                    items: items,
                    onChanged: settings.voiceEnabled
                        ? (value) {
                            if (value != null) {
                              ref
                                  .read(settingsProvider.notifier)
                                  .updateSettings(
                                    settings.copyWith(
                                      voiceOutputVoice: value,
                                    ),
                                  );
                            }
                          }
                        : null,
                  );
                },
              ),
            const SizedBox(height: 8),
            Text(
              'If offline, RC automatically falls back to on-device speech.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHolidaySection(
    BuildContext context,
    WidgetRef ref,
    models.AppSettings settings,
    dynamic roster,
  ) {
    final isReadOnly = roster.readOnly as bool? ?? false;
      const allTypes = [
        'Public',
        'Bank',
        'Observance',
        'Optional',
        'School',
        'Authorities',
      ];
      const observanceTypes = [
        'religious',
        'observance',
        'national',
        'local',
      ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.public,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Holidays & Locale',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 12),
            FutureBuilder<List<CountryInfo>>(
              future: CountryService.instance.getCountries(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const LinearProgressIndicator();
                }
                if (!snapshot.hasData) {
                  return const Text('Unable to load country list.');
                }
                final countries = snapshot.data!;
                final selected = countries.firstWhere(
                  (c) => c.code == settings.holidayCountryCode,
                  orElse: () => countries.first,
                );
                return DropdownButtonFormField<String>(
                  value: selected.code,
                  items: countries
                      .map((country) => DropdownMenuItem(
                            value: country.code,
                            child: Text('${country.flag} ${country.name}'),
                          ))
                      .toList(),
                  onChanged: isReadOnly
                      ? null
                      : (value) {
                          if (value != null) {
                            final chosen = countries.firstWhere(
                              (c) => c.code == value,
                              orElse: () => countries.first,
                            );
                            ref.read(settingsProvider.notifier).updateSettings(
                                  settings.copyWith(
                                    holidayCountryCode: value,
                                    timeZone: chosen.timezones.isNotEmpty
                                        ? chosen.timezones.first
                                        : settings.timeZone,
                                    siteLat: chosen.lat ?? settings.siteLat,
                                    siteLon: chosen.lon ?? settings.siteLon,
                                    siteName: chosen.name,
                                  ),
                                );
                          }
                        },
                  decoration: const InputDecoration(
                    labelText: 'Country',
                    border: OutlineInputBorder(),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            Text(
              'Holiday types',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: allTypes.map((type) {
                  final selected = settings.holidayTypes.contains(type);
                  return FilterChip(
                    label: Text(type),
                  selected: selected,
                  onSelected: isReadOnly
                      ? null
                      : (value) {
                          final updated =
                              List<String>.from(settings.holidayTypes);
                          if (value) {
                            if (!updated.contains(type)) {
                              updated.add(type);
                            }
                          } else {
                            updated.remove(type);
                          }
                          ref.read(settingsProvider.notifier).updateSettings(
                                settings.copyWith(holidayTypes: updated),
                              );
                        },
                );
                }).toList(),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                title: const Text('Religious & cultural overlay'),
                subtitle: const Text('Show religious and cultural observances'),
                value: settings.showObservanceOverlay,
                onChanged: (value) {
                  ref.read(settingsProvider.notifier).updateSettings(
                        settings.copyWith(showObservanceOverlay: value),
                      );
                },
                secondary: const Icon(Icons.temple_hindu),
              ),
              SafeTextField(
                initialValue: settings.calendarificApiKey,
                decoration: const InputDecoration(
                  labelText: 'Calendarific API key',
                  helperText: 'Required for religious/cultural observances',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                onChanged: (value) {
                  ref.read(settingsProvider.notifier).updateSettings(
                        settings.copyWith(calendarificApiKey: value.trim()),
                      );
                },
              ),
              const SizedBox(height: 8),
              Text(
                'Observance types',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: observanceTypes.map((type) {
                  final selected =
                      settings.observanceTypes.contains(type);
                  return FilterChip(
                    label: Text(type),
                    selected: selected,
                    onSelected: (value) {
                      final updated =
                          List<String>.from(settings.observanceTypes);
                      if (value) {
                        if (!updated.contains(type)) {
                          updated.add(type);
                        }
                      } else {
                        updated.remove(type);
                      }
                      ref.read(settingsProvider.notifier).updateSettings(
                            settings.copyWith(observanceTypes: updated),
                          );
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                title: const Text('Sports overlay'),
                subtitle: const Text('Show major sporting events'),
                value: settings.showSportsOverlay,
                onChanged: (value) {
                  ref.read(settingsProvider.notifier).updateSettings(
                        settings.copyWith(showSportsOverlay: value),
                      );
                },
                secondary: const Icon(Icons.sports_soccer),
              ),
              SafeTextField(
                initialValue: settings.sportsApiKey,
                decoration: const InputDecoration(
                  labelText: 'Sports API key',
                  helperText: 'TheSportsDB API key',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                onChanged: (value) {
                  ref.read(settingsProvider.notifier).updateSettings(
                        settings.copyWith(sportsApiKey: value.trim()),
                      );
                },
              ),
              const SizedBox(height: 8),
              SafeTextField(
                initialValue: settings.sportsLeagueIds.join(','),
                decoration: const InputDecoration(
                  labelText: 'Sports league IDs',
                  helperText: 'Comma-separated league IDs',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) {
                  final ids = value
                      .split(',')
                      .map((e) => e.trim())
                      .where((e) => e.isNotEmpty)
                      .toList();
                  ref.read(settingsProvider.notifier).updateSettings(
                        settings.copyWith(sportsLeagueIds: ids),
                      );
                },
              ),
              const SizedBox(height: 12),
              if (settings.hiddenOverlayDates.isNotEmpty) ...[
                OutlinedButton.icon(
                  onPressed: () {
                    ref.read(settingsProvider.notifier).updateSettings(
                          settings.copyWith(hiddenOverlayDates: []),
                        );
                  },
                  icon: const Icon(Icons.visibility),
                  label: Text(
                    'Show ${settings.hiddenOverlayDates.length} hidden overlays',
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Text(
                'Uses Nager.Date for public holidays, Calendarific for observances, and TheSportsDB for sports.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.grey[600]),
              ),
            const SizedBox(height: 16),
            _buildLocaleSection(context, ref, settings, roster),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: isReadOnly
                  ? null
                  : () => _showHolidayImportDialog(
                        context,
                        ref,
                        settings,
                        roster,
                      ),
              icon: const Icon(Icons.download),
              label: const Text('Import Holidays'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocaleSection(
    BuildContext context,
    WidgetRef ref,
    models.AppSettings settings,
    dynamic roster,
  ) {
    final isReadOnly = roster.readOnly as bool? ?? false;
    final locationController =
        TextEditingController(text: settings.siteName);
    List<LocationResult> results = [];

    return StatefulBuilder(
      builder: (context, setState) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Location & Timezone',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          SafeTextField(
            controller: locationController,
            decoration: InputDecoration(
              labelText: 'Search location',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: const Icon(Icons.search),
                onPressed: isReadOnly
                    ? null
                    : () async {
                        final query = locationController.text.trim();
                        if (query.isEmpty) return;
                        try {
                          final found =
                              await LocationService.instance.search(query);
                          setState(() => results = found);
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Location error: $e')),
                            );
                          }
                        }
                      },
              ),
            ),
            readOnly: isReadOnly,
          ),
          if (results.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...results.map(
              (result) => ListTile(
                title: Text(result.name),
                subtitle: Text(
                  '${result.lat.toStringAsFixed(4)}, ${result.lon.toStringAsFixed(4)}',
                ),
                onTap: isReadOnly
                    ? null
                    : () {
                        ref.read(settingsProvider.notifier).updateSettings(
                              settings.copyWith(
                                siteName: result.name,
                                siteLat: result.lat,
                                siteLon: result.lon,
                              ),
                            );
                        setState(() => results = []);
                      },
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'Selected timezone: ${settings.timeZone}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            title: const Text('Show weather overlay'),
            subtitle: const Text('Overlay forecast on the roster'),
            value: settings.showWeatherOverlay,
            onChanged: isReadOnly
                ? null
                : (value) {
                    ref.read(settingsProvider.notifier).updateSettings(
                          settings.copyWith(showWeatherOverlay: value),
                        );
                  },
          ),
          SwitchListTile(
            title: const Text('Show map preview'),
            subtitle: const Text('Preview selected location'),
            value: settings.showMapPreview,
            onChanged: isReadOnly
                ? null
                : (value) {
                    ref.read(settingsProvider.notifier).updateSettings(
                          settings.copyWith(showMapPreview: value),
                        );
                  },
          ),
          if (settings.showMapPreview &&
              settings.siteLat != null &&
              settings.siteLon != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                _mapPreviewUrl(settings.siteLat!, settings.siteLon!),
                height: 160,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
        ],
      ),
    );
  }

  String _mapPreviewUrl(double lat, double lon) {
    return 'https://staticmap.openstreetmap.de/staticmap.php'
        '?center=$lat,$lon&zoom=10&size=600x300&markers=$lat,$lon,red-pushpin';
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
              onTap: () => _openExternal(context, _privacyUrl),
            ),
            ListTile(
              leading: const Icon(Icons.description),
              title: const Text('Terms of Service'),
              trailing: const Icon(Icons.open_in_new),
              onTap: () => _openExternal(context, _termsUrl),
            ),
            ListTile(
              leading: const Icon(Icons.bug_report),
              title: const Text('Report an Issue'),
              trailing: const Icon(Icons.open_in_new),
              onTap: () => _openExternal(context, _issuesUrl),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openExternal(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open link.')),
      );
    }
  }

  Widget _buildAccountSection(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.manage_accounts,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Account',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Manage access to your account and data.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () async {
                await _confirmLogout(context);
              },
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Sign Out'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () async {
                await _confirmDeleteAccount(context);
              },
              icon: const Icon(Icons.delete_forever_rounded, color: Colors.red),
              label: const Text(
                'Delete Account',
                style: TextStyle(color: Colors.red),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: Colors.red.withOpacity(0.6)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoleTemplatesSection(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.admin_panel_settings,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Role Templates',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 12),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: AwsService.instance.getRoleTemplates(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const LinearProgressIndicator();
                }
                if (!snapshot.hasData) {
                  return const Text('Unable to load role templates.');
                }
                final templates = snapshot.data!;
                return Column(
                  children: templates.map((template) {
                    final permissions =
                        (template['permissions'] as List<dynamic>? ?? [])
                            .map((e) => e.toString())
                            .join(', ');
                    return ListTile(
                      leading: const Icon(Icons.security),
                      title: Text(template['name']?.toString() ?? 'Role'),
                      subtitle: Text(
                        template['description']?.toString() ?? '',
                      ),
                      trailing: Tooltip(
                        message: permissions,
                        child: const Icon(Icons.info_outline),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout?'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await AwsService.instance.signOut();
    }
  }

  Future<void> _confirmDeleteAccount(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete account?'),
        content: const Text(
          'This permanently deletes your account and removes your membership '
          'from rosters and teams. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await AwsService.instance.deleteAccount();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Account deleted')),
        );
      }
    }
  }

  Future<void> _showHolidayImportDialog(
    BuildContext context,
    WidgetRef ref,
    models.AppSettings settings,
    dynamic roster,
  ) async {
    final activeStaff = roster.getActiveStaffNames() as List<String>;
    final selectedStaff = <String>{...activeStaff};
    bool includeNextYear = false;
    bool addEvents = true;
    bool applyLeave = false;
    bool allStaff = true;
    bool isLoading = false;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Import Holidays'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                    title: const Text('Add as roster events'),
                    value: addEvents,
                    onChanged: (value) => setState(() => addEvents = value),
                  ),
                  SwitchListTile(
                    title: const Text('Apply leave changes'),
                    subtitle: const Text('Set selected staff to AL on holidays'),
                    value: applyLeave,
                    onChanged: (value) => setState(() => applyLeave = value),
                  ),
                  SwitchListTile(
                    title: const Text('Include next year'),
                    value: includeNextYear,
                    onChanged: (value) =>
                        setState(() => includeNextYear = value),
                  ),
                  if (applyLeave) ...[
                    SwitchListTile(
                      title: const Text('Apply to all active staff'),
                      value: allStaff,
                      onChanged: (value) => setState(() => allStaff = value),
                    ),
                    if (!allStaff)
                      Wrap(
                        spacing: 8,
                        children: activeStaff.map((name) {
                          final selected = selectedStaff.contains(name);
                          return FilterChip(
                            label: Text(name),
                            selected: selected,
                            onSelected: (value) {
                              setState(() {
                                if (value) {
                                  selectedStaff.add(name);
                                } else {
                                  selectedStaff.remove(name);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isLoading ? null : () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: isLoading
                    ? null
                    : () async {
                        if (!addEvents && !applyLeave) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content:
                                  Text('Select at least one import action'),
                            ),
                          );
                          return;
                        }
                        if (settings.holidayTypes.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Select at least one holiday type'),
                            ),
                          );
                          return;
                        }
                        setState(() => isLoading = true);
                        try {
                          final year = DateTime.now().year;
                          final holidays = <HolidayItem>[];
                          holidays.addAll(await HolidayService.instance
                              .getHolidays(
                                  countryCode:
                                      settings.holidayCountryCode,
                                  year: year));
                          if (includeNextYear) {
                            holidays.addAll(await HolidayService.instance
                                .getHolidays(
                                    countryCode:
                                        settings.holidayCountryCode,
                                    year: year + 1));
                          }
                          final filtered = holidays.where((holiday) {
                            return holiday.types
                                .any(settings.holidayTypes.contains);
                          }).toList();
                          if (filtered.isEmpty) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('No holidays matched filters'),
                                ),
                              );
                            }
                            setState(() => isLoading = false);
                            return;
                          }
                          final staffList = allStaff
                              ? activeStaff
                              : selectedStaff.toList();
                          final result =
                              await roster.importHolidays(
                            holidays: filtered,
                            addEvents: addEvents,
                            applyLeaveOverrides: applyLeave,
                            staffNames: staffList,
                          );
                          if (context.mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Imported ${result['events']} events, ${result['overrides']} leave changes',
                                ),
                              ),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error: $e')),
                            );
                          }
                        } finally {
                          if (context.mounted) {
                            setState(() => isLoading = false);
                          }
                        }
                      },
                child: isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Import'),
              ),
            ],
          );
        },
      ),
    );
  }
}





