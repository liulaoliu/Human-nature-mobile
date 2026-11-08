import 'package:dlaoshi_app/core/article_vocab.dart';
import 'package:dlaoshi_app/core/vocab/library.dart';
import 'package:dlaoshi_app/core/vocab/tombstones.dart';
import 'package:dlaoshi_app/models/vocab.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/vocab_fixture.dart';

const now = '2026-10-02T00:00:00.000Z';

VocabLibrary _lib(List<VocabItem> items, {List<ArticleVocabEntry>? entries}) =>
    VocabLibrary(items: items, articleEntries: entries ?? const []);

void main() {
  group('编辑 / 状态 / 删除', () {
    test('editItem 默认置为 edited', () {
      var lib = _lib([vocabItem(id: 'v1', word: 'run')]);
      lib = editItem(lib, 'v1', const VocabItemPatch(note: '易混淆'),
          now: DateTime.parse(now));
      expect(lib.items[0].note, '易混淆');
      expect(lib.items[0].status, VocabStatus.edited);
    });

    test('只给手动改过的核心字段记来源；改笔记不锁字段', () {
      var lib = _lib([vocabItem(id: 'v1', word: 'run')]);
      lib = editItem(lib, 'v1', const VocabItemPatch(note: '易混淆'));
      expect(lib.items[0].fieldSources, isNull);
      lib = editItem(lib, 'v1', const VocabItemPatch(meaning: '跑'));
      expect(lib.items[0].fieldSources, {VocabField.meaning: VocabFieldSource.manual});
    });

    test('setStatus', () {
      var lib = _lib([vocabItem(id: 'v1', word: 'run')]);
      lib = setStatus(lib, 'v1', VocabStatus.mastered);
      expect(lib.items[0].status, VocabStatus.mastered);
    });

    test('removeItem 删词条并连带删掉各篇收录', () {
      var lib = _lib(
        [vocabItem(id: 'v1', word: 'running', lemma: 'run')],
        entries: [articleEntry(lemma: 'run')],
      );
      lib = removeItem(lib, 'v1');
      expect(lib.items, isEmpty);
      expect(lib.articleEntries, isEmpty);
      expect(lib.tombstones.single.kind, VocabTombstoneKind.item);
    });

    test('removeByLemma 按词形删', () {
      final lib = _lib(
        [vocabItem(id: 'v1', word: 'running', lemma: 'run')],
        entries: [articleEntry(lemma: 'run')],
      );
      expect(removeByLemma(lib, 'run').items, isEmpty);
      expect(removeByLemma(lib, 'Running').articleEntries, isEmpty);
    });
  });

  group('筛选 / 分组 / 排序', () {
    final a = vocabItem(
      id: 'vocab:a',
      word: 'apple',
      lemma: 'apple',
      status: VocabStatus.queried,
      source: const VocabSource(articleId: 'art1'),
      tags: const ['food'],
      createdAt: now,
    );
    final b = vocabItem(
      id: 'vocab:b',
      word: 'banana',
      lemma: 'banana',
      status: VocabStatus.unqueried,
      source: const VocabSource(articleId: 'art2'),
      createdAt: now,
    );
    final c = vocabItem(
      id: 'vocab:c',
      word: 'cherry',
      lemma: 'cherry',
      meaning: '樱桃',
      status: VocabStatus.mastered,
      source: const VocabSource(articleId: 'art1'),
      createdAt: now,
    );

    test('按状态筛选', () {
      expect(
        filterItems(
          [a, b, c],
          const VocabFilter(status: [VocabStatus.queried, VocabStatus.mastered]),
        ).map((x) => x.lemma),
        ['apple', 'cherry'],
      );
    });

    test('按文章筛选', () {
      expect(
        filterItems([a, b, c], const VocabFilter(articleId: 'art1'))
            .map((x) => x.lemma),
        ['apple', 'cherry'],
      );
    });

    test('按标签筛选', () {
      expect(
        filterItems([a, b, c], const VocabFilter(tag: 'food'))
            .map((x) => x.lemma),
        ['apple'],
      );
    });

    test('模糊查询命中含义', () {
      expect(
        filterItems([a, b, c], const VocabFilter(query: '樱桃'))
            .map((x) => x.lemma),
        ['cherry'],
      );
    });

    test('按到期日筛选', () {
      final due = vocabItem(
        id: 'vocab:d',
        lemma: 'due',
        reviewState: const ReviewState(due: '2026-09-01T00:00:00.000Z', interval: 1, repetitions: 1),
      );
      final future = vocabItem(
        id: 'vocab:e',
        lemma: 'future',
        reviewState: const ReviewState(due: '2027-01-01T00:00:00.000Z', interval: 1, repetitions: 1),
      );
      expect(
        filterItems([due, future], VocabFilter(dueBefore: DateTime.parse(now)))
            .map((x) => x.lemma),
        ['due'],
      );
    });

    test('按首字母分组', () {
      expect(
        groupItems([a, c], VocabGroupBy.alphabet).map((g) => g.key),
        ['A', 'C'],
      );
    });

    test('按文章分组', () {
      expect(
        groupItems([a, b, c], VocabGroupBy.article).map((g) => g.key),
        ['art1', 'art2'],
      );
    });

    test('按日期分组', () {
      expect(groupItems([a, b], VocabGroupBy.date).first.key, '2026-10-02');
    });

    test('按状态分组', () {
      expect(
        groupItems([a, b, c], VocabGroupBy.status).map((g) => g.key).toList()..sort(),
        ['mastered', 'queried', 'unqueried'],
      );
    });

    test('按字母排序', () {
      expect(
        sortItems([c, a, b], VocabSortBy.word).map((x) => x.lemma),
        ['apple', 'banana', 'cherry'],
      );
    });

    test('按到期排序，未排期的排最后', () {
      final due = vocabItem(
        id: 'vocab:d',
        lemma: 'due',
        reviewState: const ReviewState(due: '2026-09-01T00:00:00.000Z', interval: 1, repetitions: 1),
      );
      expect(
        sortItems([b, due], VocabSortBy.due).map((x) => x.lemma),
        ['due', 'banana'],
      );
    });
  });

  group('articleWordsOf（本篇生词归属）', () {
    test('只认显式收进本篇的条目；总词库里别的词不继承', () {
      final lib = _lib(
        [
          vocabItem(id: 'vocab:a', word: 'estrange', lemma: 'estrange'),
          vocabItem(id: 'vocab:b', word: 'bungle', lemma: 'bungle'),
          vocabItem(id: 'vocab:c', word: 'unrelated', lemma: 'unrelated'),
        ],
        entries: [
          articleEntry(articleId: 'art-A', lemma: 'estrange', addedAt: '2026-01-01T00:00:00.000Z'),
          articleEntry(
            articleId: 'art-A',
            lemma: 'bungle',
            origin: VocabOrigin.auto,
            addedAt: '2026-01-01T00:00:01.000Z',
          ),
        ],
      );
      expect(articleWordsOf(lib, 'art-A').map((it) => it.lemma), ['estrange', 'bungle']);
      expect(articleWordsOf(lib, 'art-B'), isEmpty);
    });
  });

  group('markPrinted / unprintedItems', () {
    VocabLibrary twoWords() => _lib([
          vocabItem(id: 'v-run', word: 'run', lemma: 'run'),
          vocabItem(id: 'v-jump', word: 'jump', lemma: 'jump'),
        ]);

    test('给指定词条写上打印时间，其余不动', () {
      final out = markPrinted(twoWords(), ['v-run'], now: DateTime.parse(now));
      expect(out.items.firstWhere((it) => it.lemma == 'run').lastPrintedAt, now);
      expect(out.items.firstWhere((it) => it.lemma == 'jump').lastPrintedAt, isNull);
    });

    test('isPrinted / unprintedItems 把没有 lastPrintedAt 的算作未打印', () {
      var lib = twoWords();
      expect(unprintedItems(lib.items), hasLength(2));
      lib = markPrinted(lib, ['v-run']);
      expect(isPrinted(lib.items.first), isTrue);
      expect(unprintedItems(lib.items), hasLength(1));
    });

    test('传空集合原样返回', () {
      final lib = twoWords();
      expect(identical(markPrinted(lib, const []), lib), isTrue);
    });
  });

  group('优先重排', () {
    test('isPriority 只看未过期的 priorityUntil', () {
      final item = vocabItem(id: 'v1', word: 'run');
      expect(isPriority(item), isFalse);
      final future = item.copyWith(priorityUntil: () => '2999-01-01T00:00:00.000Z');
      expect(isPriority(future), isTrue);
      final past = item.copyWith(priorityUntil: () => '2000-01-01T00:00:00.000Z');
      expect(isPriority(past), isFalse);
    });

    test('prioritizeItems 只改传进来的那几个', () {
      final lib = _lib([
        vocabItem(id: 'v1', word: 'run'),
        vocabItem(id: 'v2', word: 'jump'),
      ]);
      final out = prioritizeItems(lib, ['v1'], '2999-01-01T00:00:00.000Z');
      expect(out.items[0].priorityUntil, '2999-01-01T00:00:00.000Z');
      expect(out.items[1].priorityUntil, isNull);
    });
  });

  group('墓碑', () {
    test('删掉的词不会被服务端那份并回来', () {
      final removed = removeItem(
        _lib([vocabItem(id: 'vocab:bank', word: 'bank')]),
        'vocab:bank',
      );
      final server = _lib([vocabItem(id: 'vocab:bank', word: 'bank')]);
      final merged = mergeLibrariesForSync(removed, server);
      expect(merged.items, isEmpty);
      expect(merged.tombstones, hasLength(1));
    });

    test('删完又加回来的新词（updatedAt 晚于墓碑）不会被误删', () {
      final removed = removeItem(
        _lib([vocabItem(id: 'vocab:bank', word: 'bank')]),
        'vocab:bank',
      );
      final readded = removed.copyWith(
        items: [vocabItem(id: 'vocab:bank', word: 'bank', updatedAt: '2999-01-01T00:00:00.000Z')],
      );
      expect(applyTombstones(readded).items, hasLength(1));
    });

    test('同一条两边都改过：updatedAt 更新的赢', () {
      final local = _lib([
        vocabItem(id: 'vocab:bank', word: 'bank', meaning: '本机', updatedAt: '2026-10-24T00:00:00.000Z'),
      ]);
      final server = _lib([
        vocabItem(id: 'vocab:bank', word: 'bank', meaning: '服务端', updatedAt: '2026-10-23T00:00:00.000Z'),
      ]);
      expect(mergeLibrariesForSync(local, server).items.single.meaning, '本机');

      final localOld = _lib([
        vocabItem(id: 'vocab:bank', word: 'bank', meaning: '本机', updatedAt: '2026-10-22T00:00:00.000Z'),
      ]);
      expect(mergeLibrariesForSync(localOld, server).items.single.meaning, '服务端');
    });

    test('篇条目也有墓碑：从这篇移出后不会被并回来', () {
      var local = _lib(
        [vocabItem(id: 'vocab:bank', word: 'bank')],
        entries: [
          articleEntry(articleId: 'art-1', lemma: 'bank', addedAt: '2026-10-01T00:00:00.000Z'),
        ],
      );
      local = removeArticleEntry(local, 'art-1', 'bank');
      expect(local.tombstones.any((t) => t.kind == VocabTombstoneKind.article), isTrue);

      final server = _lib(
        [vocabItem(id: 'vocab:bank', word: 'bank')],
        entries: [
          articleEntry(articleId: 'art-1', lemma: 'bank', addedAt: '2026-10-01T00:00:00.000Z'),
        ],
      );
      expect(mergeLibrariesForSync(local, server).articleEntries, isEmpty);
    });
  });
}
