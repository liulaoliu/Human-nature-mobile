/// 朗读引擎的档位选择与各自的音色表（纯逻辑，不碰平台通道）。
///
/// 为什么要有「多档」而不是只有系统 TTS：
///   1. 系统 TTS 在国产手机上音色差、断句怪，学英语听着别扭；
///   2. 用户 2026-11-15 明确要「像 Web 端那样能选」——Web 端是 Edge 在线朗读
///      （音质最好），外加一个离线兜底；
///   3. 离线档打包进 APK，开箱即用，不联网也能读。
///
/// 各档的取舍（体积 / 内存 / 是否需要网络）：
///   - [TtsProvider.system]：系统自带合成器，0 体积、0 内存，但音色跟着系统走；
///   - [TtsProvider.kitten]：端侧神经 TTS，模型 int8 档 ~24MB（已打进 APK），
///     运行时 ~235MB，纯离线，8 音色；胜在快、省内存，音色一般；
///   - [TtsProvider.kokoro]：端侧神经 TTS，Kokoro-82M q8f16 ~86MB（打进 APK），
///     运行时 ~500MB，纯离线，音色自然得多（用户 2026-11-15 反馈 Kitten
///     「差强人意」后立项，见 `docs/TODO.md` 第二十六件）；
///   - [TtsProvider.edge]：微软 Edge 在线朗读，音质最好、不需要下载任何东西，
///     但**必须联网**，断网就没声 —— 所以它只能当「想听好听的时候」那一档。
library;

/// 朗读引擎。
enum TtsProvider {
  /// 系统 TTS（`flutter_tts`）。永远可用，兜底。
  system,

  /// 端侧神经 TTS（`neural_tts` 的 Kitten int8），模型随 APK 打包。
  kitten,

  /// 端侧神经 TTS（`neural_tts` 的 Kokoro-82M fp16），模型随 APK 打包。
  /// 音色比 Kitten 自然，代价是包体和内存都更大。
  kokoro,

  /// 微软 Edge 在线朗读（`flutter_edge_tts`），需要网络。
  edge,
}

/// 存「用哪一档朗读」的键。存的是 [TtsProvider.name]，不存序号 ——
/// 以后加档位时序号会错位（和主题存名字是同一个理由）。
const String ttsProviderKey = 'tts:provider';

/// 存「用哪个音色」的键（每档各存一份自己的 id 就行，换档时按档位校验）。
const String ttsVoiceKey = 'tts:voice';

/// 给人看的中文名。
const Map<TtsProvider, String> ttsProviderLabel = <TtsProvider, String>{
  TtsProvider.system: '系统朗读',
  TtsProvider.kitten: '离线神经朗读（Kitten）',
  TtsProvider.kokoro: '离线神经朗读（Kokoro）',
  TtsProvider.edge: 'Edge 在线朗读',
};

/// 设置页那一行的副标题：把体积 / 联网 / 内存这些取舍说清楚，
/// 用户自己按手机情况挑。
const Map<TtsProvider, String> ttsProviderHint = <TtsProvider, String>{
  TtsProvider.system: '用手机自带的合成器，不占空间，音色跟着系统走',
  TtsProvider.kitten: '离线、模型已打进 App（约 24MB），运行吃 200MB 上下内存；语速快、音色一般',
  TtsProvider.kokoro: '离线、模型已打进 App（约 86MB），音色自然得多，运行吃 500MB 上下内存',
  TtsProvider.edge: '音质最好，但要联网；断网会自动退回系统朗读',
};

/// 一档朗读的完整信息，给设置页画列表用。
class TtsProviderInfo {
  const TtsProviderInfo({
    required this.provider,
    required this.label,
    required this.hint,
    required this.offline,
  });

  final TtsProvider provider;
  final String label;
  final String hint;

  /// 需不需要网络。设置页据此提示「断开网络就用不了」。
  final bool offline;
}

/// 档位的固定顺序（设置页按这个顺序画）：离线两档在中间，在线档垫底。
const List<TtsProvider> ttsProviders = <TtsProvider>[
  TtsProvider.system,
  TtsProvider.kitten,
  TtsProvider.kokoro,
  TtsProvider.edge,
];

/// 各档的展示信息。
List<TtsProviderInfo> get ttsProviderInfos => <TtsProviderInfo>[
  for (final p in ttsProviders)
    TtsProviderInfo(
      provider: p,
      label: ttsProviderLabel[p] ?? p.name,
      hint: ttsProviderHint[p] ?? '',
      offline: p != TtsProvider.edge,
    ),
];

/// 一个可选的音色。
class TtsVoiceOption {
  const TtsVoiceOption({required this.id, required this.label});

  /// 传给引擎的 id（Kitten 是 `expr-voice-2-f` 这种，Edge 是 `en-US-AriaNeural`）。
  final String id;

  /// 给人看的名字。
  final String label;

  @override
  bool operator ==(Object other) =>
      other is TtsVoiceOption && other.id == id && other.label == label;

  @override
  int get hashCode => Object.hash(id, label);

  @override
  String toString() => 'TtsVoiceOption($id, $label)';
}

/// Kitten 的 8 个音色（与 `neural_tts` 里 `kittenVoices` 的 id 对齐，
/// 这里只留英文名 —— 中文名是我们自己给的，别和引擎 id 混）。
const List<TtsVoiceOption> kittenVoiceOptions = <TtsVoiceOption>[
  TtsVoiceOption(id: 'expr-voice-2-f', label: 'Bella · 女'),
  TtsVoiceOption(id: 'expr-voice-3-f', label: 'Luna · 女'),
  TtsVoiceOption(id: 'expr-voice-4-f', label: 'Rosie · 女'),
  TtsVoiceOption(id: 'expr-voice-5-f', label: 'Kiki · 女'),
  TtsVoiceOption(id: 'expr-voice-2-m', label: 'Jasper · 男'),
  TtsVoiceOption(id: 'expr-voice-3-m', label: 'Bruno · 男'),
  TtsVoiceOption(id: 'expr-voice-4-m', label: 'Hugo · 男'),
  TtsVoiceOption(id: 'expr-voice-5-m', label: 'Leo · 男'),
];

/// Edge 的英文音色（只列几个常用的 —— Edge 目录里 300 多个，
/// 全列出来设置页选不动，而且学习用途只需要美/英各几个）。
const List<TtsVoiceOption> edgeVoiceOptions = <TtsVoiceOption>[
  TtsVoiceOption(id: 'en-US-AriaNeural', label: 'Aria · 美音女'),
  TtsVoiceOption(id: 'en-US-JennyNeural', label: 'Jenny · 美音女'),
  TtsVoiceOption(id: 'en-US-GuyNeural', label: 'Guy · 美音男'),
  TtsVoiceOption(id: 'en-US-ChristopherNeural', label: 'Christopher · 美音男'),
  TtsVoiceOption(id: 'en-GB-SoniaNeural', label: 'Sonia · 英音女'),
  TtsVoiceOption(id: 'en-GB-RyanNeural', label: 'Ryan · 英音男'),
];

/// Kokoro 的 6 个音色（只打这 6 个 style embedding，别把 22 个都塞进 APK）。
///
/// id 与 `neural_tts` 里 `kokoroVoices` 对齐；`bf_*` / `bm_*` 是英式音。
/// 默认 `af_heart`：Kokoro 官方 demo 的默认音色，最稳。
const List<TtsVoiceOption> kokoroVoiceOptions = <TtsVoiceOption>[
  TtsVoiceOption(id: 'af_heart', label: 'Heart · 女'),
  TtsVoiceOption(id: 'af_bella', label: 'Bella · 女'),
  TtsVoiceOption(id: 'af_nicole', label: 'Nicole · 女'),
  TtsVoiceOption(id: 'am_michael', label: 'Michael · 男'),
  TtsVoiceOption(id: 'bf_emma', label: 'Emma · 英音女'),
  TtsVoiceOption(id: 'bm_george', label: 'George · 英音男'),
];

/// 每档的默认音色。系统档没有音色可选，回 null。
String? defaultTtsVoice(TtsProvider provider) {
  switch (provider) {
    case TtsProvider.system:
      return null;
    case TtsProvider.kitten:
      return kittenVoiceOptions.first.id;
    case TtsProvider.kokoro:
      return kokoroVoiceOptions.first.id;
    case TtsProvider.edge:
      return edgeVoiceOptions.first.id;
  }
}

/// 这一档有哪些音色可选（系统档给空表）。
List<TtsVoiceOption> ttsVoiceOptionsOf(TtsProvider provider) {
  switch (provider) {
    case TtsProvider.system:
      return const <TtsVoiceOption>[];
    case TtsProvider.kitten:
      return kittenVoiceOptions;
    case TtsProvider.kokoro:
      return kokoroVoiceOptions;
    case TtsProvider.edge:
      return edgeVoiceOptions;
  }
}

/// 把存下来的档位字符串解析回枚举；认不出 / 空 → 系统档。
///
/// 认不出就回兜底档，而不是抛：手机换过引擎、旧备份里没有这个键、
/// 甚至手改过 prefs —— 任何一种都不该让朗读整体不可用。
TtsProvider parseTtsProvider(Object? raw) {
  final text = raw is String ? raw.trim().toLowerCase() : '';
  for (final p in TtsProvider.values) {
    if (p.name == text) return p;
  }
  return TtsProvider.system;
}

/// 解析存下来的音色：不在这一档的可选列表里就退回默认。
///
/// 为什么要按档位校验：Kitten 和 Edge 的 id 完全不相干，
/// 换档之后拿旧的 id 去喂新引擎只会得到一句「未知音色」。
String? parseTtsVoice(Object? raw, TtsProvider provider) {
  final text = raw is String ? raw.trim() : '';
  if (text.isEmpty) return defaultTtsVoice(provider);
  for (final o in ttsVoiceOptionsOf(provider)) {
    if (o.id == text) return text;
  }
  return defaultTtsVoice(provider);
}

/// 音色 id 的中文名；认不出就把 id 原样还给界面。
String ttsVoiceLabel(TtsProvider provider, String? id) {
  if (id == null || id.isEmpty) return '默认';
  for (final o in ttsVoiceOptionsOf(provider)) {
    if (o.id == id) return o.label;
  }
  return id;
}

/// 把 [SpeechPort.setRate] 那个 0–1 的语速换算成神经引擎的倍率。
///
/// 两套刻度不一样：`flutter_tts` 的 0.5 大概就是「正常语速」，而神经引擎
/// 传的是字面倍率（1.0 = 原速）。跟读默认 0.45 应该落在「略慢但不拖沓」，
/// 所以 0.45 → 0.95、0.5 → 1.0、1.0 → 1.5。
double neuralRateOf(double portRate) => (0.5 + portRate).clamp(0.5, 1.8);

/// 把 0–1 的语速换算成 Edge SSML 的 `rate` 字符串（`+0%` / `-30%` 这种）。
///
/// Edge 的 0% 就是原速，所以 0.5 → `+0%`，0.45 → `-10%`，1.0 → `+100%`。
String edgeRateOf(double portRate) {
  final percent = ((portRate - 0.5) * 200).round();
  final sign = percent >= 0 ? '+' : '';
  return '$sign$percent%';
}
