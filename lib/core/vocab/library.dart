/// 词库本身的增删改与查询：新建、编辑、状态、删除、打印标记、优先重排、
/// 本篇归属、筛选 / 分组 / 排序。
///
/// 纯函数；不做词形/合并规则（那些在 `vocab/word.dart` / `vocab/merge.dart`）。
/// 对应 Web 版 `src/core/vocab/library.ts`。
library;

import '../../models/vocab.dart';
import '../activity/activity.dart';
import '../article_vocab.dart';
import 'tombstones.dart';
import 'word.dart';

/// 空词库。
VocabLibrary createLibrary() => const VocabLibrary(
      schemaVersion: vocabSchemaVersion,
      items: [],
      articleEntries: [],
    );

/// 词条可编辑的补丁（id / lemma 不可改）。
class VocabItemPatch {
  const VocabItemPatch({
    this.word,
    this.kind,
    this.phonetic,
    this.partOfSpeech,
    this.meaning,
    this.definition,
    this.note,
    this.tags,
    this.usage,
    this.grammarMarks,
    this.phrases,
    this.idioms,
    this.status,
  });

  final String? word;
  final VocabItemKind? kind;
  final String? phonetic;
  final String? partOfSpeech;
  final String? meaning;
  final String? definition;
  final String? note;
  final List<String>? tags;
  final List<String>? usage;
  final List<String>? grammarMarks;
  final List<String>? phrases;
  final List<String>? idioms;
  final VocabStatus? status;

  /// 这次补丁显式写了哪些核心字段（用来标「手动改过」）。
  Set<VocabField> get touchedFields {
    final out = <VocabField>{};
    if (phonetic != null) out.add(VocabField.phonetic);
    if (partOfSpeech != null) out.add(VocabField.partOfSpeech);
    if (meaning != null) out.add(VocabField.meaning);
    if (definition != null) out.add(VocabField.definition);
    return out;
  }
}

/// 手动编辑一个词条，默认把状态置为 edited（不会被后续查询覆盖）。
VocabLibrary editItem(
  VocabLibrary library,
  String id,
  VocabItemPatch patch, {
  DateTime? now,
}) {
  final at = (now ?? DateTime.now()).toIso8601String();
  final touched = patch.touchedFields;
  return library.copyWith(
    items: library.items.map((it) {
      if (it.id != id) return it;
      // 手动改过的核心字段逐个标来源；之后 AI / 词典只锁这些字段，不整条锁死。
      final sources = {...?it.fieldSources};
      for (final field in touched) {
        sources[field] = VocabFieldSource.manual;
      }
      return it.copyWith(
        word: patch.word,
        kind: patch.kind != null ? () => patch.kind : null,
        phonetic: patch.phonetic != null ? () => patch.phonetic : null,
        partOfSpeech:
            patch.partOfSpeech != null ? () => patch.partOfSpeech : null,
        meaning: patch.meaning != null ? () => patch.meaning : null,
        definition: patch.definition != null ? () => patch.definition : null,
        note: patch.note,
        tags: patch.tags,
        usage: patch.usage,
        grammarMarks:
            patch.grammarMarks != null ? () => patch.grammarMarks : null,
        phrases: patch.phrases != null ? () => patch.phrases : null,
        idioms: patch.idioms != null ? () => patch.idioms : null,
        fieldSources: touched.isEmpty ? null : () => sources,
        status: patch.status ?? VocabStatus.edited,
        updatedAt: at,
      );
    }).toList(growable: false),
  );
}

/// 改状态（背单词里标「已掌握」等）。
VocabLibrary setStatus(
  VocabLibrary library,
  String id,
  VocabStatus status, {
  DateTime? now,
}) {
  final at = (now ?? DateTime.now()).toIso8601String();
  return library.copyWith(
    items: library.items
        .map((it) =>
            it.id == id ? it.copyWith(status: status, updatedAt: at) : it)
        .toList(growable: false),
  );
}

/// 删词条（连带删掉它在各篇的收录，并记墓碑）。
VocabLibrary removeItem(VocabLibrary library, String id) {
  final target = library.items.where((it) => it.id == id).firstOrNull;
  final items = library.items.where((it) => it.id != id).toList(growable: false);
  final entries = target == null
      ? library.articleEntries
      : library.articleEntries
          .where((e) => e.lemma != target.lemma)
          .toList(growable: false);
  final next = library.copyWith(items: items, articleEntries: entries);
  // 记墓碑：合并本机/服务端时才不会把用户删掉的词又并回来。
  return target == null ? next : addItemTombstone(next, target);
}

/// 记录 A4 打印：把传进来的这批词条写上 `lastPrintedAt`。
///
/// 打印后调用，用于「不重复打印」（下次可只打印未打印的）。
VocabLibrary markPrinted(
  VocabLibrary library,
  Iterable<String> ids, {
  DateTime? now,
}) {
  final set = ids.toSet();
  if (set.isEmpty) return library;
  final iso = (now ?? DateTime.now()).toIso8601String();
  return library.copyWith(
    items: library.items
        .map((it) => set.contains(it.id)
            ? it.copyWith(lastPrintedAt: () => iso, updatedAt: iso)
            : it)
        .toList(growable: false),
  );
}

/// 是否打印过（老数据没有 lastPrintedAt，按未打印算）。
bool isPrinted(VocabItem item) => item.lastPrintedAt != null;

/// 未打印过的词条（用于「只打未打印」）。
List<VocabItem> unprintedItems(List<VocabItem> items) =>
    items.where((it) => it.lastPrintedAt == null).toList(growable: false);

/// 答错的词 → 标记「优先重排」到 `until`（默认次日）。
///
/// 队列会把这些词排到最前，实现「今日鞭打、次日优先重练」。
VocabLibrary prioritizeItems(
  VocabLibrary library,
  Iterable<String> ids,
  String until,
) {
  final set = ids.toSet();
  if (set.isEmpty) return library;
  return library.copyWith(
    items: library.items
        .map((it) =>
            set.contains(it.id) ? it.copyWith(priorityUntil: () => until) : it)
        .toList(growable: false),
  );
}

/// 是否正处于「优先重排」（priorityUntil 未过期）。
bool isPriority(VocabItem item, {DateTime? now}) {
  final until = item.priorityUntil;
  if (until == null) return false;
  final at = DateTime.tryParse(until);
  if (at == null) return false;
  return at.isAfter(now ?? DateTime.now());
}

/// 某一篇的「本篇生词」：只认**显式收进这一篇**的条目（见 `article_vocab.dart`）。
///
/// 不能再用「来源是本文 或 正文里出现过该词」：那会让新文章继承总词库里
/// 恰好出现的 the / is / are，用户并没有在这篇标过它们。
List<VocabItem> articleWordsOf(VocabLibrary library, String articleIdentity) =>
    articleItemsOf(library, articleIdentity);

/// 按词形（lemma）删除。
VocabLibrary removeByLemma(VocabLibrary library, String word) {
  final lemma = lemmaOf(word);
  return library.copyWith(
    items: library.items
        .where((it) => it.lemma != lemma)
        .toList(growable: false),
    articleEntries: library.articleEntries
        .where((e) => e.lemma != lemma)
        .toList(growable: false),
  );
}

/// 筛选条件。
class VocabFilter {
  const VocabFilter({
    this.status,
    this.articleId,
    this.tag,
    this.query,
    this.dueBefore,
  });

  final List<VocabStatus>? status;
  final String? articleId;
  final String? tag;

  /// 在 word / meaning / usage 里模糊匹配。
  final String? query;

  /// 到期时间早于该时刻。
  final DateTime? dueBefore;
}

/// 按条件筛词条。
List<VocabItem> filterItems(List<VocabItem> items, VocabFilter filter) {
  final q = filter.query?.trim().toLowerCase();
  return items.where((it) {
    final status = filter.status;
    if (status != null && !status.contains(it.status)) return false;
    final articleId = filter.articleId;
    if (articleId != null && it.source?.articleId != articleId) return false;
    final tag = filter.tag;
    if (tag != null && !it.tags.contains(tag)) return false;
    final dueBefore = filter.dueBefore;
    if (dueBefore != null) {
      final due = it.reviewState.due;
      if (due == null) return false;
      final at = DateTime.tryParse(due);
      if (at == null || at.isAfter(dueBefore)) return false;
    }
    if (q != null && q.isNotEmpty) {
      final hay = '${it.word} ${it.meaning ?? ''} ${it.usage.join(' ')}'
          .toLowerCase();
      if (!hay.contains(q)) return false;
    }
    return true;
  }).toList(growable: false);
}

/// 分组方式。
enum VocabGroupBy { alphabet, article, date, status }

/// 一组词条。
class VocabGroup {
  const VocabGroup({required this.key, required this.items});

  final String key;
  final List<VocabItem> items;
}

/// 按 `by` 分组，组键升序。
List<VocabGroup> groupItems(List<VocabItem> items, VocabGroupBy by) {
  final map = <String, List<VocabItem>>{};
  for (final it in items) {
    final String key;
    switch (by) {
      case VocabGroupBy.alphabet:
        final c = it.lemma.isEmpty ? '' : it.lemma[0].toUpperCase();
        key = RegExp(r'[A-Z]').hasMatch(c) ? c : '#';
      case VocabGroupBy.article:
        key = it.source?.articleId ?? '未分类';
      case VocabGroupBy.date:
        final at = DateTime.tryParse(it.createdAt)?.toLocal();
        key = at == null ? '未分类' : dayKeyLocal(at);
      case VocabGroupBy.status:
        key = vocabStatusName(it.status);
    }
    (map[key] ??= <VocabItem>[]).add(it);
  }
  final keys = map.keys.toList()..sort();
  return [
    for (final k in keys) VocabGroup(key: k, items: map[k]!),
  ];
}

/// 排序方式。
enum VocabSortBy { word, createdAt, updatedAt, due }

/// 按 `by` 排序，返回新列表（不改入参）。
List<VocabItem> sortItems(List<VocabItem> items, VocabSortBy by) {
  final out = [...items];
  out.sort((a, b) {
    switch (by) {
      case VocabSortBy.word:
        return a.lemma.compareTo(b.lemma);
      case VocabSortBy.createdAt:
        return b.createdAt.compareTo(a.createdAt);
      case VocabSortBy.updatedAt:
        return b.updatedAt.compareTo(a.updatedAt);
      case VocabSortBy.due:
        final da = a.reviewState.due;
        final db = b.reviewState.due;
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        return da.compareTo(db);
    }
  });
  return out;
}
