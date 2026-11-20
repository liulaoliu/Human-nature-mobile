/// 朗读的统一入口：按用户在设置里选的那一档造实现，并在需要时自动兜底。
///
/// 六处 ViewModel 注入的都是这一个对象（`main.dart` 里造一次），
/// 用户换档 / 换音色走的都是它 —— 这样「哪一档」这件事只有一个写入方。
///
/// 兜底规则（用户 2026-11-15 拍板「1 兜底」）：
///   - 系统档：直接系统朗读，没有兜底可退；
///   - Kitten 档：模型拷不来 / ONNX 起不来 → 这一次退回系统朗读，并记住
///     「降级过」让设置页能提示（下次仍会先试 Kitten，用户换了手机能自愈）；
///   - Kokoro 档：同上（模型更大，起不来时同样只降级这一次）；
///   - Edge 档：断网 / 被墙 / 合成超时 → 这一次退回系统朗读。
///
/// 为什么不在构造时就选定实现：启动时不知道手机会不会连网，
/// 而且换档不该要求重启 App。所以持有一个可变委托，换档当场换掉。
library;

import 'package:flutter/foundation.dart';

import '../core/ports.dart';
import '../core/tts_engine.dart';
import '../core/tts_provider.dart';
import 'edge_speech.dart';
import 'kitten_speech.dart';
import 'kokoro_speech.dart';
import 'shadowing_speech.dart';
import 'tts_audio_cache.dart';

/// 按档位造一个朗读实现。
///
/// [voice] 是用户选音色（系统档忽略）。造不出来（缺插件 / 平台不支持）时
/// 返回 [SystemSpeech]，让朗读整体可用。
///
/// [cache] 只给 Kokoro 用：缓存命中的句子直接播文件，连模型都不加载。
SpeechPort createSpeechFor(
  TtsProvider provider, {
  String? voice,
  String? systemEngine,
  TtsAudioCache? cache,
  double rate = 0.45,
}) {
  switch (provider) {
    case TtsProvider.system:
      return SystemSpeech(engine: systemEngine, rate: rate);
    case TtsProvider.kitten:
      return KittenSpeech(voice: voice, rate: rate);
    case TtsProvider.kokoro:
      return KokoroSpeech(voice: voice, cache: cache, rate: rate);
    case TtsProvider.edge:
      return EdgeSpeech(voice: voice, rate: rate);
  }
}

/// 带兜底的朗读入口。
///
/// 也实现 [SpeechEnginePort]（「挑系统合成引擎」）：只有系统档支持，
/// 别的档现问现答返回空表 —— 这样跟读页那个引擎选择器不用改，
/// 换了档只是列表变空/变有，不会因为类型不对就整块消失。
class PickSpeech implements SpeechPort, SpeechEnginePort, SpeechProgressPort {
  PickSpeech({
    TtsProvider provider = TtsProvider.system,
    String? voice,
    String? systemEngine,
    this.cache,
    double? rate,
  }) : _current = provider,
       _voiceId = voice,
       _engineHint = systemEngine,
       _rate = rate ?? defaultTtsRateOf(provider) {
    _delegate = _build();
    _forwardListener();
  }

  TtsProvider _current;
  String? _voiceId;

  /// 用哪个系统合成器。
  ///
  /// **可变**（33.8）：用户在设置页选了引擎 B、再切到 Kokoro 档、再切回系统档时，
  /// 重建出来的 `SystemSpeech` 要还是 B。以前它是 `final` 且 [setEngine] 只转发给
  /// 当前 delegate 不更新这里，于是「切回系统档」和「降级兜底」都会跳回系统默认。
  String? _engineHint;

  final TtsAudioCache? cache;

  late SpeechPort _delegate;

  /// 上一次朗读是否发生了降级（设置页 / 设置页的提示用）。
  bool _fellBack = false;

  /// 降级的原因（给人看的一句话；没降级时是 null）。
  ///
  /// 为什么非要有它：用户 2026-11-15 报「Edge 换任意音色试听，听起来都和系统
  /// 默认一样」—— 实际上 Edge 的 WSS 握手被服务端 403，这里静默退回了系统
  /// 朗读，界面只在列表最底部写了一行小字，用户根本没看见。所以他以为音色
  /// 换了不生效，实际是「换的那一档压根没出声」。
  String? _fallbackReason;

  void Function(int start, int end)? _wordListener;

  /// 当前档位。
  TtsProvider get provider => _current;

  /// 当前音色 id。
  String? get voice => _voiceId;

  /// 最近一次朗读是不是退回了系统朗读。
  bool get fellBack => _fellBack;

  /// 退回系统朗读的原因（没退回时是 null）。
  String? get fallbackReason => _fallbackReason;

  SpeechPort get delegate => _delegate;

  SpeechPort _build() => createSpeechFor(
    _current,
    voice: _voiceId,
    systemEngine: _engineHint,
    cache: cache,
    rate: _rate,
  );

  void _forwardListener() {
    final listener = _wordListener;
    final d = _delegate;
    if (d is SpeechProgressPort) {
      (d as SpeechProgressPort).setWordListener(listener);
    }
  }

  @override
  void setWordListener(void Function(int start, int end)? listener) {
    _wordListener = listener;
    _forwardListener();
  }

  /// 换档（设置页刚改完就调）。旧实现的资源会尽量释放。
  Future<void> setProvider(TtsProvider next) async {
    if (next == _current) return;
    await _releaseDelegate();
    _current = next;
    _fellBack = false;
    _fallbackReason = null;
    _delegate = _build();
    _forwardListener();
  }

  /// 换音色（只影响当前档；换档后由 `setProvider` 重造实现）。
  Future<void> setVoice(String? next) async {
    if (next == _voiceId) return;
    _voiceId = next;
    _fellBack = false;
    _fallbackReason = null;
    await _releaseDelegate();
    _delegate = _build();
    _forwardListener();
  }

  Future<void> _releaseDelegate() async {
    final d = _delegate;
    try {
      if (d is KittenSpeech) {
        await d.dispose();
      } else if (d is KokoroSpeech) {
        await d.dispose();
      } else if (d is EdgeSpeech) {
        await d.dispose();
      }
    } catch (e) {
      debugPrint('释放朗读实现失败：$e');
    }
  }

  @override
  bool get isSpeaking => _delegate.isSpeaking;

  /// 现在装了哪些系统合成引擎。
  ///
  /// 非系统档返回空表（神经档的音色是 App 自己给的，不是手机装的合成器）。
  @override
  Future<List<SpeechEngine>> engines() async {
    final d = _delegate;
    if (d is SpeechEnginePort) {
      return (d as SpeechEnginePort).engines();
    }
    return const <SpeechEngine>[];
  }

  /// 换系统合成引擎；非系统档只记下来，下次切回系统档时用。
  @override
  Future<void> setEngine(String? name) async {
    // 先记下来（33.8）：`_engineHint` 决定下次 `_build()` 造什么、兜底用什么。
    // 以前只在它是当前 delegate 时转发，切档后就忘了用户选过哪个引擎。
    _engineHint = readTtsEngine(name);
    final d = _delegate;
    if (d is SpeechEnginePort) {
      await (d as SpeechEnginePort).setEngine(_engineHint);
    }
    // 兜底实现是常驻的，也要跟着换 —— 降级时不能又跳回系统默认引擎。
    final fb = _fallback;
    if (fb != null && fb is SpeechEnginePort && !identical(fb, d)) {
      await (fb as SpeechEnginePort).setEngine(_engineHint);
    }
  }

  /// 记住上一次设过的语速（`setRate` 传进来的），兜底时沿用 ——
  /// 否则降级后语速会跳回默认，跟读的节奏就乱了。
  ///
  /// 构造时由 [TtsViewModel] 按**当前档**的偏好传进来（每档各存一份，
  /// 见 `core/tts_provider.dart` 的 [ttsRateKey]）。
  double _rate;

  /// 当前语速：0.1–1.5 的刻度，具体上限按档取（`maxTtsRateOf`）——
  /// 系统档与 Edge 封顶 1.0，Kokoro / Kitten 能到 1.5。
  double get rate => _rate;

  @override
  Future<void> setRate(double rate) async {
    _rate = rate;
    await _delegate.setRate(rate);
    final fb = _fallback;
    if (fb != null && !identical(fb, _delegate)) {
      await fb.setRate(rate);
    }
  }

  /// 只合成、不播放（预生成朗读用）。只有 Kokoro 档支持。
  ///
  /// 返回实际写出的文件路径（AAC 编码器失败时会退成 WAV）。
  Future<String> synthesizeToFile(String text, String path) async {
    final d = _delegate;
    if (d is KokoroSpeech) {
      return d.synthesizeToFile(text, path);
    }
    throw StateError('当前朗读档不是 Kokoro，无法生成离线音频');
  }

  SpeechPort? _fallback;

  /// 常驻一个系统实现做兜底 —— 造它是免费的（`FlutterTts` 构造不碰通道），
  /// 而且降级时能立刻用，不用等第二次构造。
  SpeechPort _fallbackOf() => _fallback ??= SystemSpeech(engine: _engineHint);

  @override
  Future<void> speak(String text) async {
    final raw = text.trim();
    if (raw.isEmpty) return;
    try {
      await _delegate.speak(raw);
      _fellBack = false;
      _fallbackReason = null;
    } catch (e) {
      if (_current == TtsProvider.system) rethrow;
      final why = _explain(e);
      debugPrint('${ttsProviderLabel[_current]} 朗读失败，退回系统朗读：$e');
      _fellBack = true;
      _fallbackReason = why;
      final fb = _fallbackOf();
      await fb.setRate(_rate);
      await fb.speak(raw);
    }
  }

  /// 把底层异常翻译成一句人话 —— 设置页要把它原样显示给用户。
  ///
  /// 用户看不懂 `EdgeTtsException(websocket_upgrade_failed): ... status 403`；
  /// 但「连不上微软的朗读服务」+「已经用系统朗读代替」这两件事他得知道，
  /// 否则就会像 2026-11-15 那样以为「换音色没生效」。
  String _explain(Object error) {
    final text = error.toString();
    switch (_current) {
      case TtsProvider.edge:
        final blocked =
            text.contains('403') ||
            text.contains('401') ||
            text.contains('websocket_upgrade_failed') ||
            text.contains('connection_failed');
        if (blocked) {
          return '连不上微软的在线朗读服务（${_shortOf(error)}），'
              '这一次用的是系统朗读 —— 换个网络再试，或者先用离线神经朗读。';
        }
        return '在线朗读失败（${_shortOf(error)}），这一次用的是系统朗读。';
      case TtsProvider.kitten:
        return '离线神经朗读没跑起来（${_shortOf(error)}），'
            '这一次用的是系统朗读 —— 模型文件可能没装全，重启 App 再试。';
      case TtsProvider.kokoro:
        return 'Kokoro 离线朗读没跑起来（${_shortOf(error)}），'
            '这一次用的是系统朗读 —— 模型文件可能没装全，重启 App 再试。';
      case TtsProvider.system:
        return _shortOf(error);
    }
  }

  /// 异常名 + 关键片段，去掉又长又没用的堆栈。
  String _shortOf(Object error) {
    final full = error.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (full.length <= 90) return full;
    return '${full.substring(0, 90)}…';
  }

  @override
  Future<void> stop() async {
    try {
      await _delegate.stop();
    } catch (e) {
      debugPrint('停止朗读失败：$e');
    }
    try {
      await _fallback?.stop();
    } catch (e) {
      debugPrint('停止兜底朗读失败：$e');
    }
  }
}
