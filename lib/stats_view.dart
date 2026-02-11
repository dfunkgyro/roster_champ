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
        _buildHealthScoreCard(context, stats),
        const SizedBox(height: 16),
        _buildUtilizationCard(context, stats),
        const SizedBox(height: 16),
        _buildOvertimeRiskCard(context, stats),
        const SizedBox(height: 16),
        _buildLeaveBurndownCard(context, stats),
        const SizedBox(height: 16),
        _buildComplianceCard(context, stats),
        const SizedBox(height: 16),
        _buildCoverageHeatmapCard(context, roster),
        const SizedBox(height: 16),
        _buildStaffStatsCard(context, roster),
        const SizedBox(height: 16),
        _buildLeaveBalancesCard(context, roster),
        const SizedBox(height: 16),
        _buildAISuggestionsCard(context, stats),
      ],
    );
  }

  Widget _buildHealthScoreCard(
    BuildContext context,
    Map<String, dynamic> stats,
  ) {
    final health = stats['healthScore'] as Map<String, dynamic>?;
    if (health == null) {
      return const SizedBox.shrink();
    }

    String pct(double value) => '${(value * 100).toStringAsFixed(0)}%';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.favorite,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Roster Health',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildStatRow(
              context,
              'Overall',
              pct((health['overall'] as num).toDouble()),
              Icons.health_and_safety,
            ),
            _buildStatRow(
              context,
              'Coverage',
              pct((health['coverage'] as num).toDouble()),
              Icons.people_alt,
            ),
            _buildStatRow(
              context,
              'Workload',
              pct((health['workload'] as num).toDouble()),
              Icons.bar_chart,
            ),
            _buildStatRow(
              context,
              'Fairness',
              pct((health['fairness'] as num).toDouble()),
              Icons.balance,
            ),
            _buildStatRow(
              context,
              'Leave',
              pct((health['leave'] as num).toDouble()),
              Icons.beach_access,
            ),
            _buildStatRow(
              context,
              'Pattern',
              pct((health['pattern'] as num).toDouble()),
              Icons.pattern,
            ),
          ],
        ),
      ),
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
              'Total Changes',
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

  Widget _buildUtilizationCard(
    BuildContext context,
    Map<String, dynamic> stats,
  ) {
    String pct(double value) => '${(value * 100).toStringAsFixed(1)}%';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.timeline,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Utilization & Costs',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildStatRow(
              context,
              'Utilization Rate',
              pct((stats['utilizationRate'] as num?)?.toDouble() ?? 0),
              Icons.percent,
            ),
            _buildStatRow(
              context,
              'Avg Shifts/Staff',
              (stats['avgShiftsPerStaff'] as num?)?.toStringAsFixed(1) ?? '0',
              Icons.av_timer,
            ),
            _buildStatRow(
              context,
              'Workload Spread',
              (stats['shiftStdDev'] as num?)?.toStringAsFixed(2) ?? '0',
              Icons.balance,
            ),
            _buildStatRow(
              context,
              'Projected Cost',
              stats['projectedCost'] != null
                  ? '\$${(stats['projectedCost'] as num).toStringAsFixed(0)}'
                  : '\$0',
              Icons.attach_money,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOvertimeRiskCard(
    BuildContext context,
    Map<String, dynamic> stats,
  ) {
    final overtime = stats['overtimeRisk'] as Map<String, dynamic>?;
    if (overtime == null) return const SizedBox.shrink();
    final highRiskCount = overtime['highRiskCount'] as int? ?? 0;
    final highRiskStaff =
        (overtime['highRiskStaff'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Overtime Risk',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildStatRow(
              context,
              'High Risk Staff',
              '$highRiskCount',
              Icons.person_off,
              highRiskCount > 0 ? Colors.orange : null,
            ),
            if (highRiskStaff.isNotEmpty)
              Text(
                highRiskStaff.join(', '),
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLeaveBurndownCard(
    BuildContext context,
    Map<String, dynamic> stats,
  ) {
    final burndown = stats['leaveBurndown'] as Map<String, dynamic>?;
    if (burndown == null) return const SizedBox.shrink();
    final atRisk = (burndown['atRiskStaff'] as List<dynamic>? ?? [])
        .map((e) => e.toString())
        .toList();
    final scheduled =
        burndown['scheduledLeaveDays'] as Map<String, dynamic>? ?? {};

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.beach_access_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Leave Burndown',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (scheduled.isEmpty)
              const Text('No upcoming leave scheduled.')
            else
              ...scheduled.entries.map((entry) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(entry.key),
                        Text('${entry.value} days'),
                      ],
                    ),
                  )),
            if (atRisk.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'At Risk: ${atRisk.join(', ')}',
                style: TextStyle(color: Colors.orange[700]),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildComplianceCard(
    BuildContext context,
    Map<String, dynamic> stats,
  ) {
    final compliance = stats['compliance'] as Map<String, dynamic>?;
    if (compliance == null) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.rule_folder,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Compliance',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildStatRow(
              context,
              'Coverage Violations',
              '${compliance['coverageViolations'] ?? 0}',
              Icons.people_alt,
            ),
            _buildStatRow(
              context,
              'Shift Target Gaps',
              '${compliance['shiftCoverageViolations'] ?? 0}',
              Icons.view_week,
            ),
            _buildStatRow(
              context,
              'Max Consecutive Breaches',
              '${compliance['maxConsecutiveViolations'] ?? 0}',
              Icons.timeline,
            ),
            _buildStatRow(
              context,
              'Rest Rule Breaches',
              '${compliance['minRestViolations'] ?? 0}',
              Icons.bedtime,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCoverageHeatmapCard(BuildContext context, dynamic roster) {
    final heatmap = roster.buildCoverageHeatmap(days: 14);
    if (heatmap.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.view_week,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Coverage Heatmap (14 days)',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 120,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: heatmap.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final dateKey = heatmap.keys.elementAt(index);
                  final shifts = heatmap[dateKey] ?? {};
                  return Container(
                    width: 90,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          dateKey,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: ListView(
                            physics: const NeverScrollableScrollPhysics(),
                            children: shifts.entries
                                .map(
                                  (entry) => Padding(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 2),
                                    child: Text(
                                      '${entry.key}: ${entry.value}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
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
