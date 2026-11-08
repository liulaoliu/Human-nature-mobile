import 'package:dlaoshi_app/core/article_vocab.dart';
import 'package:dlaoshi_app/models/vocab.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/vocab_fixture.dart';

const now = '2026-10-20T00:00:00.000Z';
final nowDate = DateTime.parse(now);

VocabLibrary _lib(List<VocabItem> items, {List<ArticleVocabEntry> entries = const []}) =>
    VocabLibrary(items: items, articleEntries: entries);

void main() {
  group('addArticleEntry：按篇收录', () {
    test('普通单词收进指定篇，编号顺序 = 数组顺序', () {
      var l = _lib([
        vocabItem(id: 'v1', lemma: 'alpha'),
        vocabItem(id: 'v2', lemma: 'beta'),
      ]);
      l = addArticleEntry(l, articleId: 'A', lemma: 'beta', origin: VocabOrigin.auto, now: nowDate);
      l = addArticleEntry(l, articleId: 'A', lemma: 'alpha', origin: VocabOrigin.manual, now: nowDate);
      expect(articleEntriesOf(l, 'A').map((e) => e.lemma), ['beta', 'alpha']);
      expect(articleItemsOf(l, 'A').map((it) => it.lemma), ['beta', 'alpha']);
    });

    test('写入细分来源；已有来源不被后来的动作覆盖', () {
      var l = _lib([vocabItem(id: 'v1', lemma: 'alpha')]);
      l = addArticleEntry(
        l,
        articleId: 'A',
        lemma: 'alpha',
        origin: VocabOrigin.auto,
        via: VocabVia.dict,
        now: nowDate,
      );
      expect(articleEntriesOf(l, 'A')[0].via, VocabVia.dict);
      l = addArticleEntry(
        l,
        articleId: 'A',
        lemma: 'alpha',
        origin: VocabOrigin.manual,
        via: VocabVia.manual,
        now: nowDate,
      );
      expect(articleEntriesOf(l, 'A')[0].via, VocabVia.dict);
    });

    test('旧条目没有 via：后来的动作可以补上，但不改 origin', () {
      var l = _lib(
        [vocabItem(id: 'v1', lemma: 'alpha')],
        entries: [
          articleEntry(articleId: 'A', lemma: 'alpha', origin: VocabOrigin.manual, addedAt: now),
        ],
      );
      l = addArticleEntry(
        l,
        articleId: 'A',
        lemma: 'alpha',
        origin: VocabOrigin.auto,
        via: VocabVia.ai,
        now: nowDate,
      );
      final e = articleEntriesOf(l, 'A')[0];
      expect(e.origin, VocabOrigin.manual);
      expect(e.via, VocabVia.ai);
    });

    test('同篇同词只收一次，只补空着的语境，不改变顺序', () {
      var l = _lib([vocabItem(id: 'v1', lemma: 'alpha')]);
      l = addArticleEntry(l, articleId: 'A', lemma: 'alpha', origin: VocabOrigin.auto, now: nowDate);
      l = addArticleEntry(
        l,
        articleId: 'A',
        lemma: 'alpha',
        origin: VocabOrigin.manual,
        sentenceId: 's1',
        sentenceText: 'A.',
        now: nowDate,
      );
      l = addArticleEntry(
        l,
        articleId: 'A',
        lemma: 'alpha',
        origin: VocabOrigin.manual,
        sentenceId: 's2',
        sentenceText: 'B.',
        now: nowDate,
      );
      final entries = articleEntriesOf(l, 'A');
      expect(entries, hasLength(1));
      expect(entries[0].origin, VocabOrigin.auto);
      expect(entries[0].sentenceId, 's1');
      expect(entries[0].sentenceText, 'A.');
    });

    test('已掌握词 / 不存在的词不收', () {
      var l = _lib([
        vocabItem(id: 'v1', word: 'done', lemma: 'done', status: VocabStatus.mastered),
        vocabItem(id: 'v2', word: 'take off', lemma: 'take off', kind: VocabItemKind.phrase),
      ]);
      l = addArticleEntry(l, articleId: 'A', lemma: 'done', origin: VocabOrigin.manual, now: nowDate);
      l = addArticleEntry(l, articleId: 'A', lemma: 'missing', origin: VocabOrigin.manual, now: nowDate);
      expect(articleEntriesOf(l, 'A'), isEmpty);
    });

    test('语言点（词组 / 习语 / 用法）也能收进本篇，但不进单词编号', () {
      var l = _lib([
        vocabItem(id: 'v1', word: 'take off', lemma: 'take off', kind: VocabItemKind.phrase),
      ]);
      l = addArticleEntry(l, articleId: 'A', lemma: 'take off', origin: VocabOrigin.auto, now: nowDate);
      expect(articleEntriesOf(l, 'A'), hasLength(1));
      expect(articleItemsOf(l, 'A'), isEmpty);
    });

    test('同一词可以各自收进多篇，条目互不影响', () {
      var l = _lib([vocabItem(id: 'v1', lemma: 'alpha')]);
      l = addArticleEntry(l, articleId: 'A', lemma: 'alpha', origin: VocabOrigin.auto, meaning: '甲', now: nowDate);
      l = addArticleEntry(l, articleId: 'B', lemma: 'alpha', origin: VocabOrigin.manual, meaning: '乙', now: nowDate);
      expect(articleEntriesOf(l, 'A')[0].meaning, '甲');
      expect(articleEntriesOf(l, 'B')[0].meaning, '乙');
    });

    test('空 articleId / 空 lemma 原样返回', () {
      final l = _lib([vocabItem(id: 'v1', lemma: 'alpha')]);
      expect(identical(addArticleEntry(l, articleId: '  ', lemma: 'alpha', origin: VocabOrigin.manual), l), isTrue);
      expect(identical(addArticleEntry(l, articleId: 'A', lemma: ' ', origin: VocabOrigin.manual), l), isTrue);
    });
  });

  group('removeArticleEntry / markArticlePrinted', () {
    test('从一篇删除只动这一篇，不影响全库和别的篇', () {
      var l = _lib([vocabItem(id: 'v1', lemma: 'alpha')]);
      l = addArticleEntry(l, articleId: 'A', lemma: 'alpha', origin: VocabOrigin.manual, now: nowDate);
      l = addArticleEntry(l, articleId: 'B', lemma: 'alpha', origin: VocabOrigin.manual, now: nowDate);
      l = removeArticleEntry(l, 'A', 'alpha');
      expect(articleEntriesOf(l, 'A'), isEmpty);
      expect(articleEntriesOf(l, 'B'), hasLength(1));
      expect(l.items, hasLength(1));
    });

    test('打印标记按篇独立', () {
      var l = _lib([vocabItem(id: 'v1', lemma: 'alpha')]);
      l = addArticleEntry(l, articleId: 'A', lemma: 'alpha', origin: VocabOrigin.manual, now: nowDate);
      l = addArticleEntry(l, articleId: 'B', lemma: 'alpha', origin: VocabOrigin.manual, now: nowDate);
      l = markArticlePrinted(l, 'A', ['alpha'], now: nowDate);
      expect(articleEntriesOf(l, 'A')[0].printedAt, now);
      expect(articleEntriesOf(l, 'B')[0].printedAt, isNull);
    });

    test('打印空集合原样返回', () {
      final l = _lib([vocabItem(id: 'v1', lemma: 'alpha')]);
      expect(identical(markArticlePrinted(l, 'A', const []), l), isTrue);
    });
  });

  group('articleEntryViews / mergeArticleEntries', () {
    test('按加入顺序过滤已掌握 / 非单词 / 缺失词，重复 lemma 只留第一条', () {
      final l = _lib(
        [
          vocabItem(id: 'v1', word: 'alpha', lemma: 'alpha'),
          vocabItem(id: 'v2', word: 'done', lemma: 'done', status: VocabStatus.mastered),
          vocabItem(id: 'v3', word: 'take off', lemma: 'take off', kind: VocabItemKind.phrase),
        ],
        entries: [
          articleEntry(articleId: 'A', lemma: 'alpha', addedAt: now),
          articleEntry(articleId: 'A', lemma: 'done', addedAt: now),
          articleEntry(articleId: 'A', lemma: 'take off', addedAt: now),
          articleEntry(articleId: 'A', lemma: 'alpha', origin: VocabOrigin.auto, addedAt: now),
          articleEntry(articleId: 'A', lemma: 'missing', origin: VocabOrigin.auto, addedAt: now),
        ],
      );
      expect(articleEntryViews(l, 'A').map((v) => v.item.lemma), ['alpha']);
    });

    test('合并按篇条目：同篇同 lemma 保留本机，其余追加', () {
      final a = [
        articleEntry(articleId: 'A', lemma: 'alpha', origin: VocabOrigin.manual, addedAt: now),
      ];
      final b = [
        articleEntry(
          articleId: 'A',
          lemma: 'alpha',
          origin: VocabOrigin.auto,
          addedAt: '2026-01-01T00:00:00.000Z',
        ),
        articleEntry(articleId: 'B', lemma: 'beta', origin: VocabOrigin.auto, addedAt: now),
      ];
      final out = mergeArticleEntries(a, b);
      expect(out, hasLength(2));
      expect(out[0].origin, VocabOrigin.manual);
      expect(out[1].articleId, 'B');
    });

    test('articleIndexIn 只数普通单词', () {
      final l = _lib(
        [
          vocabItem(id: 'v1', lemma: 'alpha'),
          vocabItem(id: 'v2', word: 'take off', lemma: 'take off', kind: VocabItemKind.phrase),
          vocabItem(id: 'v3', lemma: 'beta'),
        ],
        entries: [
          articleEntry(articleId: 'A', lemma: 'take off', addedAt: now),
          articleEntry(articleId: 'A', lemma: 'alpha', addedAt: now),
          articleEntry(articleId: 'A', lemma: 'beta', addedAt: now),
        ],
      );
      expect(articleIndexIn(l, 'A', 'alpha'), 1);
      expect(articleIndexIn(l, 'A', 'beta'), 2);
      expect(articleIndexIn(l, 'A', 'take off'), 0);
      expect(articleIndexIn(l, 'A', 'missing'), 0);
    });
  });

  group('articleEntryViewsFrom：多篇 / 多归属键', () {
    final items = [
      vocabItem(id: 'v-alpha', word: 'alpha', lemma: 'alpha'),
      vocabItem(id: 'v-done', word: 'done', lemma: 'done', status: VocabStatus.mastered),
      vocabItem(id: 'v-take', word: 'take off', lemma: 'take off', kind: VocabItemKind.phrase),
      vocabItem(id: 'v-use', word: 'alpha 的用法', lemma: 'alpha 的用法', kind: VocabItemKind.usage),
    ];
    final entries = [
      articleEntry(articleId: 'saved:A', lemma: 'alpha', origin: VocabOrigin.auto, addedAt: now),
      articleEntry(articleId: 'a-key', lemma: 'take off', origin: VocabOrigin.auto, addedAt: now),
      articleEntry(articleId: 'A', lemma: 'alpha', origin: VocabOrigin.manual, addedAt: now),
      articleEntry(articleId: 'a-key', lemma: 'done', addedAt: now),
      articleEntry(articleId: 'a-key', lemma: 'alpha 的用法', origin: VocabOrigin.auto, addedAt: now),
      articleEntry(articleId: 'B', lemma: 'alpha', origin: VocabOrigin.auto, addedAt: now),
    ];

    test('同一篇的多个归属键合并；同 lemma 只留第一条；不混进别的篇', () {
      final views = articleEntryViewsFrom(items, entries, ['saved:A', 'a-key', 'A'], includeLang: true);
      expect(views.map((v) => v.item.lemma), ['alpha', 'take off', 'alpha 的用法']);
      expect(views[0].entry.articleId, 'saved:A');
    });

    test('默认只要单词、跳过已掌握；两个选项各自放开', () {
      expect(articleEntryViewsFrom(items, entries, ['a-key']).map((v) => v.item.lemma), isEmpty);
      expect(
        articleEntryViewsFrom(items, entries, ['a-key'], includeMastered: true).map((v) => v.item.lemma),
        ['done'],
      );
      expect(
        articleEntryViewsFrom(items, entries, ['a-key'], includeLang: true).map((v) => v.item.lemma),
        ['take off', 'alpha 的用法'],
      );
      expect(
        articleEntryViewsFrom(items, entries, ['a-key'], includeLang: true, includeMastered: true)
            .map((v) => v.item.lemma),
        ['take off', 'done', 'alpha 的用法'],
      );
    });

    test('找不到的词条 / 空篇：跳过，不报错', () {
      final views = articleEntryViewsFrom(
        items,
        [articleEntry(articleId: 'A', lemma: 'missing', origin: VocabOrigin.auto, addedAt: now)],
        ['A'],
        includeLang: true,
      );
      expect(views, isEmpty);
      expect(articleEntryViewsFrom(items, entries, const []), isEmpty);
    });
  });
}
