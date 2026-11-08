/// 词条核心字段来源（唯一事实来源）。
///
/// 字段：音标 / 词性 / 中文释义 / 英英释义。
/// 写入方：AI 查词、离线词典（ECDICT / M-W）、手动编辑。
///
/// 旧数据没有 `fieldSources`：仍按 `status == edited / mastered` 整条锁，
/// 但不假装知道具体来源。
///
/// 对应 Web 版 `src/core/vocabFields.ts`。
library;

import '../models/vocab.dart';

/// 可能被自动覆盖的核心字段（顺序即界面顺序）。
const List<VocabField> vocabFields = <VocabField>[
  VocabField.phonetic,
  VocabField.partOfSpeech,
  VocabField.meaning,
  VocabField.definition,
];

/// 字段来源的合法取值。
const List<VocabFieldSource> vocabFieldSources = <VocabFieldSource>[
  VocabFieldSource.ai,
  VocabFieldSource.dict,
  VocabFieldSource.manual,
];

/// 字段名（落盘 / 备份 JSON 的键）。
const Map<VocabField, String> _fieldNames = <VocabField, String>{
  VocabField.phonetic: 'phonetic',
  VocabField.partOfSpeech: 'partOfSpeech',
  VocabField.meaning: 'meaning',
  VocabField.definition: 'definition',
};

/// 来源名（落盘 / 备份 JSON 的值）。
const Map<VocabFieldSource, String> _sourceNames = <VocabFieldSource, String>{
  VocabFieldSource.ai: 'ai',
  VocabFieldSource.dict: 'dict',
  VocabFieldSource.manual: 'manual',
};

String vocabFieldName(VocabField field) => _fieldNames[field]!;

String vocabFieldSourceName(VocabFieldSource source) => _sourceNames[source]!;

/// 外部字符串 → 字段；不认识返回 null。
VocabField? parseVocabField(Object? raw) {
  if (raw is! String) return null;
  for (final e in _fieldNames.entries) {
    if (e.value == raw) return e.key;
  }
  return null;
}

/// 外部字符串 → 来源；不认识返回 null。
VocabFieldSource? parseVocabFieldSource(Object? raw) {
  if (raw is! String) return null;
  for (final e in _sourceNames.entries) {
    if (e.value == raw) return e.key;
  }
  return null;
}

/// 外部输入（备份 JSON / 本地库）里的字段来源先过这里：只留认识的键值，空对象当没有。
Map<VocabField, VocabFieldSource>? normalizeVocabFieldSources(Object? value) {
  if (value is! Map) return null;
  final out = <VocabField, VocabFieldSource>{};
  for (final field in vocabFields) {
    final source = parseVocabFieldSource(value[_fieldNames[field]]);
    if (source != null) out[field] = source;
  }
  return out.isEmpty ? null : out;
}

/// 这个字段是否禁止自动覆盖。
///
/// - 新数据：只看该字段有没有被手动改过（`fieldSources[field] == manual`）；
/// - 旧数据没有 `fieldSources`：保持原行为，edited / mastered 整条锁；
/// - mastered 始终整条锁（用户已明确掌握，不让自动结果改词义）。
bool isFieldLocked(VocabItem item, VocabField field) {
  if (item.status == VocabStatus.mastered) return true;
  final sources = item.fieldSources;
  if (sources != null) return sources[field] == VocabFieldSource.manual;
  return item.status == VocabStatus.edited;
}

/// 界面标签；没有记录来源时返回空串。
String fieldSourceLabel(VocabFieldSource? source) => switch (source) {
      VocabFieldSource.ai => 'AI',
      VocabFieldSource.dict => '词典',
      VocabFieldSource.manual => '手动',
      null => '',
    };
