import 'package:uuid/uuid.dart';
import '../models.dart';
import 'notification_service.dart';

/// Service for managing shift swap requests and approvals
class ShiftSwapService {
  static final ShiftSwapService instance = ShiftSwapService._internal();
  ShiftSwapService._internal();

  final _uuid = const Uuid();

  /// Create a new shift swap request
  ShiftSwapRequest createSwapRequest({
    required String requesterId,
    required String requesterName,
    required String targetStaffId,
    required String targetStaffName,
    required DateTime shiftDate,
    required String shiftType,
    String? reason,
  }) {
    return ShiftSwapRequest(
      id: _uuid.v4(),
      requesterId: requesterId,
      requesterName: requesterName,
      targetStaffId: targetStaffId,
      targetStaffName: targetStaffName,
      shiftDate: shiftDate,
      shiftType: shiftType,
      reason: reason,
      requestDate: DateTime.now(),
    );
  }

  /// Approve a shift swap request
  Future<ShiftSwapRequest> approveSwapRequest(
    ShiftSwapRequest request,
    String approverId,
    String approverName, {
    String? note,
  }) async {
    final approved = request.copyWith(
      status: ApprovalStatus.approved,
      approverId: approverId,
      approverName: approverName,
      responseDate: DateTime.now(),
      responseNote: note,
    );

    // Send notification
    await NotificationService.instance.notifyShiftSwapApproval(
      staffName: request.requesterName,
      shiftDate: request.shiftDate,
      approved: true,
    );

    return approved;
  }

  /// Reject a shift swap request
  Future<ShiftSwapRequest> rejectSwapRequest(
    ShiftSwapRequest request,
    String approverId,
    String approverName,
    String reason,
  ) async {
    final rejected = request.copyWith(
      status: ApprovalStatus.rejected,
      approverId: approverId,
      approverName: approverName,
      responseDate: DateTime.now(),
      responseNote: reason,
    );

    // Send notification
    await NotificationService.instance.notifyShiftSwapApproval(
      staffName: request.requesterName,
      shiftDate: request.shiftDate,
      approved: false,
    );

    return rejected;
  }

  /// Cancel a shift swap request
  ShiftSwapRequest cancelSwapRequest(
    ShiftSwapRequest request,
  ) {
    return request.copyWith(
      status: ApprovalStatus.cancelled,
      responseDate: DateTime.now(),
    );
  }

  /// Execute an approved swap (update the roster)
  Map<String, dynamic> executeSwap({
    required ShiftSwapRequest request,
    required Map<String, Map<DateTime, String>> currentRoster,
  }) {
    if (request.status != ApprovalStatus.approved) {
      return {
        'success': false,
        'error': 'Swap request is not approved',
      };
    }

    final requesterSchedule = currentRoster[request.requesterName];
    final targetSchedule = currentRoster[request.targetStaffName];

    if (requesterSchedule == null || targetSchedule == null) {
      return {
        'success': false,
        'error': 'Staff member not found in roster',
      };
    }

    final requesterShift = requesterSchedule[request.shiftDate];
    final targetShift = targetSchedule[request.shiftDate];

    if (requesterShift == null) {
      return {
        'success': false,
        'error': 'Requester has no shift on specified date',
      };
    }

    // Perform the swap
    requesterSchedule[request.shiftDate] = targetShift ?? 'OFF';
    targetSchedule[request.shiftDate] = requesterShift;

    return {
      'success': true,
      'swapped_shifts': {
        request.requesterName: {'from': requesterShift, 'to': targetShift ?? 'OFF'},
        request.targetStaffName: {'from': targetShift ?? 'OFF', 'to': requesterShift},
      },
    };
  }

  /// Check if a swap is valid
  Map<String, dynamic> validateSwap({
    required ShiftSwapRequest request,
    required Map<String, Map<DateTime, String>> currentRoster,
    required List<SchedulingConstraint> constraints,
  }) {
    final issues = <String>[];

    // Check if both staff members exist
    if (!currentRoster.containsKey(request.requesterName)) {
      issues.add('Requester not found in roster');
    }
    if (!currentRoster.containsKey(request.targetStaffName)) {
      issues.add('Target staff not found in roster');
    }

    if (issues.isNotEmpty) {
      return {'is_valid': false, 'issues': issues};
    }

    final requesterSchedule = currentRoster[request.requesterName]!;
    final targetSchedule = currentRoster[request.targetStaffName]!;

    final requesterShift = requesterSchedule[request.shiftDate];
    final targetShift = targetSchedule[request.shiftDate];

    // Check if requester actually has a shift
    if (requesterShift == null || requesterShift == 'OFF') {
      issues.add('Requester has no shift to swap on this date');
    }

    // Check if swap would violate constraints
    final wouldViolateRequester = _wouldViolateConstraints(
      schedule: requesterSchedule,
      swapDate: request.shiftDate,
      newShift: targetShift ?? 'OFF',
      constraints: constraints,
    );

    final wouldViolateTarget = _wouldViolateConstraints(
      schedule: targetSchedule,
      swapDate: request.shiftDate,
      newShift: requesterShift ?? 'OFF',
      constraints: constraints,
    );

    if (wouldViolateRequester.isNotEmpty) {
      issues.add('Swap would violate constraints for ${request.requesterName}: ${wouldViolateRequester.join(", ")}');
    }

    if (wouldViolateTarget.isNotEmpty) {
      issues.add('Swap would violate constraints for ${request.targetStaffName}: ${wouldViolateTarget.join(", ")}');
    }

    return {
      'is_valid': issues.isEmpty,
      'issues': issues,
    };
  }

  /// Check if a swap would violate constraints
  List<String> _wouldViolateConstraints({
    required Map<DateTime, String> schedule,
    required DateTime swapDate,
    required String newShift,
    required List<SchedulingConstraint> constraints,
  }) {
    final violations = <String>[];

    // Create a temporary schedule with the swap
    final tempSchedule = Map<DateTime, String>.from(schedule);
    tempSchedule[swapDate] = newShift;

    // Check max consecutive days
    final maxConsecutiveConstraint = constraints.firstWhere(
      (c) => c.type == ConstraintType.maxConsecutiveDays && c.isActive,
      orElse: () => SchedulingConstraint(
        id: '',
        type: ConstraintType.maxConsecutiveDays,
        name: 'Default',
        value: 7,
      ),
    );

    final consecutiveDays = _countConsecutiveDays(tempSchedule, swapDate);
    if (consecutiveDays > maxConsecutiveConstraint.value) {
      violations.add('Would exceed ${maxConsecutiveConstraint.value} consecutive days');
    }

    // Check minimum rest between shifts
    final minRestConstraint = constraints.firstWhere(
      (c) => c.type == ConstraintType.minRestHours && c.isActive,
      orElse: () => SchedulingConstraint(
        id: '',
        type: ConstraintType.minRestHours,
        name: 'Default',
        value: 11,
      ),
    );

    final previousDay = swapDate.subtract(const Duration(days: 1));
    final nextDay = swapDate.add(const Duration(days: 1));

    final previousShift = tempSchedule[previousDay];
    final nextShift = tempSchedule[nextDay];

    // Check rest after night shift
    if (previousShift == 'N' && newShift == 'D') {
      violations.add('Insufficient rest after night shift');
    }

    if (newShift == 'N' && nextShift == 'D') {
      violations.add('Insufficient rest before day shift');
    }

    return violations;
  }

  /// Count consecutive working days around a date
  int _countConsecutiveDays(Map<DateTime, String> schedule, DateTime date) {
    int count = 0;

    // Count backwards
    DateTime checkDate = date;
    while (schedule[checkDate] != null) {
      final shift = schedule[checkDate]!;
      if (shift != 'OFF' && shift != 'L') {
        count++;
        checkDate = checkDate.subtract(const Duration(days: 1));
      } else {
        break;
      }
    }

    // Count forwards (but don't double-count the swap date)
    checkDate = date.add(const Duration(days: 1));
    while (schedule[checkDate] != null) {
      final shift = schedule[checkDate]!;
      if (shift != 'OFF' && shift != 'L') {
        count++;
        checkDate = checkDate.add(const Duration(days: 1));
      } else {
        break;
      }
    }

    return count;
  }

  /// Get pending swap requests for a staff member
  List<ShiftSwapRequest> getPendingSwapsForStaff(
    String staffId,
    List<ShiftSwapRequest> allSwaps,
  ) {
    return allSwaps
        .where((swap) =>
            (swap.requesterId == staffId || swap.targetStaffId == staffId) &&
            swap.status == ApprovalStatus.pending)
        .toList();
  }

  /// Get swap history for a staff member
  List<ShiftSwapRequest> getSwapHistory(
    String staffId,
    List<ShiftSwapRequest> allSwaps,
  ) {
    return allSwaps
        .where((swap) =>
            swap.requesterId == staffId || swap.targetStaffId == staffId)
        .toList()
      ..sort((a, b) => b.requestDate.compareTo(a.requestDate));
  }

  /// Get swap statistics
  Map<String, dynamic> getSwapStatistics(List<ShiftSwapRequest> allSwaps) {
    final total = allSwaps.length;
    final pending = allSwaps.where((s) => s.status == ApprovalStatus.pending).length;
    final approved = allSwaps.where((s) => s.status == ApprovalStatus.approved).length;
    final rejected = allSwaps.where((s) => s.status == ApprovalStatus.rejected).length;
    final cancelled = allSwaps.where((s) => s.status == ApprovalStatus.cancelled).length;

    final approvalRate = total > 0 ? (approved / total * 100).toStringAsFixed(1) : '0.0';

    return {
      'total': total,
      'pending': pending,
      'approved': approved,
      'rejected': rejected,
      'cancelled': cancelled,
      'approval_rate': approvalRate,
    };
  }

  /// Suggest swap partners (staff with compatible shifts)
  List<Map<String, dynamic>> suggestSwapPartners({
    required String staffId,
    required DateTime date,
    required Map<String, Map<DateTime, String>> roster,
    required List<SchedulingConstraint> constraints,
  }) {
    final suggestions = <Map<String, dynamic>>[];

    final staffSchedule = roster.entries.firstWhere(
      (entry) => entry.key == staffId,
      orElse: () => MapEntry('', {}),
    ).value;

    if (staffSchedule.isEmpty) return suggestions;

    final staffShift = staffSchedule[date];
    if (staffShift == null || staffShift == 'OFF' || staffShift == 'L') {
      return suggestions;
    }

    // Find staff who are off or have compatible shifts
    roster.forEach((otherStaff, otherSchedule) {
      if (otherStaff == staffId) return;

      final otherShift = otherSchedule[date];

      // Check if swap would be valid
      final validation = validateSwap(
        request: ShiftSwapRequest(
          id: 'temp',
          requesterId: staffId,
          requesterName: staffId,
          targetStaffId: otherStaff,
          targetStaffName: otherStaff,
          shiftDate: date,
          shiftType: staffShift,
          requestDate: DateTime.now(),
        ),
        currentRoster: roster,
        constraints: constraints,
      );

      if (validation['is_valid'] as bool) {
        suggestions.add({
          'staff_id': otherStaff,
          'staff_name': otherStaff,
          'their_shift': otherShift ?? 'OFF',
          'compatibility_score': _calculateCompatibilityScore(
            staffShift,
            otherShift ?? 'OFF',
          ),
        });
      }
    });

    // Sort by compatibility score
    suggestions.sort((a, b) =>
        (b['compatibility_score'] as double)
            .compareTo(a['compatibility_score'] as double));

    return suggestions;
  }

  /// Calculate compatibility score for a swap
  double _calculateCompatibilityScore(String shift1, String shift2) {
    // Higher score for more compatible swaps
    if (shift2 == 'OFF') return 1.0; // Perfect - they're not working
    if (shift1 == shift2) return 0.5; // Same shift type
    if ((shift1 == 'D' && shift2 == 'E') || (shift1 == 'E' && shift2 == 'D')) {
      return 0.7; // Similar shifts
    }
    return 0.3; // Less compatible
  }

  /// Send notification for new swap request
  Future<void> notifySwapRequest(ShiftSwapRequest request) async {
    await NotificationService.instance.notifyShiftSwapRequest(
      requesterName: request.requesterName,
      targetName: request.targetStaffName,
      shiftDate: request.shiftDate,
      shiftType: request.shiftType,
    );
  }

  /// Get approval status display name
  String getStatusDisplayName(ApprovalStatus status) {
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
