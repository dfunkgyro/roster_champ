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

enum OperationType {
  addStaff,
  removeStaff,
  addOverride,
  removeOverride,
  updatePattern,
  addEvent,
  removeEvent,
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

// Staff Member
class StaffMember {
  final String id;
  final String name;
  final bool isActive;
  final double leaveBalance;
  final Map<String, dynamic>? metadata;

  StaffMember({
    required this.id,
    required this.name,
    this.isActive = true,
    this.leaveBalance = 31.0, // Changed from 20.0 to 31.0 days
    this.metadata,
  });

  StaffMember copyWith({
    String? id,
    String? name,
    bool? isActive,
    double? leaveBalance,
    Map<String, dynamic>? metadata,
  }) {
    return StaffMember(
      id: id ?? this.id,
      name: name ?? this.name,
      isActive: isActive ?? this.isActive,
      leaveBalance: leaveBalance ?? this.leaveBalance,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'isActive': isActive,
        'leaveBalance': leaveBalance,
        'metadata': metadata,
      };

  factory StaffMember.fromJson(Map<String, dynamic> json) => StaffMember(
        id: json['id'] as String,
        name: json['name'] as String,
        isActive: json['isActive'] as bool? ?? true,
        leaveBalance: (json['leaveBalance'] as num?)?.toDouble() ??
            31.0, // Changed from 20.0 to 31.0
        metadata: json['metadata'] as Map<String, dynamic>?,
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
  final SuggestionPriority priority;
  final SuggestionType type;
  final DateTime createdDate;
  final bool isRead;
  final List<String>? affectedStaff;
  final String? actionType;

  AiSuggestion({
    required this.id,
    required this.title,
    required this.description,
    required this.priority,
    required this.type,
    required this.createdDate,
    this.isRead = false,
    this.affectedStaff,
    this.actionType,
  });

  AiSuggestion copyWith({
    String? id,
    String? title,
    String? description,
    SuggestionPriority? priority,
    SuggestionType? type,
    DateTime? createdDate,
    bool? isRead,
    List<String>? affectedStaff,
    String? actionType,
  }) {
    return AiSuggestion(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      priority: priority ?? this.priority,
      type: type ?? this.type,
      createdDate: createdDate ?? this.createdDate,
      isRead: isRead ?? this.isRead,
      affectedStaff: affectedStaff ?? this.affectedStaff,
      actionType: actionType ?? this.actionType,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'priority': priority.index,
        'type': type.index,
        'createdDate': createdDate.toIso8601String(),
        'isRead': isRead,
        'affectedStaff': affectedStaff,
        'actionType': actionType,
      };

  factory AiSuggestion.fromJson(Map<String, dynamic> json) => AiSuggestion(
        id: json['id'] as String,
        title: json['title'] as String,
        description: json['description'] as String,
        priority: SuggestionPriority.values[json['priority'] as int? ?? 0],
        type: SuggestionType.values[json['type'] as int? ?? 0],
        createdDate: DateTime.parse(json['createdDate'] as String),
        isRead: json['isRead'] as bool? ?? false,
        affectedStaff: (json['affectedStaff'] as List<dynamic>?)
            ?.map((e) => e as String)
            .toList(),
        actionType: json['actionType'] as String?,
      );
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

// Roster Update
class RosterUpdate {
  final String id;
  final String userId;
  final OperationType operationType;
  final Map<String, dynamic> data;
  final DateTime timestamp;

  RosterUpdate({
    required this.id,
    required this.userId,
    required this.operationType,
    required this.data,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'userId': userId,
        'operationType': operationType.index,
        'data': data,
        'timestamp': timestamp.toIso8601String(),
      };

  factory RosterUpdate.fromJson(Map<String, dynamic> json) => RosterUpdate(
        id: json['id'] as String,
        userId: json['userId'] as String,
        operationType: OperationType.values[json['operationType'] as int],
        data: json['data'] as Map<String, dynamic>,
        timestamp: DateTime.parse(json['timestamp'] as String),
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

  RegularShiftSwap({
    required this.id,
    required this.fromPerson,
    required this.toPerson,
    required this.fromShift,
    required this.toShift,
    required this.startDate,
    this.endDate,
    this.isActive = true,
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
      );
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

// ============================================================================
// NEW MODELS FOR ADVANCED FEATURES
// ============================================================================

// Enums for new features
enum ShiftTemplateCategory {
  healthcare,
  retail,
  hospitality,
  manufacturing,
  education,
  custom,
}

enum ApprovalStatus {
  pending,
  approved,
  rejected,
  cancelled,
}

enum LeaveType {
  annual,
  sick,
  unpaid,
  compassionate,
  maternity,
  paternity,
  study,
  custom,
}

enum UserRole {
  admin,
  manager,
  staff,
  viewer,
}

enum Permission {
  viewRoster,
  editRoster,
  approveLeave,
  approveSwaps,
  manageStaff,
  viewReports,
  exportData,
  manageSettings,
  viewAuditLogs,
  managePermissions,
}

enum NotificationType {
  shiftChange,
  shiftReminder,
  swapRequest,
  swapApproval,
  leaveRequest,
  leaveApproval,
  announcement,
  payDay,
  certificationExpiry,
}

enum ExportFormat {
  pdf,
  excel,
  csv,
  json,
  ical,
}

enum ConflictType {
  overlappingShifts,
  insufficientRest,
  maxConsecutiveDays,
  unavailableStaff,
  underStaffed,
  overStaffed,
}

enum ConstraintType {
  maxConsecutiveDays,
  minRestHours,
  maxHoursPerWeek,
  maxNightShiftsPerWeek,
  minStaffPerShift,
  maxShiftsPerPeriod,
  fairnessDistribution,
}

enum CountryCode {
  uk,
  us,
  au,
  ca,
  nz,
  ie,
  de,
  fr,
  es,
  it,
}

// Shift Template
class ShiftTemplate {
  final String id;
  final String name;
  final String description;
  final ShiftTemplateCategory category;
  final List<List<String>> pattern; // Week pattern
  final int cycleLengthWeeks;
  final Map<String, dynamic>? metadata;
  final bool isBuiltIn;

  ShiftTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.pattern,
    required this.cycleLengthWeeks,
    this.metadata,
    this.isBuiltIn = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'category': category.index,
        'pattern': pattern,
        'cycleLengthWeeks': cycleLengthWeeks,
        'metadata': metadata,
        'isBuiltIn': isBuiltIn,
      };

  factory ShiftTemplate.fromJson(Map<String, dynamic> json) => ShiftTemplate(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String,
        category: ShiftTemplateCategory.values[json['category'] as int],
        pattern: (json['pattern'] as List<dynamic>)
            .map((e) => (e as List<dynamic>).map((s) => s as String).toList())
            .toList(),
        cycleLengthWeeks: json['cycleLengthWeeks'] as int,
        metadata: json['metadata'] as Map<String, dynamic>?,
        isBuiltIn: json['isBuiltIn'] as bool? ?? false,
      );
}

// Shift Swap Request
class ShiftSwapRequest {
  final String id;
  final String requesterId;
  final String requesterName;
  final String targetStaffId;
  final String targetStaffName;
  final DateTime shiftDate;
  final String shiftType;
  final String? reason;
  final ApprovalStatus status;
  final String? approverId;
  final String? approverName;
  final DateTime requestDate;
  final DateTime? responseDate;
  final String? responseNote;

  ShiftSwapRequest({
    required this.id,
    required this.requesterId,
    required this.requesterName,
    required this.targetStaffId,
    required this.targetStaffName,
    required this.shiftDate,
    required this.shiftType,
    this.reason,
    this.status = ApprovalStatus.pending,
    this.approverId,
    this.approverName,
    required this.requestDate,
    this.responseDate,
    this.responseNote,
  });

  ShiftSwapRequest copyWith({
    ApprovalStatus? status,
    String? approverId,
    String? approverName,
    DateTime? responseDate,
    String? responseNote,
  }) {
    return ShiftSwapRequest(
      id: id,
      requesterId: requesterId,
      requesterName: requesterName,
      targetStaffId: targetStaffId,
      targetStaffName: targetStaffName,
      shiftDate: shiftDate,
      shiftType: shiftType,
      reason: reason,
      status: status ?? this.status,
      approverId: approverId ?? this.approverId,
      approverName: approverName ?? this.approverName,
      requestDate: requestDate,
      responseDate: responseDate ?? this.responseDate,
      responseNote: responseNote ?? this.responseNote,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'requesterId': requesterId,
        'requesterName': requesterName,
        'targetStaffId': targetStaffId,
        'targetStaffName': targetStaffName,
        'shiftDate': shiftDate.toIso8601String(),
        'shiftType': shiftType,
        'reason': reason,
        'status': status.index,
        'approverId': approverId,
        'approverName': approverName,
        'requestDate': requestDate.toIso8601String(),
        'responseDate': responseDate?.toIso8601String(),
        'responseNote': responseNote,
      };

  factory ShiftSwapRequest.fromJson(Map<String, dynamic> json) =>
      ShiftSwapRequest(
        id: json['id'] as String,
        requesterId: json['requesterId'] as String,
        requesterName: json['requesterName'] as String,
        targetStaffId: json['targetStaffId'] as String,
        targetStaffName: json['targetStaffName'] as String,
        shiftDate: DateTime.parse(json['shiftDate'] as String),
        shiftType: json['shiftType'] as String,
        reason: json['reason'] as String?,
        status: ApprovalStatus.values[json['status'] as int? ?? 0],
        approverId: json['approverId'] as String?,
        approverName: json['approverName'] as String?,
        requestDate: DateTime.parse(json['requestDate'] as String),
        responseDate: json['responseDate'] != null
            ? DateTime.parse(json['responseDate'] as String)
            : null,
        responseNote: json['responseNote'] as String?,
      );
}

// Leave Request
class LeaveRequest {
  final String id;
  final String staffId;
  final String staffName;
  final LeaveType leaveType;
  final DateTime startDate;
  final DateTime endDate;
  final double daysRequested;
  final String? reason;
  final ApprovalStatus status;
  final String? approverId;
  final String? approverName;
  final DateTime requestDate;
  final DateTime? responseDate;
  final String? responseNote;
  final List<String>? attachments;

  LeaveRequest({
    required this.id,
    required this.staffId,
    required this.staffName,
    required this.leaveType,
    required this.startDate,
    required this.endDate,
    required this.daysRequested,
    this.reason,
    this.status = ApprovalStatus.pending,
    this.approverId,
    this.approverName,
    required this.requestDate,
    this.responseDate,
    this.responseNote,
    this.attachments,
  });

  LeaveRequest copyWith({
    ApprovalStatus? status,
    String? approverId,
    String? approverName,
    DateTime? responseDate,
    String? responseNote,
  }) {
    return LeaveRequest(
      id: id,
      staffId: staffId,
      staffName: staffName,
      leaveType: leaveType,
      startDate: startDate,
      endDate: endDate,
      daysRequested: daysRequested,
      reason: reason,
      status: status ?? this.status,
      approverId: approverId ?? this.approverId,
      approverName: approverName ?? this.approverName,
      requestDate: requestDate,
      responseDate: responseDate ?? this.responseDate,
      responseNote: responseNote ?? this.responseNote,
      attachments: attachments,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'staffId': staffId,
        'staffName': staffName,
        'leaveType': leaveType.index,
        'startDate': startDate.toIso8601String(),
        'endDate': endDate.toIso8601String(),
        'daysRequested': daysRequested,
        'reason': reason,
        'status': status.index,
        'approverId': approverId,
        'approverName': approverName,
        'requestDate': requestDate.toIso8601String(),
        'responseDate': responseDate?.toIso8601String(),
        'responseNote': responseNote,
        'attachments': attachments,
      };

  factory LeaveRequest.fromJson(Map<String, dynamic> json) => LeaveRequest(
        id: json['id'] as String,
        staffId: json['staffId'] as String,
        staffName: json['staffName'] as String,
        leaveType: LeaveType.values[json['leaveType'] as int? ?? 0],
        startDate: DateTime.parse(json['startDate'] as String),
        endDate: DateTime.parse(json['endDate'] as String),
        daysRequested: (json['daysRequested'] as num).toDouble(),
        reason: json['reason'] as String?,
        status: ApprovalStatus.values[json['status'] as int? ?? 0],
        approverId: json['approverId'] as String?,
        approverName: json['approverName'] as String?,
        requestDate: DateTime.parse(json['requestDate'] as String),
        responseDate: json['responseDate'] != null
            ? DateTime.parse(json['responseDate'] as String)
            : null,
        responseNote: json['responseNote'] as String?,
        attachments: (json['attachments'] as List<dynamic>?)
            ?.map((e) => e as String)
            .toList(),
      );
}

// Bank Holiday
class BankHoliday {
  final String id;
  final String name;
  final DateTime date;
  final CountryCode country;
  final bool isRecurring;
  final String? region; // For region-specific holidays

  BankHoliday({
    required this.id,
    required this.name,
    required this.date,
    required this.country,
    this.isRecurring = true,
    this.region,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'date': date.toIso8601String(),
        'country': country.index,
        'isRecurring': isRecurring,
        'region': region,
      };

  factory BankHoliday.fromJson(Map<String, dynamic> json) => BankHoliday(
        id: json['id'] as String,
        name: json['name'] as String,
        date: DateTime.parse(json['date'] as String),
        country: CountryCode.values[json['country'] as int],
        isRecurring: json['isRecurring'] as bool? ?? true,
        region: json['region'] as String?,
      );
}

// School Holiday
class SchoolHoliday {
  final String id;
  final String name;
  final DateTime startDate;
  final DateTime endDate;
  final CountryCode country;
  final String? region;
  final int year;

  SchoolHoliday({
    required this.id,
    required this.name,
    required this.startDate,
    required this.endDate,
    required this.country,
    this.region,
    required this.year,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'startDate': startDate.toIso8601String(),
        'endDate': endDate.toIso8601String(),
        'country': country.index,
        'region': region,
        'year': year,
      };

  factory SchoolHoliday.fromJson(Map<String, dynamic> json) => SchoolHoliday(
        id: json['id'] as String,
        name: json['name'] as String,
        startDate: DateTime.parse(json['startDate'] as String),
        endDate: DateTime.parse(json['endDate'] as String),
        country: CountryCode.values[json['country'] as int],
        region: json['region'] as String?,
        year: json['year'] as int,
      );
}

// Scheduling Constraint
class SchedulingConstraint {
  final String id;
  final ConstraintType type;
  final String name;
  final int value;
  final bool isActive;
  final List<String>? affectedStaff; // null means all staff
  final Map<String, dynamic>? metadata;

  SchedulingConstraint({
    required this.id,
    required this.type,
    required this.name,
    required this.value,
    this.isActive = true,
    this.affectedStaff,
    this.metadata,
  });

  SchedulingConstraint copyWith({
    bool? isActive,
    int? value,
  }) {
    return SchedulingConstraint(
      id: id,
      type: type,
      name: name,
      value: value ?? this.value,
      isActive: isActive ?? this.isActive,
      affectedStaff: affectedStaff,
      metadata: metadata,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.index,
        'name': name,
        'value': value,
        'isActive': isActive,
        'affectedStaff': affectedStaff,
        'metadata': metadata,
      };

  factory SchedulingConstraint.fromJson(Map<String, dynamic> json) =>
      SchedulingConstraint(
        id: json['id'] as String,
        type: ConstraintType.values[json['type'] as int],
        name: json['name'] as String,
        value: json['value'] as int,
        isActive: json['isActive'] as bool? ?? true,
        affectedStaff: (json['affectedStaff'] as List<dynamic>?)
            ?.map((e) => e as String)
            .toList(),
        metadata: json['metadata'] as Map<String, dynamic>?,
      );
}

// Roster Anomaly (for special cases like Christmas)
class RosterAnomaly {
  final String id;
  final String name;
  final String description;
  final DateTime startDate;
  final DateTime? endDate;
  final int cycleYears; // How many years before repeating
  final Map<String, List<String>> staffRotation; // Year offset -> staff list
  final bool isActive;
  final Map<String, dynamic>? rules;

  RosterAnomaly({
    required this.id,
    required this.name,
    required this.description,
    required this.startDate,
    this.endDate,
    this.cycleYears = 1,
    required this.staffRotation,
    this.isActive = true,
    this.rules,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'startDate': startDate.toIso8601String(),
        'endDate': endDate?.toIso8601String(),
        'cycleYears': cycleYears,
        'staffRotation': staffRotation,
        'isActive': isActive,
        'rules': rules,
      };

  factory RosterAnomaly.fromJson(Map<String, dynamic> json) => RosterAnomaly(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String,
        startDate: DateTime.parse(json['startDate'] as String),
        endDate: json['endDate'] != null
            ? DateTime.parse(json['endDate'] as String)
            : null,
        cycleYears: json['cycleYears'] as int? ?? 1,
        staffRotation: (json['staffRotation'] as Map<String, dynamic>).map(
          (k, v) =>
              MapEntry(k, (v as List<dynamic>).map((e) => e as String).toList()),
        ),
        isActive: json['isActive'] as bool? ?? true,
        rules: json['rules'] as Map<String, dynamic>?,
      );
}

// Labor Cost Settings
class LaborCostSettings {
  final String id;
  final Map<String, double> shiftRates; // Shift type -> hourly rate
  final double overtimeMultiplier;
  final double weekendMultiplier;
  final double holidayMultiplier;
  final double nightShiftMultiplier;
  final String currency;
  final DateTime lastUpdated;

  LaborCostSettings({
    required this.id,
    required this.shiftRates,
    this.overtimeMultiplier = 1.5,
    this.weekendMultiplier = 1.5,
    this.holidayMultiplier = 2.0,
    this.nightShiftMultiplier = 1.25,
    this.currency = 'GBP',
    required this.lastUpdated,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'shiftRates': shiftRates,
        'overtimeMultiplier': overtimeMultiplier,
        'weekendMultiplier': weekendMultiplier,
        'holidayMultiplier': holidayMultiplier,
        'nightShiftMultiplier': nightShiftMultiplier,
        'currency': currency,
        'lastUpdated': lastUpdated.toIso8601String(),
      };

  factory LaborCostSettings.fromJson(Map<String, dynamic> json) =>
      LaborCostSettings(
        id: json['id'] as String,
        shiftRates: (json['shiftRates'] as Map<String, dynamic>)
            .map((k, v) => MapEntry(k, (v as num).toDouble())),
        overtimeMultiplier:
            (json['overtimeMultiplier'] as num?)?.toDouble() ?? 1.5,
        weekendMultiplier:
            (json['weekendMultiplier'] as num?)?.toDouble() ?? 1.5,
        holidayMultiplier:
            (json['holidayMultiplier'] as num?)?.toDouble() ?? 2.0,
        nightShiftMultiplier:
            (json['nightShiftMultiplier'] as num?)?.toDouble() ?? 1.25,
        currency: json['currency'] as String? ?? 'GBP',
        lastUpdated: DateTime.parse(json['lastUpdated'] as String),
      );
}

// Pay Day
class PayDay {
  final String id;
  final DateTime date;
  final double? amount;
  final bool isRecurring;
  final String? frequency; // monthly, biweekly, weekly
  final bool notificationEnabled;

  PayDay({
    required this.id,
    required this.date,
    this.amount,
    this.isRecurring = true,
    this.frequency = 'monthly',
    this.notificationEnabled = true,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date.toIso8601String(),
        'amount': amount,
        'isRecurring': isRecurring,
        'frequency': frequency,
        'notificationEnabled': notificationEnabled,
      };

  factory PayDay.fromJson(Map<String, dynamic> json) => PayDay(
        id: json['id'] as String,
        date: DateTime.parse(json['date'] as String),
        amount: (json['amount'] as num?)?.toDouble(),
        isRecurring: json['isRecurring'] as bool? ?? true,
        frequency: json['frequency'] as String? ?? 'monthly',
        notificationEnabled: json['notificationEnabled'] as bool? ?? true,
      );
}

// User with Role
class AppUser {
  final String id;
  final String name;
  final String email;
  final UserRole role;
  final List<Permission> customPermissions;
  final bool isActive;
  final DateTime createdAt;
  final Map<String, dynamic>? metadata;

  AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.customPermissions = const [],
    this.isActive = true,
    required this.createdAt,
    this.metadata,
  });

  // Get effective permissions based on role + custom permissions
  List<Permission> getEffectivePermissions() {
    final rolePermissions = _getRolePermissions(role);
    return {...rolePermissions, ...customPermissions}.toList();
  }

  static List<Permission> _getRolePermissions(UserRole role) {
    switch (role) {
      case UserRole.admin:
        return Permission.values;
      case UserRole.manager:
        return [
          Permission.viewRoster,
          Permission.editRoster,
          Permission.approveLeave,
          Permission.approveSwaps,
          Permission.viewReports,
          Permission.exportData,
        ];
      case UserRole.staff:
        return [Permission.viewRoster];
      case UserRole.viewer:
        return [Permission.viewRoster, Permission.viewReports];
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'role': role.index,
        'customPermissions': customPermissions.map((p) => p.index).toList(),
        'isActive': isActive,
        'createdAt': createdAt.toIso8601String(),
        'metadata': metadata,
      };

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: json['id'] as String,
        name: json['name'] as String,
        email: json['email'] as String,
        role: UserRole.values[json['role'] as int? ?? 0],
        customPermissions: (json['customPermissions'] as List<dynamic>?)
                ?.map((e) => Permission.values[e as int])
                .toList() ??
            [],
        isActive: json['isActive'] as bool? ?? true,
        createdAt: DateTime.parse(json['createdAt'] as String),
        metadata: json['metadata'] as Map<String, dynamic>?,
      );
}

// Audit Log
class AuditLog {
  final String id;
  final String userId;
  final String userName;
  final String action;
  final String description;
  final DateTime timestamp;
  final Map<String, dynamic>? beforeData;
  final Map<String, dynamic>? afterData;
  final String? ipAddress;
  final String? deviceInfo;

  AuditLog({
    required this.id,
    required this.userId,
    required this.userName,
    required this.action,
    required this.description,
    required this.timestamp,
    this.beforeData,
    this.afterData,
    this.ipAddress,
    this.deviceInfo,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'userId': userId,
        'userName': userName,
        'action': action,
        'description': description,
        'timestamp': timestamp.toIso8601String(),
        'beforeData': beforeData,
        'afterData': afterData,
        'ipAddress': ipAddress,
        'deviceInfo': deviceInfo,
      };

  factory AuditLog.fromJson(Map<String, dynamic> json) => AuditLog(
        id: json['id'] as String,
        userId: json['userId'] as String,
        userName: json['userName'] as String,
        action: json['action'] as String,
        description: json['description'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
        beforeData: json['beforeData'] as Map<String, dynamic>?,
        afterData: json['afterData'] as Map<String, dynamic>?,
        ipAddress: json['ipAddress'] as String?,
        deviceInfo: json['deviceInfo'] as String?,
      );
}

// Roster Version (for version history)
class RosterVersion {
  final String id;
  final String versionNumber;
  final DateTime timestamp;
  final String userId;
  final String userName;
  final String changeDescription;
  final Map<String, dynamic> rosterData;
  final bool canRestore;

  RosterVersion({
    required this.id,
    required this.versionNumber,
    required this.timestamp,
    required this.userId,
    required this.userName,
    required this.changeDescription,
    required this.rosterData,
    this.canRestore = true,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'versionNumber': versionNumber,
        'timestamp': timestamp.toIso8601String(),
        'userId': userId,
        'userName': userName,
        'changeDescription': changeDescription,
        'rosterData': rosterData,
        'canRestore': canRestore,
      };

  factory RosterVersion.fromJson(Map<String, dynamic> json) => RosterVersion(
        id: json['id'] as String,
        versionNumber: json['versionNumber'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
        userId: json['userId'] as String,
        userName: json['userName'] as String,
        changeDescription: json['changeDescription'] as String,
        rosterData: json['rosterData'] as Map<String, dynamic>,
        canRestore: json['canRestore'] as bool? ?? true,
      );
}

// Feature Flag
class FeatureFlag {
  final String id;
  final String name;
  final String description;
  final bool isEnabled;
  final double rolloutPercentage; // 0.0 to 1.0
  final List<String>? enabledForUsers;
  final DateTime? enabledUntil;
  final Map<String, dynamic>? config;

  FeatureFlag({
    required this.id,
    required this.name,
    required this.description,
    this.isEnabled = false,
    this.rolloutPercentage = 0.0,
    this.enabledForUsers,
    this.enabledUntil,
    this.config,
  });

  bool isEnabledForUser(String userId) {
    if (!isEnabled) return false;
    if (enabledUntil != null && DateTime.now().isAfter(enabledUntil!)) {
      return false;
    }
    if (enabledForUsers != null && enabledForUsers!.contains(userId)) {
      return true;
    }
    // Simple hash-based rollout
    final hash = userId.hashCode.abs();
    return (hash % 100) / 100.0 < rolloutPercentage;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'isEnabled': isEnabled,
        'rolloutPercentage': rolloutPercentage,
        'enabledForUsers': enabledForUsers,
        'enabledUntil': enabledUntil?.toIso8601String(),
        'config': config,
      };

  factory FeatureFlag.fromJson(Map<String, dynamic> json) => FeatureFlag(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String,
        isEnabled: json['isEnabled'] as bool? ?? false,
        rolloutPercentage: (json['rolloutPercentage'] as num?)?.toDouble() ?? 0.0,
        enabledForUsers: (json['enabledForUsers'] as List<dynamic>?)
            ?.map((e) => e as String)
            .toList(),
        enabledUntil: json['enabledUntil'] != null
            ? DateTime.parse(json['enabledUntil'] as String)
            : null,
        config: json['config'] as Map<String, dynamic>?,
      );
}

// Notification Preference
class NotificationPreference {
  final String id;
  final String userId;
  final Map<NotificationType, bool> enabledTypes;
  final bool pushEnabled;
  final bool emailEnabled;
  final bool smsEnabled;
  final int reminderHoursBefore;

  NotificationPreference({
    required this.id,
    required this.userId,
    required this.enabledTypes,
    this.pushEnabled = true,
    this.emailEnabled = false,
    this.smsEnabled = false,
    this.reminderHoursBefore = 24,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'userId': userId,
        'enabledTypes':
            enabledTypes.map((k, v) => MapEntry(k.index.toString(), v)),
        'pushEnabled': pushEnabled,
        'emailEnabled': emailEnabled,
        'smsEnabled': smsEnabled,
        'reminderHoursBefore': reminderHoursBefore,
      };

  factory NotificationPreference.fromJson(Map<String, dynamic> json) =>
      NotificationPreference(
        id: json['id'] as String,
        userId: json['userId'] as String,
        enabledTypes: (json['enabledTypes'] as Map<String, dynamic>).map(
          (k, v) => MapEntry(NotificationType.values[int.parse(k)], v as bool),
        ),
        pushEnabled: json['pushEnabled'] as bool? ?? true,
        emailEnabled: json['emailEnabled'] as bool? ?? false,
        smsEnabled: json['smsEnabled'] as bool? ?? false,
        reminderHoursBefore: json['reminderHoursBefore'] as int? ?? 24,
      );
}

// Pattern Conflict
class PatternConflict {
  final String id;
  final ConflictType type;
  final String description;
  final DateTime date;
  final List<String> affectedStaff;
  final String? suggestedResolution;
  final bool isResolved;

  PatternConflict({
    required this.id,
    required this.type,
    required this.description,
    required this.date,
    required this.affectedStaff,
    this.suggestedResolution,
    this.isResolved = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.index,
        'description': description,
        'date': date.toIso8601String(),
        'affectedStaff': affectedStaff,
        'suggestedResolution': suggestedResolution,
        'isResolved': isResolved,
      };

  factory PatternConflict.fromJson(Map<String, dynamic> json) =>
      PatternConflict(
        id: json['id'] as String,
        type: ConflictType.values[json['type'] as int],
        description: json['description'] as String,
        date: DateTime.parse(json['date'] as String),
        affectedStaff: (json['affectedStaff'] as List<dynamic>)
            .map((e) => e as String)
            .toList(),
        suggestedResolution: json['suggestedResolution'] as String?,
        isResolved: json['isResolved'] as bool? ?? false,
      );
}
