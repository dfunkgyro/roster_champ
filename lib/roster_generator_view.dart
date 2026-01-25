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
  bool _quickMode = true;
  bool _showComparison = false;
  int _variationSeed = 0;
  bool _editingPreview = true;

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
  late final TextEditingController _staffCountController;
  late final TextEditingController _rotationWeeksController;

  int _weekStartDay = 0;
  final Set<int> _generalCoverDays = {1, 2, 3, 4};
  bool _renameTeams = false;
  bool _clearOverrides = true;
  bool _propagateAfterApply = true;
  bool _preserveStaffNames = true;
  bool _customNightSplit = false;
  int _weekdayNightCount = 4;
  int _weekendNightCount = 3;
  GeneratedRoster? _preview;
  int _dayOffset = 0;
  int _weekOffset = 0;
  bool _useSavedNames = false;
  final List<_CoverTierRow> _coverTiers = [];
  final TextEditingController _templateNameController =
      TextEditingController(text: 'Hybrid Template');
  final TextEditingController _presetNameController =
      TextEditingController(text: 'Variation A');

  @override
  void initState() {
    super.initState();
    _defaults = HybridRosterConfig.defaults();
    final roster = ref.read(rosterProvider);
    _weekStartDay = roster.weekStartDay;
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
      text: _formatList(_defaults.weekendNightSatTeams),
    );
    _weekendNightSunController = TextEditingController(
      text: _formatList(_defaults.weekendNightSunTeams),
    );
    _coverTiers.addAll([
      _CoverTierRow(code: 'C1', teams: _formatList([5])),
      _CoverTierRow(code: 'C2', teams: _formatList([13])),
      _CoverTierRow(code: 'C3', teams: _formatList([16])),
      _CoverTierRow(code: 'C4', teams: _formatList([11])),
    ]);
    _generalCoverController = TextEditingController(
      text: _formatList(_defaults.generalCoverTeams),
    );
    _staffCountController =
        TextEditingController(text: roster.numPeople.toString());
    _rotationWeeksController =
        TextEditingController(text: roster.cycleLength.toString());
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
    _presetNameController.dispose();
    _generalCoverController.dispose();
    _staffCountController.dispose();
    _rotationWeeksController.dispose();
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
    final roster = ref.read(rosterProvider);
    final preview = _applyOffsets(
      _quickMode
          ? _generateQuick(roster)
          : roster.generateHybridRoster(_buildConfig()),
      dayOffset: _dayOffset,
      weekOffset: _weekOffset,
    );
    setState(() => _preview = preview);
  }

  Future<void> _applyRoster() async {
    final roster = ref.read(rosterProvider);
    final staffCount =
        int.tryParse(_staffCountController.text.trim()) ?? roster.numPeople;

    final generated = _applyOffsets(
      _quickMode
          ? _generateQuick(roster)
          : roster.generateHybridRoster(_buildConfig()),
      dayOffset: _dayOffset,
      weekOffset: _weekOffset,
    );

    roster.setWeekStartDay(_weekStartDay);
    if (_preserveStaffNames) {
      roster.applyGeneratedRosterPatternOnly(
        generated,
        clearOverrides: _clearOverrides,
      );
    } else {
      final teamCount = _quickMode
          ? staffCount
          : int.tryParse(_teamCountController.text.trim()) ?? roster.numPeople;
      roster.applyGeneratedRoster(
        generated,
        teamCount: teamCount,
        clearOverrides: _clearOverrides,
        renameTeams: _renameTeams,
      );
    }
    if (_propagateAfterApply) {
      roster.propagatePattern();
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _preserveStaffNames
              ? 'Pattern applied to current roster.'
              : 'Auto roster generated.',
        ),
      ),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final roster = ref.watch(rosterProvider);
    final labels = roster.weekDayLabels;
    final quickMaxTeams =
        int.tryParse(_rotationWeeksController.text.trim()) ?? 16;
    final maxNightTeams = quickMaxTeams < 1 ? 1 : quickMaxTeams;

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
          SwitchListTile(
            title: const Text('Quick mode'),
            subtitle: const Text('Generate from staffing and rotation only'),
            value: _quickMode,
            onChanged: (value) => setState(() => _quickMode = value),
          ),
          if (_quickMode) ...[
            _buildNumberField('Staff count', _staffCountController),
            const SizedBox(height: 12),
            _buildNumberField(
              'Rotation length (weeks)',
              _rotationWeeksController,
            ),
            const SizedBox(height: 12),
            _buildWeekStartDropdown(labels),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Customize night split'),
              subtitle: const Text(
                'Choose how many teams work weekday vs weekend nights',
              ),
              value: _customNightSplit,
              onChanged: (value) => setState(() => _customNightSplit = value),
            ),
            if (_customNightSplit) ...[
              Text(
                'Weekday night teams (Mon-Thu): $_weekdayNightCount',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Slider(
                value: _weekdayNightCount
                    .clamp(0, maxNightTeams)
                    .toDouble(),
                min: 0,
                max: maxNightTeams.toDouble(),
                divisions: maxNightTeams,
                label: _weekdayNightCount.toString(),
                onChanged: (value) {
                  setState(() => _weekdayNightCount = value.round());
                },
              ),
              const SizedBox(height: 8),
              Text(
                'Weekend night teams (Fri-Sun): $_weekendNightCount',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Slider(
                value: _weekendNightCount
                    .clamp(0, maxNightTeams)
                    .toDouble(),
                min: 0,
                max: maxNightTeams.toDouble(),
                divisions: maxNightTeams,
                label: _weekendNightCount.toString(),
                onChanged: (value) {
                  setState(() => _weekendNightCount = value.round());
                },
              ),
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: _weekdayNightCount.toDouble(),
                      min: 0,
                      max: 16,
                      divisions: 16,
                      label: _weekdayNightCount.toString(),
                      onChanged: (value) {
                        setState(() => _weekdayNightCount = value.round());
                      },
                    ),
                  ),
                  Expanded(
                    child: Slider(
                      value: _weekendNightCount.toDouble(),
                      min: 0,
                      max: 16,
                      divisions: 16,
                      label: _weekendNightCount.toString(),
                      onChanged: (value) {
                        setState(() => _weekendNightCount = value.round());
                      },
                    ),
                  ),
                ],
              ),
            ],
            SwitchListTile(
              title: const Text('Show comparison preview'),
              subtitle: const Text('Compare to base 16x16 template'),
              value: _showComparison,
              onChanged: (value) => setState(() => _showComparison = value),
            ),
            SwitchListTile(
              title: const Text('Allow preview edits'),
              subtitle: const Text('Tap a cell to adjust shifts'),
              value: _editingPreview,
              onChanged: (value) => setState(() => _editingPreview = value),
            ),
            _buildSeedControl(),
            const SizedBox(height: 12),
          ],
          if (!_quickMode) ...[
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
            'Weekend night teams (Sat)',
            _weekendNightSatController,
          ),
          _buildTextField(
            'Weekend night teams (Sun)',
            _weekendNightSunController,
          ),
          const SizedBox(height: 16),
          _buildSectionTitle('Cover tiers (optional)'),
          _buildCoverTierList(),
          _buildTextField('General cover teams (C)', _generalCoverController),
          const SizedBox(height: 8),
          _buildGeneralCoverDays(labels),
          const SizedBox(height: 16),
          ],
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
              final roster = ref.read(rosterProvider);
              final generated = _applyOffsets(
                _quickMode
                    ? _generateQuick(roster)
                    : roster.generateHybridRoster(_buildConfig()),
                dayOffset: _dayOffset,
                weekOffset: _weekOffset,
              );
              roster.saveGeneratedRosterTemplate(
                name: name,
                generated: generated,
                teamCount: _quickMode
                    ? int.tryParse(_staffCountController.text.trim()) ??
                        roster.numPeople
                    : _buildConfig().teamCount,
                weekStart: _weekStartDay,
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
            title: const Text('Preserve staff names'),
            subtitle: const Text(
              'Apply pattern changes without altering the current staff list',
            ),
            value: _preserveStaffNames,
            onChanged: (value) {
              setState(() {
                _preserveStaffNames = value;
                if (_preserveStaffNames) {
                  _renameTeams = false;
                }
              });
            },
          ),
          SwitchListTile(
            title: const Text('Rename staff to Team 1..N'),
            value: _renameTeams,
            onChanged: _preserveStaffNames
                ? null
                : (value) => setState(() => _renameTeams = value),
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
          if (_preview != null)
            _showComparison && _quickMode
                ? _buildComparisonPreview(labels)
                : _buildPreviewTable(labels, _preview!),
          if (_quickMode && _preview != null) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () {
                final roster = ref.read(rosterProvider);
                final name = _templateNameController.text.trim().isEmpty
                    ? 'Quick Base Template'
                    : _templateNameController.text.trim();
                roster.setQuickBaseTemplate(
                  name: name,
                  generated: _preview!,
                  weekStart: _weekStartDay,
                );
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Quick template saved.')),
                );
              },
              icon: const Icon(Icons.bookmark_add),
              label: const Text('Set as Quick Base Template'),
            ),
            TextButton(
              onPressed: () {
                ref.read(rosterProvider).clearQuickBaseTemplate();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Quick template cleared.')),
                );
              },
              child: const Text('Clear Quick Base Template'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _presetNameController,
              decoration: const InputDecoration(
                labelText: 'Preset name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () {
                final roster = ref.read(rosterProvider);
                final name = _presetNameController.text.trim();
                if (name.isEmpty) return;
                roster.saveQuickVariationPreset(
                  name: name,
                  generated: _preview!,
                  weekStart: _weekStartDay,
                );
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Preset saved.')),
                );
              },
              icon: const Icon(Icons.save_alt),
              label: const Text('Save Variation Preset'),
            ),
            const SizedBox(height: 8),
            _buildQuickPresetList(ref.read(rosterProvider)),
          ],
        ],
      ),
    );
  }

  GeneratedRoster _generateQuick(RosterNotifier roster) {
    final rotationWeeks =
        int.tryParse(_rotationWeeksController.text.trim()) ??
            roster.cycleLength;
    final staffCount =
        int.tryParse(_staffCountController.text.trim()) ?? roster.numPeople;
    if (!_customNightSplit) {
      return roster.generateQuickRoster(
        rotationWeeks: rotationWeeks,
        staffCount: staffCount,
        weekStart: _weekStartDay,
        seed: _variationSeed,
      );
    }
    final baseConfig = buildScaledHybridConfig(
      teamCount: rotationWeeks,
      staffCount: staffCount,
      weekStartDay: _weekStartDay,
      seed: _variationSeed,
    );
    final weekdayNights = _selectTeamsByCount(
      _weekdayNightCount,
      baseConfig.teamCount,
      seed: _variationSeed,
    );
    final weekendNights = _selectTeamsByCount(
      _weekendNightCount,
      baseConfig.teamCount,
      seed: _variationSeed + 3,
    );
    final customConfig = HybridRosterConfig(
      teamCount: baseConfig.teamCount,
      weekStartDay: baseConfig.weekStartDay,
      earlyTeams: baseConfig.earlyTeams,
      lateGroupA: baseConfig.lateGroupA,
      lateGroupB: baseConfig.lateGroupB,
      nightWeekdayTeams: weekdayNights,
      fridayNightTeams: weekendNights,
      weekendDayTeams: baseConfig.weekendDayTeams,
      weekendDaySunTeams: baseConfig.weekendDaySunTeams,
      weekendNightSatTeams: weekendNights,
      weekendNightSunTeams: weekendNights,
      coverTiers: baseConfig.coverTiers,
      generalCoverTeams: baseConfig.generalCoverTeams,
      generalCoverDays: baseConfig.generalCoverDays,
    );
    final generated = HybridRosterGenerator.generate(customConfig);
    final adjusted = _applySplitNightRules(
      generated,
      weekendTeams: weekendNights,
      weekStartDay: _weekStartDay,
    );
    return adjusted;
  }

  List<int> _selectTeamsByCount(int count, int totalTeams, {int seed = 0}) {
    final safeTotal = totalTeams < 1 ? 1 : totalTeams;
    final target = count.clamp(0, safeTotal);
    if (target == 0) return [];
    if (target == safeTotal) {
      return List.generate(safeTotal, (index) => index + 1);
    }
    final used = <int>{};
    final start = seed.abs() % safeTotal;
    for (int i = 0; i < target; i++) {
      final pos = ((i * safeTotal) / target).round();
      int candidate = ((pos + start) % safeTotal) + 1;
      int guard = 0;
      while (used.contains(candidate) && guard < safeTotal) {
        candidate = (candidate % safeTotal) + 1;
        guard++;
      }
      used.add(candidate);
    }
    final list = used.toList()..sort();
    return list;
  }

  GeneratedRoster _shiftSundayNightsForward(GeneratedRoster input) {
    if (input.pattern.isEmpty) return input;
    final weeks = input.pattern.length;
    final pattern =
        input.pattern.map((week) => List<String>.from(week)).toList();
    final originalSundayNights = <int>[];
    for (int w = 0; w < weeks; w++) {
      if (pattern[w][0] == 'N12') {
        originalSundayNights.add(w);
        pattern[w][0] = 'R';
      }
    }
    for (final w in originalSundayNights) {
      final next = (w + 1) % weeks;
      pattern[next][0] = 'N12';
    }
    return GeneratedRoster(pattern: pattern, warnings: input.warnings);
  }

  GeneratedRoster _applySplitNightRules(
    GeneratedRoster input, {
    required List<int> weekendTeams,
    required int weekStartDay,
  }) {
    if (input.pattern.isEmpty || weekendTeams.isEmpty) return input;
    final weeks = input.pattern.length;
    final pattern =
        input.pattern.map((week) => List<String>.from(week)).toList();

    int mapDay(int sundayIndex) {
      return (sundayIndex - weekStartDay + 7) % 7;
    }

    final mon = mapDay(1);
    final tue = mapDay(2);
    final wed = mapDay(3);
    final thu = mapDay(4);
    final fri = mapDay(5);
    final sat = mapDay(6);
    final sun = mapDay(0);
    final restDays = [mon, tue, wed, thu];

    for (final teamId in weekendTeams) {
      final index = teamId - 1;
      if (index < 0 || index >= weeks) continue;
      if (weekStartDay == 0) {
        // Sunday belongs to the end of the previous week in this view.
        pattern[index][sun] = 'R';
        for (final day in restDays) {
          pattern[index][day] = 'R';
        }
        pattern[index][fri] = 'N12';
        pattern[index][sat] = 'N12';
        final sunWeek = (index + 1) % weeks;
        pattern[sunWeek][sun] = 'N12';
        for (final day in restDays) {
          pattern[sunWeek][day] = 'R';
        }
        pattern[sunWeek][fri] = 'D12';
        pattern[sunWeek][sat] = 'D12';
        final nextSunWeek = (index + 2) % weeks;
        pattern[nextSunWeek][sun] = 'D12';
      } else {
        for (final day in restDays) {
          pattern[index][day] = 'R';
        }
        for (final day in [fri, sat, sun]) {
          pattern[index][day] = 'N12';
        }
        final nextWeek = (index + 1) % weeks;
        for (final day in restDays) {
          pattern[nextWeek][day] = 'R';
        }
        for (final day in [fri, sat, sun]) {
          pattern[nextWeek][day] = 'D12';
        }
      }
    }

    return GeneratedRoster(pattern: pattern, warnings: input.warnings);
  }

  GeneratedRoster _generateBaseTemplate() {
    final config = buildBaseHybridConfig(weekStartDay: _weekStartDay);
    return HybridRosterGenerator.generate(config);
  }

  Widget _buildSeedControl() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Variation seed: $_variationSeed'),
        Row(
          children: [
            Expanded(
              child: Slider(
                value: _variationSeed.toDouble(),
                min: 0,
                max: 20,
                divisions: 20,
                label: _variationSeed.toString(),
                onChanged: (value) {
                  setState(() => _variationSeed = value.round());
                  if (_preview != null) {
                    _generatePreview();
                  }
                },
              ),
            ),
            IconButton(
              tooltip: 'Shuffle',
              icon: const Icon(Icons.casino),
              onPressed: () {
                setState(() => _variationSeed = (_variationSeed + 1) % 21);
                if (_preview != null) {
                  _generatePreview();
                }
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildComparisonPreview(List<String> labels) {
    final base = _applyOffsets(
      _generateBaseTemplate(),
      dayOffset: _dayOffset,
      weekOffset: _weekOffset,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Scaled preview',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        _buildPreviewTable(labels, _preview!),
        const SizedBox(height: 16),
        const Text(
          'Base 16x16 template preview',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        _buildPreviewTable(labels, base),
      ],
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
          onChanged: (value) => setState(() => _weekStartDay = value ?? 0),
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
                  onPressed: () => setState(() => _coverTiers.remove(tier)),
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
          (index) =>
              pattern[(index - normalizedWeek + totalWeeks) % totalWeeks],
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
                  ...dayRow.asMap().entries.map((entry) {
                    final dayIndex = entry.key;
                    final shift = entry.value;
                    return DataCell(
                      Text(shift),
                      onTap: _editingPreview
                          ? () => _editPreviewCell(index, dayIndex)
                          : null,
                    );
                  }).toList(),
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
                  'ID: ${template.id} - ${template.teamCount} teams',
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
                      onPressed: () =>
                          _renameTemplate(context, roster, template),
                    ),
                  ],
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildQuickPresetList(RosterNotifier roster) {
    if (roster.quickVariationPresets.isEmpty) {
      return const Text('No saved variations yet.');
    }
    return Column(
      children: roster.quickVariationPresets
          .map(
            (preset) => Card(
              child: ListTile(
                title: Text(preset.name),
                subtitle: Text('Weeks: ${preset.pattern.length}'),
                trailing: Wrap(
                  spacing: 8,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.visibility),
                      onPressed: () {
                        setState(() {
                          _preview = GeneratedRoster(
                            pattern: preset.pattern
                                .map((week) => List<String>.from(week))
                                .toList(),
                          );
                          _rotationWeeksController.text =
                              preset.pattern.length.toString();
                        });
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.bookmark_add),
                      onPressed: () {
                        ref.read(rosterProvider).setQuickBaseTemplate(
                              name: preset.name,
                              generated: GeneratedRoster(
                                pattern: preset.pattern
                                    .map((week) => List<String>.from(week))
                                    .toList(),
                              ),
                              weekStart: preset.weekStartDay,
                            );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Quick template updated.')),
                        );
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => ref
                          .read(rosterProvider)
                          .deleteQuickVariationPreset(preset.id),
                    ),
                  ],
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  Future<void> _editPreviewCell(int rowIndex, int dayIndex) async {
    if (_preview == null) return;
    final controller = TextEditingController(
      text: _preview!.pattern[rowIndex][dayIndex],
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Shift'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Shift code',
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
      final value = controller.text.trim();
      if (value.isEmpty) return;
      setState(() {
        final updated = _preview!.pattern
            .map((week) => List<String>.from(week))
            .toList();
        updated[rowIndex][dayIndex] = value;
        _preview = GeneratedRoster(
          pattern: updated,
          warnings: _preview!.warnings,
        );
      });
    }
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
