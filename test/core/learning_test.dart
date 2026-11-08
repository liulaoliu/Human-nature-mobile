import 'package:dlaoshi_app/core/activity/activity.dart';
import 'package:dlaoshi_app/core/kind_stats.dart';
import 'package:dlaoshi_app/core/learning.dart';
import 'package:dlaoshi_app/core/mistakes.dart';
import 'package:dlaoshi_app/core/practice.dart';
import 'package:flutter_test/flutter_test.dart';

/// 造一条合法的练习记录（Web 版用例里同一个 at）。
Map<String, Object?> practiceJson({
  String at = '2026-01-01T00:00:00.000Z',
  Object? kind = 'quiz',
  Object? total = 10,
  Object? correct = 8,
}) =>
    <String, Object?>{'at': at, 'kind': kind, 'total': total, 'correct': correct};

/// 造一条合法的答题事件。
Map<String, Object?> eventJson({
  String at = '2026-01-01T00:00:00.000Z',
  String day = '2026-01-01',
  String articleId = 'a1',
  String source = 'quiz',
  String kind = 'cloze',
  String cat = 'vocab',
  bool correct = true,
}) =>
    <String, Object?>{
      'at': at,
      'day': day,
      'articleId': articleId,
      'source': source,
      'kind': kind,
      'cat': cat,
      'correct': correct,
    };

void main() {
  group('learning 记录', () {
    test('LEARNING_KEYS 与 LearningSection 一一对应，键名不重复', () {
      // 每个 section 都必须有键，一个都不许漏（漏了那一段就永远不同步）。
      expect(learningKeys.length, LearningSection.values.length);
      for (final section in LearningSection.values) {
        expect(learningKeys.containsKey(section), isTrue, reason: '$section 缺键');
        expect(learningLabel.containsKey(section), isTrue, reason: '$section 缺中文名');
      }

      final storageKeys = learningKeys.values.toList();
      expect(storageKeys.toSet().length, storageKeys.length, reason: '存储键重复');
      for (final key in storageKeys) {
        expect(key.startsWith('reader:'), isTrue, reason: '$key 少了 reader: 前缀');
      }
      // 两个历史键名不是驼峰，迁移时不能「顺手改名」。
      expect(LearningSection.studyDays.storageKey, 'reader:studyStats');
      expect(LearningSection.sessions.storageKey, 'reader:vocabStats');
      expect(LearningSection.studiedDays.storageKey, 'reader:studiedToday');
      expect(LearningSection.skimmed.storageKey, 'reader:intensiveSkimmed');
    });

    test('空值 / 坏值给空记录，不抛', () {
      expect(hasLearningData(normalizeLearning(null)), isFalse);
      expect(hasLearningData(normalizeLearning('nope')), isFalse);
      expect(hasLearningData(normalizeLearning(<Object?>[])), isFalse);
      expect(
        hasLearningData(normalizeLearning(<String, Object?>{'practice': 'bad', 'activity': <Object?>[<String, Object?>{}]})),
        isFalse,
      );
    });

    test('只保留结构正确的记录', () {
      final data = normalizeLearning(<String, Object?>{
        'practice': <Object?>[
          practiceJson(),
          <String, Object?>{'kind': 'quiz'},
        ],
        'mistakes': <Object?>[
          <String, Object?>{
            'id': 'vocab:w1',
            'kind': 'vocab',
            'at': '2026-01-01T00:00:00.000Z',
            'count': 2,
            'label': 'w1',
          },
        ],
        'readDone': <Object?>[
          <String, Object?>{
            'day': '2026-01-01',
            'articleId': 'a1',
            'title': 'A',
            'at': '2026-01-01T00:00:00.000Z',
          },
        ],
        'studiedDays': <Object?>[
          <String, Object?>{
            'day': '2026-01-01',
            'ids': <Object?>['w1', 2, 'w2'],
          },
        ],
        'skimmed': <Object?>['a1', '', 3],
        'kindStats': <String, Object?>{
          'a1': <String, Object?>{
            'quiz': <String, Object?>{'total': 10, 'correct': 8},
            'bad': <String, Object?>{'total': 'x'},
          },
        },
        'answerEvents': <Object?>[
          eventJson(),
          eventJson(at: 'bad'),
        ],
      });

      expect(data.practice, hasLength(1));
      expect(data.practice.first.kind, PracticeKind.quiz);
      expect(data.practice.first.total, 10);
      expect(data.practice.first.correct, 8);
      expect(data.mistakes, hasLength(1));
      expect(data.mistakes.first.kind, MistakeKind.vocab);
      expect(data.readDone, hasLength(1));
      expect(data.readDone.first.title, 'A');
      expect(data.studiedDays, hasLength(1));
      expect(data.studiedDays.first.day, '2026-01-01');
      expect(data.studiedDays.first.ids, <String>['w1', 'w2']);
      expect(data.skimmed, <String>['a1']);
      expect(data.kindStats.keys, <String>['a1']);
      expect(data.kindStats['a1']!['quiz']!.total, 10);
      expect(data.kindStats['a1']!.containsKey('bad'), isFalse);
      expect(data.answerEvents, hasLength(1));
      expect(hasLearningData(data), isTrue);
    });

    test('数值字段坏了也丢弃，不让 NaN 进统计', () {
      final data = normalizeLearning(<String, Object?>{
        'practice': <Object?>[practiceJson(total: 'x')],
        'mistakes': <Object?>[
          <String, Object?>{
            'id': 'm1',
            'kind': 'vocab',
            'at': '2026-01-01T00:00:00.000Z',
            'count': 'x',
            'label': 'm1',
          },
        ],
        'studyDays': <Object?>[
          <String, Object?>{'day': '2026-01-01', 'seconds': 'x', 'cards': 1},
        ],
        'sessions': <Object?>[
          <String, Object?>{'at': '2026-01-01T00:00:00.000Z', 'seconds': 1, 'picked': 'x'},
        ],
        'activity': <Object?>[
          <String, Object?>{
            'day': '2026-01-01',
            'counts': <String, Object?>{'read': 'x', 'speak': 2},
          },
        ],
      });

      expect(data.practice, isEmpty);
      expect(data.mistakes, isEmpty);
      expect(data.studyDays, isEmpty);
      expect(data.sessions, isEmpty);
      // 活动只留合法分类（坏值那格丢掉，整条不丢）。
      expect(data.activity, hasLength(1));
      expect(data.activity.first.day, '2026-01-01');
      expect(data.activity.first.countOf(ActivityCat.speak), 2);
      expect(data.activity.first.countOf(ActivityCat.read), 0);
      expect(hasLearningData(data), isTrue);
    });

    test('回译存档也按学习记录校验：坏条目丢掉，好记录保留', () {
      final good = <String, Object?>{
        'id': 'bt1',
        'at': '2026-10-01T00:00:00.000Z',
        'articleId': 'a1',
        'sentenceId': 's1',
        'sourceZh': '他去了学校。',
        'answer': 'He went to school.',
        'reference': 'He went to school.',
      };
      final data = normalizeLearning(<String, Object?>{
        'backTranslations': <Object?>[
          good,
          <String, Object?>{...good, 'id': 'bad', 'sourceZh': ''},
        ],
      });
      expect(data.backTranslations, hasLength(1));
      expect(data.backTranslations.first['id'], 'bt1');
      expect(hasLearningData(data), isTrue);
    });

    test('仿写记录的来源走白名单：坏值当普通仿写，金句课记录不丢', () {
      final rec = <String, Object?>{
        'at': '2026-01-01T00:00:00.000Z',
        'articleId': 'a1',
        'model': 'M',
        'text': 'T',
      };
      final data = normalizeLearning(<String, Object?>{
        'writingHistory': <Object?>[
          <String, Object?>{...rec, 'source': 'goldenSentence', 'sentenceId': 's1'},
          <String, Object?>{...rec, 'source': 'bogus', 'sentenceId': 3},
        ],
      });
      expect(data.writingHistory, hasLength(2));
      expect(data.writingHistory.first['source'], 'goldenSentence');
      expect(data.writingHistory.first['sentenceId'], 's1');
      // 坏来源与坏句 id 都被删掉，记录本身留着（不许丢）。
      expect(data.writingHistory.last.containsKey('source'), isFalse);
      expect(data.writingHistory.last.containsKey('sentenceId'), isFalse);
    });

    test('只有事件也算有学习数据', () {
      final data = normalizeLearning(<String, Object?>{
        'answerEvents': <Object?>[eventJson()],
      });
      expect(data.answerEvents, hasLength(1));
      expect(hasLearningData(data), isTrue);
    });

    test('只有偏好 / 空记录时 hasLearningData=false', () {
      expect(hasLearningData(emptyLearning()), isFalse);
      // 每天背过的词全是空列表，也不算有数据。
      final idle = emptyLearning()
        ..studiedDays = <StudiedDay>[
          const StudiedDay(day: '2026-01-01', ids: <String>[]),
        ];
      expect(hasLearningData(idle), isFalse);
    });

    test('learningCounts 逐段报条数', () {
      final data = normalizeLearning(<String, Object?>{
        'practice': <Object?>[practiceJson()],
        'skimmed': <Object?>['a1', 'a2'],
      });
      final counts = learningCounts(data);
      expect(counts.length, LearningSection.values.length);
      expect(counts[LearningSection.practice], 1);
      expect(counts[LearningSection.skimmed], 2);
      expect(counts[LearningSection.mistakes], 0);
    });

    test('emptyLearning 每份都是新容器，改一份不影响另一份', () {
      final a = emptyLearning();
      final b = emptyLearning();
      a.practice.add(
        const PracticeRecord(at: 'x', kind: PracticeKind.quiz, total: 1, correct: 1),
      );
      a.skimmed.add('a1');
      expect(b.practice, isEmpty);
      expect(b.skimmed, isEmpty);
      expect(identical(a.practice, b.practice), isFalse);
      expect(identical(a.kindStats, b.kindStats), isFalse);
    });
  });

  group('normalizeLearningSection：单段外部输入也走同一守卫', () {
    test('每段坏值都回到空值，好值保留', () {
      expect(normalizeLearningSection(LearningSection.activity, null), isEmpty);
      expect(normalizeLearningSection(LearningSection.practice, 'nope'), isEmpty);
      expect(normalizeLearningSection(LearningSection.mistakes, <String, Object?>{}), isEmpty);
      expect(normalizeLearningSection(LearningSection.kindStats, <Object?>[]), isEmpty);
      expect(normalizeLearningSection(LearningSection.retells, null), isEmpty);
      expect(normalizeLearningSection(LearningSection.studyDays, null), isEmpty);
      expect(normalizeLearningSection(LearningSection.sessions, <String, Object?>{}), isEmpty);
      expect(normalizeLearningSection(LearningSection.skimmed, 'x'), isEmpty);

      final activity = normalizeLearningSection(LearningSection.activity, <Object?>[
        <String, Object?>{
          'day': '2026-10-01',
          'counts': <String, Object?>{'read': 2},
        },
        <String, Object?>{'day': 1},
      ]);
      final list = activity as List<DayActivity>;
      expect(list, hasLength(1));
      expect(list.first.day, '2026-10-01');
      expect(list.first.countOf(ActivityCat.read), 2);
    });

    test('单段解析与整份解析同口径', () {
      final raw = <String, Object?>{
        'at': '2026-01-01T00:00:00.000Z',
        'kind': 'quiz',
        'total': 10,
        'correct': 8,
      };
      final section = normalizeLearningSection(LearningSection.practice, <Object?>[raw, 'bad']);
      final whole = normalizeLearning(<String, Object?>{
        'practice': <Object?>[raw, 'bad'],
      });
      final fromSection = section as List<PracticeRecord>;
      expect(fromSection, hasLength(1));
      expect(fromSection.first.total, whole.practice.first.total);
      expect(fromSection.first.correct, whole.practice.first.correct);
    });
  });

  group('normalizeKindStats / 复述 / 每天背过的词', () {
    test('题型统计：非 Map 丢掉，空行不留键', () {
      final stats = normalizeKindStats(<String, Object?>{
        'a1': <String, Object?>{'quiz': <String, Object?>{'total': 3, 'correct': 2}},
        'a2': 'bad',
        'a3': <String, Object?>{'quiz': 'bad'},
      });
      expect(stats.keys, <String>['a1']);
      expect(stats['a1']!['quiz']!.total, 3);
      expect(stats['a1']!['quiz']!.correct, 2);
    });

    test('复述记录要全字段齐；words 可以是数字字符串', () {      final data = normalizeLearning(<String, Object?>{
        'retells': <Object?>[
          <String, Object?>{
            'at': '2026-01-01T00:00:00.000Z',
            'articleId': 'a1',
            'text': '他说了一遍。',
            'words': '12',
          },
          <String, Object?>{
            'at': '2026-01-01T00:00:00.000Z',
            'articleId': 'a1',
            'text': '缺 words',
          },
        ],
      });
      expect(data.retells, hasLength(1));
      expect(data.retells.first.words, 12);
      expect(data.retells.first.articleId, 'a1');
    });
  });
}
