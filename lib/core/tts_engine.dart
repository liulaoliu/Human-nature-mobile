/// 朗读引擎的选择与回放相关的纯逻辑。
///
/// 两件事：
///   1. **引擎列表的守卫**：`flutter_tts.getEngines()` 在 Android 上返回一串
///      `{name, label, ...}` 的 map，字段可能缺、可能是 null、也可能整串不是列表。
///      界面直接吃这块数据会崩，所以先过 [parseSpeechEngines]。
///   2. **记住选过的引擎**：存 `shared_preferences`，键 [ttsEngineKey]。
///      空串 / 没存过 = 用系统默认（用户在手机设置里选的那个）。
///
/// 为什么引擎和语言要分开：中文书用英文引擎会读出拼音，英文书用中文引擎
/// 干脆不发音。引擎是「用哪个合成器」，语言是「这次读什么话」，两码事。
library;

/// 一个可用的系统朗读引擎。
class SpeechEngine {
  const SpeechEngine({required this.name, required this.label});

  /// 给 `setEngine` 用的包名 / 标识。
  final String name;

  /// 给人看的名字（`label` 缺了就退回 `name`）。
  final String label;

  @override
  bool operator ==(Object other) =>
      other is SpeechEngine && other.name == name && other.label == label;

  @override
  int get hashCode => Object.hash(name, label);

  @override
  String toString() => 'SpeechEngine($name, $label)';
}

/// 存「用哪个朗读引擎」的键（空串 = 系统默认）。
const String ttsEngineKey = 'tts:engine';

/// 把 `getEngines()` 的原始返回解析成引擎列表。
///
/// 规则：
///   - 不是 `List` → 空表（界面显示「系统默认」即可，不报错）；
///   - 每项不是 `Map` 或没有非空 `name` → 跳过；
///   - `label` 缺失 / 空 → 用 `name`；
///   - 同 `name` 只留第一条（有的系统会重复列出）。
List<SpeechEngine> parseSpeechEngines(Object? raw) {
  if (raw is! List) return const <SpeechEngine>[];
  final seen = <String>{};
  final out = <SpeechEngine>[];
  for (final item in raw) {
    if (item is! Map) continue;
    final name = _text(item['name']);
    if (name.isEmpty) continue;
    if (!seen.add(name)) continue;
    final label = _text(item['label']);
    out.add(SpeechEngine(name: name, label: label.isEmpty ? name : label));
  }
  return List<SpeechEngine>.unmodifiable(out);
}

/// 读存下来的引擎名：空 / 没存过回 null（= 系统默认）。
String? readTtsEngine(String? raw) {
  final v = (raw ?? '').trim();
  return v.isEmpty ? null : v;
}

/// 当前选中的引擎在列表里还存不存在。
///
/// 卸载一个引擎之后，存的名字会变成悬空的 —— 这时应当退回系统默认，
/// 而不是拿着一个装不上的名字去 `setEngine`（那会一直抛）。
String? resolveTtsEngine(String? saved, List<SpeechEngine> engines) {
  final name = readTtsEngine(saved);
  if (name == null) return null;
  for (final e in engines) {
    if (e.name == name) return name;
  }
  return null;
}

/// 把列表里的引擎翻译成中文标签之外的显示名（`label` 里常带厂商名）。
String speechEngineLabel(SpeechEngine engine) => engine.label;

String _text(Object? raw) => raw is String ? raw.trim() : '';
