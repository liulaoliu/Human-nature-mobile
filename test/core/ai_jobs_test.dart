import 'package:dlaoshi_app/core/ai_jobs.dart';
import 'package:dlaoshi_app/models/vocab.dart';
import 'package:flutter_test/flutter_test.dart';

VocabItem mkWord(
  String word, {
  String? meaning,
  String? phonetic,
  VocabStatus status = VocabStatus.unqueried,
  VocabItemKind? kind,
  Map<VocabField, VocabFieldSource>? fieldSources,
  List<VocabContext>? contexts,
}) =>
    VocabItem(
      id: 'item-$word',
      word: word,
      lemma: word.toLowerCase(),
      kind: kind,
      meaning: meaning,
      phonetic: phonetic,
      status: status,
      fieldSources: fieldSources,
      contexts: contexts,
      createdAt: '2026-11-10T00:00:00.000Z',
      updatedAt: '2026-11-10T00:00:00.000Z',
    );

VocabLibrary libOf(List<VocabItem> items) =>
    VocabLibrary(items: items);

/// 一篇收了这些词的词库（跑批只按篇跑，没收录记录就算不出任务）。
VocabLibrary libOfArticle(String articleId, List<VocabItem> items) =>
    VocabLibrary(
      items: items,
      articleEntries: <ArticleVocabEntry>[
        for (final it in items) entryOf(articleId, it),
      ],
    );

/// 造一条「某篇收了某词」的收录记录。
ArticleVocabEntry entryOf(String articleId, VocabItem item) => ArticleVocabEntry(
      articleId: articleId,
      lemma: item.lemma,
      origin: VocabOrigin.manual,
      addedAt: '2026-11-10T00:00:00.000Z',
    );

void main() {
  group('aiFingerprint（与 Web 逐位一致）', () {
    test('空串 / a / hello 四个真值', () {
      expect(aiFingerprint(''), 'ztntfp');
      expect(aiFingerprint('a'), '1r9wi7g');
      expect(aiFingerprint('hello'), 'm3bicr');
      expect(aiFingerprint('{"version":1}'), 'yrhscy');
    });

    test('稳定：同内容同 id，不同内容不同 id', () {
      expect(aiFingerprint('run\nkeep'), aiFingerprint('run\nkeep'));
      expect(aiFingerprint('run\nkeep'), isNot(aiFingerprint('run\nkeep up')));
    });
  });

  group('aiChunk', () {
    test('空表 / size<=0 / 正常切块', () {
      expect(aiChunk<int>(<int>[], 3), isEmpty);
      expect(aiChunk<int>(<int>[1, 2, 3], 0), <List<int>>[
        <int>[1, 2, 3]
      ]);
      expect(aiChunk<int>(<int>[1, 2, 3, 4, 5], 2), <List<int>>[
        <int>[1, 2],
        <int>[3, 4],
        <int>[5],
      ]);
    });
  });

  group('aiTodoBase / aiNeedInfo 筛选', () {
    test('词组 / 习语 / 用法笔记不进词级任务', () {
      final base = aiTodoBase(libOf(<VocabItem>[
        mkWord('run'),
        mkWord('run out', kind: VocabItemKind.phrase),
        mkWord('raining cats', kind: VocabItemKind.idiom),
        mkWord('中文说明', kind: VocabItemKind.usage),
        mkWord('Look', kind: VocabItemKind.usage), // 单个英文词被错标，仍算单词
      ]));
      expect(base.map((it) => it.word).toList(), <String>['run', 'Look']);
    });

    test('没释义一律排；手填释义不动；已有释义只差音标只认 unqueried', () {
      final base = <VocabItem>[
        mkWord('noMeaning'),
        mkWord('noMeaningQueried', status: VocabStatus.queried),
        mkWord('manual', meaning: '手填', fieldSources: const <VocabField, VocabFieldSource>{
          VocabField.meaning: VocabFieldSource.manual,
        }),
        mkWord('hasBoth', meaning: '有', phonetic: '/hæz/'),
        mkWord('noPhonetic', meaning: '有释义没音标'),
        mkWord('noPhoneticQueried', meaning: '有释义没音标', status: VocabStatus.queried),
      ];
      expect(aiNeedInfo(base).map((it) => it.word).toList(), <String>[
        'noMeaning',
        'noMeaningQueried',
        'noPhonetic',
      ]);
    });
  });

  group('buildAiLookupJobs', () {
    test('空词库 / 全都补齐 → 没有任务', () {
      expect(buildAiLookupJobs(libOf(<VocabItem>[])), isEmpty);
      expect(
        buildAiLookupJobs(libOf(<VocabItem>[
          mkWord('done', meaning: '完成', phonetic: '/dʌn/', status: VocabStatus.queried),
        ])),
        isEmpty,
      );
    });

    test('3 个词一块：id 稳定、提示词含全部词、words 带回来', () {
      final library = libOfArticle('A1', <VocabItem>[
        mkWord('run'),
        mkWord('keep up'),
        mkWord('sharp'),
      ]);
      final jobs = buildAiLookupJobs(library, chunkSize: 30, articleId: 'A1');
      expect(jobs, hasLength(1));
      final job = jobs.single;
      expect(job.id, startsWith('lookup-'));
      expect(job.words, <String>['run', 'keep up', 'sharp']);
      expect(job.prompt, contains('run'));
      expect(job.prompt, contains('keep up'));
      expect(job.prompt, contains('|'));
      expect(job.label, contains('查词 1/1'));
      // 同一批词重建后 id 不变
      expect(
        buildAiLookupJobs(library, chunkSize: 30, articleId: 'A1').single.id,
        job.id,
      );
    });

    test('超过 chunkSize 会切多块，且各块 id 不同', () {
      final library = libOfArticle(
        'A1',
        List<VocabItem>.generate(5, (i) => mkWord('w$i')),
      );
      final jobs = buildAiLookupJobs(library, chunkSize: 2, articleId: 'A1');
      expect(jobs, hasLength(3));
      expect(jobs[0].words, <String>['w0', 'w1']);
      expect(jobs[1].words, <String>['w2', 'w3']);
      expect(jobs[2].words, <String>['w4']);
      expect(<String>{for (final j in jobs) j.id}, hasLength(3));
    });

    test('上下文句进提示词，空上下文不写「上下文：」', () {
      final library = libOfArticle('A1', <VocabItem>[
        mkWord('run', contexts: <VocabContext>[
          VocabContext(
            articleId: 'A',
            sentenceText: 'We run every morning.',
            at: '2026-11-10T00:00:00.000Z',
          ),
        ]),
        mkWord('sharp'),
      ]);
      final prompt =
          buildAiLookupJobs(library, articleId: 'A1').single.prompt;
      expect(prompt, contains('We run every morning.'));
      expect(prompt, contains('sharp'));
      // 标题里有一个「单词与上下文：」，词行里只该出现一个「（上下文：…）」
      expect('（上下文：'.allMatches(prompt).length, 1);
    });
  });

  group('只按篇跑（articleId）', () {
    test('只算这一篇收过的词，篇外的不进任务', () {
      final a = mkWord('alpha');
      final b = mkWord('beta');
      final c = mkWord('gamma');
      final library = VocabLibrary(
        items: <VocabItem>[a, b, c],
        articleEntries: <ArticleVocabEntry>[entryOf('A1', a), entryOf('A2', c)],
      );
      final jobs = buildAiLookupJobs(library, articleId: 'A1');
      expect(jobs.single.words, <String>['alpha']);
      final other = buildAiLookupJobs(library, articleId: 'A2');
      expect(other.single.words, <String>['gamma']);
    });

    test('篇不存在 / 没给篇 / 空白 → 不出任务（没有全库这条退路）', () {
      final a = mkWord('alpha');
      final library = VocabLibrary(
        items: <VocabItem>[a],
        articleEntries: <ArticleVocabEntry>[entryOf('A1', a)],
      );
      expect(buildAiLookupJobs(library, articleId: 'nope'), isEmpty);
      expect(buildAiLookupJobs(library), isEmpty);
      expect(buildAiLookupJobs(library, articleId: '  '), isEmpty);
    });

    test('本篇里已补齐的词不再进任务（跑过的不重跑）', () {
      final done = mkWord('done',
          meaning: '完成', phonetic: '/dʌn/', status: VocabStatus.queried);
      final todo = mkWord('todo');
      final manual = mkWord('manual', meaning: '手填', fieldSources: const {
        VocabField.meaning: VocabFieldSource.manual,
      });
      final library = VocabLibrary(
        items: <VocabItem>[done, todo, manual],
        articleEntries: <ArticleVocabEntry>[
          entryOf('A1', done),
          entryOf('A1', todo),
          entryOf('A1', manual),
        ],
      );
      final jobs = buildAiLookupJobs(library, articleId: 'A1');
      expect(jobs.single.words, <String>['todo']);
    });

    test('语言点 / 词组不算词级待办', () {
      final word = mkWord('alpha');
      final phrase = mkWord('keep up', kind: VocabItemKind.phrase);
      final library = VocabLibrary(
        items: <VocabItem>[word, phrase],
        articleEntries: <ArticleVocabEntry>[
          entryOf('A1', word),
          entryOf('A1', phrase),
        ],
      );
      final jobs = buildAiLookupJobs(library, articleId: 'A1');
      expect(jobs.single.words, <String>['alpha']);
    });

    test('aiArticleBase：空篇 / 不存在的篇都回空', () {
      final a = mkWord('alpha');
      final library = VocabLibrary(
        items: <VocabItem>[a],
        articleEntries: <ArticleVocabEntry>[entryOf('A1', a)],
      );
      expect(
        aiArticleBase(library, 'A1').map((it) => it.word),
        <String>['alpha'],
      );
      expect(aiArticleBase(library, ''), isEmpty);
      expect(aiArticleBase(library, 'nope'), isEmpty);
    });
  });
}
