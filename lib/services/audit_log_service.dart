import 'package:uuid/uuid.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';
import '../models.dart';

/// Service for creating and managing audit logs
class AuditLogService {
  static final AuditLogService instance = AuditLogService._internal();
  AuditLogService._internal();

  final _uuid = const Uuid();
  final _deviceInfo = DeviceInfoPlugin();

  String? _cachedDeviceInfo;
  String? _cachedIpAddress;

  /// Log a roster change
  Future<AuditLog> logRosterChange({
    required String userId,
    required String userName,
    required String action,
    required String description,
    Map<String, dynamic>? beforeData,
    Map<String, dynamic>? afterData,
  }) async {
    final deviceInfo = await _getDeviceInfo();
    final ipAddress = await _getIpAddress();

    return AuditLog(
      id: _uuid.v4(),
      userId: userId,
      userName: userName,
      action: action,
      description: description,
      timestamp: DateTime.now(),
      beforeData: beforeData,
      afterData: afterData,
      ipAddress: ipAddress,
      deviceInfo: deviceInfo,
    );
  }

  /// Log staff addition
  Future<AuditLog> logStaffAdded({
    required String userId,
    required String userName,
    required StaffMember staff,
  }) async {
    return await logRosterChange(
      userId: userId,
      userName: userName,
      action: 'STAFF_ADDED',
      description: 'Added staff member: ${staff.name}',
      afterData: staff.toJson(),
    );
  }

  /// Log staff removal
  Future<AuditLog> logStaffRemoved({
    required String userId,
    required String userName,
    required StaffMember staff,
  }) async {
    return await logRosterChange(
      userId: userId,
      userName: userName,
      action: 'STAFF_REMOVED',
      description: 'Removed staff member: ${staff.name}',
      beforeData: staff.toJson(),
    );
  }

  /// Log staff modification
  Future<AuditLog> logStaffModified({
    required String userId,
    required String userName,
    required StaffMember before,
    required StaffMember after,
  }) async {
    return await logRosterChange(
      userId: userId,
      userName: userName,
      action: 'STAFF_MODIFIED',
      description: 'Modified staff member: ${after.name}',
      beforeData: before.toJson(),
      afterData: after.toJson(),
    );
  }

  /// Log shift change
  Future<AuditLog> logShiftChange({
    required String userId,
    required String userName,
    required String staffName,
    required DateTime date,
    required String oldShift,
    required String newShift,
  }) async {
    return await logRosterChange(
      userId: userId,
      userName: userName,
      action: 'SHIFT_CHANGED',
      description:
          'Changed shift for $staffName on ${_formatDate(date)} from $oldShift to $newShift',
      beforeData: {'staff': staffName, 'date': date.toIso8601String(), 'shift': oldShift},
      afterData: {'staff': staffName, 'date': date.toIso8601String(), 'shift': newShift},
    );
  }

  /// Log leave approval
  Future<AuditLog> logLeaveApproval({
    required String userId,
    required String userName,
    required LeaveRequest request,
    required bool approved,
  }) async {
    return await logRosterChange(
      userId: userId,
      userName: userName,
      action: approved ? 'LEAVE_APPROVED' : 'LEAVE_REJECTED',
      description:
          '${approved ? "Approved" : "Rejected"} leave request for ${request.staffName}',
      afterData: request.toJson(),
    );
  }

  /// Log swap approval
  Future<AuditLog> logSwapApproval({
    required String userId,
    required String userName,
    required ShiftSwapRequest request,
    required bool approved,
  }) async {
    return await logRosterChange(
      userId: userId,
      userName: userName,
      action: approved ? 'SWAP_APPROVED' : 'SWAP_REJECTED',
      description:
          '${approved ? "Approved" : "Rejected"} shift swap between ${request.requesterName} and ${request.targetStaffName}',
      afterData: request.toJson(),
    );
  }

  /// Log settings change
  Future<AuditLog> logSettingsChange({
    required String userId,
    required String userName,
    required String settingName,
    required dynamic oldValue,
    required dynamic newValue,
  }) async {
    return await logRosterChange(
      userId: userId,
      userName: userName,
      action: 'SETTINGS_CHANGED',
      description: 'Changed setting: $settingName',
      beforeData: {'setting': settingName, 'value': oldValue},
      afterData: {'setting': settingName, 'value': newValue},
    );
  }

  /// Log data export
  Future<AuditLog> logDataExport({
    required String userId,
    required String userName,
    required ExportFormat format,
    required String description,
  }) async {
    return await logRosterChange(
      userId: userId,
      userName: userName,
      action: 'DATA_EXPORTED',
      description: 'Exported data: $description',
      afterData: {'format': format.name, 'description': description},
    );
  }

  /// Log data import
  Future<AuditLog> logDataImport({
    required String userId,
    required String userName,
    required String description,
  }) async {
    return await logRosterChange(
      userId: userId,
      userName: userName,
      action: 'DATA_IMPORTED',
      description: 'Imported data: $description',
      afterData: {'description': description},
    );
  }

  /// Log roster version save
  Future<AuditLog> logVersionSaved({
    required String userId,
    required String userName,
    required String versionNumber,
    required String changeDescription,
  }) async {
    return await logRosterChange(
      userId: userId,
      userName: userName,
      action: 'VERSION_SAVED',
      description: 'Saved roster version $versionNumber: $changeDescription',
      afterData: {
        'version': versionNumber,
        'description': changeDescription,
      },
    );
  }

  /// Log roster version restore
  Future<AuditLog> logVersionRestored({
    required String userId,
    required String userName,
    required String versionNumber,
  }) async {
    return await logRosterChange(
      userId: userId,
      userName: userName,
      action: 'VERSION_RESTORED',
      description: 'Restored roster to version $versionNumber',
      afterData: {'version': versionNumber},
    );
  }

  /// Log user login
  Future<AuditLog> logUserLogin({
    required String userId,
    required String userName,
  }) async {
    return await logRosterChange(
      userId: userId,
      userName: userName,
      action: 'USER_LOGIN',
      description: '$userName logged in',
    );
  }

  /// Log user logout
  Future<AuditLog> logUserLogout({
    required String userId,
    required String userName,
  }) async {
    return await logRosterChange(
      userId: userId,
      userName: userName,
      action: 'USER_LOGOUT',
      description: '$userName logged out',
    );
  }

  /// Filter audit logs by criteria
  List<AuditLog> filterLogs({
    required List<AuditLog> logs,
    String? userId,
    String? action,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    return logs.where((log) {
      if (userId != null && log.userId != userId) return false;
      if (action != null && log.action != action) return false;
      if (startDate != null && log.timestamp.isBefore(startDate)) return false;
      if (endDate != null && log.timestamp.isAfter(endDate)) return false;
      return true;
    }).toList();
  }

  /// Get audit log statistics
  Map<String, dynamic> getLogStatistics(List<AuditLog> logs) {
    final actionCounts = <String, int>{};
    final userCounts = <String, int>{};

    for (final log in logs) {
      actionCounts[log.action] = (actionCounts[log.action] ?? 0) + 1;
      userCounts[log.userName] = (userCounts[log.userName] ?? 0) + 1;
    }

    return {
      'total_logs': logs.length,
      'actions': actionCounts,
      'users': userCounts,
      'date_range': {
        'earliest': logs.isEmpty
            ? null
            : logs.map((l) => l.timestamp).reduce((a, b) => a.isBefore(b) ? a : b),
        'latest': logs.isEmpty
            ? null
            : logs.map((l) => l.timestamp).reduce((a, b) => a.isAfter(b) ? a : b),
      },
    };
  }

  /// Get recent activity
  List<AuditLog> getRecentActivity(
    List<AuditLog> logs, {
    int limit = 20,
  }) {
    final sorted = List<AuditLog>.from(logs)
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return sorted.take(limit).toList();
  }

  /// Get user activity
  List<AuditLog> getUserActivity(
    List<AuditLog> logs,
    String userId,
  ) {
    return logs
        .where((log) => log.userId == userId)
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  /// Search audit logs
  List<AuditLog> searchLogs(
    List<AuditLog> logs,
    String query,
  ) {
    final lowerQuery = query.toLowerCase();
    return logs.where((log) {
      return log.action.toLowerCase().contains(lowerQuery) ||
          log.description.toLowerCase().contains(lowerQuery) ||
          log.userName.toLowerCase().contains(lowerQuery);
    }).toList();
  }

  /// Get device info
  Future<String> _getDeviceInfo() async {
    if (_cachedDeviceInfo != null) return _cachedDeviceInfo!;

    try {
      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        _cachedDeviceInfo =
            'Android ${androidInfo.version.release} (${androidInfo.model})';
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        _cachedDeviceInfo = 'iOS ${iosInfo.systemVersion} (${iosInfo.model})';
      } else if (Platform.isLinux) {
        final linuxInfo = await _deviceInfo.linuxInfo;
        _cachedDeviceInfo = 'Linux ${linuxInfo.prettyName}';
      } else if (Platform.isMacOS) {
        final macInfo = await _deviceInfo.macOsInfo;
        _cachedDeviceInfo = 'macOS ${macInfo.osRelease}';
      } else if (Platform.isWindows) {
        final windowsInfo = await _deviceInfo.windowsInfo;
        _cachedDeviceInfo = 'Windows ${windowsInfo.productName}';
      } else {
        _cachedDeviceInfo = 'Unknown Platform';
      }
    } catch (e) {
      _cachedDeviceInfo = 'Unknown Device';
    }

    return _cachedDeviceInfo!;
  }

  /// Get IP address (simplified - would need network package for real implementation)
  Future<String?> _getIpAddress() async {
    if (_cachedIpAddress != null) return _cachedIpAddress;

    try {
      // In a real implementation, you would use a network package
      // to get the actual IP address
      _cachedIpAddress = 'N/A';
    } catch (e) {
      _cachedIpAddress = null;
    }

    return _cachedIpAddress;
  }

  /// Format date for display
  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  /// Export audit logs to CSV
  String exportToCSV(List<AuditLog> logs) {
    final buffer = StringBuffer();

    // Header
    buffer.writeln('Timestamp,User,Action,Description,IP Address,Device');

    // Data rows
    for (final log in logs) {
      final timestamp = log.timestamp.toIso8601String();
      final user = log.userName.replaceAll(',', ';');
      final action = log.action.replaceAll(',', ';');
      final description = log.description.replaceAll(',', ';');
      final ip = log.ipAddress ?? 'N/A';
      final device = (log.deviceInfo ?? 'N/A').replaceAll(',', ';');

      buffer.writeln('$timestamp,$user,$action,$description,$ip,$device');
    }

    return buffer.toString();
  }

  /// Get action display name
  String getActionDisplayName(String action) {
    switch (action) {
      case 'STAFF_ADDED':
        return 'Staff Added';
      case 'STAFF_REMOVED':
        return 'Staff Removed';
      case 'STAFF_MODIFIED':
        return 'Staff Modified';
      case 'SHIFT_CHANGED':
        return 'Shift Changed';
      case 'LEAVE_APPROVED':
        return 'Leave Approved';
      case 'LEAVE_REJECTED':
        return 'Leave Rejected';
      case 'SWAP_APPROVED':
        return 'Swap Approved';
      case 'SWAP_REJECTED':
        return 'Swap Rejected';
      case 'SETTINGS_CHANGED':
        return 'Settings Changed';
      case 'DATA_EXPORTED':
        return 'Data Exported';
      case 'DATA_IMPORTED':
        return 'Data Imported';
      case 'VERSION_SAVED':
        return 'Version Saved';
      case 'VERSION_RESTORED':
        return 'Version Restored';
      case 'USER_LOGIN':
        return 'User Login';
      case 'USER_LOGOUT':
        return 'User Logout';
      default:
        return action;
    }
  }
}
