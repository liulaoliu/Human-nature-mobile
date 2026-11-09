import 'dart:convert';

import 'package:dlaoshi_app/core/activity/activity.dart' show ActivityCat;
import 'package:dlaoshi_app/core/backup_parse.dart';
import 'package:dlaoshi_app/core/learning.dart' show LearningData;
import 'package:dlaoshi_app/data/db/backup_export.dart' show backupPayload;
import 'package:flutter_test/flutter_test.dart';

/// 跨端兼容：Web 版「导出全部（备份）」产出的 JSON，Dart 侧必须能完整吃下。
///
/// Web 侧结构见 `I:\Examples\Stutterer\src\reader\hooks\exportFiles.ts:66-96`：
/// 键名是 `stats`（会话）与 `studyStats`（背单词按天），Dart 侧的
/// `LearningSection.sessions` / `studyDays` 靠 `backup_parse.dart` 的老键名映射兜住。
/// 这份用例是那个映射的回归网 —— 改 `learning.dart` 的键名或 `backup_parse.dart`
/// 的映射时它会先响。
void main() {
  test('Web 版备份能完整解析', () {
    const at = '2026-11-08T10:00:00.000Z';
    final web = <String, Object?>{
      'version': 1,
      'exportedAt': at,
      // Web 的词库：schemaVersion + items，词条字段与 Dart 侧同名
      'library': <String, Object?>{
        'schemaVersion': 1,
        'items': <Object?>[
          <String, Object?>{
            'id': 'w1',
            'word': 'ensconced',
            'lemma': 'ensconced',
            'meaning': '安稳地待着',
            'createdAt': at,
            'updatedAt': at,
            'reviewState': <String, Object?>{
              'ease': 2.5,
              'due': at,
              'interval': 3,
              'repetitions': 2,
            },
          },
        ],
        'articleEntries': <Object?>[],
        'tombstones': <Object?>[],
        'sentenceTexts': <String, Object?>{},
      },
      // Web 的文章：sentences 里 language 是单数对象
      'articles': <Object?>[
        <String, Object?>{
          'id': 'a1',
          'title': 'A 篇',
          'text': 'He is ensconced in the job. The purges began.',
          'paragraphs': <Object?>[
            <String, Object?>{
              'id': 'p01',
              'sentenceIds': <Object?>['s1', 's2'],
            },
          ],
          'sentences': <Object?>[
            <String, Object?>{
              'id': 's1',
              'paraId': 'p01',
              'text': 'He is ensconced in the job.',
              'translation': '他在这份工作里安稳待着。',
              'vocab': <Object?>['ensconced', 'job'],
              'language': <String, Object?>{
                'phrases': <Object?>['be ensconced in — 安坐于'],
                'idioms': <Object?>[],
              },
            },
            <String, Object?>{
              'id': 's2',
              'paraId': 'p01',
              'text': 'The purges began.',
              'vocab': <Object?>['purges'],
            },
          ],
          'golden': <String, Object?>{
            'version': 1,
            'source': 'local',
            'outline': <Object?>[],
            'sentences': <Object?>[
              <String, Object?>{
                'id': 's1',
                'zh': '他在这份工作里安稳待着。',
                'targets': <Object?>[
                  <String, Object?>{
                    'en': 'ensconced',
                    'zh': '安稳地待着',
                    'kind': 'word',
                  },
                ],
              },
            ],
            'selected': <Object?>['s1'],
          },
          'createdAt': at,
          'updatedAt': at,
        },
      ],
      // 关键：Web 用老键名 stats / studyStats
      'stats': <Object?>[
        <String, Object?>{'at': at, 'seconds': 120, 'picked': 8},
      ],
      'studyStats': <Object?>[
        <String, Object?>{'day': '2026-11-08', 'seconds': 300, 'cards': 20},
      ],
      'activity': <Object?>[
        <String, Object?>{
          'day': '2026-11-08',
          'counts': <String, Object?>{'read': 1, 'vocab': 2, 'write': 1},
        },
      ],
      'writingHistory': <Object?>[
        <String, Object?>{
          'at': at,
          'articleId': 'a1',
          'model': 'He is ensconced in the job.',
          'text': 'She is ensconced in the team.',
          'source': 'writing',
          'feedback': <String, Object?>{
            'version': 2,
            'total': 80,
            'max': 100,
            'scores': <Object?>[],
            'issues': <Object?>[],
          },
        },
      ],
      'backTranslations': <Object?>[
        <String, Object?>{
          'id': 'bt1',
          'at': at,
          'articleId': 'a1',
          'sentenceId': 's1',
          'sourceZh': '他在这份工作里安稳待着。',
        },
      ],
      'practice': <Object?>[
        <String, Object?>{
          'at': at,
          'kind': 'quiz',
          'total': 5,
          'correct': 4,
        },
      ],
      'mistakes': <Object?>[
        <String, Object?>{
          'id': 'vocab:ensconced',
          'kind': 'vocab',
          'at': at,
          'count': 2,
          'label': 'ensconced',
        },
      ],
      'retells': <Object?>[],
      'studiedDays': <Object?>[
        <String, Object?>{'day': '2026-11-08', 'ids': <Object?>['w1']},
      ],
      'skimmed': <Object?>['a1'],
      'kindStats': <String, Object?>{
        'a1': <String, Object?>{
          'quiz': <String, Object?>{'total': 5, 'correct': 4},
        },
      },
      'answerEvents': <Object?>[
        <String, Object?>{
          'at': at,
          'day': '2026-11-08',
          'articleId': 'a1',
          'source': 'quiz',
          'kind': 'cloze',
          'cat': 'vocab',
          'correct': true,
        },
      ],
      'goldenDrills': <Object?>[
        <String, Object?>{
          'id': 'a1|s1|abc123',
          'articleId': 'a1',
          'sentenceId': 's1',
          'drillKey': 'abc123',
          'at': at,
          'fillFirst': true,
          'assembleFirst': true,
          'recallFirst': true,
          'fillTries': 1,
          'assembleTries': 1,
          'recallTries': 1,
          'summarySeen': true,
        },
      ],
      'writingErrorProgress': <Object?>[],
      'productionProgress': <Object?>[],
      'readDone': <Object?>[
        <String, Object?>{
          'day': '2026-11-08',
          'articleId': 'a1',
          'title': 'A 篇',
          'at': at,
        },
      ],
      'readGoal': 12,
      'goalMemo': '每天一篇',
    };

    // 先确认是合法 JSON（Web 是 JSON.stringify 出来的）
    final text = const JsonEncoder.withIndent('  ').convert(web);
    final decoded = jsonDecode(text);

    final parsed = parseBackupPayload(decoded);

    expect(parsed.errors, isEmpty, reason: '不该有任何错误：${parsed.errors}');
    expect(parsed.dropped, 0, reason: '不该丢任何一条');

    expect(parsed.articles, hasLength(1));
    final article = parsed.articles.single;
    expect(article.id, 'a1');
    expect(article.title, 'A 篇');
    expect(article.sentences, hasLength(2));
    expect(article.sentences.first.translation, '他在这份工作里安稳待着。');
    expect(article.golden, isNotNull, reason: '金句课要能带过来');

    expect(parsed.library, isNotNull);
    expect(parsed.library!.items, hasLength(1));
    expect(parsed.library!.items.single.word, 'ensconced');
    expect(parsed.library!.items.single.reviewState.repetitions, 2);

    final l = parsed.learning;
    expect(l.sessions, hasLength(1), reason: '老键名 stats → sessions');
    expect(l.sessions.single.seconds, 120);
    expect(l.studyDays, hasLength(1), reason: '老键名 studyStats → studyDays');
    expect(l.studyDays.single.cards, 20);
    expect(l.activity, hasLength(1));
    expect(l.activity.single.countOf(ActivityCat.read), 1);
    expect(l.writingHistory, hasLength(1));
    expect(l.backTranslations, hasLength(1));
    expect(l.practice, hasLength(1));
    expect(l.mistakes, hasLength(1));
    expect(l.studiedDays, hasLength(1));
    expect(l.skimmed, contains('a1'));
    expect(l.kindStats['a1']?['quiz']?.correct, 4);
    expect(l.answerEvents, hasLength(1));
    expect(l.goldenDrills, hasLength(1));
    expect(l.readDone, hasLength(1));
    expect(parsed.readGoal, 12);
    expect(parsed.goalMemo, '每天一篇');
  });

  test('App 导出的键名与 Web 版逐字一致（反向兼容）', () {
    final payload = backupPayload(
      learning: LearningData(),
      exportedAt: '2026-11-08T10:00:00.000Z',
    );

    // Web 版 exportAll 会写这些键（见 exportFiles.ts:66-96）。
    // App 少写任何一个，用户在浏览器里「导入备份」就会丢那一段。
    const webKeys = <String>[
      'version',
      'exportedAt',
      'stats',
      'studyStats',
      'activity',
      'writingHistory',
      'backTranslations',
      'practice',
      'mistakes',
      'retells',
      'studiedDays',
      'skimmed',
      'kindStats',
      'answerEvents',
      'goldenDrills',
      'writingErrorProgress',
      'productionProgress',
      'readDone',
    ];
    for (final key in webKeys) {
      expect(
        payload.containsKey(key),
        isTrue,
        reason: '导出的备份缺 "$key" —— Web 版读不到这一段',
      );
    }

    // 反过来：绝不能写出 Web 版不认的键名（否则那边当未知字段丢掉）。
    expect(payload.containsKey('sessions'), isFalse, reason: '会话要用 Web 的 stats');
    expect(payload.containsKey('studyDays'), isFalse, reason: '按天要用 Web 的 studyStats');
  });
}
