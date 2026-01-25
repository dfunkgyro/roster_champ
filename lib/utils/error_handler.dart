import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/activity_log_service.dart';
import '../services/diagnostic_service.dart';

class ErrorHandler {
  static void showErrorSnackBar(BuildContext context, dynamic error) {
    final details = describeError(error);
    final message = _buildMessage(details);
    final rawError = error?.toString() ?? '';
    debugPrint('Error: ${details.message}');
    if (details.fixes.isNotEmpty) {
      debugPrint('Possible fixes: ${details.fixes.join(" | ")}');
    }
    ActivityLogService.instance.addError(
      details.message,
      details.fixes,
      details: rawError.isEmpty ? null : rawError,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 6),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'Copy Report',
          textColor: Colors.white,
          onPressed: () async {
            final report = await DiagnosticService.instance.buildReport();
            await Clipboard.setData(ClipboardData(text: report));
          },
        ),
      ),
    );
  }

  static Future<T> wrapAsync<T>(
    Future<T> Function() operation, {
    String? context,
  }) async {
    try {
      return await operation();
    } catch (e) {
      debugPrint('Error in ${context ?? 'operation'}: $e');
      if (context != null && context.trim().isNotEmpty) {
        ActivityLogService.instance.addError(
          'Error in $context',
          const ['Retry the action'],
        );
      }
      rethrow;
    }
  }

  static String getErrorMessage(dynamic error) {
    final details = describeError(error);
    return _buildMessage(details);
  }

  static _ErrorDetails describeError(dynamic error) {
    if (error is SocketException) {
      return _ErrorDetails(
        message: 'Network connection failed',
        fixes: [
          'Check your internet connection',
          'Retry the action',
        ],
      );
    }
    if (error is HttpException) {
      return _ErrorDetails(
        message: 'Server error: ${error.message}',
        fixes: ['Retry in a moment', 'Check server status'],
      );
    }
    if (error is FormatException) {
      return _ErrorDetails(
        message: 'Data format error',
        fixes: ['Refresh or re-sync data', 'Restart the app'],
      );
    }
    if (error is PlatformException) {
      return _ErrorDetails(
        message: 'Platform error: ${error.message}',
        fixes: ['Check app permissions', 'Restart the app'],
      );
    }
    if (error is String) {
      return _describeFromMessage(error);
    }
    if (error != null) {
      return _describeFromMessage(error.toString());
    }
    return _ErrorDetails(
      message: 'An unexpected error occurred',
      fixes: ['Retry the action', 'Restart the app'],
    );
  }

  static _ErrorDetails _describeFromMessage(String message) {
    final normalized = message.toLowerCase();
    final statusCode = _extractStatusCode(message);
    if (statusCode != null) {
      final base = 'Request failed ($statusCode)';
      return _ErrorDetails(
        message: base,
        fixes: _fixesForStatus(statusCode),
      );
    }
    if (normalized.contains('unauthorized') || normalized.contains('401')) {
      return _ErrorDetails(
        message: 'Unauthorized request',
        fixes: ['Sign in again', 'Check account permissions'],
      );
    }
    if (normalized.contains('forbidden') || normalized.contains('403')) {
      return _ErrorDetails(
        message: 'Access denied',
        fixes: ['Request access from an admin', 'Switch rosters'],
      );
    }
    if (normalized.contains('timeout')) {
      return _ErrorDetails(
        message: 'Request timed out',
        fixes: ['Check your connection', 'Try again'],
      );
    }
    if (normalized.contains('bedrock')) {
      return _ErrorDetails(
        message: 'AI service error',
        fixes: ['Retry the request', 'Check model availability'],
      );
    }
    return _ErrorDetails(
      message: message.isEmpty ? 'An unexpected error occurred' : message,
      fixes: ['Retry the action', 'Check your connection'],
    );
  }

  static int? _extractStatusCode(String message) {
    final match = RegExp(r'\b([45]\d{2})\b').firstMatch(message);
    if (match == null) return null;
    return int.tryParse(match.group(1) ?? '');
  }

  static List<String> _fixesForStatus(int statusCode) {
    switch (statusCode) {
      case 400:
        return ['Check input values', 'Try again'];
      case 401:
        return ['Sign in again', 'Refresh your session'];
      case 403:
        return ['Request access from an admin', 'Verify roster membership'];
      case 404:
        return ['Refresh and try again', 'Verify the roster ID'];
      case 409:
        return ['Resolve the conflict', 'Sync and retry'];
      case 429:
        return ['Wait a moment', 'Reduce request frequency'];
      case 500:
      case 502:
      case 503:
        return ['Server is busy', 'Retry in a few minutes'];
      default:
        return ['Retry the action', 'Contact support if it persists'];
    }
  }

  static String _buildMessage(_ErrorDetails details) {
    if (details.fixes.isEmpty) return details.message;
    return '${details.message}\nFix: ${details.fixes.join(' • ')}';
  }
}

class _ErrorDetails {
  final String message;
  final List<String> fixes;

  const _ErrorDetails({
    required this.message,
    required this.fixes,
  });
}
