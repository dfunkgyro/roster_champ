import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers.dart';
import '../models.dart' as models;
import 'package:roster_champ/safe_text_field.dart';

class PatternEditorScreen extends ConsumerStatefulWidget {
  const PatternEditorScreen({super.key});

  @override
  ConsumerState<PatternEditorScreen> createState() =>
      _PatternEditorScreenState();
}

class _PatternEditorScreenState extends ConsumerState<PatternEditorScreen> {
  final List<String> _shiftTypes = [
    'D',
    'D12',
    'N',
    'L',
    'OFF',
    'R',
    'E',
    'N12',
    'C',
    'C1',
    'C2',
    'C3',
    'C4'
  ];
  final Map<String, Color> _shiftColors = {
    'D': Colors.blue,
    'D12': Colors.blueAccent,
    'N': Colors.purple,
    'L': Colors.orange,
    'OFF': Colors.grey,
    'R': Colors.green,
    'E': Colors.lightBlue,
    'N12': Colors.deepPurple,
    'C': Colors.teal,
    'C1': Colors.teal[300]!,
    'C2': Colors.teal[400]!,
    'C3': Colors.teal[600]!,
    'C4': Colors.teal[800]!,
  };
  final TextEditingController _customShiftController = TextEditingController();

  @override
  void dispose() {
    _customShiftController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final roster = ref.watch(rosterProvider);
    final pattern = roster.masterPattern;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pattern Editor'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _addWeek,
            tooltip: 'Add Week',
          ),
          IconButton(
            icon: const Icon(Icons.remove),
            onPressed: _removeWeek,
            tooltip: 'Remove Week',
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'analyze':
                  _analyzePattern();
                  break;
                case 'propagation':
                  _showPropagationSettings();
                  break;
                case 'reset':
                  _resetPattern();
                  break;
                case 'custom':
                  _showCustomShiftDialog();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'analyze',
                child: ListTile(
                  leading: Icon(Icons.psychology),
                  title: Text('Analyze Pattern'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'propagation',
                child: ListTile(
                  leading: Icon(Icons.sync),
                  title: Text('Pattern Propagation'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'custom',
                child: ListTile(
                  leading: Icon(Icons.add_circle_outline),
                  title: Text('Add Custom Shift'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'reset',
                child: ListTile(
                  leading: Icon(Icons.restart_alt),
                  title: Text('Reset Pattern'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Shift legend
          _buildShiftLegend(),

          // Pattern grid
          Expanded(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    _buildWeekHeaders(),
                    const SizedBox(height: 8),
                    ...pattern
                        .asMap()
                        .entries
                        .map((entry) => _buildWeekRow(entry.key, entry.value)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _analyzePattern,
        icon: const Icon(Icons.psychology),
        label: const Text('AI Analysis'),
      ),
    );
  }

  Widget _buildShiftLegend() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Shift Legend',
            style: GoogleFonts.inter(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: _shiftTypes.map((shift) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: _shiftColors[shift]?.withOpacity(0.2) ??
                          Colors.grey.withOpacity(0.2),
                      border: Border.all(
                        color: _shiftColors[shift] ?? Colors.grey,
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Center(
                      child: Text(
                        shift,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: _shiftColors[shift] ?? Colors.grey,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _getShiftDescription(shift),
                    style: GoogleFonts.inter(fontSize: 12),
                  ),
                ],
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _showCustomShiftDialog,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add Custom Shift'),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeekHeaders() {
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(
            'Week',
            style: GoogleFonts.inter(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 8),
        ...['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'].map((day) {
          return Expanded(
            child: Text(
              day,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildWeekRow(int weekIndex, List<String> weekShifts) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              'Week ${weekIndex + 1}',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          ...weekShifts.asMap().entries.map((entry) {
            final dayIndex = entry.key;
            final shift = entry.value;
            final shiftColor = _shiftColors[shift] ?? Colors.grey;

            return Expanded(
              child: GestureDetector(
                onTap: () => _showShiftPicker(weekIndex, dayIndex, shift),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  height: 40,
                  decoration: BoxDecoration(
                    color: shiftColor.withOpacity(0.15),
                    border: Border.all(
                      color: shiftColor,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      shift,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: shiftColor,
                        fontSize: shift.length > 2 ? 10 : 12,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  String _getShiftDescription(String shift) {
    switch (shift) {
      case 'D':
        return 'Day Shift';
      case 'N':
        return 'Night Shift';
      case 'L':
        return 'Late Shift';
      case 'OFF':
        return 'Off Duty';
      case 'R':
        return 'Rest Day';
      case 'E':
        return 'Early Shift';
      case 'N12':
        return '12hr Night';
      case 'C':
        return 'Cover Shift';
      case 'C1':
        return 'Cover Level 1';
      case 'C2':
        return 'Cover Level 2';
      case 'C3':
        return 'Cover Level 3';
      case 'C4':
        return 'Cover Level 4';
      default:
        if (shift.startsWith('C')) return 'Cover $shift';
        return shift;
    }
  }

  void _showShiftPicker(int weekIndex, int dayIndex, String currentShift) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'Select Shift for Week ${weekIndex + 1}, ${_getDayName(dayIndex)}',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 1.5,
                ),
                itemCount: _shiftTypes.length,
                itemBuilder: (context, index) {
                  final shift = _shiftTypes[index];
                  final shiftColor = _shiftColors[shift] ?? Colors.grey;

                  return GestureDetector(
                    onTap: () {
                      ref
                          .read(rosterProvider)
                          .updateMasterPatternCell(weekIndex, dayIndex, shift);
                      Navigator.pop(context);
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: shiftColor.withOpacity(0.15),
                        border: Border.all(
                          color: shift == currentShift
                              ? shiftColor.withOpacity(0.8)
                              : shiftColor,
                          width: shift == currentShift ? 3 : 2,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            shift,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: shiftColor,
                              fontSize: shift.length > 2 ? 12 : 14,
                            ),
                          ),
                          Text(
                            _getShiftDescription(shift),
                            style: TextStyle(
                              fontSize: 8,
                              color: shiftColor,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _showCustomShiftPicker(weekIndex, dayIndex);
                },
                icon: const Icon(Icons.add),
                label: const Text('Custom Shift'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCustomShiftPicker(int weekIndex, int dayIndex) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Custom Shift'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SafeTextField(
              controller: _customShiftController,
              decoration: const InputDecoration(
                labelText: 'Shift Code',
                hintText: 'e.g., C5, C6, SPECIAL',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.characters,
            ),
            const SizedBox(height: 16),
            const Text(
              'Enter a custom shift code. It will be assigned a random color.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              _customShiftController.clear();
              Navigator.pop(context);
            },
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final customShift =
                  _customShiftController.text.trim().toUpperCase();
              if (customShift.isNotEmpty) {
                // Add to shift types if not already present
                if (!_shiftTypes.contains(customShift)) {
                  setState(() {
                    _shiftTypes.add(customShift);
                    // Generate a random color for the new shift
                    _shiftColors[customShift] = _generateRandomColor();
                  });
                }
                ref
                    .read(rosterProvider)
                    .updateMasterPatternCell(weekIndex, dayIndex, customShift);
                _customShiftController.clear();
                Navigator.pop(context);
              }
            },
            child: const Text('Add Shift'),
          ),
        ],
      ),
    );
  }

  Color _generateRandomColor() {
    final colors = [
      Colors.red,
      Colors.pink,
      Colors.purple,
      Colors.deepPurple,
      Colors.indigo,
      Colors.blue,
      Colors.lightBlue,
      Colors.cyan,
      Colors.teal,
      Colors.green,
      Colors.lightGreen,
      Colors.lime,
      Colors.yellow,
      Colors.amber,
      Colors.orange,
      Colors.deepOrange,
      Colors.brown,
      Colors.blueGrey,
    ];
    return colors[_shiftTypes.length % colors.length];
  }

  String _getDayName(int dayIndex) {
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday'
    ];
    return days[dayIndex];
  }

  void _addWeek() {
    final roster = ref.read(rosterProvider);
    final newWeek = List<String>.filled(7, 'D');
    roster.masterPattern.add(newWeek);
    roster.cycleLength = roster.masterPattern.length;
    roster.notifyListeners();
  }

  void _removeWeek() {
    final roster = ref.read(rosterProvider);
    if (roster.masterPattern.length > 1) {
      roster.masterPattern.removeLast();
      roster.cycleLength = roster.masterPattern.length;
      roster.notifyListeners();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot remove the last week')),
      );
    }
  }

  void _analyzePattern() async {
    try {
      final result =
          await ref.read(rosterProvider).analyzeAndRecognizePattern();
      _showAnalysisResult(result);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Analysis failed: $e')),
      );
    }
  }

  void _showAnalysisResult(models.PatternRecognitionResult result) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pattern Analysis'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Detected ${result.detectedCycleLength}-week cycle',
                style: GoogleFonts.inter(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                  'Confidence: ${(result.confidence * 100).toStringAsFixed(1)}%'),
              const SizedBox(height: 16),
              const Text(
                'Shift Frequency:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              ...result.shiftFrequency.entries.map((entry) {
                return Text('${entry.key}: ${entry.value} shifts');
              }),
              const SizedBox(height: 16),
              const Text(
                'Suggestions:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              ...result.suggestions.map((suggestion) {
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('• $suggestion'),
                );
              }),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: () {
              ref.read(rosterProvider).applyRecognizedPattern(result);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Pattern applied successfully')),
              );
            },
            child: const Text('Apply Pattern'),
          ),
        ],
      ),
    );
  }

  void _showPropagationSettings() {
    final roster = ref.read(rosterProvider);
    final settings = roster.propagationSettings ??
        models.PatternPropagationSettings(
          isActive: false,
          weekShift: 0,
          dayShift: 0,
        );

    showDialog(
      context: context,
      builder: (context) => PatternPropagationDialog(
        initialSettings: settings,
        onSave: (isActive, weekShift, dayShift) {
          roster.updatePropagationSettings(
            isActive: isActive,
            weekShift: weekShift,
            dayShift: dayShift,
          );
        },
      ),
    );
  }

  void _showCustomShiftDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Custom Shift Type'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SafeTextField(
              controller: _customShiftController,
              decoration: const InputDecoration(
                labelText: 'Shift Code',
                hintText: 'e.g., C5, C6, SPECIAL, TRAINING',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.characters,
            ),
            const SizedBox(height: 16),
            const Text(
              'Add a new shift type that will be available in the pattern editor.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              _customShiftController.clear();
              Navigator.pop(context);
            },
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final customShift =
                  _customShiftController.text.trim().toUpperCase();
              if (customShift.isNotEmpty &&
                  !_shiftTypes.contains(customShift)) {
                setState(() {
                  _shiftTypes.add(customShift);
                  _shiftColors[customShift] = _generateRandomColor();
                });
                _customShiftController.clear();
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Added shift type: $customShift')),
                );
              } else if (_shiftTypes.contains(customShift)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content:
                          Text('Shift type "$customShift" already exists')),
                );
              }
            },
            child: const Text('Add Shift Type'),
          ),
        ],
      ),
    );
  }

  void _resetPattern() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset Pattern?'),
        content: const Text(
            'This will reset all shifts to default (Day shifts). This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final roster = ref.read(rosterProvider);
              roster.masterPattern = List.generate(
                roster.cycleLength,
                (week) => List.filled(7, 'D'),
              );
              roster.notifyListeners();
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Pattern reset successfully')),
              );
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
  }
}

class PatternPropagationDialog extends StatefulWidget {
  final models.PatternPropagationSettings initialSettings;
  final Function(bool isActive, int weekShift, int dayShift) onSave;

  const PatternPropagationDialog({
    super.key,
    required this.initialSettings,
    required this.onSave,
  });

  @override
  State<PatternPropagationDialog> createState() =>
      _PatternPropagationDialogState();
}

class _PatternPropagationDialogState extends State<PatternPropagationDialog> {
  late bool _isActive;
  late int _weekShift;
  late int _dayShift;

  @override
  void initState() {
    super.initState();
    _isActive = widget.initialSettings.isActive;
    _weekShift = widget.initialSettings.weekShift;
    _dayShift = widget.initialSettings.dayShift;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Pattern Propagation'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            title: const Text('Enable Pattern Propagation'),
            subtitle:
                const Text('Automatically propagate pattern with offsets'),
            value: _isActive,
            onChanged: (value) => setState(() => _isActive = value),
          ),
          const SizedBox(height: 16),

          // Week Offset with negative and positive range
          Text(
            'Week Offset: $_weekShift weeks',
            style: GoogleFonts.inter(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.remove),
                onPressed:
                    _isActive ? () => _updateWeekShift(_weekShift - 1) : null,
                tooltip: 'Decrease week offset',
              ),
              Expanded(
                child: Slider(
                  value: _weekShift.toDouble(),
                  min: -52,
                  max: 52,
                  divisions: 104,
                  label: '$_weekShift weeks',
                  onChanged: _isActive
                      ? (value) => _updateWeekShift(value.toInt())
                      : null,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add),
                onPressed:
                    _isActive ? () => _updateWeekShift(_weekShift + 1) : null,
                tooltip: 'Increase week offset',
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('-52',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                Text('0',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                Text('+52',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Day Offset with negative and positive range
          Text(
            'Day Offset: $_dayShift days',
            style: GoogleFonts.inter(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.remove),
                onPressed:
                    _isActive ? () => _updateDayShift(_dayShift - 1) : null,
                tooltip: 'Decrease day offset',
              ),
              Expanded(
                child: Slider(
                  value: _dayShift.toDouble(),
                  min: -7,
                  max: 7,
                  divisions: 14,
                  label: '$_dayShift days',
                  onChanged: _isActive
                      ? (value) => _updateDayShift(value.toInt())
                      : null,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add),
                onPressed:
                    _isActive ? () => _updateDayShift(_dayShift + 1) : null,
                tooltip: 'Increase day offset',
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('-7',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                Text('0',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                Text('+7',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              ],
            ),
          ),

          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'How Pattern Propagation Works:',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: Colors.blue[800],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '• Week Offset: Moves the pattern forward (+) or backward (-) by weeks\n'
                  '• Day Offset: Moves the pattern forward (+) or backward (-) by days\n'
                  '• Each staff member gets a unique offset based on their position\n'
                  '• Negative values shift the pattern earlier in time\n'
                  '• Positive values shift the pattern later in time',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    color: Colors.blue[700],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            widget.onSave(_isActive, _weekShift, _dayShift);
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  _isActive
                      ? 'Pattern propagation enabled (Week: $_weekShift, Day: $_dayShift)'
                      : 'Pattern propagation disabled',
                ),
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }

  void _updateWeekShift(int newValue) {
    setState(() {
      _weekShift = newValue.clamp(-52, 52);
    });
  }

  void _updateDayShift(int newValue) {
    setState(() {
      _dayShift = newValue.clamp(-7, 7);
    });
  }
}