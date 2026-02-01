import 'package:flutter/foundation.dart';

// Enums - Consolidated to avoid duplicate definitions
enum ConnectionStatus {
  connected,
  connecting,
  disconnected,
  error,
}

enum EventType {
  general,
  holiday,
  training,
  meeting,
  deadline,
  birthday,
  anniversary,
  custom,
  payday,
  religious,
  cultural,
  sports,
}

enum SuggestionPriority {
  low,
  medium,
  high,
  critical,
}

enum SuggestionType {
  workload,
  pattern,
  leave,
  coverage,
  fairness,
  other,
}

enum SuggestionActionType {
  setOverride,
  swapShifts,
  addEvent,
  changeStaffStatus,
  adjustLeave,
  updatePattern,
  none,
}

enum SuggestionFeedback {
  helpful,
  notHelpful,
}

enum OrgRole {
  owner,
  admin,
  manager,
  staff,
}

enum RequestStatus {
  pending,
  approved,
  denied,
  cancelled,
}

enum AvailabilityType {
  availability,
  leave,
  preference,
}

enum ActivityLogLevel {
  info,
  warning,
  error,
}

class AnalyticsEvent {
  final String id;
  final String name;
  final String type;
  final DateTime timestamp;
  final String? userId;
  final String? rosterId;
  final String? sessionId;
  final Map<String, dynamic> properties;
  final DateTime? uploadedAt;

  AnalyticsEvent({
    required this.id,
    required this.name,
    required this.type,
    required this.timestamp,
    this.userId,
    this.rosterId,
    this.sessionId,
    this.properties = const {},
    this.uploadedAt,
  });

  AnalyticsEvent copyWith({
    String? id,
    String? name,
    String? type,
    DateTime? timestamp,
    String? userId,
    String? rosterId,
    String? sessionId,
    Map<String, dynamic>? properties,
    DateTime? uploadedAt,
  }) {
    return AnalyticsEvent(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      timestamp: timestamp ?? this.timestamp,
      userId: userId ?? this.userId,
      rosterId: rosterId ?? this.rosterId,
      sessionId: sessionId ?? this.sessionId,
      properties: properties ?? this.properties,
      uploadedAt: uploadedAt ?? this.uploadedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type,
        'timestamp': timestamp.toIso8601String(),
        'userId': userId,
        'rosterId': rosterId,
        'sessionId': sessionId,
        'properties': properties,
        'uploadedAt': uploadedAt?.toIso8601String(),
      };

  factory AnalyticsEvent.fromJson(Map<String, dynamic> json) => AnalyticsEvent(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? 'event',
        type: json['type'] as String? ?? 'custom',
        timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
            DateTime.now(),
        userId: json['userId'] as String?,
        rosterId: json['rosterId'] as String?,
        sessionId: json['sessionId'] as String?,
        properties:
            Map<String, dynamic>.from(json['properties'] as Map? ?? {}),
        uploadedAt: json['uploadedAt'] != null
            ? DateTime.tryParse(json['uploadedAt'] as String)
            : null,
      );
}

enum OperationType {
  bulkUpdate,
  singleUpdate,
  delete,
  addStaff,
  removeStaff,
  addOverride,
  removeOverride,
  updatePattern,
  addEvent,
  removeEvent,
}

class RosterUpdate {
  final String id;
  final String rosterId;
  final String userId;
  final OperationType operationType;
  final Map<String, dynamic> data;
  final DateTime timestamp;

  RosterUpdate({
    required this.id,
    required this.rosterId,
    required this.userId,
    required this.operationType,
    required this.data,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'roster_id': rosterId,
        'user_id': userId,
        'operation_type': operationType.index,
        'data': data,
        'timestamp': timestamp.toIso8601String(),
      };

  factory RosterUpdate.fromJson(Map<String, dynamic> json) {
    final rawType = json['operation_type'];
    final operationIndex = rawType is int
        ? rawType
        : int.tryParse(rawType?.toString() ?? '') ?? 0;
    final rawTimestamp = json['timestamp']?.toString();
    return RosterUpdate(
      id: json['id']?.toString() ?? '',
      rosterId: json['roster_id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      operationType: OperationType.values[
          operationIndex.clamp(0, OperationType.values.length - 1)],
      data: Map<String, dynamic>.from(json['data'] as Map? ?? {}),
      timestamp: rawTimestamp != null
          ? DateTime.tryParse(rawTimestamp) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

enum SyncOperationType {
  bulkUpdate,
  singleUpdate,
  delete,
}

enum RosterUpdateType {
  override,
  staff,
  event,
  settings,
  pattern,
}

enum AppThemeMode {
  system,
  light,
  dark,
}

enum ColorSchemeType {
  blue,
  green,
  purple,
  orange,
  pink,
  teal,
  indigo,
  amber,
}

// Service Status
class ServiceStatus {
  final ConnectionStatus status;
  final String? message;
  final DateTime? lastChecked;

  const ServiceStatus({
    required this.status,
    this.message,
    this.lastChecked,
  });

  Map<String, dynamic> toJson() => {
        'status': status.index,
        'message': message,
        'lastChecked': lastChecked?.toIso8601String(),
      };

  factory ServiceStatus.fromJson(Map<String, dynamic> json) => ServiceStatus(
        status: ConnectionStatus.values[json['status'] as int],
        message: json['message'] as String?,
        lastChecked: json['lastChecked'] != null
            ? DateTime.parse(json['lastChecked'] as String)
            : null,
      );
}

class Org {
  final String id;
  final String name;
  final String ownerId;
  final DateTime createdAt;
  final DateTime? updatedAt;

  Org({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.createdAt,
    this.updatedAt,
  });

  factory Org.fromJson(Map<String, dynamic> json) => Org(
        id: json['id'] as String,
        name: json['name'] as String,
        ownerId: json['owner_id'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: json['updated_at'] != null
            ? DateTime.parse(json['updated_at'] as String)
            : null,
      );
}

class OrgMembership {
  final String orgId;
  final OrgRole role;
  final Org? org;

  OrgMembership({
    required this.orgId,
    required this.role,
    this.org,
  });

  factory OrgMembership.fromJson(Map<String, dynamic> json) => OrgMembership(
        orgId: json['org_id'] as String,
        role: _parseOrgRole(json['role']),
        org: json['orgs'] != null
            ? Org.fromJson(Map<String, dynamic>.from(json['orgs'] as Map))
            : null,
      );
}

class Team {
  final String orgId;
  final String teamId;
  final String name;
  final DateTime createdAt;

  Team({
    required this.orgId,
    required this.teamId,
    required this.name,
    required this.createdAt,
  });

  factory Team.fromJson(Map<String, dynamic> json) => Team(
        orgId: json['orgId'] as String,
        teamId: json['teamId'] as String,
        name: json['name'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

class AvailabilityRequest {
  final String rosterId;
  final String requestId;
  final String userId;
  final AvailabilityType type;
  final DateTime startDate;
  final DateTime endDate;
  final RequestStatus status;
  final String notes;
  final String? reviewedBy;
  final String? reviewNote;
  final DateTime createdAt;
  final DateTime updatedAt;

  AvailabilityRequest({
    required this.rosterId,
    required this.requestId,
    required this.userId,
    required this.type,
    required this.startDate,
    required this.endDate,
    required this.status,
    required this.notes,
    required this.createdAt,
    required this.updatedAt,
    this.reviewedBy,
    this.reviewNote,
  });

  factory AvailabilityRequest.fromJson(Map<String, dynamic> json) =>
      AvailabilityRequest(
        rosterId: json['rosterId'] as String,
        requestId: json['requestId'] as String,
        userId: json['userId'] as String,
        type: _parseAvailabilityType(json['type']),
        startDate: DateTime.parse(json['startDate'] as String),
        endDate: DateTime.parse(json['endDate'] as String),
        status: _parseRequestStatus(json['status']),
        notes: json['notes'] as String? ?? '',
        reviewedBy: json['reviewedBy'] as String?,
        reviewNote: json['reviewNote'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
      );

  Map<String, dynamic> toJson() => {
        'rosterId': rosterId,
        'requestId': requestId,
        'userId': userId,
        'type': type.name,
        'startDate': startDate.toIso8601String(),
        'endDate': endDate.toIso8601String(),
        'status': status.name,
        'notes': notes,
        'reviewedBy': reviewedBy,
        'reviewNote': reviewNote,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };
}

class TimeClockEntry {
  final String rosterId;
  final String entryId;
  final String personName;
  final DateTime date;
  final double hours;
  final String source;

  TimeClockEntry({
    required this.rosterId,
    required this.entryId,
    required this.personName,
    required this.date,
    required this.hours,
    required this.source,
  });

  Map<String, dynamic> toJson() => {
        'rosterId': rosterId,
        'entryId': entryId,
        'personName': personName,
        'date': date.toIso8601String(),
        'hours': hours,
        'source': source,
      };

  factory TimeClockEntry.fromJson(Map<String, dynamic> json) {
    return TimeClockEntry(
      rosterId: json['rosterId'] as String? ?? '',
      entryId: json['entryId'] as String? ?? '',
      personName: json['personName'] as String? ?? 'Unknown',
      date: DateTime.parse(json['date'] as String),
      hours: (json['hours'] as num?)?.toDouble() ?? 0,
      source: json['source'] as String? ?? 'import',
    );
  }
}

class PresenceEntry {
  final String rosterId;
  final String userId;
  final String displayName;
  final String device;
  final DateTime lastSeen;

  PresenceEntry({
    required this.rosterId,
    required this.userId,
    required this.displayName,
    required this.device,
    required this.lastSeen,
  });

  factory PresenceEntry.fromJson(Map<String, dynamic> json) {
    return PresenceEntry(
      rosterId: json['rosterId'] as String? ?? '',
      userId: json['userId'] as String? ?? '',
      displayName: json['displayName'] as String? ?? 'User',
      device: json['device'] as String? ?? 'unknown',
      lastSeen: DateTime.parse(json['lastSeen'] as String),
    );
  }
}

class SwapRequest {
  final String rosterId;
  final String requestId;
  final String userId;
  final String fromPerson;
  final String? toPerson;
  final DateTime date;
  final String? shift;
  final RequestStatus status;
  final String notes;
  final String? reviewedBy;
  final String? reviewNote;
  final DateTime createdAt;
  final DateTime updatedAt;

  SwapRequest({
    required this.rosterId,
    required this.requestId,
    required this.userId,
    required this.fromPerson,
    required this.toPerson,
    required this.date,
    required this.shift,
    required this.status,
    required this.notes,
    required this.createdAt,
    required this.updatedAt,
    this.reviewedBy,
    this.reviewNote,
  });

  factory SwapRequest.fromJson(Map<String, dynamic> json) => SwapRequest(
        rosterId: json['rosterId'] as String,
        requestId: json['requestId'] as String,
        userId: json['userId'] as String,
        fromPerson: json['fromPerson'] as String,
        toPerson: json['toPerson'] as String?,
        date: DateTime.parse(json['date'] as String),
        shift: json['shift'] as String?,
        status: _parseRequestStatus(json['status']),
        notes: json['notes'] as String? ?? '',
        reviewedBy: json['reviewedBy'] as String?,
        reviewNote: json['reviewNote'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
      );

  Map<String, dynamic> toJson() => {
        'rosterId': rosterId,
        'requestId': requestId,
        'userId': userId,
        'fromPerson': fromPerson,
        'toPerson': toPerson,
        'date': date.toIso8601String(),
        'shift': shift,
        'status': status.name,
        'notes': notes,
        'reviewedBy': reviewedBy,
        'reviewNote': reviewNote,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };
}

class ShiftLock {
  final String rosterId;
  final String lockId;
  final DateTime date;
  final String shift;
  final String? personName;
  final String reason;
  final String lockedBy;
  final DateTime createdAt;

  ShiftLock({
    required this.rosterId,
    required this.lockId,
    required this.date,
    required this.shift,
    required this.personName,
    required this.reason,
    required this.lockedBy,
    required this.createdAt,
  });

  factory ShiftLock.fromJson(Map<String, dynamic> json) => ShiftLock(
        rosterId: json['rosterId'] as String,
        lockId: json['lockId'] as String,
        date: DateTime.parse(json['date'] as String),
        shift: json['shift'] as String,
        personName: json['personName'] as String?,
        reason: json['reason'] as String? ?? '',
        lockedBy: json['lockedBy'] as String? ?? '',
        createdAt: DateTime.parse(json['createdAt'] as String),
      );

  Map<String, dynamic> toJson() => {
        'rosterId': rosterId,
        'lockId': lockId,
        'date': date.toIso8601String(),
        'shift': shift,
        'personName': personName,
        'reason': reason,
        'lockedBy': lockedBy,
        'createdAt': createdAt.toIso8601String(),
      };
}

class ChangeProposal {
  final String rosterId;
  final String proposalId;
  final String userId;
  final String title;
  final String description;
  final Map<String, dynamic> changes;
  final RequestStatus status;
  final String? reviewedBy;
  final String? reviewNote;
  final DateTime createdAt;
  final DateTime updatedAt;

  ChangeProposal({
    required this.rosterId,
    required this.proposalId,
    required this.userId,
    required this.title,
    required this.description,
    required this.changes,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.reviewedBy,
    this.reviewNote,
  });

  factory ChangeProposal.fromJson(Map<String, dynamic> json) => ChangeProposal(
        rosterId: json['rosterId'] as String,
        proposalId: json['proposalId'] as String,
        userId: json['userId'] as String,
        title: json['title'] as String,
        description: json['description'] as String? ?? '',
        changes: Map<String, dynamic>.from(json['changes'] as Map),
        status: _parseRequestStatus(json['status']),
        reviewedBy: json['reviewedBy'] as String?,
        reviewNote: json['reviewNote'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
      );

  Map<String, dynamic> toJson() => {
        'rosterId': rosterId,
        'proposalId': proposalId,
        'userId': userId,
        'title': title,
        'description': description,
        'changes': changes,
        'status': status.name,
        'reviewedBy': reviewedBy,
        'reviewNote': reviewNote,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };
}

class AuditLogEntry {
  final String rosterId;
  final String logId;
  final String userId;
  final String action;
  final Map<String, dynamic> metadata;
  final DateTime timestamp;

  AuditLogEntry({
    required this.rosterId,
    required this.logId,
    required this.userId,
    required this.action,
    required this.metadata,
    required this.timestamp,
  });

  factory AuditLogEntry.fromJson(Map<String, dynamic> json) => AuditLogEntry(
        rosterId: json['rosterId'] as String,
        logId: json['logId'] as String,
        userId: json['user_id'] as String? ?? '',
        action: json['action'] as String? ?? '',
        metadata: Map<String, dynamic>.from(json['metadata'] as Map? ?? {}),
        timestamp: DateTime.parse(json['timestamp'] as String),
      );

  Map<String, dynamic> toJson() => {
        'rosterId': rosterId,
        'logId': logId,
        'user_id': userId,
        'action': action,
        'metadata': metadata,
        'timestamp': timestamp.toIso8601String(),
      };
}

class ActivityLogEntry {
  final ActivityLogLevel level;
  final String message;
  final List<String> fixes;
  final DateTime timestamp;
  final String? details;

  ActivityLogEntry({
    required this.level,
    required this.message,
    required this.fixes,
    required this.timestamp,
    this.details,
  });
}

class GeneratedRosterTemplate {
  final String id;
  final String name;
  final int teamCount;
  final int weekStartDay;
  final List<List<String>> pattern;
  final DateTime createdAt;

  GeneratedRosterTemplate({
    required this.id,
    required this.name,
    required this.teamCount,
    required this.weekStartDay,
    required this.pattern,
    required this.createdAt,
  });

  factory GeneratedRosterTemplate.fromJson(Map<String, dynamic> json) =>
      GeneratedRosterTemplate(
        id: json['id'] as String,
        name: json['name'] as String,
        teamCount: json['teamCount'] as int? ?? 0,
        weekStartDay: json['weekStartDay'] as int? ?? 0,
        pattern: (json['pattern'] as List<dynamic>)
            .map((week) => (week as List<dynamic>).cast<String>().toList())
            .toList(),
        createdAt: DateTime.parse(json['createdAt'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'teamCount': teamCount,
        'weekStartDay': weekStartDay,
        'pattern': pattern,
        'createdAt': createdAt.toIso8601String(),
      };
}

// Staff Member
class StaffMember {
  final String id;
  final String name;
  final bool isActive;
  final double leaveBalance;
  final DateTime? startDate;
  final DateTime? endDate;
  final String employmentType;
  final String? leaveType;
  final DateTime? leaveStart;
  final DateTime? leaveEnd;
  final Map<String, dynamic>? metadata;
  final StaffPreferences? preferences;

  StaffMember({
    required this.id,
    required this.name,
    this.isActive = true,
    this.leaveBalance = 31.0, // Changed from 20.0 to 31.0 days
    this.startDate,
    this.endDate,
    this.employmentType = 'permanent',
    this.leaveType,
    this.leaveStart,
    this.leaveEnd,
    this.metadata,
    this.preferences,
  });

  StaffMember copyWith({
    String? id,
    String? name,
    bool? isActive,
    double? leaveBalance,
    DateTime? startDate,
    DateTime? endDate,
    String? employmentType,
    String? leaveType,
    DateTime? leaveStart,
    DateTime? leaveEnd,
    Map<String, dynamic>? metadata,
    StaffPreferences? preferences,
  }) {
    return StaffMember(
      id: id ?? this.id,
      name: name ?? this.name,
      isActive: isActive ?? this.isActive,
      leaveBalance: leaveBalance ?? this.leaveBalance,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      employmentType: employmentType ?? this.employmentType,
      leaveType: leaveType ?? this.leaveType,
      leaveStart: leaveStart ?? this.leaveStart,
      leaveEnd: leaveEnd ?? this.leaveEnd,
      metadata: metadata ?? this.metadata,
      preferences: preferences ?? this.preferences,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'isActive': isActive,
        'leaveBalance': leaveBalance,
        'startDate': startDate?.toIso8601String(),
        'endDate': endDate?.toIso8601String(),
        'employmentType': employmentType,
        'leaveType': leaveType,
        'leaveStart': leaveStart?.toIso8601String(),
        'leaveEnd': leaveEnd?.toIso8601String(),
        'metadata': metadata,
        'preferences': preferences?.toJson(),
      };

  factory StaffMember.fromJson(Map<String, dynamic> json) => StaffMember(
        id: json['id'] as String,
        name: json['name'] as String,
        isActive: json['isActive'] as bool? ?? true,
        leaveBalance: (json['leaveBalance'] as num?)?.toDouble() ??
            31.0, // Changed from 20.0 to 31.0
        startDate: json['startDate'] != null
            ? DateTime.parse(json['startDate'] as String)
            : null,
        endDate: json['endDate'] != null
            ? DateTime.parse(json['endDate'] as String)
            : null,
        employmentType: json['employmentType'] as String? ?? 'permanent',
        leaveType: json['leaveType'] as String?,
        leaveStart: json['leaveStart'] != null
            ? DateTime.parse(json['leaveStart'] as String)
            : null,
        leaveEnd: json['leaveEnd'] != null
            ? DateTime.parse(json['leaveEnd'] as String)
            : null,
        metadata: json['metadata'] as Map<String, dynamic>?,
        preferences: json['preferences'] != null
            ? StaffPreferences.fromJson(
                json['preferences'] as Map<String, dynamic>,
              )
            : null,
      );
}

class StaffPreferences {
  final List<int> preferredDaysOff;
  final List<String> preferredShifts;
  final int? maxShiftsPerWeek;
  final int? minRestDaysBetweenShifts;
  final bool avoidWeekends;
  final String? notes;

  const StaffPreferences({
    this.preferredDaysOff = const [],
    this.preferredShifts = const [],
    this.maxShiftsPerWeek,
    this.minRestDaysBetweenShifts,
    this.avoidWeekends = false,
    this.notes,
  });

  StaffPreferences copyWith({
    List<int>? preferredDaysOff,
    List<String>? preferredShifts,
    int? maxShiftsPerWeek,
    int? minRestDaysBetweenShifts,
    bool? avoidWeekends,
    String? notes,
  }) {
    return StaffPreferences(
      preferredDaysOff: preferredDaysOff ?? this.preferredDaysOff,
      preferredShifts: preferredShifts ?? this.preferredShifts,
      maxShiftsPerWeek: maxShiftsPerWeek ?? this.maxShiftsPerWeek,
      minRestDaysBetweenShifts:
          minRestDaysBetweenShifts ?? this.minRestDaysBetweenShifts,
      avoidWeekends: avoidWeekends ?? this.avoidWeekends,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toJson() => {
        'preferredDaysOff': preferredDaysOff,
        'preferredShifts': preferredShifts,
        'maxShiftsPerWeek': maxShiftsPerWeek,
        'minRestDaysBetweenShifts': minRestDaysBetweenShifts,
        'avoidWeekends': avoidWeekends,
        'notes': notes,
      };

  factory StaffPreferences.fromJson(Map<String, dynamic> json) =>
      StaffPreferences(
        preferredDaysOff: (json['preferredDaysOff'] as List<dynamic>?)
                ?.map((e) => e as int)
                .toList() ??
            [],
        preferredShifts: (json['preferredShifts'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
        maxShiftsPerWeek: json['maxShiftsPerWeek'] as int?,
        minRestDaysBetweenShifts: json['minRestDaysBetweenShifts'] as int?,
        avoidWeekends: json['avoidWeekends'] as bool? ?? false,
        notes: json['notes'] as String?,
      );
}

class RosterConstraints {
  final int minStaffPerDay;
  final int minStaffWeekend;
  final int maxConsecutiveDays;
  final int maxShiftsPerWeek;
  final int minRestDaysBetweenShifts;
  final double fairnessWeight;
  final bool balanceWeekends;
  final bool allowAiOverrides;
  final double minLeaveBalance;
  final Map<String, int> shiftCoverageTargets;
  final Map<String, Map<String, int>> shiftCoverageTargetsByDay;

  const RosterConstraints({
    this.minStaffPerDay = 2,
    this.minStaffWeekend = 2,
    this.maxConsecutiveDays = 6,
    this.maxShiftsPerWeek = 5,
    this.minRestDaysBetweenShifts = 1,
    this.fairnessWeight = 0.6,
    this.balanceWeekends = true,
    this.allowAiOverrides = true,
    this.minLeaveBalance = 1.0,
    this.shiftCoverageTargets = const {'D': 1, 'N': 1},
    this.shiftCoverageTargetsByDay = const {},
  });

  RosterConstraints copyWith({
    int? minStaffPerDay,
    int? minStaffWeekend,
    int? maxConsecutiveDays,
    int? maxShiftsPerWeek,
    int? minRestDaysBetweenShifts,
    double? fairnessWeight,
    bool? balanceWeekends,
    bool? allowAiOverrides,
    double? minLeaveBalance,
    Map<String, int>? shiftCoverageTargets,
    Map<String, Map<String, int>>? shiftCoverageTargetsByDay,
  }) {
    return RosterConstraints(
      minStaffPerDay: minStaffPerDay ?? this.minStaffPerDay,
      minStaffWeekend: minStaffWeekend ?? this.minStaffWeekend,
      maxConsecutiveDays: maxConsecutiveDays ?? this.maxConsecutiveDays,
      maxShiftsPerWeek: maxShiftsPerWeek ?? this.maxShiftsPerWeek,
      minRestDaysBetweenShifts:
          minRestDaysBetweenShifts ?? this.minRestDaysBetweenShifts,
      fairnessWeight: fairnessWeight ?? this.fairnessWeight,
      balanceWeekends: balanceWeekends ?? this.balanceWeekends,
      allowAiOverrides: allowAiOverrides ?? this.allowAiOverrides,
      minLeaveBalance: minLeaveBalance ?? this.minLeaveBalance,
      shiftCoverageTargets:
          shiftCoverageTargets ?? this.shiftCoverageTargets,
      shiftCoverageTargetsByDay:
          shiftCoverageTargetsByDay ?? this.shiftCoverageTargetsByDay,
    );
  }

  Map<String, dynamic> toJson() => {
        'minStaffPerDay': minStaffPerDay,
        'minStaffWeekend': minStaffWeekend,
        'maxConsecutiveDays': maxConsecutiveDays,
        'maxShiftsPerWeek': maxShiftsPerWeek,
        'minRestDaysBetweenShifts': minRestDaysBetweenShifts,
        'fairnessWeight': fairnessWeight,
        'balanceWeekends': balanceWeekends,
        'allowAiOverrides': allowAiOverrides,
        'minLeaveBalance': minLeaveBalance,
        'shiftCoverageTargets': shiftCoverageTargets,
        'shiftCoverageTargetsByDay': shiftCoverageTargetsByDay,
      };

  factory RosterConstraints.fromJson(Map<String, dynamic> json) =>
      RosterConstraints(
        minStaffPerDay: json['minStaffPerDay'] as int? ?? 2,
        minStaffWeekend: json['minStaffWeekend'] as int? ?? 2,
        maxConsecutiveDays: json['maxConsecutiveDays'] as int? ?? 6,
        maxShiftsPerWeek: json['maxShiftsPerWeek'] as int? ?? 5,
        minRestDaysBetweenShifts:
            json['minRestDaysBetweenShifts'] as int? ?? 1,
        fairnessWeight: (json['fairnessWeight'] as num?)?.toDouble() ?? 0.6,
        balanceWeekends: json['balanceWeekends'] as bool? ?? true,
        allowAiOverrides: json['allowAiOverrides'] as bool? ?? true,
        minLeaveBalance: (json['minLeaveBalance'] as num?)?.toDouble() ?? 1.0,
        shiftCoverageTargets:
            (json['shiftCoverageTargets'] as Map<String, dynamic>?)
                    ?.map((k, v) => MapEntry(k, v as int)) ??
                const {'D': 1, 'N': 1},
        shiftCoverageTargetsByDay:
            (json['shiftCoverageTargetsByDay'] as Map<String, dynamic>?)
                    ?.map((key, value) => MapEntry(
                          key,
                          (value as Map<String, dynamic>)
                              .map((k, v) => MapEntry(k, v as int)),
                        )) ??
                const {},
      );
}

class RosterHealthScore {
  final double overall;
  final double coverage;
  final double workload;
  final double fairness;
  final double leave;
  final double pattern;

  const RosterHealthScore({
    required this.overall,
    required this.coverage,
    required this.workload,
    required this.fairness,
    required this.leave,
    required this.pattern,
  });

  Map<String, dynamic> toJson() => {
        'overall': overall,
        'coverage': coverage,
        'workload': workload,
        'fairness': fairness,
        'leave': leave,
        'pattern': pattern,
      };

  factory RosterHealthScore.fromJson(Map<String, dynamic> json) =>
      RosterHealthScore(
        overall: (json['overall'] as num).toDouble(),
        coverage: (json['coverage'] as num).toDouble(),
        workload: (json['workload'] as num).toDouble(),
        fairness: (json['fairness'] as num).toDouble(),
        leave: (json['leave'] as num).toDouble(),
        pattern: (json['pattern'] as num).toDouble(),
      );
}

// Override
class Override {
  final String id;
  final String personName;
  final DateTime date;
  final String shift;
  final String? reason;
  final DateTime createdAt;

  Override({
    required this.id,
    required this.personName,
    required this.date,
    required this.shift,
    this.reason,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'personName': personName,
        'date': date.toIso8601String(),
        'shift': shift,
        'reason': reason,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Override.fromJson(Map<String, dynamic> json) => Override(
        id: json['id'] as String,
        personName: json['personName'] as String,
        date: DateTime.parse(json['date'] as String),
        shift: json['shift'] as String,
        reason: json['reason'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

// Event
class Event {
  final String id;
  final String title;
  final String? description;
  final DateTime date;
  final EventType eventType;
  final List<String> affectedStaff;
  final String? recurringId;

  Event({
    required this.id,
    required this.title,
    this.description,
    required this.date,
    this.eventType = EventType.general,
    this.affectedStaff = const [],
    this.recurringId,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'date': date.toIso8601String(),
        'eventType': eventType.index,
        'affectedStaff': affectedStaff,
        'recurringId': recurringId,
      };

  factory Event.fromJson(Map<String, dynamic> json) => Event(
        id: json['id'] as String,
        title: json['title'] as String,
        description: json['description'] as String?,
        date: DateTime.parse(json['date'] as String),
        eventType: EventType.values[json['eventType'] as int? ?? 0],
        affectedStaff: (json['affectedStaff'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
        recurringId: json['recurringId'] as String?,
      );
}

// AI Suggestion
class AiSuggestion {
  final String id;
  final String title;
  final String description;
  final String? reason;
  final SuggestionPriority priority;
  final SuggestionType type;
  final DateTime createdDate;
  final bool isRead;
  final List<String>? affectedStaff;
  final SuggestionActionType? actionType;
  final Map<String, dynamic>? actionPayload;
  final double? impactScore;
  final double? confidence;
  final SuggestionFeedback? feedback;
  final Map<String, dynamic>? metrics;

  AiSuggestion({
    required this.id,
    required this.title,
    required this.description,
    this.reason,
    required this.priority,
    required this.type,
    required this.createdDate,
    this.isRead = false,
    this.affectedStaff,
    this.actionType,
    this.actionPayload,
    this.impactScore,
    this.confidence,
    this.feedback,
    this.metrics,
  });

  AiSuggestion copyWith({
    String? id,
    String? title,
    String? description,
    String? reason,
    SuggestionPriority? priority,
    SuggestionType? type,
    DateTime? createdDate,
    bool? isRead,
    List<String>? affectedStaff,
    SuggestionActionType? actionType,
    Map<String, dynamic>? actionPayload,
    double? impactScore,
    double? confidence,
    SuggestionFeedback? feedback,
    Map<String, dynamic>? metrics,
  }) {
    return AiSuggestion(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      reason: reason ?? this.reason,
      priority: priority ?? this.priority,
      type: type ?? this.type,
      createdDate: createdDate ?? this.createdDate,
      isRead: isRead ?? this.isRead,
      affectedStaff: affectedStaff ?? this.affectedStaff,
      actionType: actionType ?? this.actionType,
      actionPayload: actionPayload ?? this.actionPayload,
      impactScore: impactScore ?? this.impactScore,
      confidence: confidence ?? this.confidence,
      feedback: feedback ?? this.feedback,
      metrics: metrics ?? this.metrics,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'reason': reason,
        'priority': priority.index,
        'type': type.index,
        'createdDate': createdDate.toIso8601String(),
        'isRead': isRead,
        'affectedStaff': affectedStaff,
        'actionType': actionType?.index,
        'actionPayload': actionPayload,
        'impactScore': impactScore,
        'confidence': confidence,
        'feedback': feedback?.index,
        'metrics': metrics,
      };

  factory AiSuggestion.fromJson(Map<String, dynamic> json) => AiSuggestion(
        id: json['id'] as String,
        title: json['title'] as String,
        description: json['description'] as String,
        reason: json['reason'] as String?,
        priority: SuggestionPriority.values[json['priority'] as int? ?? 0],
        type: SuggestionType.values[json['type'] as int? ?? 0],
        createdDate: DateTime.parse(json['createdDate'] as String),
        isRead: json['isRead'] as bool? ?? false,
        affectedStaff: (json['affectedStaff'] as List<dynamic>?)
            ?.map((e) => e as String)
            .toList(),
        actionType: _parseActionType(json['actionType']),
        actionPayload: json['actionPayload'] as Map<String, dynamic>?,
        impactScore: (json['impactScore'] as num?)?.toDouble(),
        confidence: (json['confidence'] as num?)?.toDouble(),
        feedback: json['feedback'] != null
            ? SuggestionFeedback.values[json['feedback'] as int]
            : null,
        metrics: json['metrics'] as Map<String, dynamic>?,
      );
}

SuggestionActionType? _parseActionType(dynamic raw) {
  if (raw == null) return null;
  if (raw is int) {
    if (raw < 0 || raw >= SuggestionActionType.values.length) return null;
    return SuggestionActionType.values[raw];
  }
  if (raw is String) {
    switch (raw) {
      case 'setOverride':
        return SuggestionActionType.setOverride;
      case 'swapShifts':
        return SuggestionActionType.swapShifts;
      case 'addEvent':
        return SuggestionActionType.addEvent;
      case 'changeStaffStatus':
        return SuggestionActionType.changeStaffStatus;
      case 'adjustLeave':
        return SuggestionActionType.adjustLeave;
      case 'updatePattern':
        return SuggestionActionType.updatePattern;
      case 'none':
        return SuggestionActionType.none;
    }
  }
  return null;
}

OrgRole _parseOrgRole(dynamic raw) {
  if (raw is int) {
    if (raw < 0 || raw >= OrgRole.values.length) return OrgRole.staff;
    return OrgRole.values[raw];
  }
  if (raw is String) {
    switch (raw) {
      case 'owner':
        return OrgRole.owner;
      case 'admin':
        return OrgRole.admin;
      case 'manager':
        return OrgRole.manager;
      case 'staff':
      case 'member':
        return OrgRole.staff;
    }
  }
  return OrgRole.staff;
}

RequestStatus _parseRequestStatus(dynamic raw) {
  if (raw is int) {
    if (raw < 0 || raw >= RequestStatus.values.length) {
      return RequestStatus.pending;
    }
    return RequestStatus.values[raw];
  }
  if (raw is String) {
    switch (raw) {
      case 'approved':
        return RequestStatus.approved;
      case 'denied':
        return RequestStatus.denied;
      case 'cancelled':
        return RequestStatus.cancelled;
      case 'pending':
      default:
        return RequestStatus.pending;
    }
  }
  return RequestStatus.pending;
}

AvailabilityType _parseAvailabilityType(dynamic raw) {
  if (raw is int) {
    if (raw < 0 || raw >= AvailabilityType.values.length) {
      return AvailabilityType.availability;
    }
    return AvailabilityType.values[raw];
  }
  if (raw is String) {
    switch (raw) {
      case 'leave':
        return AvailabilityType.leave;
      case 'preference':
        return AvailabilityType.preference;
      case 'availability':
      default:
        return AvailabilityType.availability;
    }
  }
  return AvailabilityType.availability;
}

// Pattern Recognition Result
class PatternRecognitionResult {
  final int detectedCycleLength;
  final double confidence;
  final List<List<String>> detectedPattern;
  final Map<String, int> shiftFrequency;
  final List<String> suggestions;
  final DateTime analyzedAt;

  PatternRecognitionResult({
    required this.detectedCycleLength,
    required this.confidence,
    required this.detectedPattern,
    required this.shiftFrequency,
    required this.suggestions,
    required this.analyzedAt,
  });

  Map<String, dynamic> toJson() => {
        'detectedCycleLength': detectedCycleLength,
        'confidence': confidence,
        'detectedPattern': detectedPattern,
        'shiftFrequency': shiftFrequency,
        'suggestions': suggestions,
        'analyzedAt': analyzedAt.toIso8601String(),
      };

  factory PatternRecognitionResult.fromJson(Map<String, dynamic> json) =>
      PatternRecognitionResult(
        detectedCycleLength: json['detectedCycleLength'] as int,
        confidence: (json['confidence'] as num).toDouble(),
        detectedPattern: (json['detectedPattern'] as List<dynamic>)
            .map((e) => (e as List<dynamic>).map((s) => s as String).toList())
            .toList(),
        shiftFrequency: (json['shiftFrequency'] as Map<String, dynamic>)
            .map((k, v) => MapEntry(k, v as int)),
        suggestions: (json['suggestions'] as List<dynamic>)
            .map((e) => e as String)
            .toList(),
        analyzedAt: DateTime.parse(json['analyzedAt'] as String),
      );
}

// Sync Operation
class SyncOperation {
  final String id;
  final SyncOperationType type;
  final Map<String, dynamic> data;
  final DateTime timestamp;
  final bool synced;

  SyncOperation({
    required this.id,
    required this.type,
    required this.data,
    required this.timestamp,
    this.synced = false,
  });

  SyncOperation copyWith({
    String? id,
    SyncOperationType? type,
    Map<String, dynamic>? data,
    DateTime? timestamp,
    bool? synced,
  }) {
    return SyncOperation(
      id: id ?? this.id,
      type: type ?? this.type,
      data: data ?? this.data,
      timestamp: timestamp ?? this.timestamp,
      synced: synced ?? this.synced,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.index,
        'data': data,
        'timestamp': timestamp.toIso8601String(),
        'synced': synced,
      };

  factory SyncOperation.fromJson(Map<String, dynamic> json) => SyncOperation(
        id: json['id'] as String,
        type: SyncOperationType.values[json['type'] as int],
        data: json['data'] as Map<String, dynamic>,
        timestamp: DateTime.parse(json['timestamp'] as String),
        synced: json['synced'] as bool? ?? false,
      );
}

// App Settings
class AppSettings {
  final bool darkMode;
  final bool notifications;
  final bool autoSync;
  final int syncInterval;
  final bool showWeekNumbers;
  final String dateFormat;
  final bool compactView;
  final AppThemeMode themeMode;
  final ColorSchemeType colorScheme;
  final String holidayCountryCode;
  final List<String> holidayTypes;
  final List<String> additionalHolidayCountries;
  final bool showHolidayOverlay;
  final bool showObservanceOverlay;
  final bool showSportsOverlay;
  final List<String> observanceTypes;
  final String calendarificApiKey;
  final String sportsApiKey;
  final List<String> sportsLeagueIds;
  final List<String> hiddenOverlayDates;
  final String timeZone;
  final String siteName;
  final double? siteLat;
  final double? siteLon;
  final bool showWeatherOverlay;
  final bool showMapPreview;
  final double monthSnapOffsetPx;
  final String languageCode;
  final bool voiceEnabled;
  final bool voiceAlwaysListening;
  final String voiceInputEngine;
  final String voiceOutputEngine;
  final List<String> voiceWakeWords;
  final bool analyticsEnabled;
  final bool analyticsCloudEnabled;

  const AppSettings({
    this.darkMode = false,
    this.notifications = true,
    this.autoSync = true,
    this.syncInterval = 15,
    this.showWeekNumbers = true,
    this.dateFormat = 'dd/MM/yyyy',
    this.compactView = false,
    this.themeMode = AppThemeMode.system,
    this.colorScheme = ColorSchemeType.blue,
    this.holidayCountryCode = 'US',
    this.holidayTypes = const ['Public', 'Bank'],
    this.additionalHolidayCountries = const [],
    this.showHolidayOverlay = true,
    this.showObservanceOverlay = true,
    this.showSportsOverlay = false,
    this.observanceTypes = const ['religious', 'observance'],
    this.calendarificApiKey = '',
    this.sportsApiKey = '',
    this.sportsLeagueIds = const [],
    this.hiddenOverlayDates = const [],
    this.timeZone = 'UTC',
    this.siteName = '',
    this.siteLat,
    this.siteLon,
    this.showWeatherOverlay = true,
    this.showMapPreview = true,
    this.monthSnapOffsetPx = 1200.0,
    this.languageCode = 'en',
    this.voiceEnabled = true,
    this.voiceAlwaysListening = false,
    this.voiceInputEngine = 'onDevice',
    this.voiceOutputEngine = 'aws',
    this.voiceWakeWords = const [
      'rc',
      'roster champ',
      'roster champion',
    ],
    this.analyticsEnabled = true,
    this.analyticsCloudEnabled = true,
  });

  AppSettings copyWith({
    bool? darkMode,
    bool? notifications,
    bool? autoSync,
    int? syncInterval,
    bool? showWeekNumbers,
    String? dateFormat,
    bool? compactView,
    AppThemeMode? themeMode,
    ColorSchemeType? colorScheme,
    String? holidayCountryCode,
    List<String>? holidayTypes,
    List<String>? additionalHolidayCountries,
    bool? showHolidayOverlay,
    bool? showObservanceOverlay,
    bool? showSportsOverlay,
    List<String>? observanceTypes,
    String? calendarificApiKey,
    String? sportsApiKey,
    List<String>? sportsLeagueIds,
    List<String>? hiddenOverlayDates,
    String? timeZone,
    String? siteName,
    double? siteLat,
    double? siteLon,
    bool? showWeatherOverlay,
    bool? showMapPreview,
    double? monthSnapOffsetPx,
    String? languageCode,
    bool? voiceEnabled,
    bool? voiceAlwaysListening,
    String? voiceInputEngine,
    String? voiceOutputEngine,
    List<String>? voiceWakeWords,
    bool? analyticsEnabled,
    bool? analyticsCloudEnabled,
  }) {
    return AppSettings(
      darkMode: darkMode ?? this.darkMode,
      notifications: notifications ?? this.notifications,
      autoSync: autoSync ?? this.autoSync,
      syncInterval: syncInterval ?? this.syncInterval,
      showWeekNumbers: showWeekNumbers ?? this.showWeekNumbers,
      dateFormat: dateFormat ?? this.dateFormat,
      compactView: compactView ?? this.compactView,
      themeMode: themeMode ?? this.themeMode,
      colorScheme: colorScheme ?? this.colorScheme,
      holidayCountryCode: holidayCountryCode ?? this.holidayCountryCode,
      holidayTypes: holidayTypes ?? this.holidayTypes,
      additionalHolidayCountries:
          additionalHolidayCountries ?? this.additionalHolidayCountries,
      showHolidayOverlay: showHolidayOverlay ?? this.showHolidayOverlay,
      showObservanceOverlay:
          showObservanceOverlay ?? this.showObservanceOverlay,
      showSportsOverlay: showSportsOverlay ?? this.showSportsOverlay,
      observanceTypes: observanceTypes ?? this.observanceTypes,
      calendarificApiKey: calendarificApiKey ?? this.calendarificApiKey,
      sportsApiKey: sportsApiKey ?? this.sportsApiKey,
      sportsLeagueIds: sportsLeagueIds ?? this.sportsLeagueIds,
      hiddenOverlayDates: hiddenOverlayDates ?? this.hiddenOverlayDates,
      timeZone: timeZone ?? this.timeZone,
      siteName: siteName ?? this.siteName,
      siteLat: siteLat ?? this.siteLat,
      siteLon: siteLon ?? this.siteLon,
      showWeatherOverlay: showWeatherOverlay ?? this.showWeatherOverlay,
      showMapPreview: showMapPreview ?? this.showMapPreview,
      monthSnapOffsetPx: monthSnapOffsetPx ?? this.monthSnapOffsetPx,
      languageCode: languageCode ?? this.languageCode,
      voiceEnabled: voiceEnabled ?? this.voiceEnabled,
      voiceAlwaysListening: voiceAlwaysListening ?? this.voiceAlwaysListening,
      voiceInputEngine: voiceInputEngine ?? this.voiceInputEngine,
      voiceOutputEngine: voiceOutputEngine ?? this.voiceOutputEngine,
      voiceWakeWords: voiceWakeWords ?? this.voiceWakeWords,
      analyticsEnabled: analyticsEnabled ?? this.analyticsEnabled,
      analyticsCloudEnabled:
          analyticsCloudEnabled ?? this.analyticsCloudEnabled,
    );
  }

  Map<String, dynamic> toJson() => {
        'darkMode': darkMode,
        'notifications': notifications,
        'autoSync': autoSync,
        'syncInterval': syncInterval,
        'showWeekNumbers': showWeekNumbers,
        'dateFormat': dateFormat,
        'compactView': compactView,
        'themeMode': themeMode.index,
        'colorScheme': colorScheme.index,
      'holidayCountryCode': holidayCountryCode,
      'holidayTypes': holidayTypes,
      'additionalHolidayCountries': additionalHolidayCountries,
      'showHolidayOverlay': showHolidayOverlay,
      'showObservanceOverlay': showObservanceOverlay,
      'showSportsOverlay': showSportsOverlay,
      'observanceTypes': observanceTypes,
      'calendarificApiKey': calendarificApiKey,
      'sportsApiKey': sportsApiKey,
      'sportsLeagueIds': sportsLeagueIds,
      'hiddenOverlayDates': hiddenOverlayDates,
      'timeZone': timeZone,
        'siteName': siteName,
        'siteLat': siteLat,
        'siteLon': siteLon,
        'showWeatherOverlay': showWeatherOverlay,
        'showMapPreview': showMapPreview,
        'monthSnapOffsetPx': monthSnapOffsetPx,
        'languageCode': languageCode,
        'voiceEnabled': voiceEnabled,
        'voiceAlwaysListening': voiceAlwaysListening,
      'voiceInputEngine': voiceInputEngine,
      'voiceOutputEngine': voiceOutputEngine,
      'voiceWakeWords': voiceWakeWords,
      'analyticsEnabled': analyticsEnabled,
      'analyticsCloudEnabled': analyticsCloudEnabled,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        darkMode: json['darkMode'] as bool? ?? false,
        notifications: json['notifications'] as bool? ?? true,
        autoSync: json['autoSync'] as bool? ?? true,
        syncInterval: json['syncInterval'] as int? ?? 15,
        showWeekNumbers: json['showWeekNumbers'] as bool? ?? true,
        dateFormat: json['dateFormat'] as String? ?? 'dd/MM/yyyy',
        compactView: json['compactView'] as bool? ?? false,
        themeMode: AppThemeMode.values[json['themeMode'] as int? ?? 0],
        colorScheme: ColorSchemeType.values[json['colorScheme'] as int? ?? 0],
      holidayCountryCode:
          json['holidayCountryCode'] as String? ?? 'US',
      holidayTypes: (json['holidayTypes'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const ['Public', 'Bank'],
      additionalHolidayCountries:
          (json['additionalHolidayCountries'] as List<dynamic>?)
                  ?.map((e) => e.toString())
                  .toList() ??
              const [],
      showHolidayOverlay:
          json['showHolidayOverlay'] as bool? ?? true,
      showObservanceOverlay:
          json['showObservanceOverlay'] as bool? ?? true,
      showSportsOverlay: json['showSportsOverlay'] as bool? ?? false,
      observanceTypes: (json['observanceTypes'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const ['religious', 'observance'],
      calendarificApiKey: json['calendarificApiKey'] as String? ?? '',
      sportsApiKey: json['sportsApiKey'] as String? ?? '',
      sportsLeagueIds: (json['sportsLeagueIds'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      hiddenOverlayDates: (json['hiddenOverlayDates'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      timeZone: json['timeZone'] as String? ?? 'UTC',
        siteName: json['siteName'] as String? ?? '',
        siteLat: (json['siteLat'] as num?)?.toDouble(),
        siteLon: (json['siteLon'] as num?)?.toDouble(),
        showWeatherOverlay:
            json['showWeatherOverlay'] as bool? ?? true,
        showMapPreview: json['showMapPreview'] as bool? ?? true,
        monthSnapOffsetPx:
            (json['monthSnapOffsetPx'] as num?)?.toDouble() ?? 1200.0,
        languageCode: json['languageCode'] as String? ?? 'en',
        voiceEnabled: json['voiceEnabled'] as bool? ?? true,
        voiceAlwaysListening:
            json['voiceAlwaysListening'] as bool? ?? false,
        voiceInputEngine:
            json['voiceInputEngine'] as String? ?? 'onDevice',
        voiceOutputEngine:
            json['voiceOutputEngine'] as String? ?? 'aws',
        voiceWakeWords: (json['voiceWakeWords'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const ['rc', 'roster champ', 'roster champion'],
        analyticsEnabled: json['analyticsEnabled'] as bool? ?? true,
        analyticsCloudEnabled: json['analyticsCloudEnabled'] as bool? ?? true,
      );
}

// History Entry
class HistoryEntry {
  final DateTime timestamp;
  final String action;
  final String description;
  final Map<String, dynamic>? metadata;

  HistoryEntry({
    required this.timestamp,
    required this.action,
    required this.description,
    this.metadata,
  });

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'action': action,
        'description': description,
        'metadata': metadata,
      };

  factory HistoryEntry.fromJson(Map<String, dynamic> json) => HistoryEntry(
        timestamp: DateTime.parse(json['timestamp'] as String),
        action: json['action'] as String,
        description: json['description'] as String,
        metadata: json['metadata'] as Map<String, dynamic>?,
      );
}

// Regular Shift Swap
class RegularShiftSwap {
  final String id;
  final String fromPerson;
  final String toPerson;
  final String fromShift;
  final String toShift;
  final DateTime startDate;
  final DateTime? endDate;
  final bool isActive;
  final int? weekIndex;

  RegularShiftSwap({
    required this.id,
    required this.fromPerson,
    required this.toPerson,
    required this.fromShift,
    required this.toShift,
    required this.startDate,
    this.endDate,
    this.isActive = true,
    this.weekIndex,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'fromPerson': fromPerson,
        'toPerson': toPerson,
        'fromShift': fromShift,
        'toShift': toShift,
        'startDate': startDate.toIso8601String(),
        'endDate': endDate?.toIso8601String(),
        'isActive': isActive,
        'weekIndex': weekIndex,
      };

  factory RegularShiftSwap.fromJson(Map<String, dynamic> json) =>
      RegularShiftSwap(
        id: json['id'] as String,
        fromPerson: json['fromPerson'] as String,
        toPerson: json['toPerson'] as String,
        fromShift: json['fromShift'] as String,
        toShift: json['toShift'] as String,
        startDate: DateTime.parse(json['startDate'] as String),
        endDate: json['endDate'] != null
            ? DateTime.parse(json['endDate'] as String)
            : null,
        isActive: json['isActive'] as bool? ?? true,
        weekIndex: json['weekIndex'] as int?,
      );
}

class SwapDebt {
  final String id;
  final String fromPerson;
  final String toPerson;
  final int daysOwed;
  final int daysSettled;
  final String reason;
  final DateTime createdAt;
  final DateTime? resolvedAt;
  final bool isIgnored;
  final DateTime? ignoredAt;
  final List<String> settledDates;

  const SwapDebt({
    required this.id,
    required this.fromPerson,
    required this.toPerson,
    required this.daysOwed,
    required this.daysSettled,
    required this.reason,
    required this.createdAt,
    this.resolvedAt,
    this.isIgnored = false,
    this.ignoredAt,
    this.settledDates = const [],
  });

  bool get isResolved => isIgnored || daysSettled >= daysOwed;

  Map<String, dynamic> toJson() => {
        'id': id,
        'fromPerson': fromPerson,
        'toPerson': toPerson,
        'daysOwed': daysOwed,
        'daysSettled': daysSettled,
        'reason': reason,
        'createdAt': createdAt.toIso8601String(),
        'resolvedAt': resolvedAt?.toIso8601String(),
        'isIgnored': isIgnored,
        'ignoredAt': ignoredAt?.toIso8601String(),
        'settledDates': settledDates,
      };

  factory SwapDebt.fromJson(Map<String, dynamic> json) => SwapDebt(
        id: json['id'] as String,
        fromPerson: json['fromPerson'] as String,
        toPerson: json['toPerson'] as String,
        daysOwed: json['daysOwed'] as int? ?? 0,
        daysSettled: json['daysSettled'] as int? ?? 0,
        reason: json['reason'] as String? ?? '',
        createdAt: DateTime.parse(json['createdAt'] as String),
        resolvedAt: json['resolvedAt'] != null
            ? DateTime.parse(json['resolvedAt'] as String)
            : null,
        isIgnored: json['isIgnored'] as bool? ?? false,
        ignoredAt: json['ignoredAt'] != null
            ? DateTime.parse(json['ignoredAt'] as String)
            : null,
        settledDates: (json['settledDates'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
      );

  SwapDebt copyWith({
    int? daysSettled,
    DateTime? resolvedAt,
    bool? isIgnored,
    DateTime? ignoredAt,
    List<String>? settledDates,
  }) {
    return SwapDebt(
      id: id,
      fromPerson: fromPerson,
      toPerson: toPerson,
      daysOwed: daysOwed,
      daysSettled: daysSettled ?? this.daysSettled,
      reason: reason,
      createdAt: createdAt,
      resolvedAt: resolvedAt ?? this.resolvedAt,
      isIgnored: isIgnored ?? this.isIgnored,
      ignoredAt: ignoredAt ?? this.ignoredAt,
      settledDates: settledDates ?? this.settledDates,
    );
  }
}

// Pattern Propagation Settings
class PatternPropagationSettings {
  final bool isActive;
  final int weekShift;
  final int dayShift;
  final DateTime? lastApplied;

  PatternPropagationSettings({
    required this.isActive,
    required this.weekShift,
    required this.dayShift,
    this.lastApplied,
  });

  PatternPropagationSettings copyWith({
    bool? isActive,
    int? weekShift,
    int? dayShift,
    DateTime? lastApplied,
  }) {
    return PatternPropagationSettings(
      isActive: isActive ?? this.isActive,
      weekShift: weekShift ?? this.weekShift,
      dayShift: dayShift ?? this.dayShift,
      lastApplied: lastApplied ?? this.lastApplied,
    );
  }

  Map<String, dynamic> toJson() => {
        'isActive': isActive,
        'weekShift': weekShift,
        'dayShift': dayShift,
        'lastApplied': lastApplied?.toIso8601String(),
      };

  factory PatternPropagationSettings.fromJson(Map<String, dynamic> json) =>
      PatternPropagationSettings(
        isActive: json['isActive'] as bool? ?? false,
        weekShift: json['weekShift'] as int? ?? 0,
        dayShift: json['dayShift'] as int? ?? 0,
        lastApplied: json['lastApplied'] != null
            ? DateTime.parse(json['lastApplied'] as String)
            : null,
      );
}
