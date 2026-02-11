import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:audioplayers/audioplayers.dart';
import '../models.dart' as models;
import '../aws_service.dart';

class VoiceService {
  VoiceService._internal();
  static final VoiceService instance = VoiceService._internal();

  final SpeechToText _speech = SpeechToText();
  final FlutterTts _tts = FlutterTts();
  final AudioPlayer _player = AudioPlayer();
  final ValueNotifier<bool> isListening = ValueNotifier(false);

  bool _initialized = false;
  bool _enabled = false;
  bool _alwaysListening = false;
  bool _manualListening = false;
  String _inputEngine = 'onDevice';
  String _outputEngine = 'aws';
  String _outputVoice = 'aws:Joanna';
  List<String> _wakeWords = const [
    'rc',
    'roster champ',
    'roster champion',
  ];

  Function(String text)? onCommand;
  DateTime? _lastNetworkCheck;
  bool _lastNetworkOk = true;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = await _speech.initialize(
      onStatus: _onStatus,
      onError: (error) => debugPrint('Voice STT error: $error'),
    );
    await _tts.setSpeechRate(0.48);
    await _tts.setPitch(1.0);
  }

  void configure(models.AppSettings settings) {
    _enabled = settings.voiceEnabled;
    _alwaysListening = settings.voiceAlwaysListening;
    _inputEngine = settings.voiceInputEngine;
    _outputEngine = settings.voiceOutputEngine;
    _outputVoice = settings.voiceOutputVoice;
    _wakeWords = settings.voiceWakeWords;

    if (!_enabled) {
      stopListening();
      return;
    }

    if (_alwaysListening && !isListening.value) {
      startListening(pushToTalk: false);
    } else if (!_alwaysListening && !_manualListening) {
      stopListening();
    }
  }

  Future<void> startListening({required bool pushToTalk}) async {
    if (!_enabled) return;
    await initialize();
    if (!_initialized) return;
    if (isListening.value) return;

    _manualListening = pushToTalk;
    isListening.value = true;

    final useOnDevice = _inputEngine == 'onDevice' || !await _hasNetwork();
    try {
      await _speech.listen(
        onResult: _onResult,
        listenMode: ListenMode.confirmation,
        partialResults: true,
        cancelOnError: true,
        onDevice: useOnDevice,
      );
    } catch (e) {
      if (useOnDevice && await _hasNetwork()) {
        await _speech.listen(
          onResult: _onResult,
          listenMode: ListenMode.confirmation,
          partialResults: true,
          cancelOnError: true,
          onDevice: false,
        );
      } else {
        debugPrint('Voice listen failed: $e');
      }
    }
  }

  Future<void> stopListening() async {
    if (!isListening.value) return;
    await _speech.stop();
    isListening.value = false;
    _manualListening = false;
  }

  Future<void> speak(String text, models.AppSettings settings) async {
    if (!settings.voiceEnabled) return;
    final cleaned = text.trim();
    if (cleaned.isEmpty) return;
    if (settings.voiceOutputEngine == 'aws' &&
        AwsService.instance.isAuthenticated &&
        AwsService.instance.region != null) {
      final success = await _speakAws(cleaned);
      if (success) return;
    }
    await _tts.stop();
    if (settings.voiceOutputEngine == 'onDevice') {
      await _applyDeviceVoice(settings.voiceOutputVoice);
    }
    await _tts.speak(cleaned);
  }

  Future<bool> _hasNetwork() async {
    final now = DateTime.now();
    if (_lastNetworkCheck != null &&
        now.difference(_lastNetworkCheck!).inSeconds < 10) {
      return _lastNetworkOk;
    }
    _lastNetworkCheck = now;
    try {
      final result = await InternetAddress.lookup('example.com')
          .timeout(const Duration(seconds: 2));
      _lastNetworkOk = result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (_) {
      _lastNetworkOk = false;
    }
    return _lastNetworkOk;
  }

  void _onStatus(String status) {
    if (status == 'notListening') {
      isListening.value = false;
      if (_enabled && _alwaysListening && !_manualListening) {
        startListening(pushToTalk: false);
      }
    }
  }

  void _onResult(SpeechRecognitionResult result) {
    final text = result.recognizedWords.trim();
    if (text.isEmpty) return;

    if (_manualListening) {
      if (result.finalResult) {
        onCommand?.call(text);
        stopListening();
      }
      return;
    }

    if (!_alwaysListening) return;
    if (!result.finalResult) return;

    final command = _extractWakeCommand(text);
    if (command == null) return;
    onCommand?.call(command);
  }

  String? _extractWakeCommand(String text) {
    final lowered = text.toLowerCase();
    for (final wake in _wakeWords) {
      final idx = lowered.indexOf(wake.toLowerCase());
      if (idx != -1) {
        final after = text.substring(idx + wake.length).trim();
        return after;
      }
    }
    return null;
  }

  Future<bool> _speakAws(String text) async {
    try {
      final region = AwsService.instance.region;
      if (region == null) return false;
      final voiceId = _resolveAwsVoiceId(_outputVoice);
      final url = Uri.parse('https://polly.$region.amazonaws.com/v1/speech');
      final payload = jsonEncode({
        'OutputFormat': 'mp3',
        'Text': text,
        'VoiceId': voiceId,
        'Engine': 'neural',
      });
      final headers = await AwsService.instance.signedAwsHeaders(
        method: 'POST',
        uri: url,
        body: payload,
        service: 'polly',
        extraHeaders: const {
          'Content-Type': 'application/json',
          'Accept': 'audio/mpeg',
        },
      );
      final response = await http.post(
        url,
        headers: headers,
        body: payload,
      );
      if (response.statusCode != 200) {
        debugPrint('Polly TTS error: ${response.statusCode}');
        return false;
      }
      final bytes = response.bodyBytes;
      if (bytes.isEmpty) return false;
      await _player.stop();
      await _player.play(BytesSource(Uint8List.fromList(bytes)));
      return true;
    } catch (e) {
      debugPrint('AWS TTS failed: $e');
      return false;
    }
  }

  String _resolveAwsVoiceId(String value) {
    if (value.startsWith('aws:')) {
      return value.substring('aws:'.length);
    }
    return value.isNotEmpty ? value : 'Joanna';
  }

  Future<void> _applyDeviceVoice(String value) async {
    if (!value.startsWith('device:')) return;
    final payload = value.substring('device:'.length);
    if (payload == 'default') return;
    final parts = payload.split('|');
    if (parts.isEmpty) return;
    final name = parts[0];
    final locale = parts.length > 1 ? parts[1] : null;
    final voice = <String, String>{'name': name};
    if (locale != null && locale.isNotEmpty) {
      voice['locale'] = locale;
    }
    await _tts.setVoice(voice);
  }

  Future<List<Map<String, String>>> getDeviceVoices() async {
    try {
      final voices = await _tts.getVoices;
      final list = <Map<String, String>>[];
      for (final v in voices) {
        if (v is Map) {
          final name = v['name']?.toString();
          final locale = v['locale']?.toString();
          if (name == null || name.isEmpty) continue;
          list.add({
            'name': name,
            'locale': locale ?? '',
          });
        }
      }
      return list;
    } catch (_) {
      return [];
    }
  }
}
