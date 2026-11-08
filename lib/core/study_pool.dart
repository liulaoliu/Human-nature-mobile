/// 背单词的「候选池」：范围 / 牌组 / 组大小（纯函数）。
///
/// 为什么单独一个文件：这三条规则以前散在 `useStudyPool` 的 `useMemo` 里，
/// 而会话（组队、评分、组末拼写）和设置面板都要问「这一轮到底背哪些词、每组多少」。
/// 两边各算一份，范围和组大小迟早会对不上。
///
/// 零 IO、零状态，输入输出都是值。对应 Web 版 `src/reader/hooks/useStudyPool.ts`
/// 里的 `poolFor` / `effectiveGroupSize` 两段判定。
library;

import '../models/vocab.dart';
import 'article_vocab.dart' show articleItemsOf, kindOfItem;
import 'entry_kind.dart';
import 'vocab/review.dart';

/// 背单词范围。
enum StudyScope {
  /// 全部可背的。
  all,

  /// 只背这一篇的生词。
  article,

  /// 还没掌握的（默认）。
  unmastered,

  /// 忘过的（lapses > 0）：集中补漏。
  lapses,
}

/// 范围的中文名（设置面板用）。
const Map<StudyScope, String> studyScopeLabel = <StudyScope, String>{
  StudyScope.all: '全部',
  StudyScope.article: '本篇',
  StudyScope.unmastered: '没掌握',
  StudyScope.lapses: '忘过的',
};

/// 「每组多少词」的默认值：本篇 = 整篇（一篇一篇学），其它范围 = 20。
const int defaultStudyGroupSize = 20;

/// 按范围 + 牌组筛出这一轮的候选词。
///
/// [articleId] 只对 [StudyScope.article] 有意义：按「显式收进这一篇」的条目算
/// （见 `article_vocab.articleItemsOf`），而不是「词形在正文里出现过」——
/// 后者会让新文章凭空继承总词库里恰好出现的 the / is / are。
///
/// [docLemmas] 是给「本篇」补的一层：以前标过、来源不是这一篇、但词形确实
/// 出现在正文里的词，也该算本篇生词。传空集就是只按显式收录算。
List<VocabItem> studyPool({
  required VocabLibrary library,
  StudyScope scope = StudyScope.unmastered,
  StudyDeck deck = StudyDeck.word,
  String? articleId,
  Set<String> docLemmas = const <String>{},
}) {
  final base = library.items.where(
    (it) => inStudyDeck(
      kind: kindOfItem(it),
      word: it.word,
      meaning: it.meaning,
      deck: deck,
    ),
  );

  switch (scope) {
    case StudyScope.all:
      return base.toList(growable: false);
    case StudyScope.lapses:
      return base
          .where((it) => it.reviewState.lapses > 0)
          .toList(growable: false);
    case StudyScope.unmastered:
      return base
          .where((it) => it.status != VocabStatus.mastered)
          .toList(growable: false);
    case StudyScope.article:
      final id = articleId;
      if (id == null || id.isEmpty) return const <VocabItem>[];
      final explicit = <String>{
        for (final it in articleItemsOf(library, id)) it.id,
      };
      return base
          .where((it) => explicit.contains(it.id) || docLemmas.contains(it.lemma))
          .toList(growable: false);
  }
}

/// 组大小生效值：手动设了正数就用它；否则本篇 = 整篇，其它范围 = 20。
///
/// `groupSize <= 0` 表示「跟随范围」，不是「不分组」——不分组请传 `poolLength`。
int effectiveGroupSize({
  required int groupSize,
  required StudyScope scope,
  required int poolLength,
}) {
  if (groupSize > 0) return groupSize;
  if (scope == StudyScope.article) {
    return poolLength > 0 ? poolLength : 1;
  }
  return defaultStudyGroupSize;
}

/// 候选池里各有多少「该复习」「没学过」——只在设置面板上显示，不参与组队。
class StudyPoolCounts {
  const StudyPoolCounts({required this.due, required this.fresh, required this.total});

  final int due;
  final int fresh;
  final int total;
}

/// 候选池的三个计数（[now] 可注入，测试用）。
StudyPoolCounts studyPoolCounts(List<VocabItem> pool, {DateTime? now}) {
  final at = now ?? DateTime.now();
  var due = 0;
  var fresh = 0;
  for (final it in pool) {
    if (hasReviewHistory(it) && isDue(it, at)) due++;
    if (isFresh(it)) fresh++;
  }
  return StudyPoolCounts(due: due, fresh: fresh, total: pool.length);
}
