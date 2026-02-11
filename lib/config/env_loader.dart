import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class EnvLoader {
  static final EnvLoader _instance = EnvLoader._internal();
  static EnvLoader get instance => _instance;

  EnvLoader._internal();

  Map<String, String> _env = {};

  Future<void> load() async {
    _env = {
      'AWS_API_URL': const String.fromEnvironment(
        'AWS_API_URL',
        defaultValue: 'https://uxqxypf3p4.execute-api.us-east-1.amazonaws.com/dev',
      ),
      'AWS_REGION': const String.fromEnvironment(
        'AWS_REGION',
        defaultValue: 'us-east-1',
      ),
      'COGNITO_USER_POOL_ID': const String.fromEnvironment(
        'COGNITO_USER_POOL_ID',
        defaultValue: 'us-east-1_TrwHCKjHA',
      ),
      'COGNITO_APP_CLIENT_ID': const String.fromEnvironment(
        'COGNITO_APP_CLIENT_ID',
        defaultValue: '412n6o2tfbd0uiv80i4733n0l0',
      ),
      'COGNITO_DOMAIN': const String.fromEnvironment(
        'COGNITO_DOMAIN',
        defaultValue:
            'https://roster-dev-dhjw6acs.auth.us-east-1.amazoncognito.com',
      ),
      'COGNITO_REDIRECT_URI': const String.fromEnvironment(
        'COGNITO_REDIRECT_URI',
        defaultValue: 'rosterchamp://auth',
      ),
      'COGNITO_DESKTOP_REDIRECT_URI': const String.fromEnvironment(
        'COGNITO_DESKTOP_REDIRECT_URI',
        defaultValue: 'http://127.0.0.1:53682/',
      ),
      'COGNITO_IDENTITY_POOL_ID': const String.fromEnvironment(
        'COGNITO_IDENTITY_POOL_ID',
        defaultValue: 'us-east-1:d5e17b9b-d839-4f91-9940-62e61909b443',
      ),
    };

    await _loadAssetEnv();

    if (kDebugMode) {
      print('Environment variables loaded: ${_env.keys}');
    }
  }

  Future<void> _loadAssetEnv() async {
    try {
      final content = await rootBundle.loadString('assets/env/.env');
      final lines = content.split('\n');
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
        final index = trimmed.indexOf('=');
        if (index <= 0) continue;
        final key = trimmed.substring(0, index).trim();
        final value = trimmed.substring(index + 1).trim();
        if (key.isEmpty || value.isEmpty) continue;
        _env[key] = value;
      }
    } catch (_) {
      // Ignore missing asset env file.
    }
  }

  String get(String key, {String defaultValue = ''}) {
    return _env[key] ?? defaultValue;
  }

  String? getOrNull(String key) {
    return _env[key];
  }
}
