// 导入守卫的用例（对应 Web 版 `src/core/backupParse.test.ts` 256 行的逐条口径）。
//
// 每个用例都在回答同一个问题：**坏文件进来，现有数据会不会被弄坏？**
// 所以断言的重点不是「解析出了什么」，而是「丢了什么、丢了几条、有没有提示」。

import 'package:dlaoshi_app/core/backup_parse.dart';
import 'package:dlaoshi_app/models/document.dart';
import 'package:flutter_test/flutter_test.dart';

const at = '2026-10-01T00:00:00.000Z';

Map<String, Object?> goodSentence({
  String id = 's1',
  String text = 'Hello.',
  Map<String, Object?> over = const {},
}) =>
    {
      'id': id,
      'paraId': 'p1',
      'text': text,
      'translation': null,
      'collocations': <Object?>[],
      'vocab': <Object?>[],
      'tags': <Object?>[],
      'reviewState': {'ease': 2.5, 'due': null, 'interval': 0, 'repetitions': 0},
      ...over,
    };

Map<String, Object?> article({Map<String, Object?> over = const {}}) => {
      'id': 'a1',
      'title': 'A',
      'sourceKey': 'a1',
      'text': 'Hello.',
      'paragraphs': [
        {'id': 'p1', 'sentenceIds': ['s1']},
      ],
      'sentences': [goodSentence()],
      'updatedAt': at,
      ...over,
    };

Map<String, Object?> libraryJson(List<Object?> items) => {
      'schemaVersion': 1,
      'items': items,
    };

Map<String, Object?> goodItem() => {
      'id': 'v1',
      'word': 'run',
      'lemma': 'run',
      'status': 'unqueried',
      'note': '',
      'tags': <Object?>[],
      'usage': <Object?>[],
      'examples': <Object?>[],
      'createdAt': at,
      'updatedAt': at,
      'reviewState': {'ease': 2.5, 'due': null, 'interval': 0, 'repetitions': 0},
    };

void main() {
  test('完整备份：文章 / 词库 / 学习记录 / 目标都解析出来', () {
    final parsed = parseBackupPayload({
      'articles': [article()],
      'library': libraryJson([goodItem()]),
      'stats': [
        {'at': at, 'seconds': 60, 'picked': 5},
      ],
      'studyStats': [
        {'day': '2026-10-01', 'seconds': 60, 'cards': 3},
      ],
      'practice': [
        {'at': at, 'kind': 'quiz', 'total': 5, 'correct': 4},
      ],
      'mistakes': [
        {'id': 'vocab:run', 'kind': 'vocab', 'at': at, 'count': 1, 'label': 'run'},
      ],
      'readDone': [
        {'day': '2026-10-01', 'articleId': 'a1', 'title': 'A', 'at': at},
      ],
      'activity': [
        {
          'day': '2026-10-01',
          'counts': {'read': 2},
        },
      ],
      'skimmed': ['a1'],
      'kindStats': {
        'a1': {
          'quiz': {'total': 5, 'correct': 4},
        },
      },
      'answerEvents': [
        {
          'at': at,
          'day': '2026-10-01',
          'articleId': 'a1',
          'source': 'quiz',
          'kind': 'cloze',
          'cat': 'vocab',
          'correct': true,
        },
      ],
      'backTranslations': [
        {'id': 'bt1', 'at': at, 'articleId': 'a1', 'sentenceId': 's1', 'sourceZh': '你好。'},
      ],
      'writingErrorProgress': [
        {
          'id': 'errfix:word-spelling|spelling-bureaucracy',
          'rule': 'word-spelling',
          'key': 'spelling-bureaucracy',
          'status': 'active',
          'streak': 2,
          'createdAt': at,
          'updatedAt': at,
        },
      ],
      'readGoal': 12,
      'goalMemo': '每天一篇',
    });

    expect(parsed.articles, hasLength(1));
    expect(parsed.library?.items, hasLength(1));
    expect(parsed.learning.sessions, hasLength(1), reason: '老键名 stats → sessions');
    expect(parsed.learning.studyDays, hasLength(1), reason: '老键名 studyStats → studyDays');
    expect(parsed.learning.practice, hasLength(1));
    expect(parsed.learning.mistakes, hasLength(1));
    expect(parsed.learning.readDone, hasLength(1));
    expect(parsed.learning.activity, hasLength(1));
    expect(parsed.learning.skimmed, ['a1']);
    expect(parsed.learning.kindStats['a1']?['quiz']?.total, 5);
    expect(parsed.learning.kindStats['a1']?['quiz']?.correct, 4);
    expect(parsed.learning.answerEvents, hasLength(1));
    expect(parsed.learning.backTranslations, hasLength(1));
    expect(parsed.learning.writingErrorProgress, hasLength(1));
    expect(parsed.learning.writingErrorProgress.first['streak'], 2);
    expect(parsed.readGoal, 12);
    expect(parsed.goalMemo, '每天一篇');
    expect(parsed.dropped, 0);
    expect(parsed.errors, isEmpty);
  });

  test('词库坏条目被丢弃并计数，好条目保留（不整份失败）', () {
    final parsed = parseBackupPayload({
      'library': libraryJson([
        goodItem(),
        {'word': ''},
        null,
      ]),
    });
    expect(parsed.library?.items, hasLength(1));
    expect(parsed.dropped, 2);
    expect(parsed.errors.join(''), contains('词条'));
  });

  test('词库全坏 / 空 → 不导入（避免把现有词库清空）', () {
    final parsed = parseBackupPayload({
      'library': libraryJson([
        {'word': ''},
      ]),
    });
    expect(parsed.library, isNull);
    expect(parsed.dropped, 1);
    expect(parsed.errors.join(''), contains('已忽略'));
  });

  test('文章缺 sentences / id 被丢弃，正文结构完整的保留', () {
    final parsed = parseBackupPayload({
      'articles': [
        article(),
        article(over: {'id': ''}),
        {'id': 'a2', 'title': 'B', 'updatedAt': at},
      ],
    });
    expect(parsed.articles.map((a) => a.id), ['a1']);
    expect(parsed.dropped, 2);
  });

  test('文章来源只认白名单；旧数据 / 坏值保持未知', () {
    final parsed = parseBackupPayload({
      'articles': [
        article(over: {'id': 'a1', 'origin': 'epub'}),
        article(over: {'id': 'a2'}),
        article(over: {'id': 'a3', 'origin': 'legacy'}),
      ],
    });
    expect(
      parsed.articles.map((a) => [a.id, a.origin]),
      [
        ['a1', ArticleOrigin.epub],
        ['a2', null],
        ['a3', null],
      ],
    );
  });

  test('学习记录只留结构正确的条目，坏条目计数', () {
    final parsed = parseBackupPayload({
      'practice': [
        {'at': at, 'kind': 'quiz', 'total': 5, 'correct': 4},
        {'kind': 'quiz'},
      ],
      'skimmed': ['a1', '', 3],
      'kindStats': {
        'a1': {
          'quiz': {'total': 5, 'correct': 4},
        },
        'bad': {
          'quiz': {'total': 'x'},
        },
      },
      'answerEvents': [
        {
          'at': at,
          'day': '2026-10-01',
          'articleId': 'a1',
          'source': 'quiz',
          'kind': 'cloze',
          'cat': 'vocab',
          'correct': true,
        },
        {'at': 'bad', 'source': 'quiz', 'kind': 'cloze', 'cat': 'vocab', 'correct': true},
      ],
    });
    expect(parsed.learning.practice, hasLength(1));
    expect(parsed.learning.skimmed, ['a1']);
    expect(parsed.learning.kindStats.keys, ['a1']);
    expect(parsed.learning.answerEvents, hasLength(1));
    // 1 条练习 + 2 个 skimmed 坏值 + 1 个坏统计行 + 1 条坏事件
    expect(parsed.dropped, 5);
  });

  test('数组形态：文章数组 / 词条数组都能认', () {
    final asArticles = parseBackupPayload([article()]);
    expect(asArticles.articles, hasLength(1));
    expect(asArticles.library, isNull);

    final asItems = parseBackupPayload([
      {'word': 'run', 'lemma': 'run'},
    ]);
    expect(asItems.library?.items, hasLength(1));
  });

  test('不是对象 / 数组：不崩，返回错误计数', () {
    final parsed = parseBackupPayload('nope');
    expect(parsed.articles, isEmpty);
    expect(parsed.library, isNull);
    expect(parsed.dropped, 1);
  });

  test('老文章缺 title / text / createdAt 不整篇丢，补默认值', () {
    final parsed = parseBackupPayload({
      'articles': [
        {
          'id': 'a9',
          'paragraphs': [
            {'id': 'p1', 'sentenceIds': ['s1']},
          ],
          'sentences': [goodSentence()],
          'updatedAt': at,
        },
      ],
    });
    final a = parsed.articles.single;
    expect(a.title, '未命名');
    expect(a.text, '');
    expect(a.createdAt, isNull);
    expect(a.sentences.single.text, 'Hello.');
    expect(a.paragraphs.single.sentenceIds, ['s1']);
    expect(parsed.dropped, 0);
  });

  test('句子级字段按形状还原，坏值退默认值', () {
    final parsed = parseBackupPayload({
      'articles': [
        article(over: {
          'sentences': [
            goodSentence(over: {
              'translation': '你好。',
              'collocations': ['come to an end', 3],
              'languages': [
                {
                  'phrases': ['come to an end'],
                  'source': 'ai',
                  'at': at,
                },
                {'source': 'nonsense'},
              ],
              'reviewState': {'ease': -1, 'due': '2026-11-01', 'interval': 'x'},
            }),
          ],
        }),
      ],
    });
    final s = parsed.articles.single.sentences.single;
    expect(s.translation, '你好。');
    expect(s.collocations, ['come to an end']);
    expect(s.languages, hasLength(2));
    expect(s.languages!.first.source, LanguageSource.ai);
    expect(s.languages!.last.source, isNull);
    // ease 非正数 → 回默认 2.5；interval 不是数字 → 0
    expect(s.reviewState.ease, 2.5);
    expect(s.reviewState.interval, 0);
    expect(s.reviewState.due, '2026-11-01');
  });

  test('金句课内容与 goldenDrills 也保留（原始 JSON，P5 再加强守卫）', () {
    final parsed = parseBackupPayload({
      'articles': [
        article(over: {
          'golden': {
            'version': 1,
            'source': 'ai',
            'selected': ['s1'],
            'outline': <Object?>[],
            'sentences': [
              {
                'id': 's1',
                'targets': [
                  {'en': 'Hello', 'kind': 'word'},
                ],
              },
            ],
          },
        }),
      ],
      'goldenDrills': [
        {'id': 'a1|s1|k', 'articleId': 'a1', 'sentenceId': 's1', 'drillKey': 'k', 'at': at, 'mastered': true},
        {'id': 'bad', 'articleId': 'a1', 'at': 'bad'},
      ],
    });
    final golden = parsed.articles.single.golden;
    expect(golden, isNotNull);
    expect((golden!['sentences']! as List), hasLength(1));
    expect(parsed.learning.goldenDrills, hasLength(2), reason: '金句锤炼记录暂时只做列表守卫');
  });

  test('奶工棚进度 / 草稿原样保留给导入侧守卫', () {
    final parsed = parseBackupPayload({
      'productionProgress': [
        {
          'key': 'word:run',
          'kind': 'word',
          'text': 'run',
          'meaning': '跑',
          'attempts': 1,
          'hits': 1,
          'misses': 0,
          'streak': 1,
          'lastAt': '2026-11-01T00:00:00.000Z',
          'dueAt': '2026-11-02T00:00:00.000Z',
        },
      ],
      'productionDraft': {
        'A': {'version': 1, 'articleId': 'A'},
      },
    });
    expect(parsed.learning.productionProgress, hasLength(1));
    expect(parsed.learning.productionProgress.first['key'], 'word:run');
    expect(parsed.learning.productionProgress.first['attempts'], 1);
    expect(parsed.productionDraft, {
      'A': {'version': 1, 'articleId': 'A'},
    });
  });

  test('阅读目标：负数 / 坏值不导入，字符串数字也不认', () {
    expect(parseBackupPayload({'readGoal': -1}).readGoal, isNull);
    expect(parseBackupPayload({'readGoal': -1}).dropped, 1);
    expect(parseBackupPayload({'readGoal': '12'}).readGoal, isNull);
    expect(parseBackupPayload({'readGoal': 0}).readGoal, 0);
    expect(parseBackupPayload({'readGoal': 3.7}).readGoal, 3);
  });

  test('新键名优先于老键名（两个都给时）', () {
    final parsed = parseBackupPayload({
      'studyStats': [
        {'day': '2026-10-01', 'seconds': 60, 'cards': 3},
      ],
      'studyDays': [
        {'day': '2026-10-02', 'seconds': 90, 'cards': 5},
      ],
    });
    expect(parsed.learning.studyDays.single.day, '2026-10-02');
  });

  test('学习段格式不对（不是数组）只丢这一段', () {
    final parsed = parseBackupPayload({
      'practice': 'nope',
      'readDone': [
        {'day': '2026-10-01', 'articleId': 'a1', 'title': 'A', 'at': at},
      ],
    });
    expect(parsed.learning.practice, isEmpty);
    expect(parsed.learning.readDone, hasLength(1));
    expect(parsed.errors.join(''), contains('练习记录格式不对'));
  });

  test('null / 空对象：什么都不导入，也不报错成灾', () {
    final nullParsed = parseBackupPayload(null);
    expect(nullParsed.articles, isEmpty);
    expect(nullParsed.library, isNull);
    expect(nullParsed.dropped, 1);

    final emptyParsed = parseBackupPayload(<String, Object?>{});
    expect(emptyParsed.articles, isEmpty);
    expect(emptyParsed.dropped, 0);
    expect(emptyParsed.errors, isEmpty);
  });
}
