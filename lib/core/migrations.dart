/// 词库的老数据兼容 / 迁移**唯一收口**。
///
/// 以前这些散落在加载路径上：`dedupeLibrary` → `normalizeGrammarMarks` → `repairLanguageKinds`，
/// 各自还带一点「缺字段怎么办」的临时判断；时间一长没人知道总共迁过什么。
/// 现在：**新老字段差异、兼容、去重、清洗全在这里**，加载只调一次 `migrateLibrary`。
///
/// 约定：
///   - 只做「补默认值 / 归一 / 去重 / 丢弃无法修复的条目」，**绝不删用户的正常数据**；
///   - 迁移必须**幂等**（跑两遍结果一样）；
///   - 破坏性变更要升 `vocabSchemaVersion`，在老版本上先补一个 `migrateVnToVn+1`。
///
/// 对应 Web 版 `src/core/migrations.ts`（369 行）。
library;

import '../models/vocab.dart';
import 'entry_kind.dart';
import 'lang_points.dart';
import 'vocab/merge.dart';
import 'vocab/sentence_texts.dart';
import 'vocab/tombstones.dart';
import 'vocab/word.dart';
import 'vocab_confusables.dart';
import 'vocab_fields.dart';
import 'vocab_via.dart';

String _str(Object? v) => v is String ? v : '';

String? _strOrNull(Object? v) {
  if (v is! String) return null;
  return v.trim().isNotEmpty ? v : null;
}

List<String> _strArray(Object? v) =>
    v is List ? v.whereType<String>().toList(growable: false) : const [];

/// 能解析的 ISO 就用，否则退回 [fallback]。
String _iso(Object? v, String fallback) {
  final s = _str(v);
  if (s.isEmpty) return fallback;
  return DateTime.tryParse(s) != null ? s : fallback;
}

/// 已经形如 ISO 8601（`YYYY-MM-DDTHH:...`）。校验/自检用。
final RegExp isoIsh = RegExp(r'^\d{4}-\d{2}-\d{2}T');

final Set<VocabItemKind> _kinds = kindOrder.map(_toItemKind).toSet();

VocabItemKind _toItemKind(VocabKind kind) => switch (kind) {
      VocabKind.word => VocabItemKind.word,
      VocabKind.phrase => VocabItemKind.phrase,
      VocabKind.idiom => VocabItemKind.idiom,
      VocabKind.usage => VocabItemKind.usage,
    };

VocabItemKind? _parseKind(Object? v) {
  if (v is! String) return null;
  for (final k in _kinds) {
    if (k.name == v) return k;
  }
  return null;
}

const Set<String> _statusNames = {'unqueried', 'queried', 'edited', 'mastered'};

VocabStatus? _parseStatus(Object? v) {
  if (v is! String || !_statusNames.contains(v)) return null;
  for (final s in VocabStatus.values) {
    if (s.name == v) return s;
  }
  return null;
}

/// 已经是当前结构的条目：**原样返回**。
///
/// 为什么在意这点：加载路径会用「条目引用有没有变」判断要不要写库。
/// 如果这里每次都重建对象，就会**每打开一次页面白写一次词库**（还顺带追加快照）。
///
/// Dart 侧只有「已经是 [VocabItem]」这一种能原样复用的情况；
/// JSON 解出来的 Map 必须重建。
VocabItem? _migrateItem(Object? raw, String now) {
  if (raw is VocabItem) return raw;
  if (raw is! Map) return null;
  final o = raw;

  final word = _str(o['word']).trim();
  final lemmaRaw = _str(o['lemma']).trim();
  final lemma = lemmaRaw.isNotEmpty ? lemmaRaw : word.toLowerCase();
  if (word.isEmpty || lemma.isEmpty) return null;

  final kind = _parseKind(o['kind']);
  final status = _parseStatus(o['status']) ??
      (_str(o['meaning']).isNotEmpty ? VocabStatus.queried : VocabStatus.unqueried);
  final rs = o['reviewState'] is Map ? o['reviewState'] as Map : const {};
  final due = _strOrNull(rs['due']);

  num? numOf(Object? v) => v is num ? v : null;

  final ease = numOf(rs['ease']);
  final interval = numOf(rs['interval']);
  final repetitions = numOf(rs['repetitions']);
  final lapses = numOf(rs['lapses']);
  final relearn = numOf(rs['relearn']);
  final passes = numOf(rs['meaningPasses']);

  final examples = <VocabExample>[];
  final rawExamples = o['examples'];
  if (rawExamples is List) {
    for (final e in rawExamples) {
      final ex = e is Map ? e : const {};
      final text = _str(ex['text']).trim();
      if (text.isEmpty) continue;
      examples.add(VocabExample(
        text: text,
        translation: _strOrNull(ex['translation']),
        articleId: _strOrNull(ex['articleId']),
        fileName: _strOrNull(ex['fileName']),
        sentenceId: _strOrNull(ex['sentenceId']),
        origin: _parseExampleOrigin(ex['origin']),
      ));
    }
  }

  VocabSource? source;
  final rawSource = o['source'];
  if (rawSource is Map) {
    final articleId = _str(rawSource['articleId']).trim();
    if (articleId.isNotEmpty) {
      source = VocabSource(
        articleId: articleId,
        fileName: _strOrNull(rawSource['fileName']),
        sentenceId: _strOrNull(rawSource['sentenceId']),
        sentenceText: _str(rawSource['sentenceText']),
      );
    }
  }

  final contexts = <VocabContext>[];
  final rawContexts = o['contexts'];
  if (rawContexts is List) {
    for (final c in rawContexts) {
      final cc = c is Map ? c : const {};
      final articleId = _str(cc['articleId']).trim();
      if (articleId.isEmpty) continue;
      contexts.add(VocabContext(
        articleId: articleId,
        fileName: _strOrNull(cc['fileName']),
        sentenceId: _strOrNull(cc['sentenceId']),
        sentenceText: _str(cc['sentenceText']),
        meaning: _strOrNull(cc['meaning']),
        at: _iso(cc['at'], now),
      ));
    }
  }

  List<VocabConfusable>? confusables;
  final rawConfusables = o['confusables'];
  if (rawConfusables is List) {
    final out = <VocabConfusable>[];
    for (final c in rawConfusables) {
      final cc = c is Map ? c : const {};
      final w = _str(cc['word']).trim();
      if (w.isEmpty) continue;
      out.add(VocabConfusable(word: w, meaning: _strOrNull(cc['meaning'])));
    }
    confusables = out;
  }

  List<String>? optionalStrings(Object? v) => v is List ? _strArray(v) : null;

  final meaning = cleanGloss(_str(o['meaning']));
  final definition = cleanGloss(_str(o['definition']));

  return VocabItem(
    id: _str(o['id']).trim().isNotEmpty ? _str(o['id']).trim() : 'vocab:$lemma',
    word: word,
    lemma: lemma,
    kind: kind,
    langPointId: o['langPointId'] is String ? o['langPointId'] as String : null,
    phonetic: _strOrNull(o['phonetic']),
    partOfSpeech: _strOrNull(o['partOfSpeech']),
    meaning: meaning.isEmpty ? null : meaning,
    grammarMarks: optionalStrings(o['grammarMarks']),
    definition: definition.isEmpty ? null : definition,
    fieldSources: normalizeVocabFieldSources(o['fieldSources']),
    usage: _strArray(o['usage']),
    phrases: optionalStrings(o['phrases']),
    idioms: optionalStrings(o['idioms']),
    examples: examples,
    source: source,
    contexts: contexts,
    status: status,
    note: _str(o['note']),
    tags: _strArray(o['tags']),
    lastPrintedAt: _strOrNull(o['lastPrintedAt']),
    confusables: confusables,
    confusablesSource: parseVocabConfusableSource(o['confusablesSource']),
    priorityUntil: _strOrNull(o['priorityUntil']),
    reviewState: ReviewState(
      ease: ease != null && ease > 0 ? ease.toDouble() : 2.5,
      due: due,
      interval: interval != null && interval >= 0 ? interval.toInt() : 0,
      repetitions: repetitions != null && repetitions >= 0 ? repetitions.toInt() : 0,
      lapses: lapses != null && lapses >= 0 ? lapses.toInt() : 0,
      relearn: relearn != null && relearn > 0 ? relearn.toInt() : 0,
      // 「没看答案就选对释义」的次数：老数据没有，按 0（首次选对只判模糊）
      meaningPasses: passes != null && passes > 0 ? passes.toInt() : 0,
    ),
    createdAt: _iso(o['createdAt'], now),
    updatedAt: _iso(o['updatedAt'], now),
  );
}

VocabExampleOrigin? _parseExampleOrigin(Object? v) {
  if (v is! String) return null;
  for (final o in VocabExampleOrigin.values) {
    if (o.name == v) return o;
  }
  return null;
}

VocabMeaningSource? _parseMeaningSource(Object? v) {
  if (v is! String) return null;
  for (final s in VocabMeaningSource.values) {
    if (s.name == v) return s;
  }
  return null;
}

ArticleVocabEntry? _migrateEntry(
  Object? raw,
  Map<String, VocabItem> items,
  String now,
) {
  if (raw is ArticleVocabEntry) {
    // 已是当前结构：只要指向的词还在就原样复用。
    return items.containsKey(raw.lemma) ? raw : null;
  }
  if (raw is! Map) return null;
  final articleId = _str(raw['articleId']).trim();
  final lemma = _str(raw['lemma']).trim();
  if (articleId.isEmpty || lemma.isEmpty) return null;
  if (!items.containsKey(lemma)) return null;
  return ArticleVocabEntry(
    articleId: articleId,
    lemma: lemma,
    origin: raw['origin'] == 'auto' ? VocabOrigin.auto : VocabOrigin.manual,
    via: parseVocabVia(raw['via']),
    addedAt: _iso(raw['addedAt'], now),
    sentenceId: _strOrNull(raw['sentenceId']),
    sentenceText: _str(raw['sentenceText']),
    meaning: _strOrNull(raw['meaning']),
    meaningSource: _parseMeaningSource(raw['meaningSource']),
    printedAt: _strOrNull(raw['printedAt']),
  );
}

/// 老数据没有按篇表：只从能证明「在这一篇标过」的来源/语境补，绝不按正文出现推。
List<ArticleVocabEntry> _deriveLegacyEntries(List<VocabItem> items, String now) {
  final derived = <({ArticleVocabEntry entry, int order})>[];
  var order = 0;
  for (final it in items) {
    if (it.status == VocabStatus.mastered) continue;
    final byArticle = <String, ArticleVocabEntry>{};

    final sourceArticle = it.source?.fileName?.trim() ?? '';
    if (sourceArticle.isNotEmpty) {
      byArticle[sourceArticle] = ArticleVocabEntry(
        articleId: sourceArticle,
        lemma: it.lemma,
        origin: VocabOrigin.manual,
        via: VocabVia.legacy,
        addedAt: it.createdAt.isNotEmpty ? it.createdAt : now,
        sentenceId: it.source?.sentenceId,
        sentenceText: it.source?.sentenceText ?? '',
        printedAt: it.lastPrintedAt,
      );
    }

    for (final c in it.contexts ?? const <VocabContext>[]) {
      final articleId = c.fileName?.trim() ?? '';
      if (articleId.isEmpty) continue;
      final prev = byArticle[articleId];
      if (prev != null) {
        var sentenceId = prev.sentenceId;
        var sentenceText = prev.sentenceText;
        var meaning = prev.meaning;
        var meaningSource = prev.meaningSource;
        if ((sentenceId ?? '').isEmpty && c.sentenceId != null) sentenceId = c.sentenceId;
        if ((sentenceText ?? '').isEmpty && c.sentenceText.isNotEmpty) {
          sentenceText = c.sentenceText;
        }
        if ((meaning ?? '').isEmpty && (c.meaning?.trim().isNotEmpty ?? false)) {
          meaning = c.meaning!.trim();
          meaningSource = VocabMeaningSource.context;
        }
        byArticle[articleId] = prev.copyWith(
          sentenceId: sentenceId,
          sentenceText: sentenceText,
          meaning: () => meaning,
          meaningSource: meaningSource,
        );
        continue;
      }
      byArticle[articleId] = ArticleVocabEntry(
        articleId: articleId,
        lemma: it.lemma,
        origin: VocabOrigin.manual,
        via: VocabVia.legacy,
        addedAt: _iso(c.at, now),
        sentenceId: c.sentenceId,
        sentenceText: c.sentenceText,
        meaning: _strOrNull(c.meaning),
        meaningSource: (c.meaning?.trim().isNotEmpty ?? false)
            ? VocabMeaningSource.context
            : null,
        printedAt: it.lastPrintedAt,
      );
    }

    for (final e in byArticle.values) {
      derived.add((entry: e, order: order++));
    }
  }
  // 加入时间升序；同一时刻按词条顺序稳定
  derived.sort((a, b) {
    final byAt = a.entry.addedAt.compareTo(b.entry.addedAt);
    return byAt != 0 ? byAt : a.order - b.order;
  });
  return derived.map((x) => x.entry).toList(growable: false);
}

/// 解析一条墓碑。
///
/// Web 版 `JSON.parse` 出来就是最终形状，Dart 侧必须显式转：
/// 不认识 `kind` 的、`key` 为空的直接丢（墓碑没有键就没法匹配，留着只会误删）。
VocabTombstone? _parseTombstone(Object? raw, String now) {
  if (raw is VocabTombstone) return raw.key.isEmpty ? null : raw;
  if (raw is! Map) return null;
  final key = _str(raw['key']).trim();
  if (key.isEmpty) return null;
  final kindRaw = _str(raw['kind']);
  // 只有 item / article 两种键；缺省按 item（老数据只记过全库词条），
  // 但写成不认识的值就说明数据坏了，丢掉比猜错安全（猜错会误删词）。
  final VocabTombstoneKind kind;
  if (kindRaw.isEmpty || kindRaw == 'item') {
    kind = VocabTombstoneKind.item;
  } else if (kindRaw == 'article') {
    kind = VocabTombstoneKind.article;
  } else {
    return null;
  }
  return VocabTombstone(
    kind: kind,
    key: key,
    at: _iso(raw['at'], now),
    lemma: _strOrNull(raw['lemma']),
  );
}

List<ArticleVocabEntry> _migrateArticleEntries(
  Object? raw,
  List<VocabItem> items,
  String now,
) {
  final byLemma = <String, VocabItem>{for (final it in items) it.lemma: it};
  if (raw is! List) return _deriveLegacyEntries(items, now);

  final migrated = <ArticleVocabEntry>[];
  for (final e in raw) {
    final m = _migrateEntry(e, byLemma, now);
    if (m != null) migrated.add(m);
  }

  // 已经全是合法条目、且没有重复 → 保住原数组引用，避免每次加载都白写一次库
  if (raw is List<ArticleVocabEntry> && migrated.length == raw.length) {
    final seen = <String>{};
    var dup = false;
    for (final e in migrated) {
      if (!seen.add(e.key)) dup = true;
    }
    if (!dup) return raw;
  }

  final seen = <String>{};
  return migrated.where((e) => seen.add(e.key)).toList(growable: false);
}

/// 把任意（老版本的 / 手改过的 / 半坏的）词库迁成当前结构：
/// 逐条洗 → 早先版本误标的类型修正 → 按词性过滤语法标记 → 按 lemma 去重。
/// **幂等**：已经是当前结构的库，跑完内容和原样一致（引用都会尽量复用）。
VocabLibrary migrateLibrary(Object? raw, [DateTime? now]) {
  final at = (now ?? DateTime.now()).toUtc().toIso8601String();
  if (raw is! Map && raw is! VocabLibrary) {
    return const VocabLibrary(schemaVersion: vocabSchemaVersion);
  }

  final List<Object?> rawItems;
  final Object? rawEntries;
  final Map<String, String>? sentenceTexts;
  final List<VocabTombstone>? tombstones;

  if (raw is VocabLibrary) {
    rawItems = raw.items;
    rawEntries = raw.articleEntries;
    sentenceTexts = raw.sentenceTexts.isEmpty ? null : raw.sentenceTexts;
    tombstones = raw.tombstones.isEmpty ? null : raw.tombstones;
  } else {
    final o = raw as Map;
    final list = o['items'];
    rawItems = list is List ? list : const [];
    rawEntries = o['articleEntries'];
    final st = o['sentenceTexts'];
    sentenceTexts = st is Map
        ? {
            for (final e in st.entries)
              if (e.key is String && e.value is String) e.key as String: e.value as String,
          }
        : null;
    final tb = o['tombstones'];
    if (tb is List) {
      final parsed = <VocabTombstone>[];
      for (final raw in tb) {
        final stone = _parseTombstone(raw, at);
        if (stone != null) parsed.add(stone);
      }
      tombstones = parsed;
    } else {
      tombstones = null;
    }
  }

  final items = <VocabItem>[];
  for (final it in rawItems) {
    final migrated = _migrateItem(it, at);
    if (migrated != null) items.add(migrated);
  }

  final articleEntries = _migrateArticleEntries(rawEntries, items, at);
  final library = VocabLibrary(
    schemaVersion: vocabSchemaVersion,
    items: items,
    articleEntries: articleEntries,
    sentenceTexts: sentenceTexts ?? const {},
    tombstones: tombstones ?? const [],
  );

  // 先修类型/旧键，再按 lemma 去重：否则旧 usage 笔记的坏键会和同名真单词合并，
  // 修完键之后才去重才能把「笔记」和「单词」分开。
  final normalized = normalizeGrammarMarks(dedupeLibrary(repairLanguageKinds(library)));
  return hydrateSentenceTexts(applyTombstones(normalized));
}

/// 老版本 → 当前版本要做的破坏性兼容都写在这里（现在只有 v1，占位给未来）。
VocabLibrary migrateToCurrent(VocabLibrary library) {
  if (library.schemaVersion == vocabSchemaVersion) return library;
  // 未来：case 0: return migrateV0ToV1(library) …
  return library.copyWith(schemaVersion: vocabSchemaVersion);
}

/// 只给测试/文档用：当前的复习状态默认值（避免各处重复 new 一份）。
ReviewState defaultReviewStateForTest() => defaultReviewState;
