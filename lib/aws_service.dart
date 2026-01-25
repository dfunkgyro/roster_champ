import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:amazon_cognito_identity_dart_2/cognito.dart';
import 'models.dart' as models;
import 'config/env_loader.dart';

class AwsService {
  static final AwsService _instance = AwsService._internal();
  static AwsService get instance => _instance;

  AwsService._internal();

  bool _initialized = false;
  String? _apiUrl;
  String? _userPoolId;
  String? _userPoolClientId;
  String? _region;
  String? _cognitoDomain;
  String? _redirectUri;
  String? _desktopRedirectUri;
  String? _identityPoolId;
  String? _providerName;

  String? _userId;
  String? _userEmail;
  String? _displayName;
  String? _idToken;
  String? _accessToken;
  String? _refreshToken;
  String? _awsAccessKeyId;
  String? _awsSecretAccessKey;
  String? _awsSessionToken;
  int? _awsExpireTime;

  String? _currentRosterId;
  Timer? _updatesTimer;
  String? _lastUpdateTimestamp;

  Function(bool isAuthenticated)? _onAuthStateChanged;

  set onAuthStateChanged(Function(bool isAuthenticated)? callback) {
    _onAuthStateChanged = callback;
  }

  Future<void> initialize() async {
    try {
      await EnvLoader.instance.load();
      _apiUrl = EnvLoader.instance.get('AWS_API_URL');
      if (_apiUrl != null) {
        _apiUrl = _apiUrl!.trim();
        while (_apiUrl!.endsWith('/')) {
          _apiUrl = _apiUrl!.substring(0, _apiUrl!.length - 1);
        }
      }
      _userPoolId = EnvLoader.instance.get('COGNITO_USER_POOL_ID');
      _userPoolClientId = EnvLoader.instance.get('COGNITO_APP_CLIENT_ID');
      _region = EnvLoader.instance.get('AWS_REGION');
      _cognitoDomain = EnvLoader.instance.get('COGNITO_DOMAIN');
      _redirectUri = EnvLoader.instance.get('COGNITO_REDIRECT_URI');
      _desktopRedirectUri =
          EnvLoader.instance.get('COGNITO_DESKTOP_REDIRECT_URI');
      _identityPoolId = EnvLoader.instance.get('COGNITO_IDENTITY_POOL_ID');
      if (_region != null && _userPoolId != null) {
        _providerName = 'cognito-idp.$_region.amazonaws.com/$_userPoolId';
      }

      if (_apiUrl == null ||
          _apiUrl!.isEmpty ||
          _userPoolId == null ||
          _userPoolId!.isEmpty ||
          _userPoolClientId == null ||
          _userPoolClientId!.isEmpty ||
          _identityPoolId == null ||
          _identityPoolId!.isEmpty) {
        debugPrint('AWS configuration not set in .env file');
        _initialized = false;
        return;
      }

      await _loadSession();
      _initialized = true;
      debugPrint('AWS service initialized');
    } catch (e) {
      debugPrint('AWS initialization error: $e');
      _initialized = false;
    }
  }

  CognitoUserPool _userPool() {
    return CognitoUserPool(_userPoolId!, _userPoolClientId!);
  }

  Future<void> _loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    _idToken = prefs.getString('aws_id_token');
    _accessToken = prefs.getString('aws_access_token');
    _refreshToken = prefs.getString('aws_refresh_token');
    _awsAccessKeyId = prefs.getString('aws_access_key_id');
    _awsSecretAccessKey = prefs.getString('aws_secret_access_key');
    _awsSessionToken = prefs.getString('aws_session_token');
    _awsExpireTime = prefs.getInt('aws_expire_time');
    _currentRosterId = prefs.getString('aws_current_roster_id');
    _hydrateFromToken();
  }

  Future<void> _saveSession() async {
    final prefs = await SharedPreferences.getInstance();
    if (_idToken != null) {
      await prefs.setString('aws_id_token', _idToken!);
    }
    if (_accessToken != null) {
      await prefs.setString('aws_access_token', _accessToken!);
    }
    if (_refreshToken != null) {
      await prefs.setString('aws_refresh_token', _refreshToken!);
    }
    if (_awsAccessKeyId != null) {
      await prefs.setString('aws_access_key_id', _awsAccessKeyId!);
    }
    if (_awsSecretAccessKey != null) {
      await prefs.setString('aws_secret_access_key', _awsSecretAccessKey!);
    }
    if (_awsSessionToken != null) {
      await prefs.setString('aws_session_token', _awsSessionToken!);
    }
    if (_awsExpireTime != null) {
      await prefs.setInt('aws_expire_time', _awsExpireTime!);
    }
    if (_currentRosterId != null) {
      await prefs.setString('aws_current_roster_id', _currentRosterId!);
    }
  }

  Future<void> _clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('aws_id_token');
    await prefs.remove('aws_access_token');
    await prefs.remove('aws_refresh_token');
    await prefs.remove('aws_access_key_id');
    await prefs.remove('aws_secret_access_key');
    await prefs.remove('aws_session_token');
    await prefs.remove('aws_expire_time');
    await prefs.remove('aws_current_roster_id');
  }

  void _hydrateFromToken() {
    if (_idToken == null) return;
    final payload = _decodeJwt(_idToken!);
    _userId = payload['sub'] as String?;
    _userEmail = payload['email'] as String?;
    _displayName =
        payload['name'] as String? ?? payload['given_name'] as String?;
  }

  Map<String, dynamic> _decodeJwt(String token) {
    final parts = token.split('.');
    if (parts.length < 2) return {};
    final normalized = base64Url.normalize(parts[1]);
    final decoded = utf8.decode(base64Url.decode(normalized));
    return jsonDecode(decoded) as Map<String, dynamic>;
  }

  Future<void> _loadAwsCredentials(
    String token, {
    String? authenticator,
  }) async {
    if (_identityPoolId == null || _identityPoolId!.isEmpty) {
      throw Exception('Identity pool not configured');
    }
    final credentials = CognitoCredentials(
      _identityPoolId!,
      _userPool(),
      region: _region,
    );
    try {
      await credentials.getAwsCredentials(
        token,
        authenticator ?? _providerName,
      );
    } catch (e) {
      final message = e.toString();
      if (message.contains('NotAuthorizedException') ||
          message.contains('invalid login token') ||
          message.contains('token expired')) {
        await _refreshSessionIfNeeded();
        if (_idToken == null) rethrow;
        await credentials.getAwsCredentials(
          _idToken!,
          authenticator ?? _providerName,
        );
      } else {
        rethrow;
      }
    }
    _awsAccessKeyId = credentials.accessKeyId;
    _awsSecretAccessKey = credentials.secretAccessKey;
    _awsSessionToken = credentials.sessionToken;
    _awsExpireTime = credentials.expireTime;
    _userId = credentials.userIdentityId ?? _userId;
  }

  Future<void> _ensureAwsCredentials() async {
    await _refreshSessionIfNeeded();
    if (_awsAccessKeyId == null ||
        _awsSecretAccessKey == null ||
        _awsExpireTime == null ||
        DateTime.now().millisecondsSinceEpoch > _awsExpireTime! - 60000) {
      if (_idToken == null) return;
      await _loadAwsCredentials(_idToken!);
      await _saveSession();
    }
  }

  bool _isTokenExpiring(String token, {int bufferSeconds = 120}) {
    final payload = _decodeJwt(token);
    final exp = payload['exp'];
    if (exp is! int) return false;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return exp <= now + bufferSeconds;
  }

  Future<void> _refreshSessionIfNeeded() async {
    if (_idToken == null) return;
    if (!_isTokenExpiring(_idToken!)) return;
    if (_refreshToken == null || _userEmail == null) {
      await signOut();
      throw Exception('Session expired. Please sign in again.');
    }
    try {
      final pool = _userPool();
      final user = CognitoUser(_userEmail!, pool);
      final refreshToken = CognitoRefreshToken(_refreshToken!);
      final session = await user.refreshSession(refreshToken);
      if (session == null) {
        throw Exception('Session refresh failed. Please sign in again.');
      }
      _idToken = session.getIdToken().getJwtToken();
      _accessToken = session.getAccessToken().getJwtToken();
      _refreshToken = session.getRefreshToken()?.getToken() ?? _refreshToken;
      _hydrateFromToken();
      await _saveSession();
    } catch (_) {
      await signOut();
      rethrow;
    }
  }

  Future<bool> checkConnection() async {
    if (!_initialized || _apiUrl == null) return false;
    try {
      final response = await http
          .get(Uri.parse('$_apiUrl/health'))
          .timeout(const Duration(seconds: 8));
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('AWS connection check failed: $e');
      return false;
    }
  }

  bool get isConfigured =>
      _apiUrl != null &&
      _apiUrl!.isNotEmpty &&
      _userPoolId != null &&
      _userPoolId!.isNotEmpty &&
      _userPoolClientId != null &&
      _userPoolClientId!.isNotEmpty &&
      _identityPoolId != null &&
      _identityPoolId!.isNotEmpty;

  bool get isAuthenticated => _accessToken != null || _idToken != null;
  String? get apiUrl => _apiUrl;
  String? get userId => _userId;
  String? get userEmail => _userEmail;
  String? get displayName => _displayName;

  String? get currentRosterId => _currentRosterId;
  set currentRosterId(String? rosterId) {
    _currentRosterId = rosterId;
    _saveSession();
  }

  Future<bool> signUp(String email, String password, String displayName) async {
    if (!_initialized) throw Exception('AWS not initialized');
    final pool = _userPool();
    final attributes = [
      AttributeArg(name: 'email', value: email),
      AttributeArg(name: 'name', value: displayName),
    ];
    try {
      final result =
          await pool.signUp(email, password, userAttributes: attributes);
      if (result.userConfirmed == false) {
        debugPrint('User signup requires confirmation');
      }
      _displayName = displayName;
      return result.userConfirmed == false;
    } catch (e) {
      final message = e.toString();
      if (message.contains('UsernameExistsException')) {
        throw Exception('An account with this email already exists.');
      }
      if (message.contains('InvalidPasswordException')) {
        throw Exception(
          'Password does not meet policy requirements. Use at least 8 characters with a number and a symbol.',
        );
      }
      if (message.contains('InvalidParameterException')) {
        throw Exception('Invalid signup details. Check your email format.');
      }
      rethrow;
    }
  }

  Future<void> signIn(String email, String password) async {
    if (!_initialized) throw Exception('AWS not initialized');
    final pool = _userPool();
    final user = CognitoUser(email, pool);
    final authDetails = AuthenticationDetails(
      username: email,
      password: password,
    );
    try {
      final session = await user.authenticateUser(authDetails);
      if (session == null) {
        throw Exception('Sign-in failed. Please try again.');
      }
      _idToken = session.getIdToken().getJwtToken();
      _accessToken = session.getAccessToken().getJwtToken();
      _refreshToken = session.getRefreshToken()?.getToken();
    } catch (e) {
      final message = e.toString();
      if (message.contains('UserNotConfirmedException')) {
        throw Exception('Account not confirmed. Check your email for the code.');
      }
      if (message.contains('NotAuthorizedException') ||
          message.contains('UserNotFoundException')) {
        throw Exception('Email or password is incorrect.');
      }
      rethrow;
    }
    _hydrateFromToken();
    if (_idToken != null) {
      await _loadAwsCredentials(_idToken!);
    }
    await _saveSession();
    _onAuthStateChanged?.call(true);
  }

  Future<void> confirmSignUp(String email, String code) async {
    if (!_initialized) throw Exception('AWS not initialized');
    final pool = _userPool();
    final user = CognitoUser(email, pool);
    await user.confirmRegistration(code);
  }

  Future<void> resendConfirmationCode(String email) async {
    if (!_initialized) throw Exception('AWS not initialized');
    final pool = _userPool();
    final user = CognitoUser(email, pool);
    await user.resendConfirmationCode();
  }

  Future<void> signOut() async {
    _idToken = null;
    _accessToken = null;
    _refreshToken = null;
    _awsAccessKeyId = null;
    _awsSecretAccessKey = null;
    _awsSessionToken = null;
    _awsExpireTime = null;
    _userId = null;
    _userEmail = null;
    _displayName = null;
    _currentRosterId = null;
    _updatesTimer?.cancel();
    await _clearSession();
    _onAuthStateChanged?.call(false);
  }


  Future<void> deleteAccount() async {
    await _post('/account/delete', {});
    await signOut();
  }

  Future<void> resetPassword(String email) async {
    if (!_initialized) throw Exception('AWS not initialized');
    final pool = _userPool();
    final user = CognitoUser(email, pool);
    await user.forgotPassword();
  }

  Future<void> updateProfile(String displayName) async {
    if (!_initialized) throw Exception('AWS not initialized');
    _displayName = displayName;
    await _post('/profile', {
      'displayName': displayName,
      'email': _userEmail,
    });
  }

  Future<Map<String, dynamic>?> getUserSettings() async {
    final response = await _get('/settings/get');
    if (response is Map && response.isNotEmpty) {
      return Map<String, dynamic>.from(response as Map);
    }
    return null;
  }

  Future<void> saveUserSettings(Map<String, dynamic> settings) async {
    await _post('/settings/save', {
      'settings': settings,
    });
  }

  Future<void> sendPresenceHeartbeat(String rosterId, {String? device}) async {
    await _post('/presence/heartbeat', {
      'rosterId': rosterId,
      'device': device ?? 'app',
      'displayName': _displayName ?? _userEmail ?? 'User',
    });
  }

  Future<List<models.PresenceEntry>> getPresence(String rosterId) async {
    final response = await _get('/presence/list?rosterId=$rosterId');
    return (response as List<dynamic>)
        .map((item) => models.PresenceEntry.fromJson(
              Map<String, dynamic>.from(item as Map),
            ))
        .toList();
  }

  Future<int> importTimeClockEntries({
    required String rosterId,
    required List<models.TimeClockEntry> entries,
  }) async {
    final response = await _post('/timeclock/import', {
      'rosterId': rosterId,
      'entries': entries.map((e) => e.toJson()).toList(),
    });
    return response['imported'] as int? ?? 0;
  }

  Future<List<models.TimeClockEntry>> getTimeClockEntries(
    String rosterId,
  ) async {
    final response = await _get('/timeclock?rosterId=$rosterId');
    return (response as List<dynamic>)
        .map((item) => models.TimeClockEntry.fromJson(
              Map<String, dynamic>.from(item as Map),
            ))
        .toList();
  }

  Future<void> submitAiFeedback({
    required String rosterId,
    required String suggestionId,
    required String feedback,
    Map<String, dynamic>? impact,
    String? notes,
  }) async {
    await _post('/ai/feedback', {
      'rosterId': rosterId,
      'suggestionId': suggestionId,
      'feedback': feedback,
      'impact': impact,
      'notes': notes ?? '',
    });
  }

  Future<List<Map<String, dynamic>>> getRoleTemplates() async {
    final response = await _get('/roles/templates');
    return (response as List<dynamic>)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  Future<String> createRoster(
    String rosterName,
    String? password, {
    String? orgId,
  }) async {
    final response = await _post('/rosters/create', {
      'name': rosterName,
      'password': password,
      'orgId': orgId,
    });
    final rosterId = response['rosterId'] as String;
    currentRosterId = rosterId;
    return rosterId;
  }

  Future<Map<String, dynamic>> exportRosterToCloud(String rosterId) async {
    final response = await _post('/exports/roster', {'rosterId': rosterId});
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> createShareCode({
    required String rosterId,
    String role = 'viewer',
    int? expiresInHours,
    int? maxUses,
    String? customCode,
  }) async {
    final response = await _post('/share/create', {
      'rosterId': rosterId,
      'role': role,
      'expiresInHours': expiresInHours,
      'maxUses': maxUses,
      if (customCode != null && customCode.trim().isNotEmpty)
        'customCode': customCode.trim(),
    });
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> accessRosterByCode(String code) async {
    final response = await _postNoAuth('/share/access', {'code': code});
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> accessRosterByCodeAuthenticated(String code) async {
    final response = await _post('/share/access-auth', {'code': code});
    return Map<String, dynamic>.from(response as Map);
  }

  Future<String> submitLeaveRequestWithCode({
    required String code,
    required DateTime startDate,
    DateTime? endDate,
    String? notes,
    String? guestName,
  }) async {
    final response = await _postNoAuth('/share/leave', {
      'code': code,
      'startDate': startDate.toIso8601String(),
      'endDate': (endDate ?? startDate).toIso8601String(),
      'notes': notes ?? '',
      'guestName': guestName ?? '',
    });
    return response['requestId'] as String;
  }

  Future<bool> joinRoster(String rosterId, String? password) async {
    await _post('/rosters/join', {
      'rosterId': rosterId,
      'password': password,
    });
    currentRosterId = rosterId;
    return true;
  }

  Future<List<Map<String, dynamic>>> getUserRosters() async {
    final response = await _get('/rosters');
    return (response as List<dynamic>).cast<Map<String, dynamic>>();
  }

  Future<void> deleteRoster(String rosterId) async {
    await _post('/rosters/delete', {'rosterId': rosterId});
    if (_currentRosterId == rosterId) {
      _currentRosterId = null;
      await _saveSession();
    }
  }

  Future<String> createOrg(String name) async {
    final response = await _post('/orgs/create', {'name': name});
    return response['orgId'] as String;
  }

  Future<List<models.OrgMembership>> getUserOrgs() async {
    final response = await _get('/orgs');
    return (response as List<dynamic>)
        .map((item) => models.OrgMembership.fromJson(
              Map<String, dynamic>.from(item as Map),
            ))
        .toList();
  }

  Future<void> updateOrgMemberRole(
    String orgId,
    String memberUserId,
    models.OrgRole role,
  ) async {
    await _post('/orgs/members/role', {
      'orgId': orgId,
      'memberUserId': memberUserId,
      'role': role.name,
    });
  }

  Future<String> createTeam(String orgId, String name) async {
    final response = await _post('/teams/create', {
      'orgId': orgId,
      'name': name,
    });
    return response['teamId'] as String;
  }

  Future<List<models.Team>> getTeams(String orgId) async {
    final response = await _get('/teams?orgId=$orgId');
    return (response as List<dynamic>)
        .map((item) => models.Team.fromJson(
              Map<String, dynamic>.from(item as Map),
            ))
        .toList();
  }

  Future<void> addTeamMember(
    String orgId,
    String teamId,
    String memberUserId, {
    String role = 'member',
  }) async {
    await _post('/teams/members/add', {
      'orgId': orgId,
      'teamId': teamId,
      'memberUserId': memberUserId,
      'role': role,
    });
  }

  Future<String> createAvailabilityRequest({
    required String rosterId,
    required models.AvailabilityType type,
    required DateTime startDate,
    DateTime? endDate,
    String? notes,
  }) async {
    final response = await _post('/availability/request', {
      'rosterId': rosterId,
      'type': type.name,
      'startDate': startDate.toIso8601String(),
      'endDate': (endDate ?? startDate).toIso8601String(),
      'notes': notes ?? '',
    });
    return response['requestId'] as String;
  }

  Future<List<models.AvailabilityRequest>> getAvailabilityRequests(
    String rosterId,
  ) async {
    final response = await _get('/availability/requests?rosterId=$rosterId');
    return (response as List<dynamic>)
        .map((item) => models.AvailabilityRequest.fromJson(
              Map<String, dynamic>.from(item as Map),
            ))
        .toList();
  }

  Future<void> reviewAvailabilityRequest({
    required String rosterId,
    required String requestId,
    required models.RequestStatus decision,
    String? note,
  }) async {
    await _post('/availability/approve', {
      'rosterId': rosterId,
      'requestId': requestId,
      'decision': decision.name,
      'note': note ?? '',
    });
  }

  Future<String> createSwapRequest({
    required String rosterId,
    required String fromPerson,
    String? toPerson,
    required DateTime date,
    String? shift,
    String? notes,
  }) async {
    final response = await _post('/swaps/request', {
      'rosterId': rosterId,
      'fromPerson': fromPerson,
      'toPerson': toPerson,
      'date': date.toIso8601String(),
      'shift': shift,
      'notes': notes ?? '',
    });
    return response['requestId'] as String;
  }

  Future<List<models.SwapRequest>> getSwapRequests(String rosterId) async {
    final response = await _get('/swaps/requests?rosterId=$rosterId');
    return (response as List<dynamic>)
        .map((item) => models.SwapRequest.fromJson(
              Map<String, dynamic>.from(item as Map),
            ))
        .toList();
  }

  Future<void> respondSwapRequest({
    required String rosterId,
    required String requestId,
    required models.RequestStatus decision,
    String? note,
  }) async {
    await _post('/swaps/respond', {
      'rosterId': rosterId,
      'requestId': requestId,
      'decision': decision.name,
      'note': note ?? '',
    });
  }

  Future<String> setShiftLock({
    required String rosterId,
    required DateTime date,
    required String shift,
    String? personName,
    String? reason,
  }) async {
    final response = await _post('/locks/set', {
      'rosterId': rosterId,
      'date': date.toIso8601String(),
      'shift': shift,
      'personName': personName,
      'reason': reason ?? '',
    });
    return response['lockId'] as String;
  }

  Future<List<models.ShiftLock>> getShiftLocks(String rosterId) async {
    final response = await _get('/locks?rosterId=$rosterId');
    return (response as List<dynamic>)
        .map((item) => models.ShiftLock.fromJson(
              Map<String, dynamic>.from(item as Map),
            ))
        .toList();
  }

  Future<void> removeShiftLock(String rosterId, String lockId) async {
    await _post('/locks/remove', {
      'rosterId': rosterId,
      'lockId': lockId,
    });
  }

  Future<String> createChangeProposal({
    required String rosterId,
    required String title,
    required Map<String, dynamic> changes,
    String? description,
  }) async {
    final response = await _post('/proposals/create', {
      'rosterId': rosterId,
      'title': title,
      'description': description ?? '',
      'changes': changes,
    });
    return response['proposalId'] as String;
  }

  Future<List<models.ChangeProposal>> getChangeProposals(
    String rosterId,
  ) async {
    final response = await _get('/proposals?rosterId=$rosterId');
    return (response as List<dynamic>)
        .map((item) => models.ChangeProposal.fromJson(
              Map<String, dynamic>.from(item as Map),
            ))
        .toList();
  }

  Future<void> resolveChangeProposal({
    required String rosterId,
    required String proposalId,
    required models.RequestStatus decision,
    String? note,
  }) async {
    await _post('/proposals/resolve', {
      'rosterId': rosterId,
      'proposalId': proposalId,
      'decision': decision.name,
      'note': note ?? '',
    });
  }

  Future<List<models.AuditLogEntry>> getAuditLogs(
    String rosterId,
  ) async {
    final response = await _get('/audit?rosterId=$rosterId');
    return (response as List<dynamic>)
        .map((item) => models.AuditLogEntry.fromJson(
              Map<String, dynamic>.from(item as Map),
            ))
        .toList();
  }

  void subscribeToRosterUpdates(
    String rosterId,
    Function(models.RosterUpdate) onUpdate,
  ) {
    _updatesTimer?.cancel();
    _updatesTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      try {
        final updates = await getRosterUpdates(rosterId, _lastUpdateTimestamp);
        for (final update in updates) {
          onUpdate(update);
          _lastUpdateTimestamp = update.timestamp.toIso8601String();
        }
      } catch (e) {
        debugPrint('Update polling failed: $e');
      }
    });
  }

  Future<List<models.RosterUpdate>> getRosterUpdates(
    String rosterId,
    String? since,
  ) async {
    final query = since != null ? '?rosterId=$rosterId&since=$since' : '?rosterId=$rosterId';
    final response = await _get('/roster/updates$query');
    final list = (response as List<dynamic>)
        .map((item) => models.RosterUpdate.fromJson(
              Map<String, dynamic>.from(item as Map),
            ))
        .toList();
    return list;
  }

  Future<void> publishRosterUpdate(models.RosterUpdate update) async {
    await _post('/roster/update', {
      'rosterId': update.rosterId,
      'update': update.toJson(),
    });
  }

  Future<int> saveRosterData(String rosterId, Map<String, dynamic> data) async {
    final response = await _post('/roster/save', {
      'rosterId': rosterId,
      'data': data,
    });
    return response['version'] as int? ?? 0;
  }

  Future<Map<String, dynamic>?> loadRosterData(String rosterId) async {
    final response = await _get('/roster/load?rosterId=$rosterId');
    if (response == null) return null;
    return Map<String, dynamic>.from(response as Map);
  }

  Future<bool> resolveConflict(
    String rosterId,
    int localVersion,
    Map<String, dynamic> localData,
  ) async {
    final remote = await loadRosterData(rosterId);
    if (remote == null) return true;
    final remoteVersion = remote['version'] as int? ?? 0;
    return localVersion >= remoteVersion;
  }

  Future<dynamic> _get(String path) async {
    final url = Uri.parse('$_apiUrl$path');
    final headers = await _authHeaders('GET', url, '');
    final response = await http.get(url, headers: headers);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response.body.isEmpty ? {} : jsonDecode(response.body);
    }
    throw Exception('AWS API GET error: ${response.statusCode}');
  }

  Future<dynamic> _post(String path, Map<String, dynamic> body) async {
    final url = Uri.parse('$_apiUrl$path');
    final payload = jsonEncode(body);
    final headers = await _authHeaders('POST', url, payload);
    final response = await http.post(
      url,
      headers: headers,
      body: payload,
    );
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response.body.isEmpty ? {} : jsonDecode(response.body);
    }
    throw Exception('AWS API POST error: ${response.statusCode} ${response.body}');
  }

  Future<dynamic> _postNoAuth(String path, Map<String, dynamic> body) async {
    final url = Uri.parse('$_apiUrl$path');
    final response = await http.post(
      url,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response.body.isEmpty ? {} : jsonDecode(response.body);
    }
    throw Exception('AWS API POST error: ${response.statusCode} ${response.body}');
  }

  Map<String, String> _headers() {
    return {'Content-Type': 'application/json'};
  }

  Map<String, String> authHeaders() {
    return _headers();
  }

  Future<Map<String, String>> signedHeaders(
    String method,
    Uri uri,
    String body,
  ) async {
    return _authHeaders(method, uri, body);
  }

  Future<Map<String, String>> _authHeaders(
    String method,
    Uri uri,
    String body,
  ) async {
    await _refreshSessionIfNeeded();
    final token = _accessToken ?? _idToken;
    if (token == null) {
      throw Exception('Not signed in or session expired. Please sign in again.');
    }
    return {
      ..._headers(),
      'Authorization': 'Bearer $token',
    };
  }

  String _formatAmzDate(DateTime date) {
    final two = (int n) => n.toString().padLeft(2, '0');
    return '${date.year}${two(date.month)}${two(date.day)}T${two(date.hour)}${two(date.minute)}${two(date.second)}Z';
  }

  String _formatDate(DateTime date) {
    final two = (int n) => n.toString().padLeft(2, '0');
    return '${date.year}${two(date.month)}${two(date.day)}';
  }

  String _canonicalQuery(Map<String, List<String>> params) {
    if (params.isEmpty) return '';
    final pairs = <String>[];
    final keys = params.keys.toList()..sort();
    for (final key in keys) {
      final values = params[key] ?? [];
      final sortedValues = [...values]..sort();
      for (final value in sortedValues) {
        pairs.add(
          '${Uri.encodeQueryComponent(key)}=${Uri.encodeQueryComponent(value)}',
        );
      }
    }
    return pairs.join('&');
  }

  List<int> _getSignatureKey(
    String key,
    String dateStamp,
    String regionName,
    String serviceName,
  ) {
    List<int> sign(List<int> keyBytes, String data) {
      return Hmac(sha256, keyBytes).convert(utf8.encode(data)).bytes;
    }

    final kDate = sign(utf8.encode('AWS4$key'), dateStamp);
    final kRegion = sign(kDate, regionName);
    final kService = sign(kRegion, serviceName);
    return sign(kService, 'aws4_request');
  }

  Future<String?> getLastRosterId() async {
    if (_userId == null) return null;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('last_roster_id_${_userId ?? 'unknown'}');
  }

  Future<void> setLastRosterId(String? rosterId) async {
    if (_userId == null) return;
    final prefs = await SharedPreferences.getInstance();
    if (rosterId == null || rosterId.isEmpty) {
      await prefs.remove('last_roster_id_${_userId ?? 'unknown'}');
    } else {
      await prefs.setString('last_roster_id_${_userId ?? 'unknown'}', rosterId);
    }
  }
}

