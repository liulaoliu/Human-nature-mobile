/// 朗读实现：端侧神经 TTS（`neural_tts` 的 Kitten int8 档）。
///
/// 为什么自己管「模型放哪儿」而不走 `neural_tts` 的下载器：
///   1. 用户要求开箱即用 —— 模型随 APK 打包在 `assets/tts/`，首次朗读只做一次
///      「从 assets 拷到应用支持目录」的本地复制，不联网、不需要进度条；
///   2. 它的 `isEngineDownloaded()` 要求 `espeak-ng-data.zip` 解压后的 `.complete`
///      存在，而那个 zip 在 HuggingFace 上已经 404（2026-11-15 实测）——
///      照它的状态判定，永远「没装好」，引擎根本起不来。
///   所以这里只做两件事：把文件摆到位（幂等），然后 `createEngine` + `load`。
///
/// 音素化用**真 espeak-ng**（`EspeakPhonemizer`），不是 Kotlin 那套自己写的
/// 「词典 + 规则瀑布」（2026-11-17 实测：词级词典与句级 espeak 逐词只有
/// **36.8%** 一致 —— 功能词全被塞了主重音、`in the` / `on the` 这类连读也没有，
/// 听起来就是「每个词都对，整句调子不对」）。espeak-ng 的 C 库由 `espeak`
/// 包的 native assets 编进 APK（`lib/arm64-v8a/libespeak_native.so`），
/// 只有数据要自己带：见 [espeakAssetsPrefix]（官方 18MB 里英文用得到的部分，
/// 其中 `lang/` 那棵必须整个带上，见 `installAssetsFromBundle` 的注释）。
///
/// 代价：Android 侧没有逐词进度回调（平台通道只有 initialize/speak/stop 等），
/// 所以**不实现** `SpeechProgressPort` —— 跟读页会自己判「这台设备不亮词」。
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:neural_tts/neural_tts.dart';
import 'package:path_provider/path_provider.dart';

import '../core/ports.dart';
import '../core/tts_chunk.dart';
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
  // Kotlin `KittenEngine.initialize` 仍要这个路径（`dictPath`）：它是插件自带的
  // 词典音素器的输入，正常路径用不到，但缺了 `Phonemizer(dictPath)` 会退化成
  // 纯规则、OOV 兜底也更差。留着以防万一，代价只是 3.4MB。
  'assets/tts/en-us.bin': 'en-us.bin',
};

/// espeak-ng 运行时数据在 assets 里的根目录。
///
/// 落盘位置是 `<支持目录>/tts/espeak/`，目录内容就是官方 `espeak-ng-data` 的
/// 英文子集（2026-11-17 逐文件二分出来，音素输出与完整 18MB 数据逐字节一致）。
///
/// **为什么按目录整棵拷，而不是像 [kittenAssets] 那样列成表**：
/// 2026-11-17 第一版只列了 `lang/{eu,ko,qu}` 三个文件，结果真机上
/// `Espeak.init(..., voice: 'en-us')` 抛 `ArgumentError: Unknown voice: en-us`
/// —— `espeak_SetVoiceByName` 要先读 `lang/gmw/en-US` 才知道 `en-us` 该怎么配，
/// 而 `lang/` 下是 33 个目录 141 个文件（全量只有 15KB），漏一个就整档不可用。
/// 列成表既脆又没法发现遗漏，所以改成读 `AssetManifest` 把整棵树搬过去。
const String espeakAssetsPrefix = 'assets/tts/espeak/';

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
  Phonemizer? _phonemizer;
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
  /// espeak 的英文数据也算在内：少了它 `EspeakPhonemizer` 起不来，
  /// 表现出来是「点了没声音」而不是「读错」，更该在设置页就拦住。
  static Future<bool> modelsPresent() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final tts = Directory('${dir.path}/tts');
      for (final rel in kittenAssets.values) {
        final f = File('${tts.path}/$rel');
        if (!await f.exists() || await f.length() == 0) return false;
      }
      // espeak：只验「起得来的最小集」，不逐个列 141 个 lang 文件。
      for (final rel in const <String>[
        'espeak/en_dict',
        'espeak/phondata',
        'espeak/phontab',
        'espeak/phonindex',
        'espeak/lang/gmw/en-US',
      ]) {
        final f = File('${tts.path}/$rel');
        if (!await f.exists() || await f.length() == 0) return false;
      }
      return true;
    } catch (e) {
      debugPrint('Kitten 模型检查失败：$e');
      return false;
    }
  }

  /// 把 assets 里的文件拷到应用支持目录（已存在且非空的跳过）。
  static Future<void> installAssetsFromBundle() async {
    if (_assetsCopied) return;
    final dir = await getApplicationSupportDirectory();
    final tts = Directory('${dir.path}/tts');
    Future<void> copyOne(String assetKey, String rel) async {
      final target = File('${tts.path}/$rel');
      if (await target.exists() && await target.length() > 0) return;
      await target.parent.create(recursive: true);
      final data = await rootBundle.load(assetKey);
      await target.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
    }

    for (final entry in kittenAssets.entries) {
      await copyOne(entry.key, entry.value);
    }
    // espeak 数据整棵拷：目录里到底有哪些文件由 assets 自己说了算，
    // 免得漏掉 `lang/gmw/en-US` 这种「少一个就 Unknown voice」的关键小文件。
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    for (final key in manifest.listAssets()) {
      if (!key.startsWith(espeakAssetsPrefix)) continue;
      await copyOne(key, key.substring('assets/tts/'.length));
    }
    _assetsCopied = true;
  }

  /// espeak-ng 的数据目录（`<支持目录>/tts/espeak`，里面直接放 `en_dict` 等）。
  static Future<String> espeakDataDir() async {
    final dir = await getApplicationSupportDirectory();
    return '${dir.path}/tts/espeak';
  }

  Future<Engine> _ensureEngine() async {
    final existing = _engine;
    if (_ready && existing != null) return existing;
    await installAssetsFromBundle();
    final engine = createEngine(EngineId.kitten);
    // 音素化交给真 espeak-ng：Kotlin 自己那套「词典 + 规则瀑布」在句子层面
    // 与 espeak 只有 36.8% 一致（功能词被塞主重音、没有连读），见文件头注释。
    final phonemizer = EspeakPhonemizer(dataPath: await espeakDataDir());
    engine.setPhonemizer(phonemizer);
    await engine.load();
    _phonemizer = phonemizer;
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
    final phonemizer = _phonemizer;
    _phonemizer = null;
    try {
      await engine?.release();
    } catch (e) {
      debugPrint('Kitten 释放失败：$e');
    }
    // espeak 的实例是进程级的（`espeak_Terminate` 之后还能重新 init，但
    // 重新 init 要重读 849KB 数据），换音色没必要动它，这里只释放引擎。
    phonemizer?.dispose();
  }

  @override
  Future<void> setRate(double value) async {
    rate = value.clamp(0.1, 1.0);
  }

  /// 送进引擎之前的文本处理：归一化 + 把数字展开成英文单词。
  ///
  /// 为什么还要展开数字：即使音素化换成了真 espeak，它读 `1990s` 也是
  /// "nineteen hundred ninety z"、读 `30,000` 也会带上千分位（2026-11-17 实测）。
  /// 展开成 `nineteen ninety's` / `thirty thousand` 之后 espeak 才是对的，
  /// 所以这一步与用哪套音素器无关，必须留着。
  ///
  /// 为什么不是 `phonemize: false` 交给 Kotlin（2026-11-17 翻案）：Kotlin 那套是
  /// 自己写的「词级词典 + 规则瀑布」，与真 espeak 句子级输出逐词只有 **36.8%**
  /// 一致 —— 功能词（`she`/`he`/`it`/`this`）全被塞了主重音，`in the`、`on the`
  /// 这类连读也没有，模型收到的是训练分布外的韵律，听起来就是「整句调子不对」。
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
      // 按官方口径自己切块、自己音素化（见 [phonemeChunksFor]）。
      final chunks = phonemeChunksFor(raw, _phonemizer);
      await engine.play(
        raw,
        voice,
        rate: neuralRateOf(rate),
        phonemize: true,
        phonemeChunks: chunks,
      );
    } catch (e) {
      debugPrint('Kitten 朗读失败：$e');
      rethrow;
    } finally {
      _speaking = false;
    }
  }

  /// 按官方 `kittentts` 的顺序准备喂给 ONNX 的块。
  ///
  /// 官方流程（`onnx_model.py` 的 `generate` / `_prepare_inputs`）：
  ///   1. `chunk_text(text, max_len=400)` —— 切**原文**；
  ///   2. 每块 `phonemizer.phonemize` —— 真 espeak，句子级（有连读、功能词不加重音）；
  ///   3. 每块 `ref_id = min(len(该块原文), 399)` —— style 行按**原文**长度取。
  ///
  /// 这三步以前分散在 Kotlin 里，且第 2 步用的是「词级词典 + 规则」，第 3 步拿到
  /// 的是音素串长度 —— 三处都与官方不同。现在统一在 Dart 侧按官方顺序做一遍，
  /// 把结果作为 `phonemeChunks` 交给引擎（Kotlin 只负责 ONNX 与播放）。
  ///
  /// [phonemizer] 为 null（比如测试里没初始化 espeak）时返回 null，引擎会退回
  /// 自己的切块 + 词典音素化那条老路。
  @visibleForTesting
  static List<Map<String, Object?>>? phonemeChunksFor(
    String text,
    Phonemizer? phonemizer,
  ) {
    if (phonemizer == null) return null;
    final chunks = ttsChunkText(text);
    if (chunks.isEmpty) return null;
    final out = <Map<String, Object?>>[];
    for (final chunk in chunks) {
      final phonemes = phonemizer.convert(chunk, language: 'en-us').trim();
      if (phonemes.isEmpty) continue;
      out.add({'phonemes': phonemes, 'refLength': chunk.length});
    }
    return out.isEmpty ? null : out;
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
    final phonemizer = _phonemizer;
    _phonemizer = null;
    phonemizer?.dispose();
    if (engine == null) return;
    try {
      await engine.release();
    } catch (e) {
      debugPrint('Kitten 释放失败：$e');
    }
  }
}
