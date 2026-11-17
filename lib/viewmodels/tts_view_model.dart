/// 朗读设置：选哪一档、选哪个音色，并把选择立刻作用到全 App 的朗读上。
///
/// 为什么做成一个全局 ViewModel 而不是每页自己读 prefs：
///   - 「用哪一档朗读」是**全局唯一**的一个状态（精读点句、背单词、拷打、
///     跟读都读同一份），按项目的「一组状态一个写入方」约定，
///     它只能有一个写入方 —— 就是这里；
///   - 六处 ViewModel 拿的是同一个 [PickSpeech] 实例，换档当场生效，
///     用户不用重启 App 就能试听。
library;

import 'package:flutter/foundation.dart';

import '../core/tts_engine.dart';
import '../core/tts_provider.dart';
import '../data/prefs_store.dart';
import '../data/tts_prefs.dart';
import '../services/pick_speech.dart';
import '../services/shadowing_speech.dart';
import '../services/tts_audio_cache.dart';

/// 朗读档位 + 音色的选择。
class TtsViewModel extends ChangeNotifier {
  TtsViewModel({required PrefsStore prefsStore, TtsAudioCache? audioCache})
    : _prefs = TtsPrefs(prefsStore),
      _provider = TtsPrefs(prefsStore).loadProvider(),
      _systemEngine = TtsPrefs(prefsStore).loadEngine() {
    final voice = _prefs.loadVoice(_provider);
    _voice = voice;
    // 语速按档读：Kitten 的默认值和另外三档不一样（见 defaultTtsRateOf）。
    _rate = _prefs.loadRate(_provider);
    _speech = PickSpeech(
      provider: _provider,
      voice: voice,
      systemEngine: _systemEngine,
      cache: audioCache,
      rate: _rate,
    );
  }

  final TtsPrefs _prefs;
  late final PickSpeech _speech;
  String? _systemEngine;

  TtsProvider _provider;
  String? _voice;
  double _rate = 0.45;

  /// 全 App 共用的朗读入口（带兜底）。
  PickSpeech get speech => _speech;

  /// 现在用哪一档。
  TtsProvider get provider => _provider;

  /// 现在用哪个音色（系统档为 null）。
  String? get voice => _voice;

  /// 当前这一档的语速（0–1 刻度，0.5 大致是正常语速）。
  ///
  /// **每档各存一份**：用户 2026-11-17 要求「不同引擎分开，因为不同引擎设置不同」。
  double get rate => _rate;

  /// 这一档的音色选项（系统档为空表）。
  List<TtsVoiceOption> get voiceOptions => ttsVoiceOptionsOf(_provider);

  /// 音色在界面上的名字。
  String get voiceLabel => ttsVoiceLabel(_provider, _voice);

  /// 最近一次朗读有没有退回系统档（设置页据此提示）。
  bool get fellBack => _speech.fellBack;

  /// 退回系统档的原因（一句话，给用户看；没退回时是 null）。
  String? get fallbackReason => _speech.fallbackReason;

  /// 换档：先落盘，再重建朗读实现（换档当场生效）。
  ///
  /// 语速也一起换 —— 读回**新档**自己存的那份，而不是沿用旧档的值。
  Future<void> setProvider(TtsProvider next) async {
    if (next == _provider) return;
    _provider = next;
    final voice = parseTtsVoice(_prefs.loadVoice(next), next);
    _voice = voice;
    _rate = _prefs.loadRate(next);
    notifyListeners();
    await _prefs.saveProvider(next);
    await _prefs.saveVoice(voice);
    await _speech.setProvider(next);
    await _speech.setVoice(voice);
    await _speech.setRate(_rate);
    notifyListeners();
  }

  /// 调当前这一档的语速，存本机（只影响这一档）。
  Future<void> setRate(double next) async {
    final value = next.clamp(minTtsRate, maxTtsRate);
    if (value == _rate) return;
    _rate = value;
    notifyListeners();
    await _prefs.saveRate(_provider, value);
    await _speech.setRate(value);
    notifyListeners();
  }

  /// 换音色：只影响当前档。
  Future<void> setVoice(String? next) async {
    final value = parseTtsVoice(next, _provider);
    if (value == _voice) return;
    _voice = value;
    notifyListeners();
    await _prefs.saveVoice(value);
    await _speech.setVoice(value);
    notifyListeners();
  }

  /// 系统档的合成引擎（手机里装了多个 TTS 时可选）。
  ///
  /// 只对系统档有意义，其它档忽略。
  Future<List<SpeechEngine>> systemEngines() async {
    final system = _speech.delegate;
    if (system is SystemSpeech) return system.engines();
    return const <SpeechEngine>[];
  }

  /// 现在选的是哪个系统合成器（null = 手机设置的默认）。
  String? get systemEngine => _systemEngine;

  /// 换系统合成引擎（null = 手机设置的默认）。
  Future<void> setSystemEngine(String? name) async {
    _systemEngine = name;
    await _prefs.saveEngine(name);
    final system = _speech.delegate;
    if (system is SystemSpeech) await system.setEngine(name);
    notifyListeners();
  }

  /// 试听：读一句短句，让用户当场听出差别。
  ///
  /// 失败（比如联网档断网）不弹错 —— [PickSpeech] 会自动退回系统朗读，
  /// 用户至少能听到声音，设置页再用 [fellBack] 提示一句。
  Future<void> preview() async {
    await _speech.speak('Reading makes perfect.');
    notifyListeners();
  }

  /// 停下试听。
  Future<void> stopPreview() async {
    await _speech.stop();
    notifyListeners();
  }
}
