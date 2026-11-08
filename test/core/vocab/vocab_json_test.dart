// 词库序列化口径（`lib/core/vocab/vocab_json.dart`）的测试。
//
// 这一层最容易出「写出去和对回来不是同一份」的问题，所以除了逐键断言，
// 还专门验证**往返一致性**：`encode → jsonDecode → migrateLibrary` 得到的库，
// 关键字段必须和原件逐条相等；否则仓储的「内容没变就跳过写库」永远判不中。

import 'dart:convert';

import 'package:dlaoshi_app/core/migrations.dart';
import 'package:dlaoshi_app/core/vocab/vocab_json.dart';
import 'package:dlaoshi_app/models/vocab.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/vocab_fixture.dart';

void main() {
  group('vocabItemToJson', () {
    test('必写字段齐全，可选字段为空时不出现', () {
      final json = vocabItemToJson(vocabItem());

      for (final key in <String>[
        'id',
        'word',
        'lemma',
        'phonetic',
        'partOfSpeech',
        'meaning',
        'definition',
        'usage',
        'examples',
        'source',
        'status',
        'note',
        'tags',
        'reviewState',
        'createdAt',
        'updatedAt',
      ]) {
        expect(json.containsKey(key), isTrue, reason: '缺少必写字段 $key');
      }

      // 可选字段：没有值就不写（对应 Web 版 undefined 被 stringify 丢掉）。
      for (final key in <String>[
        'kind',
        'langPointId',
        'lastPrintedAt',
        'fieldSources',
        'grammarMarks',
        'phrases',
        'idioms',
        'contexts',
        'confusables',
        'confusablesSource',
        'priorityUntil',
      ]) {
        expect(json.containsKey(key), isFalse, reason: '不该写出空字段 $key');
      }

      expect(json['id'], 'v1');
      expect(json['word'], 'alpha');
      expect(json['status'], 'unqueried');
      expect(json['usage'], isEmpty);
      expect(json['examples'], isEmpty);
      expect(json['source'], isNull);
    });

    test('可选字段有值才写，值原样带出', () {
      final json = vocabItemToJson(vocabItem(
        kind: VocabItemKind.phrase,
        lastPrintedAt: '2026-02-02T00:00:00.000Z',
        grammarMarks: const ['及物'],
        phrases: const ['run out'],
        idioms: const ['run in the family'],
        confusables: const [VocabConfusable(word: 'runny', meaning: '流鼻涕的')],
        confusablesSource: VocabConfusableSource.dict,
      ));

      expect(json['kind'], 'phrase');
      expect(json['lastPrintedAt'], '2026-02-02T00:00:00.000Z');
      expect(json['grammarMarks'], ['及物']);
      expect(json['phrases'], ['run out']);
      expect(json['idioms'], ['run in the family']);
      expect(json['confusables'], [
        {'word': 'runny', 'meaning': '流鼻涕的'},
      ]);
      expect(json['confusablesSource'], 'dict');
    });

    test('fieldSources 用字段名/来源名，不写枚举', () {
      final json = vocabItemToJson(vocabItem(
        fieldSources: const {
          VocabField.phonetic: VocabFieldSource.dict,
          VocabField.meaning: VocabFieldSource.manual,
        },
      ));

      expect(json['fieldSources'], {
        'phonetic': 'dict',
        'meaning': 'manual',
      });
    });

    test('空 fieldSources 当作没有', () {
      final json = vocabItemToJson(
        vocabItem(fieldSources: const <VocabField, VocabFieldSource>{}),
      );
      expect(json.containsKey('fieldSources'), isFalse);
    });

    test('reviewState 七个字段全写', () {
      final json = vocabItemToJson(vocabItem(
        reviewState: const ReviewState(
          ease: 2.7,
          due: '2026-03-03T00:00:00.000Z',
          interval: 5,
          repetitions: 2,
          lapses: 1,
          relearn: 3,
          meaningPasses: 4,
        ),
      ));

      expect(json['reviewState'], {
        'ease': 2.7,
        'due': '2026-03-03T00:00:00.000Z',
        'interval': 5,
        'repetitions': 2,
        'lapses': 1,
        'relearn': 3,
        'meaningPasses': 4,
      });
    });

    test('默认复习状态也写全，不省略 0 和 null', () {
      final json = vocabItemToJson(vocabItem());
      final rs = json['reviewState'] as Map<String, Object?>;
      expect(rs.keys.toSet(), {
        'ease',
        'due',
        'interval',
        'repetitions',
        'lapses',
        'relearn',
        'meaningPasses',
      });
      expect(rs['due'], isNull);
      expect(rs['interval'], 0);
    });

    test('例句 / 来源 / 语境带出可选子字段', () {
      final json = vocabItemToJson(vocabItem(
        examples: const [
          VocabExample(text: 'I run daily.', translation: '我每天跑步。'),
        ],
        source: const VocabSource(
          articleId: 'A',
          fileName: 'a.md',
          sentenceId: 's1',
          sentenceText: 'I run daily.',
        ),
        contexts: const [
          VocabContext(
            articleId: 'A',
            fileName: 'a.md',
            sentenceId: 's1',
            sentenceText: 'I run daily.',
            meaning: '跑',
            at: '2026-01-02T00:00:00.000Z',
          ),
        ],
      ));

      expect(json['examples'], [
        {'text': 'I run daily.', 'translation': '我每天跑步。'},
      ]);
      expect(json['source'], {
        'articleId': 'A',
        'fileName': 'a.md',
        'sentenceId': 's1',
        'sentenceText': 'I run daily.',
      });
      expect(json['contexts'], [
        {
          'articleId': 'A',
          'fileName': 'a.md',
          'sentenceId': 's1',
          'sentenceText': 'I run daily.',
          'meaning': '跑',
          'at': '2026-01-02T00:00:00.000Z',
        },
      ]);
    });
  });

  group('vocabLibraryToJson', () {
    test('空表不输出 articleEntries / tombstones / sentenceTexts', () {
      final json = vocabLibraryToJson(emptyLibrary());
      expect(json.keys.toSet(), {'schemaVersion', 'items'});
      expect(json['schemaVersion'], vocabSchemaVersion);
    });

    test('按篇条目与墓碑照抄字段名', () {
      final json = vocabLibraryToJson(VocabLibrary(
        items: [vocabItem()],
        articleEntries: [
          articleEntry(
            articleId: 'A',
            lemma: 'alpha',
            via: VocabVia.ai,
            sentenceId: 's1',
            sentenceText: 'Alpha.',
            meaning: '阿尔法',
            meaningSource: VocabMeaningSource.ai,
            printedAt: '2026-02-02T00:00:00.000Z',
          ),
        ],
        tombstones: const [
          VocabTombstone(
            kind: VocabTombstoneKind.item,
            key: 'item:v1',
            at: '2026-01-03T00:00:00.000Z',
            lemma: 'alpha',
          ),
        ],
        sentenceTexts: const {'A\u0000s1': 'Alpha.'},
      ));

      expect(json['articleEntries'], [
        {
          'articleId': 'A',
          'lemma': 'alpha',
          'origin': 'manual',
          'via': 'ai',
          'addedAt': '2026-01-01T00:00:00.000Z',
          'sentenceId': 's1',
          'sentenceText': 'Alpha.',
          'meaning': '阿尔法',
          'meaningSource': 'ai',
          'printedAt': '2026-02-02T00:00:00.000Z',
        },
      ]);
      expect(json['tombstones'], [
        {
          'kind': 'item',
          'key': 'item:v1',
          'at': '2026-01-03T00:00:00.000Z',
          'lemma': 'alpha',
        },
      ]);
      expect(json['sentenceTexts'], {'A\u0000s1': 'Alpha.'});
    });

    test('encodeVocabLibrary 产出紧凑 JSON（无空白）', () {
      final text = encodeVocabLibrary(emptyLibrary());
      expect(text.contains('\n'), isFalse);
      expect(text.contains(': '), isFalse);
      expect(jsonDecode(text), isA<Map<String, Object?>>());
    });
  });

  group('往返一致性', () {
    test('写出去再读回来，词条关键字段逐条相同', () {
      final lib = VocabLibrary(
        items: [
          vocabItem(
            id: 'v1',
            word: 'running',
            lemma: 'run',
            kind: VocabItemKind.word,
            phonetic: '/ˈrʌnɪŋ/',
            partOfSpeech: 'v.',
            meaning: '跑',
            definition: 'to move fast on foot',
            usage: const ['run a business 经营'],
            phrases: const ['run out'],
            tags: const ['运动'],
            note: 'notep',
            status: VocabStatus.edited,
            fieldSources: const {VocabField.meaning: VocabFieldSource.manual},
            reviewState: const ReviewState(
              ease: 2.6,
              due: '2026-04-04T00:00:00.000Z',
              interval: 3,
              repetitions: 1,
              lapses: 2,
              relearn: 0,
              meaningPasses: 5,
            ),
            examples: const [VocabExample(text: 'I run.', origin: VocabExampleOrigin.ai)],
          ),
          vocabItem(id: 'v2', word: 'bank', lemma: 'bank'),
        ],
        articleEntries: [articleEntry(articleId: 'A', lemma: 'run')],
      );

      final back = migrateLibrary(jsonDecode(encodeVocabLibrary(lib)));

      expect(back.items.length, lib.items.length);
      final first = back.items.first;
      final origin = lib.items.first;
      expect(first.id, origin.id);
      expect(first.word, origin.word);
      expect(first.lemma, origin.lemma);
      expect(first.kind, origin.kind);
      expect(first.phonetic, origin.phonetic);
      expect(first.partOfSpeech, origin.partOfSpeech);
      expect(first.meaning, origin.meaning);
      expect(first.definition, origin.definition);
      expect(first.usage, origin.usage);
      expect(first.phrases, origin.phrases);
      expect(first.tags, origin.tags);
      expect(first.note, origin.note);
      expect(first.status, origin.status);
      expect(first.fieldSources, origin.fieldSources);
      expect(first.reviewState, origin.reviewState);
      expect(first.examples.single.text, 'I run.');
      expect(first.examples.single.origin, VocabExampleOrigin.ai);
      expect(back.items[1].word, 'bank');

      expect(back.articleEntries.single.articleId, 'A');
      expect(back.articleEntries.single.lemma, 'run');
      expect(back.articleEntries.single.origin, VocabOrigin.manual);
    });

    test('序列化两遍结果一致（幂等，供「内容没变」比对）', () {
      final lib = VocabLibrary(
        items: [vocabItem(id: 'v1', meaning: '甲')],
        articleEntries: [articleEntry()],
        tombstones: const [
          VocabTombstone(
            // 指向别的文章：指向 A 的话会按时间把上面那条收录删掉（那是正确行为）。
            kind: VocabTombstoneKind.article,
            key: 'article:B\u0000alpha',
            at: '2026-01-05T00:00:00.000Z',
          ),
        ],
        sentenceTexts: const {'A\u0000s1': 'Alpha.'},
      );

      final once = encodeVocabLibrary(lib);
      final twice = encodeVocabLibrary(
        migrateLibrary(jsonDecode(once)),
      );
      expect(twice, once);
    });

    test('空库往返仍是空库', () {
      final back = migrateLibrary(jsonDecode(encodeVocabLibrary(emptyLibrary())));
      expect(back.items, isEmpty);
      expect(back.articleEntries, isEmpty);
      expect(back.tombstones, isEmpty);
    });
  });
}
