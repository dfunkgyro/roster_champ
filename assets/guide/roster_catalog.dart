import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';
import 'supabase_service.dart';

final rosterCatalogProvider =
    StateNotifierProvider<RosterCatalogController, RosterCatalogState>((ref) {
  return RosterCatalogController();
});

class RosterMeta {
  final String id;
  final String ownerId;
  final String companyName;
  final String departmentName;
  final String teamName;
  final String role;
  final String source;
  final DateTime createdAt;
  final DateTime updatedAt;

  const RosterMeta({
    required this.id,
    required this.ownerId,
    required this.companyName,
    required this.departmentName,
    required this.teamName,
    required this.role,
    required this.source,
    required this.createdAt,
    required this.updatedAt,
  });

  String get displayName {
    if (teamName.isNotEmpty) {
      return '$companyName / $departmentName / $teamName';
    }
    return '$companyName / $departmentName';
  }

  RosterMeta copyWith({
    String? companyName,
    String? departmentName,
    String? teamName,
    String? role,
    String? source,
    DateTime? updatedAt,
  }) {
    return RosterMeta(
      id: id,
      ownerId: ownerId,
      companyName: companyName ?? this.companyName,
      departmentName: departmentName ?? this.departmentName,
      teamName: teamName ?? this.teamName,
      role: role ?? this.role,
      source: source ?? this.source,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'ownerId': ownerId,
        'companyName': companyName,
        'departmentName': departmentName,
        'teamName': teamName,
        'role': role,
        'source': source,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory RosterMeta.fromJson(Map<String, dynamic> json) => RosterMeta(
        id: json['id'] as String,
        ownerId: json['ownerId'] as String,
        companyName: json['companyName'] as String? ?? '',
        departmentName: json['departmentName'] as String? ?? '',
        teamName: json['teamName'] as String? ?? '',
        role: json['role'] as String? ?? 'admin',
        source: json['source'] as String? ?? 'local',
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
      );
}

class RosterCatalogState {
  final List<RosterMeta> rosters;
  final String? activeRosterId;
  final bool isLoading;
  final bool hasLoaded;
  final String? ownerId;

  const RosterCatalogState({
    this.rosters = const [],
    this.activeRosterId,
    this.isLoading = false,
    this.hasLoaded = false,
    this.ownerId,
  });

  RosterMeta? get activeRoster {
    for (final roster in rosters) {
      if (roster.id == activeRosterId) {
        return roster;
      }
    }
    if (rosters.isNotEmpty) {
      return rosters.first;
    }
    return null;
  }

  RosterCatalogState copyWith({
    List<RosterMeta>? rosters,
    String? activeRosterId,
    bool? isLoading,
    bool? hasLoaded,
    String? ownerId,
  }) {
    return RosterCatalogState(
      rosters: rosters ?? this.rosters,
      activeRosterId: activeRosterId ?? this.activeRosterId,
      isLoading: isLoading ?? this.isLoading,
      hasLoaded: hasLoaded ?? this.hasLoaded,
      ownerId: ownerId ?? this.ownerId,
    );
  }
}

class RosterCatalogController extends StateNotifier<RosterCatalogState> {
  RosterCatalogController() : super(const RosterCatalogState());

  String? _ownerId;

  Future<void> loadCatalog(String ownerId, {required bool isGuest}) async {
    if (_ownerId == ownerId && state.rosters.isNotEmpty) return;
    _ownerId = ownerId;
    state = state.copyWith(isLoading: true);

    final rosterList = <RosterMeta>[];
    String? activeRosterId;

    if (isGuest) {
      final prefs = await SharedPreferences.getInstance();
      final catalogJson = prefs.getString(_catalogKey(ownerId));
      if (catalogJson != null && catalogJson.isNotEmpty) {
        final decoded = json.decode(catalogJson) as List<dynamic>;
        rosterList.addAll(decoded
            .map((item) => RosterMeta.fromJson(item as Map<String, dynamic>)));
      }
      activeRosterId = prefs.getString(_activeKey(ownerId));
    } else {
      try {
        final api = SupabaseRosterApi();
        final cloudRosters = await api.fetchRosters();
        for (final roster in cloudRosters) {
          rosterList.add(RosterMeta(
            id: roster.id,
            ownerId: ownerId,
            companyName: roster.companyName,
            departmentName: roster.departmentName,
            teamName: roster.teamName,
            role: roster.role,
            source: 'cloud',
            createdAt: roster.createdAt,
            updatedAt: roster.updatedAt,
          ));
        }
      } catch (_) {
        final prefs = await SharedPreferences.getInstance();
        final catalogJson = prefs.getString(_catalogKey(ownerId));
        if (catalogJson != null && catalogJson.isNotEmpty) {
          final decoded = json.decode(catalogJson) as List<dynamic>;
          rosterList.addAll(decoded
              .map((item) => RosterMeta.fromJson(item as Map<String, dynamic>)));
        }
      }
      if (rosterList.isNotEmpty) {
        activeRosterId = rosterList.first.id;
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _catalogKey(ownerId),
        json.encode(rosterList.map((r) => r.toJson()).toList()),
      );
      if (activeRosterId != null) {
        await prefs.setString(_activeKey(ownerId), activeRosterId);
      }
    }
    state = state.copyWith(
      rosters: rosterList,
      activeRosterId: activeRosterId,
      isLoading: false,
      hasLoaded: true,
      ownerId: ownerId,
    );
  }

  Future<void> setActiveRoster(String ownerId, String rosterId) async {
    _ownerId = ownerId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeKey(ownerId), rosterId);
    state = state.copyWith(
      activeRosterId: rosterId,
      ownerId: ownerId,
      hasLoaded: true,
    );
  }

  Future<RosterMeta> addRoster({
    required String ownerId,
    required String companyName,
    required String departmentName,
    required String teamName,
    required bool isGuest,
  }) async {
    if (!isGuest) {
      final api = SupabaseRosterApi();
      final cloudRoster = await api.createRoster(
        companyName: companyName.trim(),
        departmentName: departmentName.trim(),
        teamName: teamName.trim(),
      );
      final roster = RosterMeta(
        id: cloudRoster.id,
        ownerId: ownerId,
        companyName: cloudRoster.companyName,
        departmentName: cloudRoster.departmentName,
        teamName: cloudRoster.teamName,
        role: cloudRoster.role,
        source: 'cloud',
        createdAt: cloudRoster.createdAt,
        updatedAt: cloudRoster.updatedAt,
      );
      final updated = [...state.rosters, roster];
      state = state.copyWith(
        rosters: updated,
        activeRosterId: roster.id,
        ownerId: ownerId,
        hasLoaded: true,
      );
      await _saveCatalog(ownerId, updated);
      await setActiveRoster(ownerId, roster.id);
      return roster;
    }

    final now = DateTime.now();
    final roster = RosterMeta(
      id: now.microsecondsSinceEpoch.toString(),
      ownerId: ownerId,
      companyName: companyName.trim(),
      departmentName: departmentName.trim(),
      teamName: teamName.trim(),
      role: 'admin',
      source: 'local',
      createdAt: now,
      updatedAt: now,
    );
    final updated = [...state.rosters, roster];
    await _saveCatalog(ownerId, updated);
    state = state.copyWith(
      rosters: updated,
      activeRosterId: roster.id,
      ownerId: ownerId,
      hasLoaded: true,
    );
    await setActiveRoster(ownerId, roster.id);
    return roster;
  }

  Future<void> updateRoster(
      String ownerId, RosterMeta roster, bool isGuest) async {
    final updated = state.rosters
        .map((r) => r.id == roster.id ? roster : r)
        .toList();
    if (isGuest || roster.source == 'local') {
      await _saveCatalog(ownerId, updated);
    } else {
      final api = SupabaseRosterApi();
      await api.updateRosterMeta(
        rosterId: roster.id,
        companyName: roster.companyName,
        departmentName: roster.departmentName,
        teamName: roster.teamName,
      );
    }
    await _saveCatalog(ownerId, updated);
    state = state.copyWith(rosters: updated, ownerId: ownerId, hasLoaded: true);
  }

  Future<void> removeRoster(
      String ownerId, String rosterId, bool isGuest) async {
    final roster = state.rosters.firstWhere(
      (r) => r.id == rosterId,
      orElse: () => RosterMeta(
        id: rosterId,
        ownerId: ownerId,
        companyName: '',
        departmentName: '',
        teamName: '',
        role: 'staff',
        source: 'local',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
    if (!isGuest && roster.source == 'cloud') {
      final api = SupabaseRosterApi();
      await api.leaveRoster(rosterId: rosterId);
    }
    final updated = state.rosters.where((r) => r.id != rosterId).toList();
    await _saveCatalog(ownerId, updated);
    final newActive = updated.isNotEmpty ? updated.first.id : null;
    state = state.copyWith(
      rosters: updated,
      activeRosterId: newActive,
      ownerId: ownerId,
      hasLoaded: true,
    );
    final prefs = await SharedPreferences.getInstance();
    if (newActive != null) {
      await prefs.setString(_activeKey(ownerId), newActive);
    } else {
      await prefs.remove(_activeKey(ownerId));
    }
  }

  Future<void> _saveCatalog(String ownerId, List<RosterMeta> rosters) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonData = json.encode(rosters.map((r) => r.toJson()).toList());
    await prefs.setString(_catalogKey(ownerId), jsonData);
  }

  String _catalogKey(String ownerId) => 'roster_catalog_${_safe(ownerId)}';
  String _activeKey(String ownerId) => 'roster_active_${_safe(ownerId)}';

  String _safe(String value) {
    return value.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
  }
}
