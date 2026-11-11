/// 背单词三个入口的「当前这一份池子」。
///
/// 为什么单独一个值对象：`StudyViewModel` 既管落盘、又管会话、又管池子的话，
/// 方法数会顶到上帝类门禁（40）。池子这件事只依赖「词库 + 设置 + 当前文章」，
/// 全部是值，抽出来既能单独测，也能让 ViewModel 只留一个 `pools` 出口。
///
/// 计算仍走 [learnPool] / [reviewPool] / [recallPool] / [studyPoolCounts]，
/// 这里只负责把散在各处的参数收成一份。
library;

import '../models/vocab.dart';
import 'entry_kind.dart';
import 'study_pool.dart';

/// 三个入口各自的候选池 + 组大小。
class StudyPools {
  const StudyPools({
    required this.library,
    this.deck = StudyDeck.word,
    this.articleId,
    this.docLemmas = const <String>{},
    this.recallScope = RecallScope.article,
    this.recentIds = const <String>{},
    this.groupSize = 0,
    this.now,
  });

  final VocabLibrary library;
  final StudyDeck deck;

  /// 当前打开的文章 id；没打开过就是 null。
  final String? articleId;

  /// 正文里出现过的词形（给「本篇」补一层）。
  final Set<String> docLemmas;

  final RecallScope recallScope;

  /// 最近 N 天学过的词 id（回顾 · 最近 7 天用）。
  final Set<String> recentIds;

  /// 用户设的每组词数，0 = 跟随入口。
  final int groupSize;

  /// 可注入的「现在」（复习到期判定）。
  final DateTime? now;

  /// 学习池：本篇还没学过的生词。
  List<VocabItem> get learn => learnPool(
        library: library,
        deck: deck,
        articleId: articleId,
        docLemmas: docLemmas,
      );

  /// 复习池：有学习记录且到期的。
  List<VocabItem> get review =>
      reviewPool(library: library, deck: deck, now: now);

  /// 回顾池：按 [recallScope] 挑已经学过的词。
  List<VocabItem> get recall => recallPool(
        library: library,
        deck: deck,
        scope: recallScope,
        articleId: articleId,
        docLemmas: docLemmas,
        recentIds: recentIds,
      );

  /// 某个入口的候选池。
  List<VocabItem> of(StudyEntry entry) => switch (entry) {
        StudyEntry.learn => learn,
        StudyEntry.review => review,
        StudyEntry.recall => recall,
      };

  /// 三个入口各有多少词（开轮页显示）。
  StudyPoolCounts get counts => StudyPoolCounts(
        learn: learn.length,
        review: review.length,
        recall: recall.length,
      );

  /// 组大小生效值：手动设了正数就用它；否则学习 = 整篇，复习 / 回顾 = 20。
  int groupSizeFor(StudyEntry entry) => effectiveGroupSize(
        groupSize: groupSize,
        entry: entry,
        poolLength: of(entry).length,
      );
}
