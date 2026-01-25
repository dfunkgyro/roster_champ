import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../aws_service.dart';
import '../services/activity_log_service.dart';

class DiagnosticService {
  DiagnosticService._internal();
  static final DiagnosticService instance = DiagnosticService._internal();

  Future<String> buildReport() async {
    final buffer = StringBuffer();
    final now = DateTime.now().toIso8601String();
    buffer.writeln('Roster Champ Diagnostic Report');
    buffer.writeln('Generated: $now');
    buffer.writeln('');

    final packageInfo = await PackageInfo.fromPlatform();
    buffer.writeln('App');
    buffer.writeln('  Name: ${packageInfo.appName}');
    buffer.writeln('  Version: ${packageInfo.version}+${packageInfo.buildNumber}');
    buffer.writeln('  Package: ${packageInfo.packageName}');
    buffer.writeln('');

    buffer.writeln('Platform');
    buffer.writeln('  Target: ${defaultTargetPlatform.name}');
    buffer.writeln('  IsWeb: $kIsWeb');
    final deviceInfo = DeviceInfoPlugin();
    try {
      if (Platform.isAndroid) {
        final info = await deviceInfo.androidInfo;
        buffer.writeln('  Android: ${info.manufacturer} ${info.model}');
        buffer.writeln('  SDK: ${info.version.sdkInt}');
      } else if (Platform.isWindows) {
        final info = await deviceInfo.windowsInfo;
        buffer.writeln('  Windows: ${info.productName}');
        buffer.writeln('  Build: ${info.buildNumber}');
      } else if (Platform.isIOS) {
        final info = await deviceInfo.iosInfo;
        buffer.writeln('  iOS: ${info.utsname.machine}');
        buffer.writeln('  Version: ${info.systemVersion}');
      } else if (Platform.isMacOS) {
        final info = await deviceInfo.macOsInfo;
        buffer.writeln('  macOS: ${info.model}');
        buffer.writeln('  Version: ${info.osRelease}');
      } else if (Platform.isLinux) {
        final info = await deviceInfo.linuxInfo;
        buffer.writeln('  Linux: ${info.name}');
        buffer.writeln('  Version: ${info.version}');
      }
    } catch (e) {
      buffer.writeln('  Device info error: $e');
    }
    buffer.writeln('');

    final aws = AwsService.instance;
    buffer.writeln('AWS');
    buffer.writeln('  Configured: ${aws.isConfigured}');
    buffer.writeln('  Authenticated: ${aws.isAuthenticated}');
    buffer.writeln('  UserId: ${_redact(aws.userId)}');
    buffer.writeln('  UserEmail: ${_redact(aws.userEmail)}');
    buffer.writeln('');

    buffer.writeln('Recent Activity');
    final logs = ActivityLogService.instance.entries.take(20).toList();
    if (logs.isEmpty) {
      buffer.writeln('  None');
    } else {
      for (final entry in logs) {
        buffer.writeln(
          '  [${entry.level.name}] ${entry.timestamp.toIso8601String()} - ${entry.message}',
        );
        if (entry.details != null && entry.details!.trim().isNotEmpty) {
          buffer.writeln('    Details: ${entry.details}');
        }
        if (entry.fixes.isNotEmpty) {
          buffer.writeln('    Fixes: ${entry.fixes.join(" | ")}');
        }
      }
    }
    buffer.writeln('');

    return buffer.toString();
  }

  String _redact(String? value) {
    if (value == null || value.isEmpty) return '';
    if (value.length <= 6) return '***';
    return '${value.substring(0, 3)}***${value.substring(value.length - 3)}';
  }
}
