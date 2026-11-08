// 打印 / 导出选片计划的用例（对应 Web 版 `src/core/printPlan.test.ts`）。
//
// 这些用例就是原来「测不到」的那部分领域判断：按日期筛、未打印筛、
// 多选文章归并、内容口径、标题命名。

import 'package:dlaoshi_app/core/entry_kind.dart';
import 'package:dlaoshi_app/core/print_plan.dart';
import 'package:dlaoshi_app/models/vocab.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/vocab_fixture.dart';

VocabSource src(String articleId, {String sentenceId = 's1'}) => VocabSource(
      articleId: articleId,
      fileName: articleId,
      sentenceId: sentenceId,
      sentenceText: '',
    );

final List<VocabItem> lib = [
  vocabItem(
    id: '1',
    word: 'run',
    lemma: 'run',
    source: src('A'),
    createdAt: '2026-10-01T10:00:00+08:00',
  ),
  vocabItem(
    id: '2',
    word: 'wall',
    lemma: 'wall',
    source: src('B'),
    createdAt: '2026-10-02T10:00:00+08:00',
    lastPrintedAt: '2026-10-02T12:00:00+08:00',
  ),
  vocabItem(
    id: '3',
    word: 'fall back on',
    lemma: 'fall back on',
    kind: VocabItemKind.phrase,
    meaning: '转而依靠',
    source: src('A', sentenceId: 's2'),
    createdAt: '2026-10-03T10:00:00+08:00',
  ),
  vocabItem(
    id: '4',
    word: '注意 run 的用法',
    lemma: '注意 run 的用法',
    kind: VocabItemKind.usage,
    source: src('A', sentenceId: 's3'),
    createdAt: '2026-10-03T11:00:00+08:00',
  ),
];

final refA = PrintArticleRef(id: 'A', title: 'A 篇', lemmas: {'run'});
final refB = PrintArticleRef(id: 'B', title: 'B 篇');

PrintPlanInput base({
  List<VocabItem>? libraryItems,
  List<VocabItem>? articleItems,
  List<ArticleVocabEntry>? articleEntries,
  bool hasEntries = false,
  String? articleId,
  List<PrintArticleRef>? articles,
  Set<String>? pickedArticles,
  Set<String>? pickedDates,
  PrintContent content = PrintContent.all,
  PrintScope scope = PrintScope.all,
}) =>
    PrintPlanInput(
      libraryItems: libraryItems ?? lib,
      articleItems:
          articleItems ?? lib.where((it) => it.source?.fileName == 'A').toList(),
      articleId: articleId,
      // `articleEntries` 传 null 与「空表」语义不同：null = 老调用方走兜底。
      articleEntries: hasEntries ? (articleEntries ?? const []) : null,
      articleTitle: 'A 篇',
      articles: articles ?? [refA, refB],
      pickedArticles: pickedArticles ?? {'A'},
      pickedDates: pickedDates ?? {'2026-10-02'},
      content: content,
      scope: scope,
    );

void main() {
  group('printRowsForItems', () {
    test('只在一处拼行结构：篇 id / 标题 / 编号 / 语境释义', () {
      final one = vocabItem(id: 'w1', word: 'run', lemma: 'run', meaning: '跑');
      final rows = printRowsForItems(
        [one],
        articleId: 'a1',
        articleTitle: 'A 篇',
        numberOf: (_) => 2,
        meaningOf: (_) => '跑步',
      );
      expect(rows, hasLength(1));
      expect(rows.single.item, same(one));
      expect(rows.single.articleId, 'a1');
      expect(rows.single.articleTitle, 'A 篇');
      expect(rows.single.number, 2);
      expect(rows.single.meaning, '跑步');
    });
  });

  group('planPrint：内容口径', () {
    test('单词 / 词组习语 / 用法 三类各自过滤，all 不过滤', () {
      expect(contentKinds(PrintContent.all), isNull);
      expect(contentKinds(PrintContent.word), [VocabKind.word]);
      expect(contentKinds(PrintContent.phrases), [VocabKind.phrase, VocabKind.idiom]);
      expect(contentKinds(PrintContent.usage), [VocabKind.usage]);

      expect(
        planPrint(base(content: PrintContent.word)).pool.map((it) => it.word),
        ['run', 'wall'],
      );
      expect(
        planPrint(base(content: PrintContent.phrases))
            .pool
            .map((it) => it.word),
        ['fall back on'],
      );
      expect(
        planPrint(base(content: PrintContent.usage)).pool.map((it) => it.word),
        ['注意 run 的用法'],
      );
      expect(planPrint(base()).pool, hasLength(4));
      expect(planPrint(base()).contentCounts, {
        PrintContent.all: 4,
        PrintContent.word: 2,
        PrintContent.phrases: 1,
        PrintContent.usage: 1,
      });
    });
  });

  group('planPrint：范围', () {
    test('本篇：只取这一篇（内容口径同时生效）', () {
      final p = planPrint(base(scope: PrintScope.article, content: PrintContent.word));
      expect(p.items.map((it) => it.word), ['run']);
      expect(p.isArticleOrder, isTrue);
    });

    test('本篇过滤后为空 → 保持空，不降级到全部（新文章不能继承总词库）', () {
      final p = planPrint(base(
        scope: PrintScope.article,
        content: PrintContent.usage,
        articleItems: const [],
      ));
      expect(p.items, isEmpty);
      expect(p.rows, isEmpty);
      expect(p.isArticleOrder, isTrue);
      expect(p.canAct, isFalse);
    });

    test('按文章：多选多篇，同一条只算一次', () {
      final p = planPrint(base(
        scope: PrintScope.byArticle,
        pickedArticles: {'A', 'B'},
      ));
      expect(p.items.map((it) => it.id), ['1', '3', '4', '2']);
      expect(p.articleCount['A'], 3);
      expect(p.articleCount['B'], 1);
    });

    test('按日期：只取选中的日子，dates 倒序列出有内容的天', () {
      final p = planPrint(base(
        scope: PrintScope.date,
        pickedDates: {'2026-10-01'},
      ));
      expect(p.items.map((it) => it.word), ['run']);
      expect(p.dates.map((d) => d.day), ['2026-10-03', '2026-10-02', '2026-10-01']);
      expect(p.dates.first.count, 2, reason: '10-03 有词组与用法两条');
    });

    test('未打印：跳过已打印过的条目', () {
      final p = planPrint(base(scope: PrintScope.unprinted));
      expect(p.items.map((it) => it.word), ['run', 'fall back on', '注意 run 的用法']);
      expect(p.unprinted, hasLength(3));
    });
  });

  group('planPrint：按篇条目 / 行', () {
    final entries = [
      ArticleVocabEntry(
        articleId: 'A',
        lemma: 'run',
        origin: VocabOrigin.manual,
        addedAt: '2026-10-01T00:00:00.000Z',
      ),
      ArticleVocabEntry(
        articleId: 'A',
        lemma: 'fall back on',
        origin: VocabOrigin.manual,
        addedAt: '2026-10-01T00:00:01.000Z',
      ),
      ArticleVocabEntry(
        articleId: 'B',
        lemma: 'run',
        origin: VocabOrigin.auto,
        addedAt: '2026-10-01T00:00:02.000Z',
      ),
    ];

    test('按文章：同一词在两篇各一行、各用自己的编号，不再跨篇去重', () {
      final p = planPrint(base(
        hasEntries: true,
        articleEntries: entries,
        articleId: 'A',
        scope: PrintScope.byArticle,
        pickedArticles: {'A', 'B'},
      ));
      expect(
        p.rows.map((r) => '${r.articleId}:${r.item.lemma}:${r.number}'),
        ['A:run:1', 'A:fall back on:null', 'B:run:1'],
      );
      expect(p.items.map((it) => it.lemma), ['run', 'fall back on', 'run']);
      expect(p.articleCount['A'], 2);
      expect(p.articleCount['B'], 1);
    });

    test('本篇：单词行按本篇顺序编号，语言点行不编号', () {
      final p = planPrint(base(
        hasEntries: true,
        articleEntries: entries,
        articleId: 'A',
        scope: PrintScope.article,
      ));
      expect(
        p.rows.map((r) => '${r.item.lemma}:${r.number}'),
        ['run:1', 'fall back on:null', '注意 run 的用法:null'],
      );
    });

    test('已有按篇表时不再用正文 lemma 兜底（新文章不继承总词库）', () {
      final p = planPrint(base(
        hasEntries: true,
        articleEntries: const [],
        articleId: 'A',
        scope: PrintScope.byArticle,
        pickedArticles: {'A'},
      ));
      expect(p.rows, isEmpty);
      expect(p.articleCount['A'], 0);
    });
  });

  group('planPrint：标题命名', () {
    test('本篇/按文章/按日期/未打印/全部 各有名字，且随内容口径变', () {
      expect(planPrint(base(scope: PrintScope.article)).title, 'A 篇');
      expect(
        planPrint(base(scope: PrintScope.article, content: PrintContent.phrases))
            .title,
        'A 篇·词组习语表',
      );
      expect(
        planPrint(base(scope: PrintScope.byArticle, pickedArticles: {'A'})).title,
        '词表-A 篇',
      );
      expect(
        planPrint(base(scope: PrintScope.byArticle, pickedArticles: {'A', 'B'}))
            .title,
        '词表-2篇',
      );
      expect(
        planPrint(base(scope: PrintScope.date, pickedDates: {'2026-10-01'})).title,
        '词表-新增-2026-10-01',
      );
      expect(
        planPrint(base(
          scope: PrintScope.date,
          pickedDates: {'2026-10-01', '2026-10-02'},
        )).title,
        '词表-新增-2天',
      );
      expect(
        planPrint(base(scope: PrintScope.unprinted, content: PrintContent.usage))
            .title,
        '全部用法笔记（未打印）',
      );
      expect(planPrint(base()).title, '全部生词');
    });
  });

  group('planPrint：空结果', () {
    test('canAct 跟着结果走（没条目就禁用动作按钮）', () {
      final empty = planPrint(base(libraryItems: const [], articleItems: const []));
      expect(empty.canAct, isFalse);
      expect(planPrint(base()).canAct, isTrue);
    });
  });
}
