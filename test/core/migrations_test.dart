import 'package:dlaoshi_app/core/library_validate.dart';
import 'package:dlaoshi_app/core/migrations.dart';
import 'package:dlaoshi_app/core/vocab/library.dart';
import 'package:dlaoshi_app/models/vocab.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/vocab_fixture.dart';

/// 迁移收口 + 不变量校验。
/// 这两件事是「数据结构设计」落地的地方：**老数据能进来、坏数据能被发现**。
///
/// 用例逐条对照 Web 版 `src/core/migrations.test.ts`（263 行）。
final testNow = DateTime.parse('2026-10-02T00:00:00.000Z');

String isoOf(DateTime t) => t.toUtc().toIso8601String();

Map<String, Object?> item(Map<String, Object?> raw) => raw;

void main() {
  group('migrateLibrary：宽容解析', () {
    test('空 / 非对象 → 空库，不炸', () {
      expect(migrateLibrary(null).items, isEmpty);
      expect(migrateLibrary('nope').items, isEmpty);
      expect(migrateLibrary(<String, Object?>{}).schemaVersion, vocabSchemaVersion);
    });

    test('缺字段的老条目：补 id/lemma/时间/复习状态，保留能用的内容', () {
      final out = migrateLibrary({
        'items': [
          {
            'word': 'Run',
            'meaning': '跑\n走',
            'examples': [
              {'text': 'I run.'},
            ],
            'status': 'weird',
          },
          {'word': '', 'lemma': 'x'}, // 无 word → 丢弃
          {'noWord': true}, // 丢弃
        ],
      }, testNow);
      expect(out.items, hasLength(1));
      final it = out.items[0];
      expect(it.id, 'vocab:run');
      expect(it.lemma, 'run');
      expect(it.meaning, '跑 走'); // 清洗掉转义换行
      expect(it.status, VocabStatus.queried); // 有释义 → queried
      expect(it.examples[0].text, 'I run.');
      expect(it.reviewState.ease, 2.5);
      expect(it.reviewState.due, isNull);
      expect(it.reviewState.interval, 0);
      expect(it.reviewState.repetitions, 0);
      expect(it.createdAt, isoOf(testNow));
    });

    test('幂等：迁移两遍结果一样、引用尽量复用', () {
      final once = migrateLibrary({
        'items': [
          {'word': 'run'},
          {'word': 'wall'},
        ],
      }, testNow);
      final twice = migrateLibrary(once, testNow);
      expect(twice.items.map((i) => i.word), ['run', 'wall']);
      expect(libraryErrors(twice), isEmpty);
      // 已是当前结构：条目原样复用（不让加载路径白写库）
      expect(identical(twice.items[0], once.items[0]), isTrue);
    });

    test('relearn 保留正数，坏值不保留', () {
      final out = migrateLibrary({
        'items': [
          {
            'word': 'run',
            'reviewState': {
              'ease': 2.5,
              'due': null,
              'interval': 1,
              'repetitions': 0,
              'relearn': 2,
            },
          },
          {
            'word': 'wall',
            'reviewState': {
              'ease': 2.5,
              'due': null,
              'interval': 1,
              'repetitions': 0,
              'relearn': 'x',
            },
          },
        ],
      }, testNow);
      expect(out.items.firstWhere((i) => i.word == 'run').reviewState.relearn, 2);
      expect(out.items.firstWhere((i) => i.word == 'wall').reviewState.relearn, 0);
    });

    test('核心字段来源逐项清洗，坏值不保留', () {
      final out = migrateLibrary({
        'items': [
          {
            'word': 'run',
            'lemma': 'run',
            'meaning': '跑',
            'fieldSources': {'meaning': 'manual', 'phonetic': 'bad', 'extra': 'ai'},
          },
          {'word': 'wall', 'lemma': 'wall', 'meaning': '墙'},
        ],
      }, testNow);
      expect(
        out.items.firstWhere((i) => i.lemma == 'run').fieldSources,
        {VocabField.meaning: VocabFieldSource.manual},
      );
      expect(out.items.firstWhere((i) => i.lemma == 'wall').fieldSources, isNull);
    });

    test('易混项来源只认 ai / dict；旧数据与坏值不猜', () {
      final out = migrateLibrary({
        'items': [
          {
            'word': 'adapt',
            'lemma': 'adapt',
            'confusables': [
              {'word': 'adopt'},
            ],
            'confusablesSource': 'ai',
          },
          {
            'word': 'adept',
            'lemma': 'adept',
            'confusables': [
              {'word': 'adopt'},
            ],
            'confusablesSource': 'dict',
          },
          {
            'word': 'adopt',
            'lemma': 'adopt',
            'confusables': [
              {'word': 'adept'},
            ],
            'confusablesSource': 'manual',
          },
          {
            'word': 'legacy',
            'lemma': 'legacy',
            'confusables': [
              {'word': 'adopt'},
            ],
          },
        ],
      }, testNow);
      expect(
        out.items.firstWhere((i) => i.lemma == 'adapt').confusablesSource,
        VocabConfusableSource.ai,
      );
      expect(
        out.items.firstWhere((i) => i.lemma == 'adept').confusablesSource,
        VocabConfusableSource.dict,
      );
      expect(out.items.firstWhere((i) => i.lemma == 'adopt').confusablesSource, isNull);
      expect(out.items.firstWhere((i) => i.lemma == 'legacy').confusablesSource, isNull);
    });

    test('早先版本误标的类型 / 与词性不符的语法标记，一并修掉', () {
      final out = migrateLibrary({
        'items': [
          {'word': 'purge', 'lemma': 'purge', 'kind': 'usage'}, // 旧 bug：单词被标成用法 → 改回单词
          {
            'word': 'run',
            'lemma': 'run',
            'partOfSpeech': 'adj.',
            'grammarMarks': ['不可数'], // 形容词不该有「不可数」
          },
        ],
      }, testNow);
      final purge = out.items.firstWhere((i) => i.lemma == 'purge');
      final run = out.items.firstWhere((i) => i.lemma == 'run');
      expect(purge.kind, isNull);
      expect(run.grammarMarks, isEmpty);
    });

    test('按 lemma 去重（老数据里同一词两条 → 合成一条）', () {
      final out = migrateLibrary({
        'items': [
          {'word': 'run', 'lemma': 'run', 'meaning': '跑'},
          {'word': 'running', 'lemma': 'run', 'phonetic': '/rʌn/'},
        ],
      }, testNow);
      expect(out.items, hasLength(1));
      expect(out.items[0].meaning, '跑');
      expect(out.items[0].phonetic, '/rʌn/');
    });
  });

  group('migrateLibrary：按篇收录表', () {
    test('老数据没有 articleEntries：只从 source / contexts 推导，不按正文出现猜', () {
      final out = migrateLibrary({
        'items': [
          {
            'word': 'run',
            'lemma': 'run',
            'createdAt': '2026-08-01T00:00:00.000Z',
            'updatedAt': '2026-08-01T00:00:00.000Z',
            'source': {'articleId': 'A', 'fileName': 'A', 'sentenceId': 's1', 'sentenceText': 'I run.'},
            'contexts': [
              {
                'articleId': 'B',
                'fileName': 'B',
                'sentenceId': 's2',
                'sentenceText': 'Run!',
                'meaning': '跑',
                'at': '2026-09-01T00:00:00.000Z',
              },
            ],
          },
          {
            'word': 'done',
            'lemma': 'done',
            'status': 'mastered',
            'source': {'articleId': 'C', 'fileName': 'C', 'sentenceId': 's3', 'sentenceText': 'x'},
          },
        ],
      }, testNow);
      expect(
        out.articleEntries.map((e) => '${e.articleId}:${e.lemma}:${e.origin.name}'),
        ['A:run:manual', 'B:run:manual'],
      );
      expect(out.articleEntries.firstWhere((e) => e.articleId == 'B').meaning, '跑');
      // 已掌握词不补成本篇生词
      expect(out.articleEntries.any((e) => e.lemma == 'done'), isFalse);
    });

    test('旧 usage 笔记的坏键先修好再按 lemma 去重：不会吞掉同名单词', () {
      final out = migrateLibrary({
        'items': [
          {'word': 'mantra', 'lemma': 'mantra', 'status': 'unqueried'},
          {
            'id': 'vocab:mantra',
            'word': 'mantra 本义为“曼怛罗、祷文”，引申为反复强调的口头禅。',
            'lemma': 'mantra',
            'kind': 'usage',
            'status': 'queried',
          },
        ],
        'articleEntries': [
          {'articleId': 'A', 'lemma': 'mantra', 'origin': 'manual', 'addedAt': isoOf(testNow)},
        ],
      }, testNow);
      expect(out.items.where((it) => it.lemma == 'mantra'), hasLength(1));
      expect(out.items.firstWhere((it) => it.lemma == 'mantra').kind, isNull);
      // 同名单词存在时，按篇条目继续指向单词，不被改名到用法笔记上
      expect(out.articleEntries[0].lemma, 'mantra');
      final note = out.items.firstWhere((it) => it.kind == VocabItemKind.usage);
      expect(note.id, isNot('vocab:mantra'));
      expect(note.lemma, contains('本义为'));
      expect(libraryErrors(out), isEmpty);
    });

    test('老数据的语言点也推导按篇条目（侧栏语言点页签靠它）', () {
      final out = migrateLibrary({
        'items': [
          {
            'word': 'fall back on',
            'lemma': 'fall back on',
            'kind': 'phrase',
            'createdAt': '2026-08-01T00:00:00.000Z',
            'updatedAt': '2026-08-01T00:00:00.000Z',
            'source': {
              'articleId': 'A',
              'fileName': 'A',
              'sentenceId': 's1',
              'sentenceText': 'We fall back on it.',
            },
          },
        ],
      }, testNow);
      expect(out.articleEntries.map((e) => '${e.articleId}:${e.lemma}'), ['A:fall back on']);
      expect(libraryErrors(out), isEmpty);
    });

    test('已有 articleEntries：保留合法顺序，丢掉孤儿 / 重复 / 非法条目', () {
      final out = migrateLibrary({
        'items': [
          {'word': 'run', 'lemma': 'run'},
        ],
        'articleEntries': [
          {'articleId': 'A', 'lemma': 'run', 'origin': 'auto', 'addedAt': '2026-10-01T00:00:00.000Z'},
          {'articleId': 'A', 'lemma': 'run', 'origin': 'manual', 'addedAt': '2026-10-01T00:00:01.000Z'},
          {
            'articleId': 'A',
            'lemma': 'missing',
            'origin': 'manual',
            'addedAt': '2026-10-01T00:00:02.000Z',
          },
          {'articleId': '', 'lemma': 'run', 'origin': 'manual', 'addedAt': '2026-10-01T00:00:03.000Z'},
        ],
      }, testNow);
      expect(out.articleEntries, hasLength(1));
      final e = out.articleEntries[0];
      expect(e.articleId, 'A');
      expect(e.lemma, 'run');
      expect(e.origin, VocabOrigin.auto);
      expect(e.addedAt, '2026-10-01T00:00:00.000Z');
      expect(libraryErrors(out), isEmpty);
    });

    test('保留合法 via；非法来源当没记', () {
      final out = migrateLibrary({
        'items': [
          {'word': 'run', 'lemma': 'run'},
          {'word': 'walk', 'lemma': 'walk'},
        ],
        'articleEntries': [
          {'articleId': 'A', 'lemma': 'run', 'origin': 'auto', 'via': 'dict', 'addedAt': '2026-10-01T00:00:00.000Z'},
          {'articleId': 'A', 'lemma': 'walk', 'origin': 'manual', 'via': '乱写', 'addedAt': '2026-10-01T00:00:01.000Z'},
        ],
      }, testNow);
      expect(out.articleEntries[0].via, VocabVia.dict);
      expect(out.articleEntries[1].via, isNull);
      expect(libraryErrors(out), isEmpty);
    });

    test('幂等：已是当前结构时 articleEntries 引用复用', () {
      final entries = [
        articleEntry(articleId: 'A', lemma: 'run', origin: VocabOrigin.auto, addedAt: '2026-10-01T00:00:00.000Z'),
      ];
      final first = migrateLibrary({
        'items': [
          {'word': 'run', 'lemma': 'run'},
        ],
        'articleEntries': entries,
      }, testNow);
      final second = migrateLibrary(first, testNow);
      expect(identical(second.articleEntries, first.articleEntries), isTrue);
    });
  });

  group('migrateToCurrent', () {
    test('已是当前版本 → 原样返回', () {
      final lib = createLibrary();
      expect(identical(migrateToCurrent(lib), lib), isTrue);
    });

    test('老版本号 → 抬到当前版本', () {
      expect(migrateToCurrent(const VocabLibrary(schemaVersion: 0)).schemaVersion, vocabSchemaVersion);
    });
  });

  group('libraryValidate：不变量校验', () {
    test('干净库没有任何问题', () {
      final lib = createLibrary().copyWith(items: [vocabItem(id: 'vocab:alpha')]);
      expect(validateLibrary(lib), isEmpty);
    });

    test('非对象 / 缺 id / word 空 / lemma 重复 都报 error', () {
      expect(libraryErrors(null), hasLength(1));
      final bad = VocabLibrary(items: [
        vocabItem(id: ''),
        vocabItem(id: 'v2', lemma: 'alpha'),
      ]);
      final errors = libraryErrors(bad);
      expect(errors.any((e) => e.message.contains('缺少 id')), isTrue);
      expect(errors.any((e) => e.message.contains('lemma 重复')), isTrue);
    });

    test('articleEntries 指向不存在的词 / 重复 / 缺 addedAt 都报 error', () {
      final lib = VocabLibrary(
        items: [vocabItem()],
        articleEntries: [
          articleEntry(lemma: 'alpha'),
          articleEntry(lemma: 'alpha'),
          articleEntry(lemma: 'ghost'),
        ],
      );
      final errors = libraryErrors(lib).map((e) => e.message).toList();
      expect(errors.any((m) => m.contains('重复')), isTrue);
      expect(errors.any((m) => m.contains('不存在的词')), isTrue);
    });

    test('id 与 lemma 不一致只是 warn，不算致命', () {
      final lib = VocabLibrary(items: [vocabItem(id: 'vocab:other', lemma: 'alpha')]);
      expect(libraryErrors(lib), isEmpty);
      expect(validateLibrary(lib).any((i) => i.message.contains('不一致')), isTrue);
    });
  });
}
