/// 背单词的三个入口（学习 / 复习 / 回顾）与候选池规则。
///
/// 为什么是三个入口而不是一个「范围」下拉：范围（全部 / 本篇 / 没掌握 / 忘过的）
/// 要求用户先想清楚「我现在该背哪一批」，而这三个词已经把这个选择说完了 ——
/// 学习 = 本篇还没学过的，复习 = 到期该过的，回顾 = 学过的再练一遍。
/// 下拉还多一层歧义：选「本篇」时到底背新词还是背复习？两个按钮不会。
///
/// 零 IO、零状态，输入输出都是值。
library;

import '../models/vocab.dart';
import 'article_vocab.dart' show articleEntryViews, kindOfItem;
import 'entry_kind.dart';
import 'vocab/review.dart';

/// 背单词的三个入口。
enum StudyEntry {
  /// 学习：本篇还没学过的生词（新词额度在这一层扣）。
  learn,

  /// 复习：有学习记录且到期的，全库范围。
  review,

  /// 回顾：已经学过的词再练一遍，不改排期由调用方决定。
  recall,
}

/// 入口的中文名。
const Map<StudyEntry, String> studyEntryLabel = <StudyEntry, String>{
  StudyEntry.learn: '学习',
  StudyEntry.review: '复习',
  StudyEntry.recall: '回顾',
};

/// 回顾的筛选维度。
enum RecallScope {
  /// 这一篇学过的词。
  article,

  /// 最近 7 天学过的词（跨文章）。
  last7Days,
}

/// 回顾筛选的中文名。
const Map<RecallScope, String> recallScopeLabel = <RecallScope, String>{
  RecallScope.article: '本篇学过',
  RecallScope.last7Days: '最近 7 天',
};

/// 「每组多少词」的默认值（学习入口例外：一轮就把本篇生词过完）。
const int defaultStudyGroupSize = 20;

/// 回顾「最近 N 天」的天数。
const int recallRecentDays = 7;

/// 按牌组过滤（只看单词 / 只看搭配）。
Iterable<VocabItem> _deckBase(VocabLibrary library, StudyDeck deck) =>
    library.items.where(
      (it) => inStudyDeck(
        kind: kindOfItem(it),
        word: it.word,
        meaning: it.meaning,
        deck: deck,
      ),
    );

/// 这一篇里「显式收进来」的词 id。
///
/// 只认 `articleEntries`，不认「词形在正文里出现过」——后者会让新文章凭空继承
/// 总词库里恰好出现的 the / is / are。正文词形另走 [docLemmas] 补一层。
///
/// **必须走 `includeLang: true`**：默认口径只给「普通单词」，选「背搭配」时
/// 词组 / 习语会被过滤掉，本篇搭配就永远凑不出池子。牌组过滤由 [_deckBase] 负责。
Set<String> _explicitIds(VocabLibrary library, String articleId) => <String>{
  for (final v in articleEntryViews(library, articleId, includeLang: true))
    v.item.id,
};

/// 学习池：本篇还没学过的生词。
///
/// [articleId] 为空（还没打开过文章）时**退回全库新词**：新装的 App 一个词都
/// 没收过，点「学习」不该什么都拿不到。一旦打开过文章，就只认这一篇。
///
/// [docLemmas] 是给「本篇」补的一层：以前标过、来源不是这一篇、但词形确实
/// 出现在正文里的词，也算本篇生词。
List<VocabItem> learnPool({
  required VocabLibrary library,
  StudyDeck deck = StudyDeck.word,
  String? articleId,
  Set<String> docLemmas = const <String>{},
}) {
  final id = articleId;
  final scoped = id != null && id.isNotEmpty;
  final explicit = scoped ? _explicitIds(library, id) : const <String>{};
  return <VocabItem>[
    for (final it in _deckBase(library, deck))
      if (isFresh(it) &&
          (!scoped || explicit.contains(it.id) || docLemmas.contains(it.lemma)))
        it,
  ];
}

/// 复习池：有学习记录且到期的词，全库范围。
///
/// 用户要的「学完本篇就进没掌握 + 忘过的」，落到这里就是「现在到期的」——
/// 没到期的不该现在出现，那是 [recallPool] 的事。
List<VocabItem> reviewPool({
  required VocabLibrary library,
  StudyDeck deck = StudyDeck.word,
  DateTime? now,
}) {
  final at = now ?? DateTime.now();
  return <VocabItem>[
    for (final it in _deckBase(library, deck))
      if (hasReviewHistory(it) && isDue(it, at)) it,
  ];
}

/// 回顾池：已经学过的词再练一遍。
///
/// [scope] 决定筛选维度：[RecallScope.article] 只看这一篇，
/// [RecallScope.last7Days] 只看 [recentIds] 里的（调用方从学习记录里取）。
/// 两边都只取 [hasReviewHistory] 的词 —— 没学过的词属于「学习」，不该混进来。
List<VocabItem> recallPool({
  required VocabLibrary library,
  StudyDeck deck = StudyDeck.word,
  RecallScope scope = RecallScope.article,
  String? articleId,
  Set<String> docLemmas = const <String>{},
  Set<String> recentIds = const <String>{},
}) {
  final base = _deckBase(library, deck);
  if (scope == RecallScope.last7Days) {
    return <VocabItem>[
      for (final it in base)
        if (hasReviewHistory(it) && recentIds.contains(it.id)) it,
    ];
  }
  final id = articleId;
  if (id == null || id.isEmpty) return const <VocabItem>[];
  final explicit = _explicitIds(library, id);
  return <VocabItem>[
    for (final it in base)
      if (hasReviewHistory(it) &&
          (explicit.contains(it.id) || docLemmas.contains(it.lemma)))
        it,
  ];
}

/// 组大小生效值：手动设了正数就用它；否则学习 = 整篇（一轮过完），
/// 复习 / 回顾 = [defaultStudyGroupSize]。
///
/// `groupSize <= 0` 表示「跟随入口」，不是「不分组」。
int effectiveGroupSize({
  required int groupSize,
  required StudyEntry entry,
  required int poolLength,
}) {
  if (groupSize > 0) return groupSize;
  if (entry == StudyEntry.learn) return poolLength > 0 ? poolLength : 1;
  return defaultStudyGroupSize;
}

/// 开轮页要显示的三个计数。
class StudyPoolCounts {
  const StudyPoolCounts({required this.learn, required this.review, required this.recall});

  /// 本篇还能学的新词。
  final int learn;

  /// 现在到期的复习。
  final int review;

  /// 本篇学过的词（回顾默认维度）。
  final int recall;

  bool get isEmpty => learn == 0 && review == 0 && recall == 0;
}

/// 一次算齐三个入口各有多少词（[now] 可注入，测试用）。
StudyPoolCounts studyPoolCounts({
  required VocabLibrary library,
  StudyDeck deck = StudyDeck.word,
  String? articleId,
  Set<String> docLemmas = const <String>{},
  RecallScope recallScope = RecallScope.article,
  Set<String> recentIds = const <String>{},
  DateTime? now,
}) {
  return StudyPoolCounts(
    learn: learnPool(
      library: library,
      deck: deck,
      articleId: articleId,
      docLemmas: docLemmas,
    ).length,
    review: reviewPool(library: library, deck: deck, now: now).length,
    recall: recallPool(
      library: library,
      deck: deck,
      scope: recallScope,
      articleId: articleId,
      docLemmas: docLemmas,
      recentIds: recentIds,
    ).length,
  );
}
