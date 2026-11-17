/// 朗读实现：端侧神经 TTS（`neural_tts` 的 Kitten int8 档）。
///
/// 为什么自己管「模型放哪儿」而不走 `neural_tts` 的下载器：
///   1. 用户要求开箱即用 —— 模型随 APK 打包在 `assets/tts/`，首次朗读只做一次
///      「从 assets 拷到应用支持目录」的本地复制，不联网、不需要进度条；
///   2. 它的 `isEngineDownloaded()` 要求 `espeak-ng-data.zip` 解压后的 `.complete`
///      存在，而那个 zip 在 HuggingFace 上已经 404（2026-11-15 实测）——
///      照它的状态判定，永远「没装好」，引擎根本起不来。
///   所以这里只做两件事：把四个文件摆到位（幂等），然后 `createEngine` + `load`。
///   音素化交给引擎自己（`phonemize: false` → Kotlin 查 `assets/tts/en-us.bin`
///   这本 12.4 万词的 espeak 词典），**不要**用 Dart 的 `phonemize` 包算好再传：
///   那条路与真 espeak 逐字节只有 2.4% 一致（见 [KittenSpeech.prepareText] 的注释）。
///
/// 代价：Android 侧没有逐词进度回调（平台通道只有 initialize/speak/stop 等），
/// 所以**不实现** `SpeechProgressPort` —— 跟读页会自己判「这台设备不亮词」。
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:neural_tts/neural_tts.dart';
import 'package:path_provider/path_provider.dart';

import '../core/ports.dart';
import '../core/tts_number_words.dart';
import '../core/tts_provider.dart';
import '../core/tts_text.dart';

/// 打进 APK 的模型文件：assets 路径 → 在 `<支持目录>/tts/` 下的相对位置。
///
/// 布局要和 `neural_tts` 的 `initializationArguments()` 对得上：
/// 模型与音色在 `<tts>/kitten/`，音素词典在 `<tts>/en-us.bin`。
const Map<String, String> kittenAssets = <String, String>{
  'assets/tts/kitten/kitten_tts_nano_v0_8.onnx': 'kitten/kitten_tts_nano_v0_8.onnx',
  'assets/tts/kitten/voices.npz': 'kitten/voices.npz',
  'assets/tts/kitten/config.json': 'kitten/config.json',
  'assets/tts/en-us.bin': 'en-us.bin',
};

/// 端侧神经朗读（Kitten）。
class KittenSpeech implements SpeechPort {
  KittenSpeech({this.rate = 0.45, String? voice})
    : _voiceId = (voice == null || voice.trim().isEmpty)
          ? defaultTtsVoice(TtsProvider.kitten)
          : parseTtsVoice(voice, TtsProvider.kitten);

  /// 语速（0–1 档，和 [SystemSpeech] 用同一套刻度）。
  double rate;

  /// 选中的音色 id。
  String? _voiceId;

  Engine? _engine;
  bool _ready = false;
  bool _speaking = false;

  /// 已经拷过文件没有（同一个进程里只拷一次）。
  static bool _assetsCopied = false;

  @override
  bool get isSpeaking => _speaking;

  /// 当前音色 id（设置页显示用）。
  String? get voiceId => _voiceId;

  /// 模型是否已经就位（给设置页判断「能不能用」）。
  ///
  /// 只看文件在不在 —— 这是唯一可靠的判据（见文件头第 2 条）。
  static Future<bool> modelsPresent() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final tts = Directory('${dir.path}/tts');
      for (final rel in kittenAssets.values) {
        final f = File('${tts.path}/$rel');
        if (!await f.exists() || await f.length() == 0) return false;
      }
      return true;
    } catch (e) {
      debugPrint('Kitten 模型检查失败：$e');
      return false;
    }
  }

  /// 把 assets 里的四个文件拷到应用支持目录（已存在且非空的跳过）。
  static Future<void> installAssetsFromBundle() async {
    if (_assetsCopied) return;
    final dir = await getApplicationSupportDirectory();
    final tts = Directory('${dir.path}/tts');
    for (final entry in kittenAssets.entries) {
      final target = File('${tts.path}/${entry.value}');
      if (await target.exists() && await target.length() > 0) continue;
      await target.parent.create(recursive: true);
      final data = await rootBundle.load(entry.key);
      await target.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
    }
    _assetsCopied = true;
  }

  Future<Engine> _ensureEngine() async {
    final existing = _engine;
    if (_ready && existing != null) return existing;
    await installAssetsFromBundle();
    final engine = createEngine(EngineId.kitten);
    await engine.load();
    _engine = engine;
    _ready = true;
    return engine;
  }

  Future<Voice> _resolveVoice(Engine engine) async {
    final voices = await engine.getVoices();
    final want = _voiceId;
    for (final v in voices) {
      if (v.id == want) return v;
    }
    return voices.isEmpty
        ? const Voice(id: 'expr-voice-2-f', name: 'Bella', engine: EngineId.kitten)
        : voices.first;
  }

  /// 换音色；下次朗读生效。
  Future<void> setVoice(String? id) async {
    final next = parseTtsVoice(id, TtsProvider.kitten);
    if (next == _voiceId) return;
    _voiceId = next;
    _ready = false;
    final engine = _engine;
    _engine = null;
    try {
      await engine?.release();
    } catch (e) {
      debugPrint('Kitten 释放失败：$e');
    }
  }

  @override
  Future<void> setRate(double value) async {
    rate = value.clamp(0.1, 1.0);
  }

  /// 送进引擎之前的文本处理：归一化 + 把数字展开成英文单词。
  ///
  /// 为什么要自己展开数字：Kitten 的音素来自 `assets/tts/en-us.bin`（espeak 词典，
  /// 12.4 万词），而 Kotlin 侧 `Phonemizer.convert` 里的 `expandDigits` 是**逐位**
  /// 替换 —— `"30,000"` 会变成 `"three zero, zero zero zero"`、`"1990's"` 变成
  /// `"one nine nine zero's"`。所以数字必须在 Dart 侧先变成单词，那边就没有数字可拆。
  ///
  /// 为什么不是 `phonemize: true`（2026-11-17 实测）：那会让 Dart 的 `phonemize`
  /// 包用 espeak 的**规则**音素化，而它的输出与真 espeak（同一本词典）逐字节只有
  /// **2.4%** 一致 —— 重音位置、`ɝ`/`ɫ`、`hw` 全不一样，听起来就是
  /// "reading makes fit"。改成 `phonemize: false` 让引擎用自带词典，一致率 **92.6%**。
  @visibleForTesting
  static String prepareText(String text) {
    final normalized = normalizeTtsText(text);
    if (normalized.trim().isEmpty) return '';
    return expandTtsNumbers(normalized).trim();
  }

  @override
  Future<void> speak(String text) async {
    final raw = prepareText(text);
    if (raw.isEmpty) return;
    _speaking = true;
    try {
      final engine = await _ensureEngine();
      final voice = await _resolveVoice(engine);
      await engine.play(raw, voice, rate: neuralRateOf(rate), phonemize: false);
    } catch (e) {
      debugPrint('Kitten 朗读失败：$e');
      rethrow;
    } finally {
      _speaking = false;
    }
  }

  @override
  Future<void> stop() async {
    _speaking = false;
    final engine = _engine;
    if (engine == null) return;
    try {
      await engine.stop();
    } catch (e) {
      debugPrint('Kitten 停止失败：$e');
    }
  }

  /// 页面销毁时调（释放 ONNX 会话，别把 200MB 内存留在后台）。
  Future<void> dispose() async {
    _speaking = false;
    final engine = _engine;
    _engine = null;
    _ready = false;
    if (engine == null) return;
    try {
      await engine.release();
    } catch (e) {
      debugPrint('Kitten 释放失败：$e');
    }
  }
}
