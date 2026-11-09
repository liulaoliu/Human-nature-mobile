/// 朗读实现：`flutter_tts` 的系统合成（不落音频文件）。
///
/// 为什么用系统 TTS 而不是预生成音频：跟读只要求「有个标准音可以跟」，
/// 系统合成够用，而且省掉几百兆音频包。代价是语速/音色跟着系统走，
/// 所以把语速做成可调的，用户自己找舒服的速度。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../core/ports.dart';

/// 系统 TTS 朗读。
class SystemSpeech implements SpeechPort {
  SystemSpeech({this.rate = 0.45, this.pitch = 1.0});

  final FlutterTts _tts = FlutterTts();

  /// 语速（0–1，系统上限）。跟读建议 0.4–0.5。
  double rate;

  /// 音高。
  final double pitch;

  bool _ready = false;
  bool _speaking = false;

  @override
  bool get isSpeaking => _speaking;

  Future<void> _ensureReady() async {
    if (_ready) return;
    _ready = true;
    try {
      // 英语内容，先钉住语言；引擎不支持就保持系统默认，不抛。
      await _tts.setLanguage('en-US');
    } catch (e) {
      debugPrint('TTS setLanguage 失败（保持系统默认）：$e');
    }
    try {
      await _tts.setSpeechRate(rate);
      await _tts.setPitch(pitch);
      // 等真正读完 speak 才返回，界面才好接着开录。
      await _tts.awaitSpeakCompletion(true);
    } catch (e) {
      debugPrint('TTS 参数设置失败：$e');
    }
  }

  /// 调语速（立刻生效，下次朗读用）。
  @override
  Future<void> setRate(double value) async {
    rate = value.clamp(0.1, 1.0);
    try {
      await _tts.setSpeechRate(rate);
    } catch (e) {
      debugPrint('TTS 调语速失败：$e');
    }
  }

  @override
  Future<void> speak(String text) async {
    final raw = text.trim();
    if (raw.isEmpty) return;
    await _ensureReady();
    _speaking = true;
    try {
      await _tts.stop();
      await _tts.speak(raw);
    } catch (e) {
      debugPrint('TTS 朗读失败：$e');
      rethrow;
    } finally {
      _speaking = false;
    }
  }

  @override
  Future<void> stop() async {
    _speaking = false;
    try {
      await _tts.stop();
    } catch (e) {
      debugPrint('TTS 停止失败：$e');
    }
  }

  /// 页面销毁时调（`flutter_tts` 没有 dispose，stop 就是最干净的收尾）。
  Future<void> dispose() => stop();
}
