/// 词库 payload 的**行级拆分与重组**（无损，字节级往返）。
///
/// 为什么需要它：`vocab.payload` 是一整段 16.4MB JSON，评一张卡却要重写整份，
/// 真机实测 1.2 秒/张（见 `test/bench/save_stages.dart`）。反转事实来源之后，
/// 每个词条单独一行、库级三段（`articleEntries` / `tombstones` /
/// `sentenceTexts`）单独一行，改一个词只写一行。
///
/// 这一层的唯一职责是保证「拆出去再拼回来，跟原来一模一样」。迁移时用它做
/// 验收：拼回来跟原 payload 逐字节不等就**抛错**，绝不静默丢字段
/// （`reviewState.relearn` / `articleEntries` 这些丢了是补不回来的）。
///
/// 规矩：
/// - **保持键的原始顺序**。重构时按原 payload 里键出现的次序吐出来，`jsonEncode`
///   才能跟原来逐字节相同 —— 顺序变了「内容没变就别写库」的快路径立刻失效。
/// - **不认识的键原样留着**（放进 [VocabRows.extras]），宁可多带一段也不能丢。
/// - 只做 JSON ↔ JSON，不碰模型、不碰数据库（本层属于 `lib/core/`）。
library;

import 'dart:convert';

import '../../models/vocab.dart';
import 'vocab_json.dart';

/// 库级三段的名字，顺序与 `vocabLibraryToJson` 的写出顺序一致。
const List<String> vocabExtrasKeys = <String>[
  'articleEntries',
  'tombstones',
  'sentenceTexts',
];

/// 拆分结果：每个词条一段 JSON 文本 + 库级零碎。
class VocabRows {
  const VocabRows({
    required this.schemaVersion,
    required this.itemKeys,
    required this.itemDocs,
    required this.extras,
  });

  /// 原 payload 的 `schemaVersion`（缺失时按 1 处理，与老库一致）。
  final int schemaVersion;

  /// 每个词条落库时的**行键**，与 [itemDocs] 一一对应、顺序相同。
  ///
  /// 有 `id` 就用 `id`，没有就退回 `@序号`；同一份列表里键重复时追加 `@序号`
  /// 避免撞主键（老数据理论上会重复）。放在这里算，是为了让写库那一层不必为了
  /// 拿键去 `jsonDecode` 每个词条（实测一万词 850ms）。
  final List<String> itemKeys;

  /// 每个词条的 JSON 文本，**列表顺序即原 `items` 顺序**。
  final List<String> itemDocs;

  /// `schemaVersion` / `items` 之外的键，**保持原顺序**。
  final Map<String, Object?> extras;

  bool get isEmpty => itemDocs.isEmpty && extras.isEmpty;

  @override
  String toString() =>
      'VocabRows(schemaVersion: $schemaVersion, items: ${itemDocs.length}, '
      'extras: ${extras.keys.join(',')})';
}

/// 把整库 payload 拆成「每词一行 + 库级一行」的形状。
///
/// [json] 必须是 [vocabLibraryToJson] 那种形状；坏条目（不是 Map 的 items 项）
/// 原样用 `jsonEncode` 存进 [VocabRows.itemDocs]，重组时还原成同一个值 ——
/// 拆分的职责是搬运，不是校验，校验在 `migrateLibrary`。
VocabRows splitVocabPayload(Map<String, Object?> json) {
  final items = json['items'];
  final docs = <String>[];
  final keys = <String>[];
  final used = <String>{};
  if (items is List) {
    for (var i = 0; i < items.length; i++) {
      final it = items[i];
      docs.add(jsonEncode(it));
      final id = it is Map ? _asText(it['id']) : null;
      var key = (id == null || id.isEmpty) ? '@$i' : id;
      if (!used.add(key)) {
        key = '$key@$i';
        used.add(key);
      }
      keys.add(key);
    }
  }
  final extras = <String, Object?>{};
  for (final key in json.keys) {
    if (key == 'schemaVersion' || key == 'items') continue;
    extras[key] = json[key];
  }
  return VocabRows(
    schemaVersion: _asInt(json['schemaVersion']) ?? 1,
    itemKeys: keys,
    itemDocs: docs,
    extras: extras,
  );
}

/// 库级三段（`articleEntries` / `tombstones` / `sentenceTexts`）是否与上一版
/// **同一个对象**。
///
/// 判据用 `identical` 而不是深度比较：这三段加起来可以到十几 MB（真机数据
/// `sentenceTexts` 3512 条），比一遍就是几十毫秒；而调用方的 `copyWith` 在
/// 没改这几段时会把原对象带过来，引用相等是**充分**条件。命不中也只是退回
/// 「重新编码一遍」，结果仍然正确 —— 所以这里宁可漏判，不许误判。
bool sameVocabExtras(VocabLibrary a, VocabLibrary b) =>
    identical(a.sentenceTexts, b.sentenceTexts) &&
    identical(a.articleEntries, b.articleEntries) &&
    identical(a.tombstones, b.tombstones);

/// 从模型**增量**构建行：能复用上一份 doc 的就不重新编码。
///
/// 复用判据默认是**对象引用**（`identical`）：调用方每次评分只 `copyWith` 换掉
/// 那一个 `VocabItem`，其余对象原样带过来，所以这里能便宜地认出「一万词里只有
/// 一条变了」。
///
/// 仓储另有 [reuseIndexes] 通道：`compactSentenceTexts` 每次都会给被剥离句子
/// 原文的词条造新对象，光看 [prevSource] 的引用比对是命不中的（实测全量重编码
/// 318ms）。仓储手上有「调用方传进来那份库」的引用，能准确算出哪些下标没变，
/// 用这个参数直接告诉这里，省掉整轮编码。
///
/// [prev] 与 [prevSource] 必须成对：`prevSource` 是生成 [prev] 时的那份库。
/// 缺任一项就整份重编码 —— 只发生在冷启动后的第一次写。
///
/// [reuseExtras] 为 true 时库级三段（`articleEntries` / `tombstones` /
/// `sentenceTexts`）原样沿用 [prev]：13MB 的 `sentenceTexts` 每次重编码要几十
/// 毫秒，而它只在「真加了一条句子原文」时才需要变。调用方必须自己确认内容
/// 没变（仓储用 `identical` 比 `sentenceTexts` 那张表，命中才开这个开关）。
///
/// 注意：这里编码的是**已经 compact 过**的库（句子原文进了 `sentenceTexts`），
/// 与 [splitVocabPayload] 吃的「落盘形状」一致。
VocabRows nextVocabRows(
  VocabLibrary library, {
  VocabRows? prev,
  VocabLibrary? prevSource,
  Set<int>? reuseIndexes,
  bool reuseExtras = false,
  String Function(VocabItem item)? encodeDoc,
}) {
  final items = library.items;
  final keys = <String>[];
  final docs = <String>[];
  final used = <String>{};
  final canReuse = prev != null && prevSource != null;
  final encode = encodeDoc ?? _encodeItem;

  for (var i = 0; i < items.length; i++) {
    final item = items[i];
    var key = item.id.isEmpty ? '@$i' : item.id;
    if (!used.add(key)) {
      key = '$key@$i';
      used.add(key);
    }
    keys.add(key);
    final aligned = canReuse &&
        i < prevSource.items.length &&
        i < prev.itemDocs.length &&
        prev.itemKeys[i] == key;
    final reuse = aligned &&
        (reuseIndexes != null
            ? reuseIndexes.contains(i)
            : identical(prevSource.items[i], item));
    docs.add(reuse ? prev.itemDocs[i] : encode(item));
  }

  if (reuseExtras && prev != null) {
    return VocabRows(
      schemaVersion: library.schemaVersion,
      itemKeys: keys,
      itemDocs: docs,
      extras: prev.extras,
    );
  }

  final extras = <String, Object?>{};
  if (library.articleEntries.isNotEmpty) {
    extras['articleEntries'] = _extraDoc(
      'articleEntries',
      prev,
      prevSource == null
          ? null
          : identical(prevSource.articleEntries, library.articleEntries),
      () => library.articleEntries
          .map(articleVocabEntryToJson)
          .toList(growable: false),
    );
  }
  if (library.tombstones.isNotEmpty) {
    extras['tombstones'] = _extraDoc(
      'tombstones',
      prev,
      prevSource == null
          ? null
          : identical(prevSource.tombstones, library.tombstones),
      () => library.tombstones.map(vocabTombstoneToJson).toList(growable: false),
    );
  }
  if (library.sentenceTexts.isNotEmpty) {
    extras['sentenceTexts'] = _extraDoc(
      'sentenceTexts',
      prev,
      prevSource == null
          ? null
          : identical(prevSource.sentenceTexts, library.sentenceTexts),
      () => <String, Object?>{
        for (final e in library.sentenceTexts.entries) e.key: e.value,
      },
    );
  }
  return VocabRows(
    schemaVersion: library.schemaVersion,
    itemKeys: keys,
    itemDocs: docs,
    extras: extras,
  );
}

/// 单个词条 → 行 doc。调用方可以传 [encodeDoc] 换成带缓存的版本
/// （仓储按对象引用缓存已编好的 doc，评分时只重编真的变了的那一条）。
String _encodeItem(VocabItem item) => jsonEncode(vocabItemToJson(item));

/// 库级那一段：整段引用没变就原样复用上一份，否则重新编码。
///
/// [reuse] 为 null 表示「没有可比的上一份」；为 true 表示两个集合是同一个对象。
Object? _extraDoc(
  String key,
  VocabRows? prev,
  bool? reuse,
  Object? Function() encode,
) {
  if (reuse == true && prev != null && prev.extras.containsKey(key)) {
    return prev.extras[key];
  }
  return encode();
}

/// 把拆出来的行拼回整库 payload；键的顺序保证与拆分前一致。
Map<String, Object?> assembleVocabPayload(VocabRows rows) {
  final out = <String, Object?>{'schemaVersion': rows.schemaVersion};
  out['items'] = <Object?>[for (final doc in rows.itemDocs) jsonDecode(doc)];
  for (final e in rows.extras.entries) {
    out[e.key] = e.value;
  }
  return out;
}

/// 行 → 落盘 payload 的**紧凑 JSON 文本**（与 [encodeVocabLibrary] 逐字节相同的口径）。
///
/// 不走「先拼 Map 再 `jsonEncode`」：一万词 `vocabLibraryToJson` + `jsonEncode`
/// 实测 500ms，而 [VocabRows.itemDocs] 里已经是编好的字符串，这里只做一次
/// 拼接（17MB 的 memcpy，实测 30ms 量级）。顺序与 [assembleVocabPayload] 一致：
/// `schemaVersion` → `items` → extras 原来的键序。
String encodeVocabRows(VocabRows rows) {
  final b = StringBuffer('{"schemaVersion":')
    ..write(rows.schemaVersion)
    ..write(',"items":[');
  for (var i = 0; i < rows.itemDocs.length; i++) {
    if (i > 0) b.write(',');
    b.write(rows.itemDocs[i]);
  }
  b.write(']');
  for (final e in rows.extras.entries) {
    b
      ..write(',')
      ..write(jsonEncode(e.key))
      ..write(':')
      ..write(jsonEncode(e.value));
  }
  b.write('}');
  return b.toString();
}

/// 两份行是否「内容完全没变」：键、每行 doc、库级三段都要一致。
///
/// 优先用 `identical`：[nextVocabRows] 复用的就是上一份的字符串对象，所以
/// 一万词的「变没变」退化成指针比较，而不是把 13MB 文本逐字比一遍。
bool vocabRowsUnchanged(VocabRows a, VocabRows b) {
  if (a.schemaVersion != b.schemaVersion) return false;
  if (a.itemKeys.length != b.itemKeys.length) return false;
  for (var i = 0; i < a.itemKeys.length; i++) {
    if (a.itemKeys[i] != b.itemKeys[i]) return false;
    if (!_sameText(a.itemDocs[i], b.itemDocs[i])) return false;
  }
  if (a.extras.length != b.extras.length) return false;
  for (final e in a.extras.entries) {
    if (!b.extras.containsKey(e.key)) return false;
    if (!identical(e.value, b.extras[e.key])) return false;
  }
  return true;
}

bool _sameText(String a, String b) => identical(a, b) || a == b;

/// 拆分再重组，返回是否**逐字节相同**（迁移的验收口径）。
///
/// 用字符串比而不是比 Map：Map 的 `==` 不看顺序，而顺序变了就等于白写一次整库。
bool vocabPayloadRoundTrips(Map<String, Object?> json) {
  final before = jsonEncode(json);
  final after = jsonEncode(assembleVocabPayload(splitVocabPayload(json)));
  return before == after;
}

int? _asInt(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v.trim());
  return null;
}

String? _asText(Object? v) {
  if (v is String) return v;
  if (v == null) return null;
  return '$v';
}