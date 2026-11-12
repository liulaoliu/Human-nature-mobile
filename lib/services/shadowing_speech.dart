/// 朗读实现：`flutter_tts` 的系统合成（不落音频文件）。
///
/// 为什么用系统 TTS 而不是预生成音频：跟读只要求「有个标准音可以跟」，
/// 系统合成够用，而且省掉几百兆音频包。代价是语速/音色跟着系统走，
/// 所以把语速做成可调的、引擎做成可选的，用户自己找舒服的组合。
///
/// 引擎（用哪个合成器）和语言（读什么话）是两件事：
/// 中文引擎读英文会念拼音，英文引擎读中文干脆不发音 —— 所以先 `setEngine`
/// 再钉死 `en-US`，顺序不能反。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../core/ports.dart';
import '../core/tts_engine.dart';

/// 系统 TTS 朗读。
class SystemSpeech implements SpeechPort, SpeechEnginePort {
  SystemSpeech({this.rate = 0.45, this.pitch = 1.0, String? engine})
    : _engine = readTtsEngine(engine);

  final FlutterTts _tts = FlutterTts();

  /// 语速（0–1，系统上限）。跟读建议 0.4–0.5。
  double rate;

  /// 音高。
  final double pitch;

  /// 用哪个合成器；null = 系统默认（用户在手机设置里选的那个）。
  String? _engine;

  bool _ready = false;
  bool _speaking = false;

  @override
  bool get isSpeaking => _speaking;

  /// 当前选中的引擎名（null = 系统默认）。
  String? get engine => _engine;

  Future<void> _ensureReady() async {
    if (_ready) return;
    _ready = true;
    // 先定引擎，再定语言：换引擎会把语言重置回系统默认，
    // 反过来的话 en-US 就白设了。
    await _applyEngine();
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

  Future<void> _applyEngine() async {
    final name = _engine;
    if (name == null) return;
    try {
      await _tts.setEngine(name);
    } catch (e) {
      // 引擎装不上（被卸载 / 名字过期）就退回系统默认，别让朗读整体失败。
      debugPrint('TTS setEngine 失败（退回系统默认）：$e');
      _engine = null;
    }
  }

  /// 列出现在手机上装了的合成引擎。
  ///
  /// 拿不到（老 Android / 权限问题）就给空表 —— 界面只显示「系统默认」。
  /// 注意 `flutter_tts` 的这个成员是 **getter**（`getEngines`），不是方法。
  @override
  Future<List<SpeechEngine>> engines() async {
    try {
      return parseSpeechEngines(await _tts.getEngines);
    } catch (e) {
      debugPrint('TTS 取引擎列表失败：$e');
      return const <SpeechEngine>[];
    }
  }

  /// 换引擎；传 null 回系统默认。
  ///
  /// 下次朗读才真正生效（下次 `_ensureReady` 之前 `_ready` 已经是 true，
  /// 所以这里要把 `_ready` 打回 false 逼它重设一遍）。
  @override
  Future<void> setEngine(String? name) async {
    _engine = readTtsEngine(name);
    _ready = false;
    await _applyEngine();
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
