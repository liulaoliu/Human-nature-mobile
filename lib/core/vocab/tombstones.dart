/// 词库删除墓碑 + 本机/服务端合并（对应 Web 版 `src/core/vocab/tombstones.ts`）。
///
/// 为什么需要：
///   - 只按 lemma 取并集，会把用户删掉的词复活（本机没这条 ≠ 用户删了这条）；
///   - 只按整库时间戳选一边，会丢掉另一边的新增/修改。
///
/// 规则：
///   - 删除时写墓碑（`kind` + `key` + `at`）；合并时先并墓碑，再按 `updatedAt` 取更新的词条。
///   - 墓碑只删除**比墓碑旧**的词条；删完又加回来的（updatedAt 更晚）保留。
///   - 同一条两边都改过：`updatedAt` 更新的赢；完全相同则本机赢（本机是未同步的一方）。
library;

import '../../models/vocab.dart';

/// 全库词条的墓碑键。
String itemTombstoneKey(String id) => 'item:$id';

/// 按篇收录的墓碑键。
String articleTombstoneKey(String articleId, String lemma) =>
    'article:$articleId\u0000$lemma';

/// ISO 时间 → 毫秒；解析不出来按 0（最旧）。
int _time(String? iso) {
  if (iso == null || iso.isEmpty) return 0;
  return DateTime.tryParse(iso)?.millisecondsSinceEpoch ?? 0;
}

VocabTombstone _newer(VocabTombstone a, VocabTombstone b) =>
    _time(b.at) >= _time(a.at) ? b : a;

/// 加/更新一条墓碑；同一 key 只留最新时间。
VocabLibrary addTombstone(VocabLibrary library, VocabTombstone tombstone) {
  final list = library.tombstones;
  final idx = list.indexWhere((t) => t.key == tombstone.key);
  if (idx < 0) {
    return library.copyWith(tombstones: [...list, tombstone]);
  }
  final prev = list[idx];
  final next = _newer(prev, tombstone);
  if (identical(next, prev)) return library;
  final tombstones = [...list];
  tombstones[idx] = next;
  return library.copyWith(tombstones: tombstones);
}

/// 记「这个全库词条被删了」。
VocabLibrary addItemTombstone(
  VocabLibrary library,
  VocabItem item, {
  String? at,
}) {
  return addTombstone(
    library,
    VocabTombstone(
      kind: VocabTombstoneKind.item,
      key: itemTombstoneKey(item.id),
      at: at ?? DateTime.now().toIso8601String(),
      lemma: item.lemma,
    ),
  );
}

/// 记「这一篇的这个收录被删了」。
VocabLibrary addArticleTombstone(
  VocabLibrary library,
  String articleId,
  String lemma, {
  String? at,
}) {
  return addTombstone(
    library,
    VocabTombstone(
      kind: VocabTombstoneKind.article,
      key: articleTombstoneKey(articleId, lemma),
      at: at ?? DateTime.now().toIso8601String(),
      lemma: lemma,
    ),
  );
}

/// 两份墓碑取并集，同 key 保留更晚的删除时间。
List<VocabTombstone> mergeTombstones(
  List<VocabTombstone> a,
  List<VocabTombstone> b,
) {
  final byKey = <String, VocabTombstone>{};
  for (final t in [...a, ...b]) {
    if (t.key.isEmpty) continue;
    final prev = byKey[t.key];
    byKey[t.key] = prev == null ? t : _newer(prev, t);
  }
  return byKey.values.toList(growable: false);
}

/// 应用墓碑：删掉比墓碑旧的词条 / 篇条目。
///
/// 删除后又重新加回来的（`updatedAt` / `addedAt` 晚于墓碑）不删。
VocabLibrary applyTombstones(VocabLibrary library) {
  final tombstones = library.tombstones;
  if (tombstones.isEmpty) return library;
  final itemTombs =
      tombstones.where((t) => t.kind == VocabTombstoneKind.item).toList();
  final articleTombs =
      tombstones.where((t) => t.kind == VocabTombstoneKind.article).toList();

  final items = library.items.where((it) {
    final at = _time(it.updatedAt);
    return !itemTombs.any((t) {
      final same = t.key == itemTombstoneKey(it.id) ||
          (t.lemma != null && t.lemma == it.lemma);
      return same && at <= _time(t.at);
    });
  }).toList(growable: false);

  final entries = library.articleEntries.where((e) {
    final at = _time(e.addedAt);
    // 删全库词条会连带删掉它在各篇的收录：服务端那份不能再并回来。
    final killedByItem = itemTombs.any(
        (t) => t.lemma != null && t.lemma == e.lemma && at <= _time(t.at));
    final killedByArticle = articleTombs.any((t) =>
        t.key == articleTombstoneKey(e.articleId, e.lemma) &&
        at <= _time(t.at));
    return !killedByItem && !killedByArticle;
  }).toList(growable: false);

  final itemsChanged = items.length != library.items.length;
  final entriesChanged = entries.length != library.articleEntries.length;
  if (!itemsChanged && !entriesChanged) return library;
  return library.copyWith(items: items, articleEntries: entries);
}

VocabItem _pickItem(VocabItem a, VocabItem b) {
  // b 是本机（后遍历）；同时间本机赢，因为本机是未同步的一方。
  return _time(b.updatedAt) >= _time(a.updatedAt) ? b : a;
}

ArticleVocabEntry _pickEntry(ArticleVocabEntry a, ArticleVocabEntry b) {
  return _time(b.addedAt) >= _time(a.addedAt) ? b : a;
}

/// 本机/服务端同步用合并：并墓碑 + 按词条更新时间取新 + 应用墓碑。
///
/// 与备份的 `mergeLibraries`（按字段互补）不同：这里同一条词只留更新的一版，
/// 避免「旧版里非空字段」把用户刚清空的释义又补回来。
VocabLibrary mergeLibrariesForSync(VocabLibrary local, VocabLibrary server) {
  final byLemma = <String, VocabItem>{};
  for (final it in [...server.items, ...local.items]) {
    final prev = byLemma[it.lemma];
    byLemma[it.lemma] = prev == null ? it : _pickItem(prev, it);
  }
  final entries = <String, ArticleVocabEntry>{};
  for (final e in [...server.articleEntries, ...local.articleEntries]) {
    final key = '${e.articleId}\u0000${e.lemma}';
    final prev = entries[key];
    entries[key] = prev == null ? e : _pickEntry(prev, e);
  }
  return applyTombstones(local.copyWith(
    items: byLemma.values.toList(growable: false),
    articleEntries: entries.values.toList(growable: false),
    tombstones: mergeTombstones(server.tombstones, local.tombstones),
    sentenceTexts: {...server.sentenceTexts, ...local.sentenceTexts},
  ));
}

/// 判断两份词库「内容是否一样」（用于合并后决定要不要回写服务端）。
String librarySignature(VocabLibrary library) {
  final items = library.items
      .map((it) => '${it.id}\u0000${it.lemma}\u0000${it.updatedAt}')
      .toList()
    ..sort();
  final entries = library.articleEntries
      .map((e) => '${e.articleId}\u0000${e.lemma}\u0000${e.addedAt}')
      .toList()
    ..sort();
  final tombs = library.tombstones.map((t) => '${t.key}\u0000${t.at}').toList()
    ..sort();
  final sentences = library.sentenceTexts.keys.toList()..sort();
  return '${items.join('\n')}\n--\n${entries.join('\n')}\n--\n'
      '${tombs.join('\n')}\n--\n${sentences.join('\n')}';
}

/// 两份词库内容是否完全一致。
bool sameLibrary(VocabLibrary a, VocabLibrary b) =>
    librarySignature(a) == librarySignature(b);
