// 生词浏览页筛选口径的用例（对应 Web 版 `src/core/vocabBrowse.test.ts` 270 行）。
//
// 本篇 / 选篇的归属只认 `articleEntries`（和侧栏、打印同一份口径），
// 这一组用例守的就是这条：别在视图里再写一份「哪些词属于这篇」。

import 'package:dlaoshi_app/core/activity/activity.dart';
import 'package:dlaoshi_app/core/vocab_browse.dart';
import 'package:dlaoshi_app/models/vocab.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/vocab_fixture.dart';

/// 构造本地时刻的 ISO（与 Web 版 `at(y,m,d,h)` 等价）。
String at(int y, int m, int d, [int h = 12]) =>
    DateTime(y, m, d, h).toUtc().toIso8601String();

final alpha = vocabItem(
  id: 'v-alpha',
  word: 'alpha',
  lemma: 'alpha',
  meaning: '阿尔法',
  createdAt: at(2026, 10, 1),
);
final beta = vocabItem(
  id: 'v-beta',
  word: 'beta',
  lemma: 'beta',
  meaning: '贝塔',
  note: '希腊字母',
  createdAt: at(2026, 10, 2),
);
final done = vocabItem(
  id: 'v-done',
  word: 'done',
  lemma: 'done',
  status: VocabStatus.mastered,
  createdAt: at(2026, 10, 2),
);
final take = vocabItem(
  id: 'v-take',
  word: 'take off',
  lemma: 'take off',
  kind: VocabItemKind.phrase,
  meaning: '起飞',
  createdAt: at(2026, 10, 3),
);
final gamma = vocabItem(
  id: 'v-gamma',
  word: 'gamma',
  lemma: 'gamma',
  createdAt: at(2026, 10, 3),
);

ArticleVocabEntry entry(String articleId, String lemma) => ArticleVocabEntry(
      articleId: articleId,
      lemma: lemma,
      origin: VocabOrigin.manual,
      addedAt: at(2026, 10, 1),
    );

final List<ArticleVocabEntry> entries = [
  entry('a-key', 'alpha'),
  entry('a-key', 'take off'),
  entry('a-key', 'gamma'),
  entry('a-key', 'alpha'), // 重复 lemma
  entry('b-key', 'beta'),
  entry('b-key', 'done'),
  entry('c-key', 'gamma'),
];

final List<VocabItem> items = [alpha, beta, done, take, gamma];

const List<BrowseArticleRef> articles = [
  BrowseArticleRef(id: 'saved:A', title: 'A 篇', aliases: ['a-key', 'A']),
  BrowseArticleRef(id: 'saved:B', title: 'B 篇', aliases: ['b-key']),
  BrowseArticleRef(id: 'saved:C', title: 'C 篇', aliases: ['c-key']),
];

VocabBrowseInput base({
  List<VocabItem>? itemList,
  List<ArticleVocabEntry>? articleEntries,
  BrowseScope scope = BrowseScope.all,
  String articleId = 'a-key',
  Set<String>? picked,
  BrowseKind kind = BrowseKind.all,
  String query = '',
  Set<String>? days,
  BrowseStatus status = BrowseStatus.all,
  bool includeMastered = false,
  DateTime? now,
}) =>
    VocabBrowseInput(
      items: itemList ?? items,
      scope: scope,
      articleId: articleId,
      articleEntries: articleEntries ?? entries,
      articles: articles,
      pickedArticleIds: picked ?? const {},
      kind: kind,
      query: query,
      days: days ?? const {},
      status: status,
      includeMastered: includeMastered,
      now: now,
    );

void main() {
  group('browseVocab：范围', () {
    test('全部：默认不含已掌握；勾选后包含', () {
      expect(
        browseVocab(base()).items.map((it) => it.lemma),
        ['alpha', 'beta', 'take off', 'gamma'],
      );
      expect(
        browseVocab(base(includeMastered: true)).items.map((it) => it.lemma),
        contains('done'),
      );
    });

    test('本篇：只认按篇收录，别名合并、同 lemma 去重、语言点也在', () {
      final out = browseVocab(base(scope: BrowseScope.article));
      expect(out.items.map((it) => it.lemma), ['alpha', 'take off', 'gamma']);
      expect(out.scopeCount, 3);
    });

    test('本篇：含已掌握时把 mastered 也带出来', () {
      final out = browseVocab(base(
        scope: BrowseScope.article,
        articleId: 'b-key',
        includeMastered: true,
      ));
      expect(out.items.map((it) => it.lemma), ['beta', 'done']);
    });

    test('选篇：只并选中的篇，按 lemma 去重；给出每篇条数', () {
      final out = browseVocab(base(
        scope: BrowseScope.picked,
        picked: {'saved:A', 'saved:C'},
        includeMastered: true,
      ));
      expect(out.items.map((it) => it.lemma), ['alpha', 'take off', 'gamma']);
      expect(out.articleCounts['saved:A'], 3);
      expect(out.articleCounts['saved:C'], 1);
      expect(out.articleCounts['saved:B'], 2);
    });

    test('没开文章 / 没选篇：空结果，不报错', () {
      expect(
        browseVocab(base(scope: BrowseScope.article, articleId: '')).items,
        isEmpty,
      );
      expect(browseVocab(base(scope: BrowseScope.picked)).items, isEmpty);
    });
  });

  group('browseVocab：类型 / 搜索 / 日期', () {
    test('类型：生词只要普通单词，语言点只要词组/习语/用法', () {
      expect(
        browseVocab(base(kind: BrowseKind.word)).items.map((it) => it.lemma),
        isNot(contains('take off')),
      );
      expect(
        browseVocab(base(kind: BrowseKind.lang)).items.map((it) => it.lemma),
        ['take off'],
      );
    });

    test('搜索：词形 / 释义 / 笔记，大小写不敏感', () {
      expect(
        browseVocab(base(query: 'ALP')).items.map((it) => it.lemma),
        ['alpha'],
      );
      expect(browseVocab(base(query: '贝塔')).items.map((it) => it.lemma), ['beta']);
      expect(browseVocab(base(query: '希腊')).items.map((it) => it.lemma), ['beta']);
    });

    test('日期：按入库日（04:00 结算）分天，倒序 + 条数', () {
      final early = vocabItem(
        id: 'v-early',
        word: 'early',
        lemma: 'early',
        createdAt: at(2026, 10, 2, 3),
      );
      final all = [...items, early];
      final out = browseVocab(base(itemList: all));

      final d1 = dayKeyLocal(DateTime.parse(at(2026, 10, 1)).toLocal());
      final d2 = dayKeyLocal(DateTime.parse(at(2026, 10, 2)).toLocal());
      final d3 = dayKeyLocal(DateTime.parse(at(2026, 10, 3)).toLocal());

      expect(out.days.first, (day: d3, count: 2), reason: 'take off + gamma');
      expect(out.days, contains((day: d2, count: 1)), reason: 'beta（done 已掌握被排除）');
      expect(out.days, contains((day: d1, count: 2)), reason: 'alpha + early（凌晨 3 点算前一天）');

      expect(
        browseVocab(base(itemList: all, days: {d1})).items.map((it) => it.lemma),
        ['alpha', 'early'],
      );
      expect(
        browseVocab(base(itemList: all, days: {d2})).items.map((it) => it.lemma),
        ['beta'],
      );
      expect(
        browseVocab(base(itemList: all, days: {d1, d2})).items.map((it) => it.lemma),
        ['alpha', 'beta', 'early'],
      );
      expect(out.items, hasLength(5));
    });

    test('scopeCount 是范围 + 含已掌握后的总数，不受类型/搜索/日期影响', () {
      final out = browseVocab(base(
        query: 'zzz',
        kind: BrowseKind.word,
        days: {'2020-01-01'},
      ));
      expect(out.items, isEmpty);
      expect(out.scopeCount, 4);
    });
  });

  group('browseVocab：复习状态', () {
    final now = DateTime.parse(at(2026, 10, 5));
    final dueItem = vocabItem(
      id: 'v-due',
      word: 'dueword',
      lemma: 'dueword',
      createdAt: at(2026, 10, 1),
      reviewState: ReviewState(due: at(2026, 10, 4)),
    );
    final lapsedItem = vocabItem(
      id: 'v-lapse',
      word: 'lapsed',
      lemma: 'lapsed',
      createdAt: at(2026, 10, 1),
      reviewState: const ReviewState(lapses: 2),
    );
    final all = [...items, dueItem, lapsedItem];

    test('待复习：只留 due 已到（受 now 控制）', () {
      expect(
        browseVocab(base(
          itemList: all,
          status: BrowseStatus.due,
          includeMastered: true,
          now: now,
        )).items.map((it) => it.lemma),
        ['dueword'],
      );
      expect(
        browseVocab(base(
          itemList: all,
          status: BrowseStatus.due,
          includeMastered: true,
          now: DateTime.parse(at(2026, 10, 3)),
        )).items,
        isEmpty,
      );
    });

    test('新词：用 isFresh（没排期、没重学），不是只看 repetitions', () {
      expect(
        browseVocab(base(
          itemList: all,
          status: BrowseStatus.fresh,
          includeMastered: true,
          now: now,
        )).items.map((it) => it.lemma),
        ['alpha', 'beta', 'take off', 'gamma', 'lapsed'],
      );
    });

    test('错过：lapses > 0；已掌握：只看 mastered（不受 includeMastered 影响）', () {
      expect(
        browseVocab(base(
          itemList: all,
          status: BrowseStatus.lapsed,
          includeMastered: true,
          now: now,
        )).items.map((it) => it.lemma),
        ['lapsed'],
      );
      expect(
        browseVocab(base(itemList: all, status: BrowseStatus.mastered, now: now))
            .items
            .map((it) => it.lemma),
        ['done'],
      );
    });

    test('状态筛选和选篇计数同口径', () {
      final out = browseVocab(base(
        itemList: all,
        articleEntries: [...entries, entry('a-key', 'lapsed')],
        scope: BrowseScope.picked,
        picked: {'saved:A'},
        status: BrowseStatus.lapsed,
        includeMastered: true,
        now: now,
      ));
      expect(out.articleCounts['saved:A'], 1);
    });
  });

  group('browseA4Rows：选篇打印', () {
    const picked = {'saved:A', 'saved:B'};

    test('按篇出行（同一词可跨篇重复），编号按篇内顺序，释义用该篇语境', () {
      final rows = browseA4Rows(base(scope: BrowseScope.picked, picked: picked));
      expect(
        rows.map((r) => [r.articleTitle, r.item.lemma, r.number]),
        [
          ['A 篇', 'alpha', 1],
          ['A 篇', 'take off', null],
          ['A 篇', 'gamma', 2],
          ['B 篇', 'beta', 1],
        ],
      );
      expect(rows.first.articleId, 'a-key');
    });

    test('跟浏览页的类型 / 搜索筛选一致', () {
      final lang = browseA4Rows(base(
        scope: BrowseScope.picked,
        picked: picked,
        kind: BrowseKind.lang,
      ));
      expect(lang.map((r) => r.item.lemma), ['take off']);

      final found = browseA4Rows(base(
        scope: BrowseScope.picked,
        picked: picked,
        query: '贝塔',
      ));
      expect(found.map((r) => r.item.lemma), ['beta']);
    });

    test('同一词在两篇各一行，各算各的编号', () {
      final rows = browseA4Rows(base(
        scope: BrowseScope.picked,
        picked: {'saved:A', 'saved:C'},
      ));
      expect(
        rows
            .where((r) => r.item.lemma == 'gamma')
            .map((r) => [r.articleTitle, r.number]),
        [
          ['A 篇', 2],
          ['C 篇', 1],
        ],
      );
    });

    test('本篇 / 全部范围不出行；没选篇也不出', () {
      expect(browseA4Rows(base()), isEmpty);
      expect(browseA4Rows(base(scope: BrowseScope.article)), isEmpty);
      expect(browseA4Rows(base(scope: BrowseScope.picked)), isEmpty);
    });
  });
}
