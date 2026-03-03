import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers.dart';
import '../aws_service.dart';
import 'login_screen.dart';
import '../home_screen.dart';
import '../ai_suggestions_view.dart';
import '../import_roster_screen.dart';
import 'package:roster_champ/safe_text_field.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class RosterSharingScreen extends ConsumerStatefulWidget {
  final int initialTabIndex;

  const RosterSharingScreen({
    super.key,
    this.initialTabIndex = 0,
  });

  @override
  ConsumerState<RosterSharingScreen> createState() =>
      _RosterSharingScreenState();
}

class _RosterSharingScreenState extends ConsumerState<RosterSharingScreen> {
  final TextEditingController _rosterNameController = TextEditingController();
  final TextEditingController _rosterIdController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _joinPasswordController = TextEditingController();
  final TextEditingController _accessCodeController = TextEditingController();
  final TextEditingController _maxUsesController = TextEditingController();
  final TextEditingController _customCodeController = TextEditingController();
  final TextEditingController _templateCodeController =
      TextEditingController();
  final TextEditingController _templatePasswordController =
      TextEditingController();
  Timer? _draftTimer;
  Timer? _sessionKeepAlive;
  static const _draftKey = 'roster_create_draft';

  bool _isLoading = false;
  List<Map<String, dynamic>> _userRosters = [];
  String? _lastRosterId;
  String? _selectedRosterId;
  String _shareRole = 'viewer';
  int? _shareExpiresInHours;
  String? _generatedCode;
  List<String> _codeSuggestions = [];
  String _sharePlan = 'none';
  int _sharePlanMaxUses = 0;
  int _sharePlanMaxMonths = 0;
  bool _shareCodesLoading = false;
  List<Map<String, dynamic>> _shareCodes = [];
  String? _pendingTemplateCode;
  String? _pendingTemplatePassword;
  bool _templateIncludeStaff = true;
  bool _templateIncludeOverrides = false;
  bool _templateCompressed = true;
  DateTime? _templateExpiresAt;

  @override
  void initState() {
    super.initState();
    _loadUserRosters();
    _loadSharePlan();
    _loadShareCodes();
    _loadDraft();
    _setupDraftListeners();
    _startSessionKeepAlive();
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    _sessionKeepAlive?.cancel();
    _rosterNameController.dispose();
    _rosterIdController.dispose();
    _passwordController.dispose();
    _joinPasswordController.dispose();
    _accessCodeController.dispose();
    _maxUsesController.dispose();
    _customCodeController.dispose();
    _templateCodeController.dispose();
    _templatePasswordController.dispose();
    super.dispose();
  }

  void _setupDraftListeners() {
    void listener() => _scheduleDraftSave();
    _rosterNameController.addListener(listener);
    _passwordController.addListener(listener);
    _templateCodeController.addListener(listener);
    _templatePasswordController.addListener(listener);
  }

  void _scheduleDraftSave() {
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 600), _saveDraft);
  }

  Future<void> _loadSharePlan() async {
    try {
      final cached = await AwsService.instance.getCachedSubscription();
      final plan = (cached['plan']?.toString().toLowerCase() ?? 'none');
      int maxUses = 0;
      int maxMonths = 0;
      switch (plan) {
        case 'enterprise':
          maxUses = 100;
          maxMonths = 36;
          break;
        case 'operations':
          maxUses = 25;
          maxMonths = 24;
          break;
        case 'starter':
          maxUses = 16;
          maxMonths = 16;
          break;
        default:
          maxUses = 0;
          maxMonths = 0;
      }
      if (mounted) {
        setState(() {
          _sharePlan = plan;
          _sharePlanMaxUses = maxUses;
          _sharePlanMaxMonths = maxMonths;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadShareCodes({String? rosterId}) async {
    setState(() => _shareCodesLoading = true);
    try {
      final response = await AwsService.instance.listShareCodes(
        rosterId: rosterId,
      );
      final items = response['items'];
      if (items is List) {
        _shareCodes = items
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
      } else {
        _shareCodes = [];
      }
    } catch (_) {
      _shareCodes = [];
    }
    if (mounted) {
      setState(() => _shareCodesLoading = false);
    }
  }

  Future<void> _saveDraft() async {
    final payload = <String, dynamic>{
      'rosterName': _rosterNameController.text.trim(),
      'password': _passwordController.text,
      'templateCode': _templateCodeController.text.trim(),
      'templatePassword': _templatePasswordController.text,
      'includeStaff': _templateIncludeStaff,
      'includeOverrides': _templateIncludeOverrides,
      'compressed': _templateCompressed,
      'expiresAt': _templateExpiresAt?.toIso8601String(),
    };
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_draftKey, jsonEncode(payload));
    } catch (_) {}
  }

  Future<void> _loadDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_draftKey);
      if (raw == null || raw.trim().isEmpty) return;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      _rosterNameController.text = data['rosterName']?.toString() ?? '';
      _passwordController.text = data['password']?.toString() ?? '';
      _templateCodeController.text =
          data['templateCode']?.toString() ?? '';
      _templatePasswordController.text =
          data['templatePassword']?.toString() ?? '';
      _templateIncludeStaff =
          data['includeStaff']?.toString() == 'true';
      _templateIncludeOverrides =
          data['includeOverrides']?.toString() == 'true';
      _templateCompressed =
          data['compressed']?.toString() != 'false';
      final expiresRaw = data['expiresAt']?.toString();
      if (expiresRaw != null && expiresRaw.isNotEmpty) {
        _templateExpiresAt = DateTime.tryParse(expiresRaw);
      }
      if (_templateCodeController.text.trim().isNotEmpty) {
        _pendingTemplateCode = _templateCodeController.text.trim();
        _pendingTemplatePassword = _templatePasswordController.text.trim();
      }
    } catch (_) {}
  }

  Future<void> _clearDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_draftKey);
    } catch (_) {}
  }

  void _startSessionKeepAlive() {
    _sessionKeepAlive?.cancel();
    _sessionKeepAlive = Timer.periodic(
      const Duration(minutes: 4),
      (_) async {
        if (!AwsService.instance.isAuthenticated) return;
        await AwsService.instance.ensureSessionFresh();
      },
    );
  }

  Future<void> _loadUserRosters() async {
    setState(() => _isLoading = true);
    try {
      _userRosters = await AwsService.instance.getUserRosters();
      _lastRosterId = await AwsService.instance.getLastRosterId();
      _selectedRosterId =
          AwsService.instance.currentRosterId ?? _lastRosterId;
      if (_selectedRosterId == null && _userRosters.isNotEmpty) {
        final roster = _userRosters.first['rosters'] as Map<String, dynamic>;
        _selectedRosterId = roster['id'] as String?;
      }
    } catch (e) {
      debugPrint('Error loading user rosters: $e');
    }
    setState(() => _isLoading = false);
  }

  Future<void> _createRoster() async {
    if (_rosterNameController.text.trim().isEmpty) {
      final today = DateTime.now();
      final dateLabel =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      final timeLabel =
          '${today.hour.toString().padLeft(2, '0')}${today.minute.toString().padLeft(2, '0')}';
      _rosterNameController.text = _pendingTemplateCode != null &&
              _pendingTemplateCode!.trim().isNotEmpty
          ? 'Template Roster $dateLabel'
          : 'Roster $dateLabel $timeLabel';
    }

    setState(() => _isLoading = true);
    try {
      await AwsService.instance.ensureSessionFresh();
      final password =
          _passwordController.text.isEmpty ? null : _passwordController.text;
      final rosterId = await AwsService.instance.createRoster(
        _rosterNameController.text,
        password,
      );
      await AwsService.instance.setLastRosterId(rosterId);
      await ref.read(rosterProvider).loadFromAWS();
      if (_pendingTemplateCode != null &&
          _pendingTemplateCode!.trim().isNotEmpty) {
        final applied = ref.read(rosterProvider).applyTemplateCode(
              _pendingTemplateCode!,
              includeStaffNames: _templateIncludeStaff,
              includeOverrides: _templateIncludeOverrides,
              password: _pendingTemplatePassword,
            );
        if (applied) {
          await ref.read(rosterProvider).saveToAWS();
        }
        _pendingTemplateCode = null;
        _pendingTemplatePassword = null;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Roster created successfully')),
        );
        await _clearDraft();
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const HomeScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      final message = e.toString();
      if (message.contains('NotAuthorizedException') ||
          message.contains('token expired') ||
          message.contains('Session expired')) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Session expired. Sign in again to finish. Your draft is saved.',
              ),
            ),
          );
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating roster: $e')),
        );
      }
    }
    setState(() => _isLoading = false);
  }

  Future<void> _showTemplateExportDialog() async {
    final roster = ref.read(rosterProvider);
    bool includeStaff = _templateIncludeStaff;
    bool includeOverrides = _templateIncludeOverrides;
    bool compress = _templateCompressed;
    DateTime? expiresAt = _templateExpiresAt;
    String password = _templatePasswordController.text.trim();
    String code = roster.generateTemplateCode(
      includeStaffNames: includeStaff,
      includeOverrides: includeOverrides,
      compress: compress,
      expiresAt: expiresAt,
      password: password.isEmpty ? null : password,
    );
    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('Template Code'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Share this code to clone the roster pattern.'),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    value: includeStaff,
                    onChanged: (value) {
                      includeStaff = value ?? true;
                      code = roster.generateTemplateCode(
                        includeStaffNames: includeStaff,
                        includeOverrides: includeOverrides,
                        compress: compress,
                        expiresAt: expiresAt,
                        password: password.isEmpty ? null : password,
                      );
                      setStateDialog(() {});
                    },
                    title: const Text('Include staff names'),
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  CheckboxListTile(
                    value: includeOverrides,
                    onChanged: (value) {
                      includeOverrides = value ?? false;
                      code = roster.generateTemplateCode(
                        includeStaffNames: includeStaff,
                        includeOverrides: includeOverrides,
                        compress: compress,
                        expiresAt: expiresAt,
                        password: password.isEmpty ? null : password,
                      );
                      setStateDialog(() {});
                    },
                    title: const Text('Include overrides'),
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  CheckboxListTile(
                    value: compress,
                    onChanged: (value) {
                      compress = value ?? true;
                      code = roster.generateTemplateCode(
                        includeStaffNames: includeStaff,
                        includeOverrides: includeOverrides,
                        compress: compress,
                        expiresAt: expiresAt,
                        password: password.isEmpty ? null : password,
                      );
                      setStateDialog(() {});
                    },
                    title: const Text('Compress code'),
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  const SizedBox(height: 8),
                  SafeTextField(
                    controller: _templatePasswordController,
                    decoration: const InputDecoration(
                      labelText: 'Password (optional)',
                      border: OutlineInputBorder(),
                    ),
                    obscureText: true,
                    onChanged: (value) {
                      password = value.trim();
                      code = roster.generateTemplateCode(
                        includeStaffNames: includeStaff,
                        includeOverrides: includeOverrides,
                        compress: compress,
                        expiresAt: expiresAt,
                        password: password.isEmpty ? null : password,
                      );
                      setStateDialog(() {});
                    },
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              firstDate: DateTime.now(),
                              lastDate: DateTime.now().add(
                                const Duration(days: 3650),
                              ),
                              initialDate: DateTime.now()
                                  .add(const Duration(days: 30)),
                            );
                            expiresAt = picked;
                            code = roster.generateTemplateCode(
                              includeStaffNames: includeStaff,
                              includeOverrides: includeOverrides,
                              compress: compress,
                              expiresAt: expiresAt,
                              password: password.isEmpty ? null : password,
                            );
                            setStateDialog(() {});
                          },
                          icon: const Icon(Icons.event),
                          label: Text(
                            expiresAt == null
                                ? 'Set expiry'
                                : 'Expires ${expiresAt!.toLocal().toString().split(' ')[0]}',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (expiresAt != null)
                        IconButton(
                          tooltip: 'Clear expiry',
                          onPressed: () {
                            expiresAt = null;
                            code = roster.generateTemplateCode(
                              includeStaffNames: includeStaff,
                              includeOverrides: includeOverrides,
                              compress: compress,
                              expiresAt: expiresAt,
                              password: password.isEmpty ? null : password,
                            );
                            setStateDialog(() {});
                          },
                          icon: const Icon(Icons.clear),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  QrImageView(
                    data: code,
                    size: 160,
                  ),
                  const SizedBox(height: 8),
                  SelectableText(code),
                ],
              ),
              actions: [
                TextButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: code));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Template code copied')),
                      );
                    }
                  },
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy'),
                ),
                TextButton.icon(
                  onPressed: () async {
                    final controller = TextEditingController();
                    final saved = await showDialog<bool>(
                      context: context,
                      builder: (context) {
                        return AlertDialog(
                          title: const Text('Save as preset'),
                          content: SafeTextField(
                            controller: controller,
                            decoration: const InputDecoration(
                              labelText: 'Preset name',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Cancel'),
                            ),
                            FilledButton(
                              onPressed: () =>
                                  Navigator.pop(context, true),
                              child: const Text('Save'),
                            ),
                          ],
                        );
                      },
                    );
                    if (saved == true) {
                      final ok = ref.read(rosterProvider).saveTemplatePresetFromCode(
                            controller.text.trim().isEmpty
                                ? 'Template'
                                : controller.text.trim(),
                            code,
                            password: password.isEmpty ? null : password,
                          );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              ok ? 'Preset saved' : 'Preset save failed',
                            ),
                          ),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.bookmark_add),
                  label: const Text('Save preset'),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _templateIncludeStaff = includeStaff;
                      _templateIncludeOverrides = includeOverrides;
                      _templateCompressed = compress;
                      _templateExpiresAt = expiresAt;
                    });
                    Navigator.of(context).pop();
                  },
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showTemplateImportDialog() async {
    _templateCodeController.text = _pendingTemplateCode ?? '';
    bool includeStaff = _templateIncludeStaff;
    bool includeOverrides = _templateIncludeOverrides;
    String password = _templatePasswordController.text.trim();
    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            final parse = ref
                .read(rosterProvider)
                .parseTemplateCode(
                  _templateCodeController.text.trim(),
                  password: password.isEmpty ? null : password,
                );
            final payload = parse.payload;
            final summary = payload == null
                ? null
                : 'Cycle ${payload['cycleLength'] ?? 'N/A'} | '
                    'Week start ${payload['weekStartDay'] ?? 'N/A'} | '
                    'Staff ${(payload['staffNames'] as List?)?.length ?? 0}';
            return AlertDialog(
              title: const Text('Use Template Code'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SafeTextField(
                    controller: _templateCodeController,
                    decoration: const InputDecoration(
                      labelText: 'Template Code',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 3,
                    onChanged: (_) => setStateDialog(() {}),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final scanned = await _scanTemplateQr();
                      if (scanned != null && scanned.isNotEmpty) {
                        _templateCodeController.text = scanned;
                        setStateDialog(() {});
                      }
                    },
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Scan QR'),
                  ),
                  const SizedBox(height: 8),
                  SafeTextField(
                    controller: _templatePasswordController,
                    decoration: const InputDecoration(
                      labelText: 'Password (if required)',
                      border: OutlineInputBorder(),
                    ),
                    obscureText: true,
                    onChanged: (value) {
                      password = value.trim();
                      setStateDialog(() {});
                    },
                  ),
                  CheckboxListTile(
                    value: includeStaff,
                    onChanged: (value) {
                      setStateDialog(() => includeStaff = value ?? true);
                    },
                    title: const Text('Include staff names'),
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  CheckboxListTile(
                    value: includeOverrides,
                    onChanged: (value) {
                      setStateDialog(() => includeOverrides = value ?? false);
                    },
                    title: const Text('Include overrides'),
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  const SizedBox(height: 8),
                  if (parse.isValid)
                    Row(
                      children: [
                        const Icon(Icons.check_circle, color: Colors.green),
                        const SizedBox(width: 8),
                        Expanded(child: Text(summary ?? 'Template ready')),
                      ],
                    )
                  else if (parse.error != null)
                    Row(
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red),
                        const SizedBox(width: 8),
                        Expanded(child: Text(parse.error!)),
                      ],
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    setState(() {
                      _pendingTemplateCode =
                          _templateCodeController.text.trim();
                      _templateIncludeStaff = includeStaff;
                      _templateIncludeOverrides = includeOverrides;
                      _pendingTemplatePassword =
                          _templatePasswordController.text.trim().isEmpty
                              ? null
                              : _templatePasswordController.text.trim();
                    });
                    Navigator.of(context).pop();
                  },
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<String?> _scanTemplateQr() async {
    String? result;
    await showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          child: SizedBox(
            width: 320,
            height: 420,
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('Scan Template QR'),
                ),
                Expanded(
                  child: MobileScanner(
                    onDetect: (capture) {
                      final barcode = capture.barcodes.isNotEmpty
                          ? capture.barcodes.first
                          : null;
                      final value = barcode?.rawValue;
                      if (value != null && value.startsWith('RC')) {
                        result = value;
                        Navigator.of(context).pop();
                      }
                    },
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            ),
          ),
        );
      },
    );
    return result;
  }

  Future<void> _joinRoster() async {
    if (_rosterIdController.text.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      final password = _joinPasswordController.text.isEmpty
          ? null
          : _joinPasswordController.text;
      await AwsService.instance
          .joinRoster(_rosterIdController.text, password);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Joined roster successfully')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error joining roster: $e')),
        );
      }
    }
    setState(() => _isLoading = false);
  }

  Future<void> _createShareCode() async {
    final rosterId = _selectedRosterId;
    if (rosterId == null || rosterId.isEmpty) return;
    final maxUsesRaw = _maxUsesController.text.trim();
    final maxUses =
        maxUsesRaw.isEmpty ? null : int.tryParse(maxUsesRaw);
    final customCode = _customCodeController.text.trim();

    setState(() => _isLoading = true);
    try {
      if (customCode.isNotEmpty) {
        try {
          final validation =
              await AwsService.instance.validateShareCode(customCode);
          if (validation['ok'] == true) {
            throw Exception('Share code already in use.');
          }
        } catch (e) {
          final msg = e.toString().toLowerCase();
          if (!msg.contains('not found') && !msg.contains('404')) {
            rethrow;
          }
        }
      }
      final response = await AwsService.instance.createShareCode(
        rosterId: rosterId,
        role: _shareRole,
        expiresInHours: _shareExpiresInHours,
        maxUses: maxUses,
        customCode: customCode.isEmpty ? null : customCode,
      );
      setState(() {
        _generatedCode = response['code'] as String?;
        _codeSuggestions = [];
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Share code created')),
        );
      }
      await _loadShareCodes(rosterId: rosterId);
    } catch (e) {
      final body = _parseErrorBody(e);
      if (body != null && body['suggestions'] is List) {
        setState(() {
          _codeSuggestions = (body['suggestions'] as List)
              .map((item) => item.toString())
              .toList();
        });
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              body?['error']?.toString() ?? 'Error creating share code: $e',
            ),
          ),
        );
      }
    }
    setState(() => _isLoading = false);
  }

  Future<void> _revokeShareCode(String code) async {
    setState(() => _isLoading = true);
    try {
      await AwsService.instance.revokeShareCode(code);
      final rosterId = _selectedRosterId;
      await _loadShareCodes(rosterId: rosterId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Share code revoked')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error revoking share code: $e')),
        );
      }
    }
    setState(() => _isLoading = false);
  }

  Future<void> _copyToClipboard(String value) async {
    if (value.trim().isEmpty) return;
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Access code copied')),
    );
  }

  Future<void> _openSharedRoster() async {
    final code = _accessCodeController.text.trim();
    if (code.isEmpty) return;
    setState(() => _isLoading = true);
    try {
      await AwsService.instance.validateShareCode(code);
      await ref.read(rosterProvider).loadSharedRosterByCode(code);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Shared roster opened')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error opening shared roster: $e')),
        );
      }
    }
    setState(() => _isLoading = false);
  }

  Future<void> _switchRoster(String rosterId) async {
    final isCurrent = AwsService.instance.currentRosterId == rosterId;
    if (!isCurrent) {
      final shouldSwitch = await _confirmRosterSwitch(rosterId);
      if (!shouldSwitch) return;
    }

    setState(() => _isLoading = true);
    try {
      AwsService.instance.currentRosterId = rosterId;
      await AwsService.instance.setLastRosterId(rosterId);
      await ref.read(rosterProvider).loadFromAWS();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Roster switched successfully')),
        );
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const HomeScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error switching roster: $e')),
        );
      }
    }
    setState(() => _isLoading = false);
  }

  Future<bool> _confirmRosterSwitch(String rosterId) async {
    final currentRosterId = AwsService.instance.currentRosterId;
    if (currentRosterId == null || currentRosterId == rosterId) {
      return true;
    }

    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Switch roster?'),
            content: const Text(
              'You are about to leave the current roster. '
              'Make sure your changes are synced before switching.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Switch'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Map<String, dynamic>? _getLastRosterMatch() {
    if (_lastRosterId == null) return null;
    for (final entry in _userRosters) {
      final roster = entry['rosters'] as Map<String, dynamic>;
      if (roster['id'] == _lastRosterId) {
        return entry;
      }
    }
    return null;
  }

  Map<String, dynamic>? _parseErrorBody(Object error) {
    final message = error.toString();
    final start = message.indexOf('{');
    final end = message.lastIndexOf('}');
    if (start == -1 || end == -1 || end <= start) return null;
    try {
      final body = message.substring(start, end + 1);
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final planLabel = _sharePlan.isEmpty || _sharePlan == 'none'
        ? 'No subscription'
        : _sharePlan[0].toUpperCase() + _sharePlan.substring(1);
    final maxMonths = _sharePlanMaxMonths;
    final maxUses = _sharePlanMaxUses;
    final maxHours = maxMonths > 0 ? maxMonths * 30 * 24 : null;
    final expiryOptions = <int?>[];
    if (maxMonths > 0) {
      expiryOptions.add(null);
      for (final hours in [24, 168, 720, 2160]) {
        if (maxHours == null || hours <= maxHours) {
          expiryOptions.add(hours);
        }
      }
    } else {
      expiryOptions.add(null);
      expiryOptions.addAll([24, 168, 720, 2160]);
    }

    return DefaultTabController(
      length: 4,
      initialIndex: widget.initialTabIndex,
      child: Scaffold(
        appBar: AppBar(
          leadingWidth: 84,
          leading: Row(
            children: [
              IconButton(
                tooltip: 'Back',
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.maybePop(context),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => Navigator.maybePop(context),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Image.asset(
                    'assets/images/rc1gold1a.gif',
                    width: 28,
                    height: 28,
                    fit: BoxFit.contain,
                    semanticLabel: 'Roster Champion mascot',
                  ),
                ),
              ),
            ],
          ),
          title: const Text('Roster Sharing'),
          actions: [
            IconButton(
              icon: const Icon(Icons.account_circle_outlined),
              tooltip: 'Account',
              onPressed: _showAccountActions,
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.group), text: 'My Rosters'),
              Tab(icon: Icon(Icons.add), text: 'Create'),
              Tab(icon: Icon(Icons.login), text: 'Join'),
              Tab(icon: Icon(Icons.key), text: 'Access Code'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildMyRostersTab(),
            _buildCreateRosterTab(),
            _buildJoinRosterTab(),
            _buildAccessCodeTab(),
          ],
        ),
      ),
    );
  }

  Future<void> _showAccountActions() async {
    final email = AwsService.instance.userEmail ?? 'Signed in';
    await showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.account_circle_outlined),
              title: Text(email),
              subtitle: const Text('Account'),
            ),
            ListTile(
              leading: const Icon(Icons.switch_account_outlined),
              title: const Text('Switch User'),
              onTap: () async {
                Navigator.pop(context);
                await _signOutAndReturn();
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout_rounded),
              title: const Text('Sign Out'),
              onTap: () async {
                Navigator.pop(context);
                await _signOutAndReturn();
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Future<void> _signOutAndReturn() async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Sign out?'),
            content: const Text('You can sign back in at any time.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Sign out'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    await AwsService.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const LoginScreen()),
      (route) => false,
    );
  }

  Future<void> _openTemplateImport() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ImportRosterScreen(
          openTemplateOnStart: true,
        ),
      ),
    );
  }

  Widget _buildMyRostersTab() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final lastRosterEntry = _getLastRosterMatch();
    final rosterEntries = _userRosters.where((entry) {
      final roster = entry['rosters'] as Map<String, dynamic>;
      return roster['id'] != _lastRosterId;
    }).toList();

    if (_userRosters.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.calendar_today_outlined, size: 64),
              const SizedBox(height: 12),
              const Text('No rosters found yet.'),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _openTemplateImport,
                icon: const Icon(Icons.qr_code_rounded),
                label: const Text('Use Template Code'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          margin: const EdgeInsets.only(bottom: 16),
          child: ListTile(
            leading: const Icon(Icons.qr_code_rounded),
            title: const Text('Use Template Code'),
            subtitle: const Text(
              'Paste a template or scan a QR code to create a new roster.',
            ),
            trailing: FilledButton(
              onPressed: _openTemplateImport,
              child: const Text('Open'),
            ),
          ),
        ),
        if (lastRosterEntry != null)
          _buildLastRosterCard(lastRosterEntry['rosters']
              as Map<String, dynamic>),
        ...rosterEntries.map((entry) {
          final roster = entry['rosters'] as Map<String, dynamic>;
          final memberInfo = entry;
          return _buildRosterCard(roster, memberInfo);
        }).toList(),
      ],
    );
  }

  Widget _buildLastRosterCard(Map<String, dynamic> roster) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: ListTile(
        leading: const Icon(Icons.history),
        title: Text('Resume: ${roster['name']}'),
        subtitle: Text('Last used roster'),
        trailing: FilledButton(
          onPressed: () => _switchRoster(roster['id'] as String),
          child: const Text('Open'),
        ),
      ),
    );
  }

  Widget _buildRosterCard(
    Map<String, dynamic> roster,
    Map<String, dynamic> memberInfo,
  ) {
    final isActive = AwsService.instance.currentRosterId == roster['id'];
    final isOwner = memberInfo['role'] == 'owner';
    final passwordProtected = roster['password_protected'] == true;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(
          passwordProtected ? Icons.lock_outline : Icons.calendar_today,
        ),
        title: Text(roster['name'] as String),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ID: ${roster['id']}'),
            Text('Role: ${memberInfo['role']}'),
            Text(
              'Created: ${DateTime.parse(roster['created_at'] as String).toString().split(' ')[0]}',
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isOwner)
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'Rename roster',
                onPressed: _isLoading
                    ? null
                    : () => _renameRoster(
                          roster['id'] as String,
                          roster['name'] as String,
                        ),
              ),
            if (isOwner)
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                tooltip: 'Delete roster',
                onPressed: _isLoading
                    ? null
                    : () => _deleteRoster(
                          roster['id'] as String,
                          roster['name'] as String,
                        ),
              ),
            if (isActive) ...[
              const Chip(
                label: Text('Active'),
                backgroundColor: Colors.green,
                labelStyle: TextStyle(color: Colors.white),
              ),
              const SizedBox(width: 8),
            ],
            FilledButton(
              onPressed: _isLoading
                  ? null
                  : () => _openRosterFromList(roster),
              child: Text(isActive ? 'Open' : 'Open'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openRosterFromList(Map<String, dynamic> roster) async {
    final rosterId = roster['id'] as String;
    final passwordProtected = roster['password_protected'] == true;
    String? password;
    if (passwordProtected) {
      password = await _promptRosterPassword();
      if (password == null || password.isEmpty) return;
    }
    setState(() => _isLoading = true);
    try {
      if (passwordProtected) {
        await AwsService.instance.joinRoster(rosterId, password);
      }
      await _switchRoster(rosterId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error opening roster: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<String?> _promptRosterPassword() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Roster password required'),
        content: SafeTextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Password',
            border: OutlineInputBorder(),
          ),
          obscureText: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Open'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _deleteRoster(String rosterId, String rosterName) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete roster?'),
            content: Text(
              'This will permanently delete "$rosterName" for all members. '
              'This cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    setState(() => _isLoading = true);
    try {
      await AwsService.instance.deleteRoster(rosterId);
      if (AwsService.instance.currentRosterId == rosterId) {
        ref.read(rosterProvider).clearAllData();
      }
      await _loadUserRosters();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Roster deleted')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting roster: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Widget _buildCreateRosterTab() {
    return Builder(
      builder: (context) {
        final tabController = DefaultTabController.of(context);
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              if (_userRosters.isNotEmpty)
                Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  child: ListTile(
                    leading: const Icon(Icons.folder_open),
                    title: const Text('Open an existing roster'),
                    subtitle:
                        const Text('View and switch to saved rosters first'),
                    trailing: TextButton(
                      onPressed: () => tabController?.animateTo(0),
                      child: const Text('View'),
                    ),
                  ),
                ),
              SafeTextField(
                controller: _rosterNameController,
                decoration: const InputDecoration(
                  labelText: 'Roster Name',
                  hintText: 'Enter roster name (auto-filled if left blank)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Tip: If you are using a template code, we can auto-fill a name.',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ),
              const SizedBox(height: 16),
              SafeTextField(
                controller: _passwordController,
                decoration: const InputDecoration(
                  labelText: 'Password (Optional)',
                  hintText: 'Set a password for this roster',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isLoading ? null : _showTemplateImportDialog,
                      icon: const Icon(Icons.qr_code_2),
                      label: const Text('Use template code'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isLoading ? null : _showTemplateExportDialog,
                      icon: const Icon(Icons.file_download),
                      label: const Text('Generate code'),
                    ),
                  ),
                ],
              ),
              if (_pendingTemplateCode != null &&
                  _pendingTemplateCode!.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Row(
                    children: const [
                      Icon(Icons.check_circle, color: Colors.green, size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Template code will be applied after roster creation.',
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _isLoading ? null : _createRoster,
                child: _isLoading
                    ? const CircularProgressIndicator()
                    : const Text('Create Roster'),
              ),
              const SizedBox(height: 16),
              const Text(
                'Creating a roster will make you the owner. Other users can join using the roster ID and password.',
                style: TextStyle(color: Colors.grey, fontSize: 12),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: Theme.of(context).dividerColor,
                  ),
                ),
                child: SizedBox(
                  height: 300,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: AiSuggestionsView(
                      initialCommand:
                          'Create roster 16 staff 8 weeks start monday',
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _renameRoster(String rosterId, String currentName) async {
    final controller = TextEditingController(text: currentName);
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Rename roster'),
            content: SafeTextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Roster name',
                border: OutlineInputBorder(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Save'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    final nextName = controller.text.trim();
    if (nextName.isEmpty || nextName == currentName) return;
    setState(() => _isLoading = true);
    try {
      await AwsService.instance.renameRoster(rosterId, nextName);
      await _loadUserRosters();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Roster renamed')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error renaming roster: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Widget _buildJoinRosterTab() {
    return Builder(
      builder: (context) {
        final tabController = DefaultTabController.of(context);
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              if (_userRosters.isNotEmpty)
                Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  child: ListTile(
                    leading: const Icon(Icons.folder_open),
                    title: const Text('Open an existing roster'),
                    subtitle:
                        const Text('View and switch to saved rosters first'),
                    trailing: TextButton(
                      onPressed: () => tabController?.animateTo(0),
                      child: const Text('View'),
                    ),
                  ),
                ),
              SafeTextField(
                controller: _rosterIdController,
                decoration: const InputDecoration(
                  labelText: 'Roster ID',
                  hintText: 'Enter roster ID to join',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              SafeTextField(
                controller: _joinPasswordController,
                decoration: const InputDecoration(
                  labelText: 'Password (if required)',
                  hintText: 'Enter roster password',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _isLoading ? null : _joinRoster,
                child: _isLoading
                    ? const CircularProgressIndicator()
                    : const Text('Join Roster'),
              ),
              const SizedBox(height: 16),
              const Text(
                'Ask the roster owner for the roster ID and password to join their roster.',
                style: TextStyle(color: Colors.grey, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAccessCodeTab() {
    final rosterOptions = _userRosters
        .map((entry) => entry['rosters'] as Map<String, dynamic>)
        .toList();
    final canGenerate = rosterOptions.isNotEmpty;
    final planLabel = _sharePlan.isEmpty || _sharePlan == 'none'
        ? 'No subscription'
        : _sharePlan[0].toUpperCase() + _sharePlan.substring(1);
    final maxMonths = _sharePlanMaxMonths;
    final maxUses = _sharePlanMaxUses;
    final maxHours = maxMonths > 0 ? maxMonths * 30 * 24 : null;
    final expiryOptions = <int?>[];
    if (maxMonths > 0) {
      expiryOptions.add(null);
      for (final hours in [24, 168, 720, 2160]) {
        if (maxHours == null || hours <= maxHours) {
          expiryOptions.add(hours);
        }
      }
    } else {
      expiryOptions.add(null);
      expiryOptions.addAll([24, 168, 720, 2160]);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          margin: const EdgeInsets.only(bottom: 16),
          child: ListTile(
            leading: const Icon(Icons.key_rounded),
            title: const Text('Share roster access'),
            subtitle: const Text(
              'Create a unique code for read-only access. Guests can request leave but cannot edit shifts.',
            ),
          ),
        ),
        Card(
          margin: const EdgeInsets.only(bottom: 16),
          child: ListTile(
            leading: const Icon(Icons.workspace_premium_outlined),
            title: Text('Plan limits: $planLabel'),
            subtitle: maxMonths > 0
                ? Text('Up to $maxUses people for $maxMonths months per code.')
                : const Text('Upgrade to Starter to enable access codes.'),
          ),
        ),
        Text(
          'Generate Access Code',
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        if (canGenerate)
          DropdownButtonFormField<String>(
            value: _selectedRosterId,
            items: rosterOptions
                .map(
                  (roster) => DropdownMenuItem<String>(
                    value: roster['id'] as String,
                    child: Text(roster['name'] as String),
                  ),
                )
                .toList(),
            onChanged: (value) {
              setState(() => _selectedRosterId = value);
              _loadShareCodes(rosterId: value);
            },
            decoration: const InputDecoration(
              labelText: 'Roster',
              border: OutlineInputBorder(),
            ),
          )
        else
          Text(
            'No rosters available to share yet.',
            style: GoogleFonts.inter(color: Colors.grey[600]),
          ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _shareRole,
          items: const [
            DropdownMenuItem(value: 'viewer', child: Text('Viewer (read-only)')),
            DropdownMenuItem(value: 'editor', child: Text('Editor (signed-in)')),
          ],
          onChanged: (value) => setState(() {
            if (value != null) _shareRole = value;
          }),
          decoration: const InputDecoration(
            labelText: 'Access level',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int?>(
          value: _shareExpiresInHours,
          items: expiryOptions
              .map(
                (hours) => DropdownMenuItem(
                  value: hours,
                  child: Text(
                    hours == null
                        ? (maxMonths > 0
                            ? 'Plan max ($maxMonths months)'
                            : 'No expiry')
                        : (hours == 24
                            ? 'Expires in 24 hours'
                            : hours == 168
                                ? 'Expires in 7 days'
                                : hours == 720
                                    ? 'Expires in 30 days'
                                    : 'Expires in 90 days'),
                  ),
                ),
              )
              .toList(),
          onChanged: (value) => setState(() => _shareExpiresInHours = value),
          decoration: const InputDecoration(
            labelText: 'Expiry',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        SafeTextField(
          controller: _maxUsesController,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'Max uses (optional)',
            helperText: maxUses > 0
                ? 'Plan max: $maxUses people'
                : 'Requires Starter or higher',
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        SafeTextField(
          controller: _customCodeController,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'Custom code (optional)',
            hintText: 'A-Z and 2-9, 6-12 characters',
            border: OutlineInputBorder(),
          ),
        ),
        if (_codeSuggestions.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'Available suggestions',
            style: GoogleFonts.inter(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: _codeSuggestions
                .map(
                  (code) => ActionChip(
                    label: Text(code),
                    onPressed: () {
                      setState(() {
                        _customCodeController.text = code;
                        _codeSuggestions = [];
                      });
                    },
                  ),
                )
                .toList(),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _isLoading || !canGenerate ? null : _createShareCode,
          child: _isLoading
              ? const CircularProgressIndicator()
              : const Text('Generate Code'),
        ),
        if (_generatedCode != null) ...[
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.key),
              title: Text('Access Code: ${_generatedCode!}'),
              subtitle: const Text('Share this code for roster access'),
              trailing: Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _isLoading
                        ? null
                        : () => _copyToClipboard(_generatedCode!),
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: const Text('Copy'),
                  ),
                  TextButton(
                    onPressed:
                        _isLoading ? null : () => _revokeShareCode(_generatedCode!),
                    child: const Text('Revoke'),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        Text(
          'Active Codes',
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        if (_shareCodesLoading)
          const Center(child: CircularProgressIndicator())
        else if (_shareCodes.isEmpty)
          Text(
            'No active codes yet.',
            style: GoogleFonts.inter(color: Colors.grey[600]),
          )
        else
          ..._shareCodes.map((item) {
            final code = item['code']?.toString() ?? '';
            final status = item['status']?.toString() ?? 'active';
            final uses = item['uses'] ?? 0;
            final maxUses = item['maxUses'];
            final expiresAt = item['expiresAt']?.toString();
            final expired = item['expired'] == true;
            final subtitleParts = <String>[];
            if (maxUses != null) {
              subtitleParts.add('Uses: $uses / $maxUses');
            } else {
              subtitleParts.add('Uses: $uses');
            }
            if (expiresAt != null && expiresAt.isNotEmpty) {
              subtitleParts.add('Expires: $expiresAt');
            }
            if (expired) subtitleParts.add('Expired');
            if (status == 'revoked') subtitleParts.add('Revoked');
            final subtitle = subtitleParts.join(' • ');
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const Icon(Icons.vpn_key_outlined),
                title: Text(code),
                subtitle: Text(subtitle),
                trailing: Wrap(
                  spacing: 8,
                  children: [
                    IconButton(
                      tooltip: 'Copy code',
                      onPressed: _isLoading ? null : () => _copyToClipboard(code),
                      icon: const Icon(Icons.copy_rounded),
                    ),
                    if (status == 'active')
                      TextButton(
                        onPressed:
                            _isLoading ? null : () => _revokeShareCode(code),
                        child: const Text('Revoke'),
                      )
                    else
                      const SizedBox.shrink(),
                  ],
                ),
              ),
            );
          }).toList(),
        const SizedBox(height: 24),
        Text(
          'Open Shared Roster',
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        SafeTextField(
          controller: _accessCodeController,
          decoration: const InputDecoration(
            labelText: 'Access code',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _isLoading ? null : _openSharedRoster,
          child: _isLoading
              ? const CircularProgressIndicator()
              : const Text('Open Roster'),
        ),
        const SizedBox(height: 12),
        Text(
          'Editors must be signed in. Guests always open read-only.',
          style: GoogleFonts.inter(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }
}
