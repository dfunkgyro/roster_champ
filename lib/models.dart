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
