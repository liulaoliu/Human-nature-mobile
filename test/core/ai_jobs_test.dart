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
      final library = libOf(<VocabItem>[
        mkWord('run'),
        mkWord('keep up'),
        mkWord('sharp'),
      ]);
      final jobs = buildAiLookupJobs(library, chunkSize: 30);
      expect(jobs, hasLength(1));
      final job = jobs.single;
      expect(job.id, startsWith('lookup-'));
      expect(job.words, <String>['run', 'keep up', 'sharp']);
      expect(job.prompt, contains('run'));
      expect(job.prompt, contains('keep up'));
      expect(job.prompt, contains('|'));
      expect(job.label, contains('查词 1/1'));
      // 同一批词重建后 id 不变
      expect(buildAiLookupJobs(library, chunkSize: 30).single.id, job.id);
    });

    test('超过 chunkSize 会切多块，且各块 id 不同', () {
      final library = libOf(
        List<VocabItem>.generate(5, (i) => mkWord('w$i')),
      );
      final jobs = buildAiLookupJobs(library, chunkSize: 2);
      expect(jobs, hasLength(3));
      expect(jobs[0].words, <String>['w0', 'w1']);
      expect(jobs[1].words, <String>['w2', 'w3']);
      expect(jobs[2].words, <String>['w4']);
      expect(<String>{for (final j in jobs) j.id}, hasLength(3));
    });

    test('上下文句进提示词，空上下文不写「上下文：」', () {
      final library = libOf(<VocabItem>[
        mkWord('run', contexts: <VocabContext>[
          VocabContext(
            articleId: 'A',
            sentenceText: 'We run every morning.',
            at: '2026-11-10T00:00:00.000Z',
          ),
        ]),
        mkWord('sharp'),
      ]);
      final prompt = buildAiLookupJobs(library).single.prompt;
      expect(prompt, contains('We run every morning.'));
      expect(prompt, contains('sharp'));
      // 标题里有一个「单词与上下文：」，词行里只该出现一个「（上下文：…）」
      expect('（上下文：'.allMatches(prompt).length, 1);
    });
  });
}
