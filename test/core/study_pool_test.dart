import 'package:dlaoshi_app/core/entry_kind.dart';
import 'package:dlaoshi_app/core/study_pool.dart';
import 'package:dlaoshi_app/models/vocab.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/vocab_fixture.dart';

/// 每个用例固定的「现在」：2026-03-10。
final DateTime _now = DateTime.parse('2026-03-10T12:00:00.000Z');

VocabLibrary _lib(List<VocabItem> items) =>
    VocabLibrary(schemaVersion: 1, items: items);

/// 一条「有学习记录、今天到期」的词。
VocabItem _due({
  required String id,
  String? word,
  VocabItemKind? kind,
  int lapses = 0,
  VocabStatus status = VocabStatus.queried,
}) =>
    vocabItem(
      id: id,
      word: word,
      kind: kind,
      meaning: '释义$id',
      status: status,
      reviewState: ReviewState(
        due: '2026-03-01T00:00:00.000Z',
        repetitions: 1,
        lapses: lapses,
      ),
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
  group('studyPool 范围', () {
    test('全部：只要可背的（用法笔记与无释义的都不进）', () {
      final lib = _lib([
        _fresh(id: 'a'),
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
      final pool = studyPool(library: lib, scope: StudyScope.all);
      expect(pool.map((it) => it.id), ['a', 'b']);
    });

    test('没掌握：mastered 的被排除', () {
      final lib = _lib([
        _fresh(id: 'a'),
        _fresh(id: 'b', status: VocabStatus.mastered),
        _fresh(id: 'c', status: VocabStatus.queried),
      ]);
      final pool = studyPool(library: lib, scope: StudyScope.unmastered);
      expect(pool.map((it) => it.id), ['a', 'c']);
    });

    test('忘过的：只留 lapses > 0', () {
      final lib = _lib([
        _due(id: 'a', lapses: 2),
        _due(id: 'b'),
        _due(id: 'c', lapses: 1),
      ]);
      final pool = studyPool(library: lib, scope: StudyScope.lapses);
      expect(pool.map((it) => it.id), ['a', 'c']);
    });

    test('本篇：只认显式收进这一篇的条目', () {
      final lib = VocabLibrary(
        schemaVersion: 1,
        items: [
          _fresh(id: 'a', word: 'alpha'),
          _fresh(id: 'b', word: 'beta'),
          _fresh(id: 'c', word: 'gamma'),
        ],
        articleEntries: [
          articleEntry(articleId: 'A', lemma: 'alpha'),
          articleEntry(articleId: 'B', lemma: 'beta'),
        ],
      );
      final pool = studyPool(
        library: lib,
        scope: StudyScope.article,
        articleId: 'A',
      );
      expect(pool.map((it) => it.id), ['a']);
    });

    test('本篇：正文里出现过的词形也算（docLemmas 补一层）', () {
      final lib = VocabLibrary(
        schemaVersion: 1,
        items: [
          _fresh(id: 'a', word: 'alpha'),
          _fresh(id: 'b', word: 'beta'),
          _fresh(id: 'c', word: 'gamma'),
        ],
        articleEntries: [articleEntry(articleId: 'A', lemma: 'alpha')],
      );
      final pool = studyPool(
        library: lib,
        scope: StudyScope.article,
        articleId: 'A',
        docLemmas: {'gamma'},
      );
      expect(pool.map((it) => it.id), ['a', 'c']);
    });

    test('本篇：没有 articleId 时是空池，不是全文', () {
      final lib = _lib([_fresh(id: 'a')]);
      expect(
        studyPool(library: lib, scope: StudyScope.article),
        isEmpty,
      );
      expect(
        studyPool(library: lib, scope: StudyScope.article, articleId: ''),
        isEmpty,
      );
    });

    test('牌组：collocation 只要词组与习语，word 只要单词', () {
      final lib = _lib([
        _fresh(id: 'w', word: 'alpha'),
        _fresh(id: 'p', word: 'in the end', kind: VocabItemKind.phrase),
        _fresh(id: 'i', word: 'hit the sack', kind: VocabItemKind.idiom),
      ]);
      expect(
        studyPool(library: lib, scope: StudyScope.all)
            .map((it) => it.id),
        ['w'],
      );
      expect(
        studyPool(
          library: lib,
          scope: StudyScope.all,
          deck: StudyDeck.collocation,
        ).map((it) => it.id),
        ['p', 'i'],
      );
    });
  });

  group('effectiveGroupSize', () {
    test('手动设了正数就用它', () {
      expect(
        effectiveGroupSize(groupSize: 7, scope: StudyScope.all, poolLength: 50),
        7,
      );
    });

    test('没设（0）+ 本篇 = 整篇长度', () {
      expect(
        effectiveGroupSize(
          groupSize: 0,
          scope: StudyScope.article,
          poolLength: 12,
        ),
        12,
      );
    });

    test('没设 + 本篇 + 空池 = 1（避免除零）', () {
      expect(
        effectiveGroupSize(
          groupSize: 0,
          scope: StudyScope.article,
          poolLength: 0,
        ),
        1,
      );
    });

    test('没设 + 其它范围 = 20', () {
      for (final scope in [StudyScope.all, StudyScope.unmastered, StudyScope.lapses]) {
        expect(
          effectiveGroupSize(groupSize: 0, scope: scope, poolLength: 3),
          20,
          reason: '$scope',
        );
      }
    });
  });

  group('studyPoolCounts', () {
    test('分别数「到期该复习」和「没学过」', () {
      final pool = [
        _due(id: 'due1'),
        _due(id: 'due2'),
        _fresh(id: 'new1'),
        vocabItem(
          id: 'later',
          meaning: '以后再说',
          reviewState: const ReviewState(
            due: '2027-01-01T00:00:00.000Z',
            repetitions: 2,
          ),
        ),
      ];
      final counts = studyPoolCounts(pool, now: _now);
      expect(counts.due, 2);
      expect(counts.fresh, 1);
      expect(counts.total, 4);
    });

    test('空池三个数都是 0', () {
      final counts = studyPoolCounts(const [], now: _now);
      expect(counts.due, 0);
      expect(counts.fresh, 0);
      expect(counts.total, 0);
    });

    test('范围标签齐全（面板要按顺序显示）', () {
      expect(studyScopeLabel.length, StudyScope.values.length);
      expect(studyScopeLabel[StudyScope.unmastered], '没掌握');
    });
  });
}
