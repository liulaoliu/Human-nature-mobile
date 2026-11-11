import 'package:dlaoshi_app/core/entry_kind.dart';
import 'package:dlaoshi_app/core/study_pool.dart';
import 'package:dlaoshi_app/core/study_pools.dart';
import 'package:dlaoshi_app/models/vocab.dart';
import 'package:flutter_test/flutter_test.dart';

VocabItem mkWord(
  String word, {
  String? meaning = '释义',
  VocabStatus status = VocabStatus.queried,
}) =>
    VocabItem(
      id: 'vocab:$word',
      word: word,
      lemma: word,
      meaning: meaning ?? '释义',
      status: status,
      createdAt: '2026-11-11T00:00:00.000Z',
      updatedAt: '2026-11-11T00:00:00.000Z',
      reviewState: const ReviewState(),
    );

VocabItem dueWord(String word) => VocabItem(
      id: 'vocab:$word',
      word: word,
      lemma: word,
      meaning: 'x-$word',
      status: VocabStatus.queried,
      createdAt: '2026-11-11T00:00:00.000Z',
      updatedAt: '2026-11-11T00:00:00.000Z',
      reviewState: const ReviewState(
        repetitions: 2,
        interval: 1,
        due: '2026-11-01T00:00:00.000Z',
      ),
    );

ArticleVocabEntry entryOf(String articleId, VocabItem item) => ArticleVocabEntry(
      articleId: articleId,
      lemma: item.lemma,
      origin: VocabOrigin.manual,
      addedAt: '2026-11-11T00:00:00.000Z',
    );

void main() {
  group('StudyPools.of 按入口分流', () {
    test('学习池只认本篇显式收录 + 正文词形', () {
      final a = mkWord('alpha');
      final b = mkWord('beta');
      final lib = VocabLibrary(
        items: [a, b],
        articleEntries: [entryOf('a1', a)],
      );
      final pools = StudyPools(library: lib, articleId: 'a1');
      expect(pools.of(StudyEntry.learn).map((e) => e.word), ['alpha']);
    });

    test('没打开文章时学习退回全库新词', () {
      final lib = VocabLibrary(items: [mkWord('alpha'), mkWord('beta')]);
      final pools = StudyPools(library: lib);
      expect(pools.of(StudyEntry.learn), hasLength(2));
    });

    test('复习池是全库到期词，不受 articleId 影响', () {
      final lib = VocabLibrary(items: [dueWord('alpha')]);
      final pools = StudyPools(library: lib, articleId: 'a1');
      expect(pools.of(StudyEntry.review).map((e) => e.word), ['alpha']);
    });

    test('回顾池按 scope 切本篇 / 最近 7 天', () {
      final a = dueWord('alpha');
      final b = dueWord('beta');
      final lib = VocabLibrary(
        items: [a, b],
        articleEntries: [entryOf('a1', a)],
      );
      final byArticle = StudyPools(library: lib, articleId: 'a1');
      expect(byArticle.of(StudyEntry.recall).map((e) => e.word), ['alpha']);

      final byRecent = StudyPools(
        library: lib,
        articleId: 'a1',
        recallScope: RecallScope.last7Days,
        recentIds: {'vocab:beta'},
      );
      expect(byRecent.of(StudyEntry.recall).map((e) => e.word), ['beta']);
    });
  });

  group('StudyPools.counts', () {
    test('三个数各算各的', () {
      final fresh = mkWord('alpha');
      final due = dueWord('beta');
      final lib = VocabLibrary(
        items: [fresh, due],
        articleEntries: [entryOf('a1', fresh), entryOf('a1', due)],
      );
      final counts = StudyPools(library: lib, articleId: 'a1').counts;
      expect(counts.learn, 1);
      expect(counts.review, 1);
      expect(counts.recall, 1);
      expect(counts.isEmpty, isFalse);
    });

    test('空库三个数都是 0', () {
      final counts = StudyPools(
        library: const VocabLibrary(),
        articleId: 'a1',
      ).counts;
      expect(counts.isEmpty, isTrue);
    });
  });

  group('StudyPools.groupSizeFor', () {
    test('学习默认整篇，复习 / 回顾默认 20', () {
      final items = [for (var i = 0; i < 5; i++) mkWord('w$i')];
      final lib = VocabLibrary(
        items: items,
        articleEntries: [for (final it in items) entryOf('a1', it)],
      );
      final pools = StudyPools(library: lib, articleId: 'a1');
      expect(pools.groupSizeFor(StudyEntry.learn), 5);
      expect(pools.groupSizeFor(StudyEntry.review), defaultStudyGroupSize);
    });

    test('手动设了正数就用手动值', () {
      final items = [for (var i = 0; i < 5; i++) dueWord('w$i')];
      final lib = VocabLibrary(
        items: items,
        articleEntries: [for (final it in items) entryOf('a1', it)],
      );
      final pools = StudyPools(library: lib, articleId: 'a1', groupSize: 2);
      expect(pools.groupSizeFor(StudyEntry.learn), 2);
      expect(pools.groupSizeFor(StudyEntry.review), 2);
    });
  });

  group('StudyPools 牌组过滤', () {
    test('背搭配时不带普通单词', () {
      final word = mkWord('alpha');
      final phrase = VocabItem(
        id: 'vocab:big deal',
        word: 'big deal',
        lemma: 'big deal',
        kind: VocabItemKind.phrase,
        meaning: '大事',
        status: VocabStatus.queried,
        createdAt: '2026-11-11T00:00:00.000Z',
        updatedAt: '2026-11-11T00:00:00.000Z',
      );
      final lib = VocabLibrary(
        items: [word, phrase],
        articleEntries: [entryOf('a1', word), entryOf('a1', phrase)],
      );
      final pools =
          StudyPools(library: lib, articleId: 'a1', deck: StudyDeck.collocation);
      expect(pools.of(StudyEntry.learn).map((e) => e.word), ['big deal']);
    });
  });
}
