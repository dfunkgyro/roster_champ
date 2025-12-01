import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers.dart';

class StatsView extends ConsumerWidget {
  const StatsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roster = ref.watch(rosterProvider);
    final stats = roster.getStatistics();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildOverviewCard(context, stats),
        const SizedBox(height: 16),
        _buildStaffStatsCard(context, roster),
        const SizedBox(height: 16),
        _buildLeaveBalancesCard(context, roster),
        const SizedBox(height: 16),
        _buildAISuggestionsCard(context, stats),
      ],
    );
  }

  Widget _buildOverviewCard(BuildContext context, Map<String, dynamic> stats) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.insights,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Overview',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildStatRow(
              context,
              'Total Staff',
              '${stats['totalStaff']}',
              Icons.people,
            ),
            _buildStatRow(
              context,
              'Active Staff',
              '${stats['activeStaff']}',
              Icons.check_circle,
              // valueColor: Colors.green,
            ),
            _buildStatRow(
              context,
              'Total Overrides',
              '${stats['totalOverrides']}',
              Icons.edit_calendar,
            ),
            _buildStatRow(
              context,
              'Leave Days',
              '${stats['totalLeaveDays']}',
              Icons.beach_access,
              // valueColor: Colors.orange,
            ),
            _buildStatRow(
              context,
              'Events',
              '${stats['totalEvents']}',
              Icons.event,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStaffStatsCard(BuildContext context, dynamic roster) {
    final activeStaff = roster.getActiveStaffNames();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.group,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Staff Members',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (activeStaff.isEmpty)
              const Text('No active staff members')
            else
              ...activeStaff.map((name) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        const Icon(Icons.person, size: 20),
                        const SizedBox(width: 8),
                        Text(name),
                      ],
                    ),
                  )),
          ],
        ),
      ),
    );
  }

  Widget _buildLeaveBalancesCard(BuildContext context, dynamic roster) {
    final balances = roster.getLeaveBalances();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.account_balance_wallet,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Leave Balances',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (balances.isEmpty)
              const Text('No staff members')
            else
              ...balances.entries.map((entry) {
                final color = entry.value < 0
                    ? Colors.red
                    : entry.value < 5
                        ? Colors.orange
                        : Colors.green;

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(entry.key),
                      Text(
                        '${entry.value.toStringAsFixed(1)} days',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildAISuggestionsCard(
    BuildContext context,
    Map<String, dynamic> stats,
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
                  Icons.psychology,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'AI Insights',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildStatRow(
              context,
              'Total Suggestions',
              '${stats['aiSuggestions']}',
              Icons.lightbulb,
            ),
            _buildStatRow(
              context,
              'Unread',
              '${stats['unreadSuggestions']}',
              Icons.notification_important,
              // valueColor: Colors.orange,
            ),
            _buildStatRow(
              context,
              'Pattern Propagation',
              stats['patternPropagationActive'] ? 'Active' : 'Inactive',
              Icons.sync,
              // valueColor: stats['patternPropagationActive']
              // ? Colors.green
              //: Colors.grey,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow(
    BuildContext context,
    String label,
    String value, [
    IconData? icon,
    Color? valueColor,
  ]) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20, color: Colors.grey[600]),
                const SizedBox(width: 8),
              ],
              Text(label),
            ],
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}
