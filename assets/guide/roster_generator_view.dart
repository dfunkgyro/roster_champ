import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers.dart';
import 'roster_generator.dart';
import 'models.dart' as models;

class RosterGeneratorView extends ConsumerStatefulWidget {
  const RosterGeneratorView({super.key});

  @override
  ConsumerState<RosterGeneratorView> createState() =>
      _RosterGeneratorViewState();
}

class _RosterGeneratorViewState extends ConsumerState<RosterGeneratorView> {
  late HybridRosterConfig _defaults;

  late final TextEditingController _teamCountController;
  late final TextEditingController _earlyController;
  late final TextEditingController _lateAController;
  late final TextEditingController _lateBController;
  late final TextEditingController _nightWeekdayController;
  late final TextEditingController _fridayNightController;
  late final TextEditingController _weekendDayController;
  late final TextEditingController _weekendDaySunController;
  late final TextEditingController _weekendNightSatController;
  late final TextEditingController _weekendNightSunController;
  late final TextEditingController _generalCoverController;

  int _weekStartDay = 0;
  final Set<int> _generalCoverDays = {1, 2, 3, 4};
  bool _renameTeams = false;
  bool _clearOverrides = true;
  bool _propagateAfterApply = true;
  GeneratedRoster? _preview;
  int _dayOffset = 0;
  int _weekOffset = 0;
  final List<_CoverTierRow> _coverTiers = [];
  final TextEditingController _templateNameController =
      TextEditingController(text: 'Hybrid Template');

  @override
  void initState() {
    super.initState();
    _defaults = HybridRosterConfig.defaults();
    _weekStartDay = ref.read(rosterProvider).weekStartDay;
    _teamCountController =
        TextEditingController(text: _defaults.teamCount.toString());
    _earlyController =
        TextEditingController(text: _formatList(_defaults.earlyTeams));
    _lateAController =
        TextEditingController(text: _formatList(_defaults.lateGroupA));
    _lateBController =
        TextEditingController(text: _formatList(_defaults.lateGroupB));
    _nightWeekdayController =
        TextEditingController(text: _formatList(_defaults.nightWeekdayTeams));
    _fridayNightController =
        TextEditingController(text: _formatList(_defaults.fridayNightTeams));
    _weekendDayController =
        TextEditingController(text: _formatList(_defaults.weekendDayTeams));
    _weekendDaySunController =
        TextEditingController(text: _formatList(_defaults.weekendDaySunTeams));
    _weekendNightSatController = TextEditingController(
        text: _formatList(_defaults.weekendNightSatTeams));
    _weekendNightSunController = TextEditingController(
        text: _formatList(_defaults.weekendNightSunTeams));
    _coverTiers.addAll([
      _CoverTierRow(code: 'C1', teams: _formatList([5])),
      _CoverTierRow(code: 'C2', teams: _formatList([13])),
      _CoverTierRow(code: 'C3', teams: _formatList([16])),
      _CoverTierRow(code: 'C4', teams: _formatList([11])),
    ]);
    _generalCoverController = TextEditingController(
        text: _formatList(_defaults.generalCoverTeams));
  }

  @override
  void dispose() {
    _teamCountController.dispose();
    _earlyController.dispose();
    _lateAController.dispose();
    _lateBController.dispose();
    _nightWeekdayController.dispose();
    _fridayNightController.dispose();
    _weekendDayController.dispose();
    _weekendDaySunController.dispose();
    _weekendNightSatController.dispose();
    _weekendNightSunController.dispose();
    for (final tier in _coverTiers) {
      tier.dispose();
    }
    _templateNameController.dispose();
    _generalCoverController.dispose();
    super.dispose();
  }

  String _formatList(List<int> values) => values.join(', ');

  List<int> _parseList(String input) {
    return input
        .split(',')
        .map((value) => int.tryParse(value.trim()))
        .whereType<int>()
        .toList();
  }

  HybridRosterConfig _buildConfig() {
    final teamCount = int.tryParse(_teamCountController.text.trim()) ?? 16;
    final coverTiers = <int, String>{};
    for (final tier in _coverTiers) {
      final code = tier.code.trim().toUpperCase();
      if (code.isEmpty) continue;
      for (final id in _parseList(tier.teams)) {
        coverTiers[id] = code;
      }
    }

    return HybridRosterConfig(
      teamCount: teamCount,
      weekStartDay: _weekStartDay,
      earlyTeams: _parseList(_earlyController.text),
      lateGroupA: _parseList(_lateAController.text),
      lateGroupB: _parseList(_lateBController.text),
      nightWeekdayTeams: _parseList(_nightWeekdayController.text),
      fridayNightTeams: _parseList(_fridayNightController.text),
      weekendDayTeams: _parseList(_weekendDayController.text),
      weekendDaySunTeams: _parseList(_weekendDaySunController.text),
      weekendNightSatTeams: _parseList(_weekendNightSatController.text),
      weekendNightSunTeams: _parseList(_weekendNightSunController.text),
      coverTiers: coverTiers,
      generalCoverTeams: _parseList(_generalCoverController.text),
      generalCoverDays: _generalCoverDays.toList()..sort(),
    );
  }

  void _generatePreview() {
    final config = _buildConfig();
    final generator = ref.read(rosterProvider.notifier);
    final preview = _applyOffsets(
      generator.generateHybridRoster(config),
      dayOffset: _dayOffset,
      weekOffset: _weekOffset,
    );
    setState(() => _preview = preview);
  }

  Future<void> _applyRoster() async {
    final config = _buildConfig();
    final roster = ref.read(rosterProvider.notifier);
    final generated = _applyOffsets(
      roster.generateHybridRoster(config),
      dayOffset: _dayOffset,
      weekOffset: _weekOffset,
    );
    roster.setWeekStartDay(config.weekStartDay);
    roster.applyGeneratedRoster(
      generated,
      teamCount: config.teamCount,
      clearOverrides: _clearOverrides,
      renameTeams: _renameTeams,
    );
    if (_propagateAfterApply) {
      roster.propagatePattern();
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Auto roster generated.')),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final roster = ref.watch(rosterProvider);
    final labels = roster.weekDayLabels;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Auto Roster Generator'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Configure the hybrid roster rules and generate the pattern.',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          _buildNumberField('Team count', _teamCountController),
          const SizedBox(height: 12),
          _buildWeekStartDropdown(labels),
          const SizedBox(height: 16),
          _buildSectionTitle('Core weekday shifts'),
          _buildTextField('Early teams (Mon-Fri)', _earlyController),
          _buildTextField('Late Group A (Mon-Tue)', _lateAController),
          _buildTextField('Late Group B (Wed-Fri)', _lateBController),
          _buildTextField('Night teams (Mon-Thu)', _nightWeekdayController),
          _buildTextField('Friday night teams', _fridayNightController),
          const SizedBox(height: 16),
          _buildSectionTitle('Weekend bridge shifts'),
          _buildTextField('Weekend day teams (Sat)', _weekendDayController),
          _buildTextField('Weekend day teams (Sun)', _weekendDaySunController),
          _buildTextField(
              'Weekend night teams (Sat)', _weekendNightSatController),
          _buildTextField(
              'Weekend night teams (Sun)', _weekendNightSunController),
          const SizedBox(height: 16),
          _buildSectionTitle('Cover tiers (optional)'),
          _buildCoverTierList(),
          _buildTextField('General cover teams (C)', _generalCoverController),
          const SizedBox(height: 8),
          _buildGeneralCoverDays(labels),
          const SizedBox(height: 16),
          _buildSectionTitle('Align pattern before apply'),
          _buildOffsetControls(),
          const SizedBox(height: 16),
          _buildSectionTitle('Template'),
          TextField(
            controller: _templateNameController,
            decoration: const InputDecoration(
              labelText: 'Template name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () {
              final name = _templateNameController.text.trim();
              if (name.isEmpty) return;
              final config = _buildConfig();
              final roster = ref.read(rosterProvider.notifier);
              final generated = _applyOffsets(
                roster.generateHybridRoster(config),
                dayOffset: _dayOffset,
                weekOffset: _weekOffset,
              );
              roster.saveGeneratedRosterTemplate(
                name: name,
                generated: generated,
                teamCount: config.teamCount,
                weekStart: config.weekStartDay,
              );
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Template saved.')),
              );
            },
            icon: const Icon(Icons.save),
            label: const Text('Save Template'),
          ),
          const SizedBox(height: 16),
          _buildSectionTitle('Saved Templates'),
          _buildTemplateList(roster),
          const SizedBox(height: 16),
          SwitchListTile(
            title: const Text('Rename staff to Team 1..N'),
            value: _renameTeams,
            onChanged: (value) => setState(() => _renameTeams = value),
          ),
          SwitchListTile(
            title: const Text('Clear existing overrides'),
            value: _clearOverrides,
            onChanged: (value) => setState(() => _clearOverrides = value),
          ),
          SwitchListTile(
            title: const Text('Propagate after apply (default on)'),
            value: _propagateAfterApply,
            onChanged: (value) => setState(() => _propagateAfterApply = value),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _generatePreview,
                  child: const Text('Preview'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _applyRoster,
                  child: const Text('Apply to Roster'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_preview != null) _buildPreviewTable(labels, _preview!),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildNumberField(String label, TextEditingController controller) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          helperText: 'Comma separated team numbers',
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  Widget _buildWeekStartDropdown(List<String> labels) {
    return InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Week starts on',
        border: OutlineInputBorder(),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: _weekStartDay,
          items: labels
              .asMap()
              .entries
              .map(
                (entry) => DropdownMenuItem(
                  value: entry.key,
                  child: Text(entry.value),
                ),
              )
              .toList(),
          onChanged: (value) =>
              setState(() => _weekStartDay = value ?? 0),
        ),
      ),
    );
  }

  Widget _buildGeneralCoverDays(List<String> labels) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: List.generate(7, (index) {
        return FilterChip(
          label: Text(labels[index]),
          selected: _generalCoverDays.contains(index),
          onSelected: (selected) {
            setState(() {
              if (selected) {
                _generalCoverDays.add(index);
              } else {
                _generalCoverDays.remove(index);
              }
            });
          },
        );
      }),
    );
  }

  Widget _buildCoverTierList() {
    return Column(
      children: [
        ..._coverTiers.map(
          (tier) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 72,
                  child: TextField(
                    controller: tier.codeController,
                    decoration: const InputDecoration(
                      labelText: 'Tier',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: tier.teamsController,
                    decoration: const InputDecoration(
                      labelText: 'Teams',
                      helperText: 'Comma separated',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: () =>
                      setState(() => _coverTiers.remove(tier)),
                ),
              ],
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () {
              final next = _coverTiers.length + 1;
              setState(() {
                _coverTiers.add(_CoverTierRow(code: 'C$next', teams: ''));
              });
            },
            icon: const Icon(Icons.add),
            label: const Text('Add cover tier'),
          ),
        ),
      ],
    );
  }

  Widget _buildOffsetControls() {
    return Row(
      children: [
        Expanded(
          child: _buildOffsetControl(
            label: 'Day offset',
            value: _dayOffset,
            onChanged: (value) => setState(() => _dayOffset = value),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildOffsetControl(
            label: 'Week offset',
            value: _weekOffset,
            onChanged: (value) => setState(() => _weekOffset = value),
          ),
        ),
      ],
    );
  }

  Widget _buildOffsetControl({
    required String label,
    required int value,
    required ValueChanged<int> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: () => onChanged(value - 1),
            ),
            Expanded(
              child: Center(
                child: Text(
                  value.toString(),
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: () => onChanged(value + 1),
            ),
          ],
        ),
      ],
    );
  }

  GeneratedRoster _applyOffsets(
    GeneratedRoster roster, {
    required int dayOffset,
    required int weekOffset,
  }) {
    var pattern =
        roster.pattern.map((week) => List<String>.from(week)).toList();

    final normalizedDay = ((dayOffset % 7) + 7) % 7;
    if (normalizedDay != 0) {
      pattern = pattern.map((week) {
        final length = week.length;
        return List<String>.generate(
          length,
          (index) => week[(index - normalizedDay + length) % length],
        );
      }).toList();
    }

    final totalWeeks = pattern.length;
    if (totalWeeks > 0) {
      final normalizedWeek =
          ((weekOffset % totalWeeks) + totalWeeks) % totalWeeks;
      if (normalizedWeek != 0) {
        pattern = List<List<String>>.generate(
          totalWeeks,
          (index) => pattern[(index - normalizedWeek + totalWeeks) % totalWeeks],
        );
      }
    }

    return GeneratedRoster(
      pattern: pattern,
      warnings: roster.warnings,
    );
  }

  Widget _buildPreviewTable(List<String> labels, GeneratedRoster preview) {
    final maxRows = preview.pattern.length > 16 ? 16 : preview.pattern.length;
    final rows = preview.pattern.take(maxRows).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (preview.warnings.isNotEmpty)
          Text(
            'Warnings: ${preview.warnings.join(' | ')}',
            style: const TextStyle(color: Colors.red),
          ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: [
              const DataColumn(label: Text('Team')),
              ...labels.map((label) => DataColumn(label: Text(label))),
            ],
            rows: List.generate(rows.length, (index) {
              final dayRow = rows[index];
              return DataRow(
                cells: [
                  DataCell(Text('Team ${index + 1}')),
                  ...dayRow.map((shift) => DataCell(Text(shift))).toList(),
                ],
              );
            }),
          ),
        ),
      ],
    );
  }

  Widget _buildTemplateList(RosterNotifier roster) {
    if (roster.generatedRosters.isEmpty) {
      return const Text('No saved templates yet.');
    }
    return Column(
      children: roster.generatedRosters
          .map(
            (template) => Card(
              child: ListTile(
                title: Text(template.name),
                subtitle: Text(
                  'ID: ${template.id} • ${template.teamCount} teams',
                ),
                trailing: Wrap(
                  spacing: 8,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.play_arrow),
                      onPressed: () {
                        roster.applyGeneratedRosterTemplate(
                          template,
                          clearOverrides: _clearOverrides,
                          renameTeams: _renameTeams,
                        );
                        if (_propagateAfterApply) {
                          roster.propagatePattern();
                        }
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Template applied.')),
                        );
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () =>
                          roster.deleteGeneratedRosterTemplate(template.id),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () => _renameTemplate(context, roster, template),
                    ),
                  ],
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  Future<void> _renameTemplate(
    BuildContext context,
    RosterNotifier roster,
    models.GeneratedRosterTemplate template,
  ) async {
    final controller = TextEditingController(text: template.name);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename template'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Template name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final newName = controller.text.trim();
      if (newName.isNotEmpty) {
        roster.renameGeneratedRosterTemplate(template.id, newName);
      }
    }
  }
}

class _CoverTierRow {
  final TextEditingController codeController;
  final TextEditingController teamsController;

  _CoverTierRow({required String code, required String teams})
      : codeController = TextEditingController(text: code),
        teamsController = TextEditingController(text: teams);

  String get code => codeController.text;
  String get teams => teamsController.text;

  void dispose() {
    codeController.dispose();
    teamsController.dispose();
  }
}
