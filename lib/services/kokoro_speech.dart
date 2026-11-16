/// 朗读实现：端侧神经 TTS（`neural_tts` 的 Kokoro-82M int8 量化档）。
///
/// 为什么要有这一档：用户 2026-11-15 反馈 Kitten 离线档「效果差强人意」，
/// 选了更重的 Kokoro-82M（详见 `docs/TODO.md` 第二十六件）。插件里
/// `KokoroEngine` / `KokoroSession` 已经写好，App 侧要做的只是「把模型文件
/// 摆到位 + 造引擎 + 传音色」——和 [KittenSpeech] 同一套骨架。
///
/// 布局（必须与 `KokoroEngine.initializationArguments()` 对得上）：
///   - `<支持目录>/tts/kokoro/model.onnx`
///   - `<支持目录>/tts/kokoro/tokenizer.json`
///   - `<支持目录>/tts/kokoro/voices/<音色 id>.bin`
///   - `<支持目录>/tts/en-us.bin`（音素词典，与 Kitten 共用一份）
///
/// 不实现 `SpeechProgressPort`：平台通道同样没有逐词区间。
library;

import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:neural_tts/neural_tts.dart';
import 'package:path_provider/path_provider.dart';

import '../core/ports.dart';
import '../core/tts_provider.dart';
import '../core/tts_text.dart';
import 'tts_audio_cache.dart' show TtsAudioCache;

/// 打包资源的版本号。换模型 / tokenizer / 音色时改这里。
///
/// 为什么非要有它：`installAssetsFromBundle` 只在「目标文件不存在」时才拷，
/// 而 App 升级不会清支持目录 —— 换了模型的老安装会一直用旧文件。2026-11-16
/// 就踩过：q8f16 在真机上输出全 NaN（十几秒静音），换 int8 量化版后，手机上
/// 那份旧模型还在，得整个卸载才换得掉。version 对不上就整包重拷。
const String kokoroAssetsRevision = '2026-11-16-int8';

/// 打进 APK 的模型文件：assets 路径 → 在 `<支持目录>/tts/` 下的相对位置。
///
/// 只带 6 个音色（`kokoroVoiceOptions`），22 个全带会多 ~11MB。
const Map<String, String> kokoroAssets = <String, String>{
  'assets/tts/kokoro/model.onnx': 'kokoro/model.onnx',
  'assets/tts/kokoro/tokenizer.json': 'kokoro/tokenizer.json',
  'assets/tts/kokoro/voices/af_heart.bin': 'kokoro/voices/af_heart.bin',
  'assets/tts/kokoro/voices/af_bella.bin': 'kokoro/voices/af_bella.bin',
  'assets/tts/kokoro/voices/af_nicole.bin': 'kokoro/voices/af_nicole.bin',
  'assets/tts/kokoro/voices/am_michael.bin': 'kokoro/voices/am_michael.bin',
  'assets/tts/kokoro/voices/bf_emma.bin': 'kokoro/voices/bf_emma.bin',
  'assets/tts/kokoro/voices/bm_george.bin': 'kokoro/voices/bm_george.bin',
  // 与 Kitten 共用同一份音素词典，别重复打包。
  'assets/tts/en-us.bin': 'en-us.bin',
};

/// 端侧神经朗读（Kokoro-82M）。
class KokoroSpeech implements SpeechPort {
  KokoroSpeech({this.rate = 0.45, String? voice, this.cache})
    : _voiceId = (voice == null || voice.trim().isEmpty)
          ? defaultTtsVoice(TtsProvider.kokoro)
          : parseTtsVoice(voice, TtsProvider.kokoro);

  /// 语速（0–1 档，和 [SystemSpeech] 用同一套刻度）。
  double rate;

  /// 选中的音色 id。
  String? _voiceId;

  /// 预生成音频缓存；命中的句子直接播文件，不加载模型。
  final TtsAudioCache? cache;

  Engine? _engine;
  bool _ready = false;
  bool _speaking = false;
  AudioPlayer? _player;
  Completer<void>? _cachedDone;

  /// 已经拷过文件没有（同一个进程里只拷一次）。
  static bool _assetsCopied = false;

  @override
  bool get isSpeaking => _speaking;

  /// 当前音色 id（设置页显示用）。
  String? get voiceId => _voiceId;

  /// 模型是否已经就位（给设置页 / 集成测试判断「能不能用」）。
  static Future<bool> modelsPresent() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final tts = Directory('${dir.path}/tts');
      for (final rel in kokoroAssets.values) {
        final f = File('${tts.path}/$rel');
        if (!await f.exists() || await f.length() == 0) return false;
      }
      return true;
    } catch (e) {
      debugPrint('Kokoro 模型检查失败：$e');
      return false;
    }
  }

  /// 把 assets 里的模型文件拷到应用支持目录。
  ///
  /// 首次要搬 ~88MB（int8 权重），在 `_ensureEngine` 里同步做 —— 试听第一句
  /// 会等它几秒。之后同一版本不重复搬；[kokoroAssetsRevision] 变了才整包重拷。
  static Future<void> installAssetsFromBundle() async {
    if (_assetsCopied) return;
    final dir = await getApplicationSupportDirectory();
    final tts = Directory('${dir.path}/tts');
    final marker = File('${tts.path}/kokoro/revision.txt');
    final installed = await marker.exists()
        ? (await marker.readAsString()).trim()
        : '';
    if (installed != kokoroAssetsRevision) {
      for (final entry in kokoroAssets.entries) {
        final target = File('${tts.path}/${entry.value}');
        await target.parent.create(recursive: true);
        final data = await rootBundle.load(entry.key);
        await target.writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          flush: true,
        );
      }
      await marker.writeAsString(kokoroAssetsRevision, flush: true);
    }
    _assetsCopied = true;
  }

  Future<Engine> _ensureEngine() async {
    final existing = _engine;
    if (_ready && existing != null) return existing;
    await installAssetsFromBundle();
    final engine = createEngine(EngineId.kokoro);
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
        ? const Voice(id: 'af_heart', name: 'Heart', engine: EngineId.kokoro)
        : voices.first;
  }

  /// 换音色；下次朗读生效。
  Future<void> setVoice(String? id) async {
    final next = parseTtsVoice(id, TtsProvider.kokoro);
    if (next == _voiceId) return;
    _voiceId = next;
    _ready = false;
    final engine = _engine;
    _engine = null;
    try {
      await engine?.release();
    } catch (e) {
      debugPrint('Kokoro 释放失败：$e');
    }
  }

  @override
  Future<void> setRate(double value) async {
    rate = value.clamp(0.1, 1.0);
  }

  @override
  Future<void> speak(String text) async {
    final raw = normalizeTtsText(text);
    if (raw.isEmpty) return;
    _speaking = true;
    try {
      final cached = await cache?.lookup(
        text: raw,
        voice: _voiceId ?? defaultTtsVoice(TtsProvider.kokoro) ?? 'af_heart',
        revision: kokoroAssetsRevision,
      );
      if (cached != null) {
        debugPrint('Kokoro 离线朗读命中缓存：${cached.path}');
        await _playCached(cached);
        return;
      }
      final engine = await _ensureEngine();
      final voice = await _resolveVoice(engine);
      await engine.play(
        raw,
        voice,
        language: 'en-us',
        rate: neuralRateOf(rate),
        phonemize: true,
      );
    } catch (e) {
      debugPrint('Kokoro 朗读失败：$e');
      rethrow;
    } finally {
      _speaking = false;
    }
  }

  /// 只合成、不播放；给「预生成朗读」用。
  Future<void> synthesizeToFile(String text, String path) async {
    final raw = normalizeTtsText(text);
    if (raw.isEmpty) throw ArgumentError.value(text, 'text', '不能为空');
    final engine = await _ensureEngine();
    final voice = await _resolveVoice(engine);
    await engine.synthesizeToFile(
      raw,
      voice,
      path: path,
      language: 'en-us',
      phonemize: true,
    );
  }

  /// 播缓存文件。用独立的 [AudioPlayer]，不经过 500MB 的 ONNX 引擎。
  Future<void> _playCached(File file) async {
    final player = _player ??= AudioPlayer(playerId: 'kokoro_tts_cache');
    final done = Completer<void>();
    _cachedDone = done;
    StreamSubscription<void>? sub;
    try {
      await player.setReleaseMode(ReleaseMode.stop);
      try {
        await player.setPlaybackRate(neuralRateOf(rate).toDouble());
      } catch (e) {
        debugPrint('缓存朗读变速失败，按原速播放：$e');
      }
      sub = player.onPlayerComplete.listen((_) {
        if (!done.isCompleted) done.complete();
      });
      await player.play(DeviceFileSource(file.path));
      await done.future;
    } finally {
      await sub?.cancel();
      if (identical(_cachedDone, done)) _cachedDone = null;
      try {
        await player.stop();
      } catch (_) {
        // 已经播完 / 已经停了。
      }
    }
  }

  @override
  Future<void> stop() async {
    _speaking = false;
    final done = _cachedDone;
    if (done != null && !done.isCompleted) done.complete();
    try {
      await _player?.stop();
    } catch (e) {
      debugPrint('停止缓存朗读失败：$e');
    }
    final engine = _engine;
    if (engine == null) return;
    try {
      await engine.stop();
    } catch (e) {
      debugPrint('Kokoro 停止失败：$e');
    }
  }

  /// 页面销毁 / 换档时调（释放 ONNX 会话，500MB 内存别留在后台）。
  Future<void> dispose() async {
    _speaking = false;
    final done = _cachedDone;
    if (done != null && !done.isCompleted) done.complete();
    final player = _player;
    _player = null;
    try {
      await player?.dispose();
    } catch (e) {
      debugPrint('释放缓存播放器失败：$e');
    }
    final engine = _engine;
    _engine = null;
    _ready = false;
    if (engine == null) return;
    try {
      await engine.release();
    } catch (e) {
      debugPrint('Kokoro 释放失败：$e');
    }
  }
}
