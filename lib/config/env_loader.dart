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
        defaultValue:
            'https://mql6snubqb.execute-api.us-east-1.amazonaws.com/prod',
      ),
      'AWS_REGION': const String.fromEnvironment(
        'AWS_REGION',
        defaultValue: 'us-east-1',
      ),
      'COGNITO_USER_POOL_ID': const String.fromEnvironment(
        'COGNITO_USER_POOL_ID',
        defaultValue: 'us-east-1_FuKEW2wJ7',
      ),
      'COGNITO_APP_CLIENT_ID': const String.fromEnvironment(
        'COGNITO_APP_CLIENT_ID',
        defaultValue: 'kmq4njoc2jcekjorhck39qg60',
      ),
      'COGNITO_DOMAIN': const String.fromEnvironment(
        'COGNITO_DOMAIN',
        defaultValue:
            'https://auth-live.rosterchampion.com',
      ),
      'COGNITO_REDIRECT_URI': const String.fromEnvironment(
        'COGNITO_REDIRECT_URI',
        defaultValue: 'rosterchamp://auth-prod',
      ),
      'COGNITO_DESKTOP_REDIRECT_URI': const String.fromEnvironment(
        'COGNITO_DESKTOP_REDIRECT_URI',
        defaultValue: 'http://127.0.0.1:53682/',
      ),
      'COGNITO_WEB_REDIRECT_URI': const String.fromEnvironment(
        'COGNITO_WEB_REDIRECT_URI',
        defaultValue: 'https://app.rosterchampion.com',
      ),
      'COGNITO_IDENTITY_POOL_ID': const String.fromEnvironment(
        'COGNITO_IDENTITY_POOL_ID',
        defaultValue: 'us-east-1:47171ba2-3887-4a2c-9137-a08c51d8dcbb',
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
