import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

class VoiceRecorderResult {
  final String path;
  final int durationMs;

  const VoiceRecorderResult({
    required this.path,
    required this.durationMs,
  });
}

class VoiceRecorderService {
  VoiceRecorderService._();
  static final VoiceRecorderService instance = VoiceRecorderService._();

  AudioRecorder? _recorder;
  bool _isRecording = false;
  String? _path;
  DateTime? _startedAt;

  bool get canRecord {
    if (kIsWeb) return false;
    return Platform.isAndroid;
  }

  AudioRecorder _getRecorder() {
    _recorder ??= AudioRecorder();
    return _recorder!;
  }

  Future<void> start() async {
    if (!canRecord) {
      throw Exception("Запись голосовых доступна только на Android");
    }

    final recorder = _getRecorder();

    final hasPermission = await recorder.hasPermission();
    if (!hasPermission) {
      throw Exception("Нет доступа к микрофону");
    }

    final dir = await getTemporaryDirectory();
    _path = "${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a";
    _startedAt = DateTime.now();

    final file = File(_path!);
    if (await file.exists()) {
      await file.delete();
    }

    try {
      await recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: _path!,
      );
      _isRecording = true;
    } catch (e) {
      _isRecording = false;
      _path = null;
      _startedAt = null;
      throw Exception("Не удалось начать запись: $e");
    }
  }

  Future<VoiceRecorderResult> stop() async {
    if (!canRecord) {
      throw Exception("Запись голосовых доступна только на Android");
    }

    if (!_isRecording || _path == null) {
      throw Exception("Запись не была начата");
    }

    final recorder = _getRecorder();
    final path = await recorder.stop();
    _isRecording = false;

    if (path == null) {
      throw Exception("Не удалось завершить запись");
    }

    final startedAt = _startedAt;
    final durationMs = startedAt == null
        ? 0
        : DateTime.now().difference(startedAt).inMilliseconds;

    _path = null;
    _startedAt = null;

    return VoiceRecorderResult(
      path: path,
      durationMs: durationMs,
    );
  }

  Future<void> cancel() async {
    if (_isRecording && _recorder != null) {
      try {
        await _recorder!.cancel();
      } catch (_) {}
    }

    _isRecording = false;

    final path = _path;
    if (path != null) {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    }

    _path = null;
    _startedAt = null;
  }

  Future<void> dispose() async {
    if (_recorder != null) {
      try {
        if (_isRecording) {
          await _recorder!.cancel();
        }
      } catch (_) {}
      _recorder = null;
    }

    _isRecording = false;
    _path = null;
    _startedAt = null;
  }
}