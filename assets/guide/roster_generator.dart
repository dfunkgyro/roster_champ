class HybridRosterConfig {
  final int teamCount;
  final int weekStartDay; // 0 = Sunday ... 6 = Saturday
  final List<int> earlyTeams;
  final List<int> lateGroupA;
  final List<int> lateGroupB;
  final List<int> nightWeekdayTeams;
  final List<int> fridayNightTeams;
  final List<int> weekendDayTeams;
  final List<int> weekendDaySunTeams;
  final List<int> weekendNightSatTeams;
  final List<int> weekendNightSunTeams;
  final Map<int, String> coverTiers;
  final List<int> generalCoverTeams;
  final List<int> generalCoverDays; // Sunday-based indices (0 = Sun)

  const HybridRosterConfig({
    required this.teamCount,
    required this.weekStartDay,
    required this.earlyTeams,
    required this.lateGroupA,
    required this.lateGroupB,
    required this.nightWeekdayTeams,
    required this.fridayNightTeams,
    required this.weekendDayTeams,
    required this.weekendDaySunTeams,
    required this.weekendNightSatTeams,
    required this.weekendNightSunTeams,
    required this.coverTiers,
    required this.generalCoverTeams,
    required this.generalCoverDays,
  });

  factory HybridRosterConfig.defaults() {
    return const HybridRosterConfig(
      teamCount: 16,
      weekStartDay: 0,
      earlyTeams: [7, 15],
      lateGroupA: [2, 9],
      lateGroupB: [6, 14],
      nightWeekdayTeams: [3, 10],
      fridayNightTeams: [2, 9],
      weekendDayTeams: [1, 8],
      weekendDaySunTeams: [2, 9],
      weekendNightSatTeams: [2, 9],
      weekendNightSunTeams: [3, 10],
      coverTiers: {
        5: 'C1',
        13: 'C2',
        16: 'C3',
        11: 'C4',
      },
      generalCoverTeams: [1, 8, 14],
      generalCoverDays: [1, 2, 3, 4], // Mon-Thu
    );
  }
}

class GeneratedRoster {
  final List<List<String>> pattern;
  final List<String> warnings;

  const GeneratedRoster({
    required this.pattern,
    this.warnings = const [],
  });
}

class HybridRosterGenerator {
  static const String restShift = 'R';

  static GeneratedRoster generate(HybridRosterConfig config) {
    final warnings = <String>[];
    final pattern = List.generate(
      config.teamCount,
      (_) => List.generate(7, (_) => restShift),
    );

    void setShift(int teamId, int dayIndex, String shift) {
      if (teamId < 1 || teamId > config.teamCount) {
        warnings.add('Team $teamId is outside the team count.');
        return;
      }
      if (dayIndex < 0 || dayIndex > 6) return;
      pattern[teamId - 1][dayIndex] = shift;
    }

    int mapDay(int sundayIndex) {
      final shift = (sundayIndex - config.weekStartDay + 7) % 7;
      return shift;
    }

    final mon = mapDay(1);
    final tue = mapDay(2);
    final wed = mapDay(3);
    final thu = mapDay(4);
    final fri = mapDay(5);
    final sat = mapDay(6);
    final sun = mapDay(0);

    for (final entry in config.coverTiers.entries) {
      for (final day in [mon, tue, wed, thu, fri]) {
        setShift(entry.key, day, entry.value);
      }
    }

    for (final team in config.generalCoverTeams) {
      for (final day in config.generalCoverDays) {
        setShift(team, mapDay(day), 'C');
      }
    }

    for (final team in config.earlyTeams) {
      for (final day in [mon, tue, wed, thu, fri]) {
        setShift(team, day, 'E');
      }
    }

    for (final team in config.lateGroupA) {
      setShift(team, mon, 'L');
      setShift(team, tue, 'L');
    }

    for (final team in config.lateGroupB) {
      setShift(team, wed, 'L');
      setShift(team, thu, 'L');
      setShift(team, fri, 'L');
    }

    for (final team in config.nightWeekdayTeams) {
      for (final day in [mon, tue, wed, thu]) {
        setShift(team, day, 'N');
      }
    }

    for (final team in config.fridayNightTeams) {
      setShift(team, fri, 'N');
    }

    for (final team in config.weekendDayTeams) {
      setShift(team, sat, 'D');
    }

    for (final team in config.weekendDaySunTeams) {
      setShift(team, sun, 'D');
    }

    for (final team in config.weekendNightSatTeams) {
      setShift(team, sat, 'N12');
    }

    for (final team in config.weekendNightSunTeams) {
      setShift(team, sun, 'N12');
    }

    return GeneratedRoster(pattern: pattern, warnings: warnings);
  }
}
