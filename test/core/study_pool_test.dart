import 'package:dlaoshi_app/core/entry_kind.dart';
import 'package:dlaoshi_app/core/study_pool.dart';
import 'package:dlaoshi_app/models/vocab.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/vocab_fixture.dart';

/// 每个用例固定的「现在」：2026-03-10。
final DateTime _now = DateTime.parse('2026-03-10T12:00:00.000Z');

VocabLibrary _lib(
  List<VocabItem> items, {
  List<ArticleVocabEntry> entries = const <ArticleVocabEntry>[],
}) =>
    VocabLibrary(schemaVersion: 1, items: items, articleEntries: entries);

/// 一条「有学习记录、今天到期」的词。
VocabItem _due({
  required String id,
  String? word,
  VocabItemKind? kind,
  int lapses = 0,
  VocabStatus status = VocabStatus.queried,
  String due = '2026-03-01T00:00:00.000Z',
}) =>
    vocabItem(
      id: id,
      word: word,
      kind: kind,
      meaning: '释义$id',
      status: status,
      reviewState: ReviewState(due: due, repetitions: 1, lapses: lapses),
    );

/// 一条从没学过的新词。
VocabItem _fresh({
  required String id,
  String? word,
  VocabItemKind? kind,
  VocabStatus status = VocabStatus.unqueried,
}) =>
    vocabItem(
      id: id,
      word: word,
      kind: kind,
      meaning: '释义$id',
      status: status,
    );

void main() {
  group('learnPool', () {
    test('只要新词：学过的、用法笔记、无释义的都不进', () {
      final lib = _lib([
        _fresh(id: 'a'),
        _due(id: 'learned'),
        vocabItem(
          id: 'note',
          word: '这是一段中文说明',
          kind: VocabItemKind.usage,
          meaning: '说明',
        ),
        vocabItem(id: 'bare', word: 'bare'),
        vocabItem(
          id: 'b',
          word: 'beta',
          kind: VocabItemKind.phrase,
          meaning: '词组释义',
        ),
      ]);
      final pool = learnPool(library: lib);
      expect(pool.map((it) => it.id), ['a', 'b']);
    });

    test('本篇：只认显式收进这一篇的条目', () {
      final lib = _lib(
        [
          _fresh(id: 'a', word: 'alpha'),
          _fresh(id: 'b', word: 'beta'),
          _fresh(id: 'c', word: 'gamma'),
        ],
        entries: [
          articleEntry(articleId: 'A', lemma: 'alpha'),
          articleEntry(articleId: 'B', lemma: 'beta'),
        ],
      );
      final pool = learnPool(library: lib, articleId: 'A');
      expect(pool.map((it) => it.id), ['a']);
    });

    test('本篇：正文里出现过的词形也算（docLemmas 补一层）', () {
      final lib = _lib(
        [
          _fresh(id: 'a', word: 'alpha'),
          _fresh(id: 'b', word: 'beta'),
          _fresh(id: 'c', word: 'gamma'),
        ],
        entries: [articleEntry(articleId: 'A', lemma: 'alpha')],
      );
      final pool = learnPool(
        library: lib,
        articleId: 'A',
        docLemmas: {'gamma'},
      );
      expect(pool.map((it) => it.id), ['a', 'c']);
    });

    test('没有 articleId 时退回全库新词（新装的 App 点「学习」不能是空的）', () {
      final lib = _lib([_fresh(id: 'a'), _fresh(id: 'b')]);
      expect(learnPool(library: lib).map((it) => it.id), ['a', 'b']);
      expect(learnPool(library: lib, articleId: '').map((it) => it.id), ['a', 'b']);
    });

    test('牌组：collocation 只要词组与习语，word 只要单词', () {
      final lib = _lib([
        _fresh(id: 'w', word: 'alpha'),
        _fresh(id: 'p', word: 'in the end', kind: VocabItemKind.phrase),
        _fresh(id: 'i', word: 'hit the sack', kind: VocabItemKind.idiom),
      ]);
      expect(learnPool(library: lib).map((it) => it.id), ['w']);
      expect(
        learnPool(library: lib, deck: StudyDeck.collocation).map((it) => it.id),
        ['p', 'i'],
      );
    });
  });

  group('reviewPool', () {
    test('只要到期的，全库范围', () {
      final lib = _lib([
        _due(id: 'a'),
        _due(id: 'later', due: '2027-01-01T00:00:00.000Z'),
        _fresh(id: 'new'),
      ]);
      expect(reviewPool(library: lib, now: _now).map((it) => it.id), ['a']);
    });

    test('本篇里学过的词也会出现在全库复习里（复习不分篇）', () {
      final lib = _lib(
        [_due(id: 'a', word: 'alpha')],
        entries: [articleEntry(articleId: 'A', lemma: 'alpha')],
      );
      expect(reviewPool(library: lib, now: _now).map((it) => it.id), ['a']);
    });
  });

  group('recallPool', () {
    test('本篇学过：只认显式收进这一篇且有学习记录的', () {
      final lib = _lib(
        [
          _due(id: 'a', word: 'alpha'),
          _due(id: 'b', word: 'beta'),
          _fresh(id: 'c', word: 'gamma'),
        ],
        entries: [
          articleEntry(articleId: 'A', lemma: 'alpha'),
          articleEntry(articleId: 'A', lemma: 'gamma'),
        ],
      );
      final pool = recallPool(library: lib, articleId: 'A');
      expect(pool.map((it) => it.id), ['a'], reason: 'gamma 没学过，不进回顾');
    });

    test('最近 7 天：只认 recentIds，且必须有学习记录', () {
      final lib = _lib([
        _due(id: 'a'),
        _due(id: 'b'),
        _fresh(id: 'c'),
      ]);
      final pool = recallPool(
        library: lib,
        scope: RecallScope.last7Days,
        recentIds: {'a', 'c'},
      );
      expect(pool.map((it) => it.id), ['a']);
    });

    test('最近 7 天不看文章：没打开过文章也有东西', () {
      final lib = _lib([_due(id: 'a')]);
      expect(
        recallPool(
          library: lib,
          scope: RecallScope.last7Days,
          recentIds: {'a'},
        ),
        hasLength(1),
      );
    });

    test('本篇没 articleId 时是空池', () {
      final lib = _lib([_due(id: 'a')]);
      expect(recallPool(library: lib), isEmpty);
      expect(recallPool(library: lib, articleId: ''), isEmpty);
    });
  });

  group('effectiveGroupSize', () {
    test('手动设了正数就用它', () {
      expect(
        effectiveGroupSize(
          groupSize: 7,
          entry: StudyEntry.learn,
          poolLength: 50,
        ),
        7,
      );
    });

    test('没设（0）+ 学习 = 整篇长度', () {
      expect(
        effectiveGroupSize(
          groupSize: 0,
          entry: StudyEntry.learn,
          poolLength: 12,
        ),
        12,
      );
    });

    test('没设 + 学习 + 空池 = 1（避免除零）', () {
      expect(
        effectiveGroupSize(
          groupSize: 0,
          entry: StudyEntry.learn,
          poolLength: 0,
        ),
        1,
      );
    });

    test('没设 + 复习 / 回顾 = 20', () {
      for (final entry in [StudyEntry.review, StudyEntry.recall]) {
        expect(
          effectiveGroupSize(groupSize: 0, entry: entry, poolLength: 3),
          defaultStudyGroupSize,
          reason: '$entry',
        );
      }
    });
  });

  group('studyPoolCounts', () {
    test('三个入口各数一遍', () {
      final lib = _lib(
        [
          _due(id: 'due1', word: 'dueone'),
          _due(id: 'due2', word: 'duetwo'),
          _fresh(id: 'new1', word: 'newone'),
          _fresh(id: 'new2', word: 'newtwo'),
          _fresh(id: 'new3', word: 'newthree'),
        ],
        entries: [
          articleEntry(articleId: 'A', lemma: 'dueone'),
          articleEntry(articleId: 'A', lemma: 'newone'),
          articleEntry(articleId: 'A', lemma: 'newtwo'),
        ],
      );
      final counts = studyPoolCounts(
        library: lib,
        articleId: 'A',
        recentIds: {'due1', 'due2'},
        now: _now,
      );
      expect(counts.learn, 2, reason: '本篇只有 new1 / new2 没学过');
      expect(counts.review, 2, reason: '复习是全库到期的');
      expect(counts.recall, 1, reason: '本篇学过且到期的只有 due1');
    });

    test('空库三个数都是 0', () {
      final counts = studyPoolCounts(library: _lib(const []), now: _now);
      expect(counts.learn, 0);
      expect(counts.review, 0);
      expect(counts.recall, 0);
      expect(counts.isEmpty, isTrue);
    });

    test('回顾切到最近 7 天时按 recentIds 数', () {
      final lib = _lib([_due(id: 'a'), _due(id: 'b')]);
      final counts = studyPoolCounts(
        library: lib,
        recallScope: RecallScope.last7Days,
        recentIds: {'b'},
        now: _now,
      );
      expect(counts.recall, 1);
    });

    test('入口与回顾范围标签齐全', () {
      expect(studyEntryLabel.length, StudyEntry.values.length);
      expect(studyEntryLabel[StudyEntry.recall], '回顾');
      expect(recallScopeLabel.length, RecallScope.values.length);
      expect(recallScopeLabel[RecallScope.last7Days], '最近 7 天');
    });
  });
}
