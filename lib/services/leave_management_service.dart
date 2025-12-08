import 'package:uuid/uuid.dart';
import '../models.dart';

/// Service for managing leave requests, balances, and predictions
class LeaveManagementService {
  static final LeaveManagementService instance =
      LeaveManagementService._internal();
  LeaveManagementService._internal();

  final _uuid = const Uuid();

  /// Calculate the number of working days between two dates
  int calculateWorkingDays(DateTime startDate, DateTime endDate) {
    int workingDays = 0;
    DateTime current = startDate;

    while (!current.isAfter(endDate)) {
      // Skip weekends (Saturday and Sunday)
      if (current.weekday != DateTime.saturday &&
          current.weekday != DateTime.sunday) {
        workingDays++;
      }
      current = current.add(const Duration(days: 1));
    }

    return workingDays;
  }

  /// Calculate leave days excluding weekends and bank holidays
  double calculateLeaveDays(
    DateTime startDate,
    DateTime endDate, {
    CountryCode? country,
    List<BankHoliday>? customHolidays,
  }) {
    int workingDays = calculateWorkingDays(startDate, endDate);

    // If country is provided, subtract bank holidays
    if (country != null) {
      final holidays = customHolidays ?? [];
      for (final holiday in holidays) {
        if (!holiday.date.isBefore(startDate) &&
            !holiday.date.isAfter(endDate)) {
          // Only subtract if it's a weekday
          if (holiday.date.weekday != DateTime.saturday &&
              holiday.date.weekday != DateTime.sunday) {
            workingDays--;
          }
        }
      }
    }

    return workingDays.toDouble();
  }

  /// Create a new leave request
  LeaveRequest createLeaveRequest({
    required String staffId,
    required String staffName,
    required LeaveType leaveType,
    required DateTime startDate,
    required DateTime endDate,
    String? reason,
    List<String>? attachments,
    CountryCode? country,
    List<BankHoliday>? customHolidays,
  }) {
    final daysRequested = calculateLeaveDays(
      startDate,
      endDate,
      country: country,
      customHolidays: customHolidays,
    );

    return LeaveRequest(
      id: _uuid.v4(),
      staffId: staffId,
      staffName: staffName,
      leaveType: leaveType,
      startDate: startDate,
      endDate: endDate,
      daysRequested: daysRequested,
      reason: reason,
      requestDate: DateTime.now(),
      attachments: attachments,
    );
  }

  /// Approve a leave request
  LeaveRequest approveLeaveRequest(
    LeaveRequest request,
    String approverId,
    String approverName, {
    String? note,
  }) {
    return request.copyWith(
      status: ApprovalStatus.approved,
      approverId: approverId,
      approverName: approverName,
      responseDate: DateTime.now(),
      responseNote: note,
    );
  }

  /// Reject a leave request
  LeaveRequest rejectLeaveRequest(
    LeaveRequest request,
    String approverId,
    String approverName,
    String reason,
  ) {
    return request.copyWith(
      status: ApprovalStatus.rejected,
      approverId: approverId,
      approverName: approverName,
      responseDate: DateTime.now(),
      responseNote: reason,
    );
  }

  /// Calculate remaining leave balance after a request
  double calculateRemainingBalance(
    double currentBalance,
    List<LeaveRequest> approvedRequests,
  ) {
    double used = 0;
    for (final request in approvedRequests) {
      if (request.status == ApprovalStatus.approved &&
          request.leaveType == LeaveType.annual) {
        used += request.daysRequested;
      }
    }
    return currentBalance - used;
  }

  /// Forecast future leave balance
  Map<String, dynamic> forecastLeaveBalance({
    required double currentBalance,
    required List<LeaveRequest> pendingRequests,
    required List<LeaveRequest> approvedRequests,
    required DateTime forecastDate,
    double annualAccrualRate = 2.583, // ~31 days per year
  }) {
    // Calculate used leave
    double usedLeave = 0;
    for (final request in approvedRequests) {
      if (request.status == ApprovalStatus.approved &&
          request.leaveType == LeaveType.annual) {
        usedLeave += request.daysRequested;
      }
    }

    // Calculate potential leave if pending approved
    double pendingLeave = 0;
    for (final request in pendingRequests) {
      if (request.status == ApprovalStatus.pending &&
          request.leaveType == LeaveType.annual) {
        pendingLeave += request.daysRequested;
      }
    }

    // Calculate accrued leave to forecast date
    final now = DateTime.now();
    final monthsUntilForecast = forecastDate.difference(now).inDays / 30.0;
    final accruedLeave = monthsUntilForecast * annualAccrualRate;

    return {
      'current_balance': currentBalance,
      'used_leave': usedLeave,
      'pending_leave': pendingLeave,
      'accrued_by_forecast': accruedLeave,
      'projected_balance':
          currentBalance - usedLeave + accruedLeave - pendingLeave,
      'projected_balance_if_pending_approved':
          currentBalance - usedLeave + accruedLeave - pendingLeave,
      'forecast_date': forecastDate,
    };
  }

  /// Detect leave clashes (too many staff on leave at the same time)
  List<Map<String, dynamic>> detectLeaveClashes({
    required List<LeaveRequest> allRequests,
    required int totalStaff,
    double maxConcurrentLeavePercentage = 0.25, // 25% max
  }) {
    final clashes = <Map<String, dynamic>>[];

    // Group requests by date ranges
    final dateRanges = <DateTime, List<LeaveRequest>>{};

    for (final request in allRequests) {
      if (request.status == ApprovalStatus.approved ||
          request.status == ApprovalStatus.pending) {
        DateTime current = request.startDate;
        while (!current.isAfter(request.endDate)) {
          dateRanges.putIfAbsent(current, () => []).add(request);
          current = current.add(const Duration(days: 1));
        }
      }
    }

    // Check each date for clashes
    dateRanges.forEach((date, requests) {
      final uniqueStaff = requests.map((r) => r.staffId).toSet().length;
      final percentage = uniqueStaff / totalStaff;

      if (percentage > maxConcurrentLeavePercentage) {
        clashes.add({
          'date': date,
          'staff_count': uniqueStaff,
          'percentage': percentage,
          'affected_staff': requests.map((r) => r.staffName).toSet().toList(),
          'severity': percentage > 0.5 ? 'critical' : 'warning',
        });
      }
    });

    return clashes;
  }

  /// AI-powered leave prediction
  /// Predicts likely leave requests based on historical patterns
  List<Map<String, dynamic>> predictLikelyLeave({
    required List<LeaveRequest> historicalRequests,
    required List<String> staffMembers,
    required DateTime startDate,
    required DateTime endDate,
  }) {
    final predictions = <Map<String, dynamic>>[];

    // Analyze historical patterns for each staff member
    for (final staff in staffMembers) {
      final staffHistory = historicalRequests
          .where((r) => r.staffName == staff && r.status == ApprovalStatus.approved)
          .toList();

      if (staffHistory.isEmpty) continue;

      // Find patterns (e.g., same time every year, frequency)
      final monthlyFrequency = <int, int>{};
      double avgDaysRequested = 0;

      for (final request in staffHistory) {
        final month = request.startDate.month;
        monthlyFrequency[month] = (monthlyFrequency[month] ?? 0) + 1;
        avgDaysRequested += request.daysRequested;
      }

      avgDaysRequested /= staffHistory.length;

      // Identify high-probability months
      final maxFrequency = monthlyFrequency.values.isEmpty
          ? 0
          : monthlyFrequency.values.reduce((a, b) => a > b ? a : b);

      monthlyFrequency.forEach((month, frequency) {
        if (frequency >= maxFrequency * 0.7) {
          // 70% threshold
          // Check if this month falls within prediction range
          final predictDate = DateTime(startDate.year, month, 15);
          if (!predictDate.isBefore(startDate) &&
              !predictDate.isAfter(endDate)) {
            predictions.add({
              'staff_name': staff,
              'predicted_month': month,
              'probability': frequency / staffHistory.length,
              'predicted_days': avgDaysRequested.round(),
              'pattern_strength': frequency / maxFrequency,
              'historical_count': frequency,
            });
          }
        }
      });
    }

    // Sort by probability
    predictions.sort((a, b) =>
        (b['probability'] as double).compareTo(a['probability'] as double));

    return predictions;
  }

  /// Calculate carry-over rules
  Map<String, dynamic> calculateCarryOver({
    required double currentBalance,
    required double annualAllowance,
    double maxCarryOver = 5.0,
    DateTime? financialYearEnd,
  }) {
    final yearEnd = financialYearEnd ?? DateTime(DateTime.now().year, 3, 31);
    final daysUntilYearEnd = yearEnd.difference(DateTime.now()).inDays;

    double willExpire = 0;
    double canCarryOver = 0;

    if (currentBalance > maxCarryOver) {
      canCarryOver = maxCarryOver;
      willExpire = currentBalance - maxCarryOver;
    } else {
      canCarryOver = currentBalance;
      willExpire = 0;
    }

    return {
      'current_balance': currentBalance,
      'max_carry_over': maxCarryOver,
      'will_carry_over': canCarryOver,
      'will_expire': willExpire,
      'days_until_year_end': daysUntilYearEnd,
      'financial_year_end': yearEnd,
      'use_it_or_lose_it': willExpire,
    };
  }

  /// Get leave statistics for a staff member
  Map<String, dynamic> getStaffLeaveStats({
    required String staffId,
    required List<LeaveRequest> allRequests,
    required double currentBalance,
  }) {
    final staffRequests =
        allRequests.where((r) => r.staffId == staffId).toList();
    final approved =
        staffRequests.where((r) => r.status == ApprovalStatus.approved);
    final pending =
        staffRequests.where((r) => r.status == ApprovalStatus.pending);
    final rejected =
        staffRequests.where((r) => r.status == ApprovalStatus.rejected);

    double totalDaysApproved = 0;
    double totalDaysPending = 0;
    final leaveByType = <LeaveType, double>{};

    for (final request in approved) {
      totalDaysApproved += request.daysRequested;
      leaveByType[request.leaveType] =
          (leaveByType[request.leaveType] ?? 0) + request.daysRequested;
    }

    for (final request in pending) {
      totalDaysPending += request.daysRequested;
    }

    return {
      'total_requests': staffRequests.length,
      'approved_requests': approved.length,
      'pending_requests': pending.length,
      'rejected_requests': rejected.length,
      'total_days_approved': totalDaysApproved,
      'total_days_pending': totalDaysPending,
      'current_balance': currentBalance,
      'remaining_balance': currentBalance - totalDaysApproved,
      'leave_by_type': leaveByType,
    };
  }

  /// Check if leave request would conflict with existing approved leave
  bool hasLeaveConflict(
    LeaveRequest newRequest,
    List<LeaveRequest> existingRequests,
  ) {
    final approved = existingRequests
        .where((r) =>
            r.staffId == newRequest.staffId &&
            r.status == ApprovalStatus.approved)
        .toList();

    for (final existing in approved) {
      // Check for date overlap
      if (!(newRequest.endDate.isBefore(existing.startDate) ||
          newRequest.startDate.isAfter(existing.endDate))) {
        return true;
      }
    }

    return false;
  }

  /// Get leave type display name
  String getLeaveTypeName(LeaveType type) {
    switch (type) {
      case LeaveType.annual:
        return 'Annual Leave';
      case LeaveType.sick:
        return 'Sick Leave';
      case LeaveType.unpaid:
        return 'Unpaid Leave';
      case LeaveType.compassionate:
        return 'Compassionate Leave';
      case LeaveType.maternity:
        return 'Maternity Leave';
      case LeaveType.paternity:
        return 'Paternity Leave';
      case LeaveType.study:
        return 'Study Leave';
      case LeaveType.custom:
        return 'Custom Leave';
    }
  }

  /// Get approval status display name
  String getApprovalStatusName(ApprovalStatus status) {
    switch (status) {
      case ApprovalStatus.pending:
        return 'Pending';
      case ApprovalStatus.approved:
        return 'Approved';
      case ApprovalStatus.rejected:
        return 'Rejected';
      case ApprovalStatus.cancelled:
        return 'Cancelled';
    }
  }
}
