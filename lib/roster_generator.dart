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

GeneratedRoster scalePatternFromTemplate({
  required List<List<String>> basePattern,
  required int targetWeeks,
  int seed = 0,
}) {
  if (basePattern.isEmpty || targetWeeks < 1) {
    return const GeneratedRoster(pattern: [], warnings: ['Empty template']);
  }
  final baseWeeks = basePattern.length;
  final normalizedSeed = seed.abs() % baseWeeks;
  final pattern = List<List<String>>.generate(targetWeeks, (index) {
    final mapped = ((index * baseWeeks) / targetWeeks).round() % baseWeeks;
    final baseIndex = (mapped + normalizedSeed) % baseWeeks;
    return List<String>.from(basePattern[baseIndex]);
  });
  return GeneratedRoster(pattern: pattern);
}

HybridRosterConfig buildBaseHybridConfig({required int weekStartDay}) {
  final base = HybridRosterConfig.defaults();
  return HybridRosterConfig(
    teamCount: base.teamCount,
    weekStartDay: weekStartDay,
    earlyTeams: base.earlyTeams,
    lateGroupA: base.lateGroupA,
    lateGroupB: base.lateGroupB,
    nightWeekdayTeams: base.nightWeekdayTeams,
    fridayNightTeams: base.fridayNightTeams,
    weekendDayTeams: base.weekendDayTeams,
    weekendDaySunTeams: base.weekendDaySunTeams,
    weekendNightSatTeams: base.weekendNightSatTeams,
    weekendNightSunTeams: base.weekendNightSunTeams,
    coverTiers: base.coverTiers,
    generalCoverTeams: base.generalCoverTeams,
    generalCoverDays: base.generalCoverDays,
  );
}

HybridRosterConfig buildScaledHybridConfig({
  required int teamCount,
  required int staffCount,
  required int weekStartDay,
  int seed = 0,
}) {
  final base = HybridRosterConfig.defaults();
  final maxBase = base.teamCount;
  final effectiveStaff = staffCount < 1 ? 1 : staffCount;
  final effectiveTeams = teamCount < 1 ? 1 : teamCount;
  final normalizedSeed = seed.abs() % effectiveTeams;

  int scalePosition(int id) {
    if (effectiveTeams == 1) return 1;
    final scaled = (id - 1) * (effectiveTeams - 1) / (maxBase - 1);
    return scaled.round() + 1;
  }

  List<int> selectTeams(List<int> baseList) {
    if (baseList.isEmpty) return [];
    final targetCount =
        ((baseList.length * effectiveStaff) / maxBase).round().clamp(
              1,
              effectiveTeams,
            );
    final used = <int>{};
    final baseSeed = (baseList.first + normalizedSeed) % effectiveTeams;
    for (int i = 0; i < targetCount; i++) {
      final pos = ((i * effectiveTeams) / targetCount + baseSeed).round() %
          effectiveTeams;
      int candidate = pos + 1;
      int guard = 0;
      while (used.contains(candidate) && guard < effectiveTeams) {
        candidate = (candidate % effectiveTeams) + 1;
        guard++;
      }
      used.add(candidate);
    }
    final list = used.toList()..sort();
    return list;
  }

  final coverTiers = <int, String>{};
  for (final entry in base.coverTiers.entries) {
    var mappedId = scalePosition(entry.key);
    if (normalizedSeed > 0) {
      mappedId = ((mappedId - 1 + normalizedSeed) % effectiveTeams) + 1;
    }
    var guard = 0;
    while (coverTiers.containsKey(mappedId) && guard < effectiveTeams) {
      mappedId = (mappedId % effectiveTeams) + 1;
      guard++;
    }
    coverTiers[mappedId] = entry.value;
  }

  return HybridRosterConfig(
    teamCount: effectiveTeams,
    weekStartDay: weekStartDay,
    earlyTeams: selectTeams(base.earlyTeams),
    lateGroupA: selectTeams(base.lateGroupA),
    lateGroupB: selectTeams(base.lateGroupB),
    nightWeekdayTeams: selectTeams(base.nightWeekdayTeams),
    fridayNightTeams: selectTeams(base.fridayNightTeams),
    weekendDayTeams: selectTeams(base.weekendDayTeams),
    weekendDaySunTeams: selectTeams(base.weekendDaySunTeams),
    weekendNightSatTeams: selectTeams(base.weekendNightSatTeams),
    weekendNightSunTeams: selectTeams(base.weekendNightSunTeams),
    coverTiers: coverTiers,
    generalCoverTeams: selectTeams(base.generalCoverTeams),
    generalCoverDays: base.generalCoverDays,
  );
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
