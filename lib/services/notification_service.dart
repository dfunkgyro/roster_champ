import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import '../models.dart';

/// Service for managing notifications and reminders
class NotificationService {
  static final NotificationService instance = NotificationService._internal();
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  /// Initialize the notification service
  Future<void> initialize() async {
    if (_initialized) return;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    _initialized = true;
  }

  /// Handle notification tap
  void _onNotificationTapped(NotificationResponse response) {
    // Handle notification tap
    // This can be expanded to navigate to specific screens
  }

  /// Request notification permissions
  Future<bool> requestPermissions() async {
    final android = await _notificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    final ios = await _notificationsPlugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );

    return android ?? ios ?? false;
  }

  /// Show immediate notification
  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
    NotificationType type = NotificationType.announcement,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      _getChannelId(type),
      _getChannelName(type),
      channelDescription: _getChannelDescription(type),
      importance: _getImportance(type),
      priority: _getPriority(type),
      icon: '@mipmap/ic_launcher',
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notificationsPlugin.show(
      id,
      title,
      body,
      details,
      payload: payload,
    );
  }

  /// Schedule a notification for a future time
  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
    String? payload,
    NotificationType type = NotificationType.shiftReminder,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      _getChannelId(type),
      _getChannelName(type),
      channelDescription: _getChannelDescription(type),
      importance: _getImportance(type),
      priority: _getPriority(type),
      icon: '@mipmap/ic_launcher',
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notificationsPlugin.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(scheduledDate, tz.local),
      details,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: payload,
    );
  }

  /// Schedule shift reminder
  Future<void> scheduleShiftReminder({
    required String staffName,
    required DateTime shiftDate,
    required String shiftType,
    required int hoursBeforeShift,
  }) async {
    final reminderTime = shiftDate.subtract(Duration(hours: hoursBeforeShift));

    // Only schedule if in the future
    if (reminderTime.isAfter(DateTime.now())) {
      await scheduleNotification(
        id: shiftDate.millisecondsSinceEpoch ~/ 1000,
        title: 'Upcoming Shift Reminder',
        body:
            'You have a $shiftType shift in $hoursBeforeShift hours on ${_formatDate(shiftDate)}',
        scheduledDate: reminderTime,
        type: NotificationType.shiftReminder,
      );
    }
  }

  /// Notify about shift change
  Future<void> notifyShiftChange({
    required String staffName,
    required DateTime shiftDate,
    required String oldShift,
    required String newShift,
  }) async {
    await showNotification(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: 'Shift Change',
      body:
          'Your shift on ${_formatDate(shiftDate)} has been changed from $oldShift to $newShift',
      type: NotificationType.shiftChange,
    );
  }

  /// Notify about shift swap request
  Future<void> notifyShiftSwapRequest({
    required String requesterName,
    required String targetName,
    required DateTime shiftDate,
    required String shiftType,
  }) async {
    await showNotification(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: 'Shift Swap Request',
      body:
          '$requesterName wants to swap their $shiftType shift on ${_formatDate(shiftDate)} with you',
      type: NotificationType.swapRequest,
    );
  }

  /// Notify about shift swap approval
  Future<void> notifyShiftSwapApproval({
    required String staffName,
    required DateTime shiftDate,
    required bool approved,
  }) async {
    await showNotification(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: approved ? 'Shift Swap Approved' : 'Shift Swap Rejected',
      body: approved
          ? 'Your shift swap request for ${_formatDate(shiftDate)} has been approved'
          : 'Your shift swap request for ${_formatDate(shiftDate)} has been rejected',
      type: NotificationType.swapApproval,
    );
  }

  /// Notify about leave request
  Future<void> notifyLeaveRequest({
    required String requesterName,
    required DateTime startDate,
    required DateTime endDate,
    required double days,
  }) async {
    await showNotification(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: 'New Leave Request',
      body:
          '$requesterName has requested $days days leave from ${_formatDate(startDate)} to ${_formatDate(endDate)}',
      type: NotificationType.leaveRequest,
    );
  }

  /// Notify about leave approval
  Future<void> notifyLeaveApproval({
    required String staffName,
    required DateTime startDate,
    required DateTime endDate,
    required bool approved,
  }) async {
    await showNotification(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: approved ? 'Leave Approved' : 'Leave Rejected',
      body: approved
          ? 'Your leave request from ${_formatDate(startDate)} to ${_formatDate(endDate)} has been approved'
          : 'Your leave request from ${_formatDate(startDate)} to ${_formatDate(endDate)} has been rejected',
      type: NotificationType.leaveApproval,
    );
  }

  /// Schedule pay day reminder
  Future<void> schedulePayDayReminder({
    required DateTime payDate,
    required double? amount,
    required int daysBefore,
  }) async {
    final reminderDate = payDate.subtract(Duration(days: daysBefore));

    if (reminderDate.isAfter(DateTime.now())) {
      final body = amount != null
          ? 'Your pay day is in $daysBefore days. Expected amount: £${amount.toStringAsFixed(2)}'
          : 'Your pay day is in $daysBefore days';

      await scheduleNotification(
        id: payDate.millisecondsSinceEpoch ~/ 1000,
        title: 'Pay Day Reminder',
        body: body,
        scheduledDate: reminderDate,
        type: NotificationType.payDay,
      );
    }
  }

  /// Send announcement to all staff
  Future<void> sendAnnouncement({
    required String title,
    required String message,
  }) async {
    await showNotification(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: title,
      body: message,
      type: NotificationType.announcement,
    );
  }

  /// Cancel a specific notification
  Future<void> cancelNotification(int id) async {
    await _notificationsPlugin.cancel(id);
  }

  /// Cancel all notifications
  Future<void> cancelAllNotifications() async {
    await _notificationsPlugin.cancelAll();
  }

  /// Get pending notifications
  Future<List<PendingNotificationRequest>> getPendingNotifications() async {
    return await _notificationsPlugin.pendingNotificationRequests();
  }

  /// Helper methods for channel configuration

  String _getChannelId(NotificationType type) {
    switch (type) {
      case NotificationType.shiftChange:
        return 'shift_changes';
      case NotificationType.shiftReminder:
        return 'shift_reminders';
      case NotificationType.swapRequest:
        return 'swap_requests';
      case NotificationType.swapApproval:
        return 'swap_approvals';
      case NotificationType.leaveRequest:
        return 'leave_requests';
      case NotificationType.leaveApproval:
        return 'leave_approvals';
      case NotificationType.announcement:
        return 'announcements';
      case NotificationType.payDay:
        return 'pay_days';
      case NotificationType.certificationExpiry:
        return 'certification_expiry';
    }
  }

  String _getChannelName(NotificationType type) {
    switch (type) {
      case NotificationType.shiftChange:
        return 'Shift Changes';
      case NotificationType.shiftReminder:
        return 'Shift Reminders';
      case NotificationType.swapRequest:
        return 'Shift Swap Requests';
      case NotificationType.swapApproval:
        return 'Shift Swap Approvals';
      case NotificationType.leaveRequest:
        return 'Leave Requests';
      case NotificationType.leaveApproval:
        return 'Leave Approvals';
      case NotificationType.announcement:
        return 'Announcements';
      case NotificationType.payDay:
        return 'Pay Day Reminders';
      case NotificationType.certificationExpiry:
        return 'Certification Expiry';
    }
  }

  String _getChannelDescription(NotificationType type) {
    switch (type) {
      case NotificationType.shiftChange:
        return 'Notifications about changes to your shifts';
      case NotificationType.shiftReminder:
        return 'Reminders about upcoming shifts';
      case NotificationType.swapRequest:
        return 'Requests to swap shifts with colleagues';
      case NotificationType.swapApproval:
        return 'Approvals or rejections of shift swap requests';
      case NotificationType.leaveRequest:
        return 'New leave requests requiring approval';
      case NotificationType.leaveApproval:
        return 'Approvals or rejections of leave requests';
      case NotificationType.announcement:
        return 'Important announcements and updates';
      case NotificationType.payDay:
        return 'Reminders about upcoming pay days';
      case NotificationType.certificationExpiry:
        return 'Alerts about expiring certifications';
    }
  }

  Importance _getImportance(NotificationType type) {
    switch (type) {
      case NotificationType.shiftChange:
      case NotificationType.swapRequest:
      case NotificationType.leaveRequest:
        return Importance.high;
      case NotificationType.shiftReminder:
      case NotificationType.payDay:
        return Importance.defaultImportance;
      case NotificationType.swapApproval:
      case NotificationType.leaveApproval:
      case NotificationType.announcement:
        return Importance.high;
      case NotificationType.certificationExpiry:
        return Importance.max;
    }
  }

  Priority _getPriority(NotificationType type) {
    switch (type) {
      case NotificationType.shiftChange:
      case NotificationType.swapRequest:
      case NotificationType.leaveRequest:
        return Priority.high;
      case NotificationType.shiftReminder:
      case NotificationType.payDay:
        return Priority.defaultPriority;
      case NotificationType.swapApproval:
      case NotificationType.leaveApproval:
      case NotificationType.announcement:
        return Priority.high;
      case NotificationType.certificationExpiry:
        return Priority.max;
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  /// Check if notifications are enabled for a specific type
  bool isNotificationEnabled(
    NotificationPreference? preferences,
    NotificationType type,
  ) {
    if (preferences == null) return true;
    return preferences.enabledTypes[type] ?? true;
  }

  /// Schedule reminders for upcoming week
  Future<void> scheduleWeeklyReminders({
    required String staffName,
    required Map<DateTime, String> weekSchedule,
    required int hoursBeforeShift,
  }) async {
    for (final entry in weekSchedule.entries) {
      final date = entry.key;
      final shift = entry.value;

      if (shift != 'OFF' && shift != 'L') {
        await scheduleShiftReminder(
          staffName: staffName,
          shiftDate: date,
          shiftType: shift,
          hoursBeforeShift: hoursBeforeShift,
        );
      }
    }
  }

  /// Batch schedule pay day reminders
  Future<void> schedulePayDayReminders({
    required List<PayDay> payDays,
    required List<int> reminderDaysBefore,
  }) async {
    for (final payDay in payDays) {
      if (payDay.notificationEnabled) {
        for (final daysBefore in reminderDaysBefore) {
          await schedulePayDayReminder(
            payDate: payDay.date,
            amount: payDay.amount,
            daysBefore: daysBefore,
          );
        }
      }
    }
  }
}
