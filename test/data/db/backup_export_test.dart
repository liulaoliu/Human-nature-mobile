import 'dart:convert';

import 'package:dlaoshi_app/core/activity/activity.dart';
import 'package:dlaoshi_app/core/answer_events.dart';
import 'package:dlaoshi_app/core/backup_parse.dart';
import 'package:dlaoshi_app/core/goals.dart';
import 'package:dlaoshi_app/core/kind_stats.dart';
import 'package:dlaoshi_app/core/learning.dart';
import 'package:dlaoshi_app/core/mistakes.dart';
import 'package:dlaoshi_app/core/practice.dart';
import 'package:dlaoshi_app/core/vocab_stats.dart';
import 'package:dlaoshi_app/data/db/backup_export.dart';
import 'package:dlaoshi_app/models/document.dart';
import 'package:dlaoshi_app/models/vocab.dart';
import 'package:flutter_test/flutter_test.dart';

/// 导出侧与导入侧必须互相吃得下。
///
/// 这层最容易出「导入成功但数据是空的」：导出写成 `learning` 嵌套、或者把
/// `studyDays` 按新键名写，导入侧（照 Web 版历史键名读）就一段都读不到，
/// 而整个流程不报错。所以这里的主用例是**导出 → 解析**的往返。
void main() {
  LearningData sample() => LearningData(
        practice: <PracticeRecord>[
          const PracticeRecord(at: '2026-11-01T00:00:00.000Z', kind: PracticeKind.quiz, total: 10, correct: 8),
        ],
        mistakes: <MistakeEntry>[
          const MistakeEntry(id: 'm1', kind: MistakeKind.vocab, at: '2026-11-01T00:00:00.000Z', count: 2, label: 'keep up with'),
        ],
        readDone: <ReadDone>[
          const ReadDone(day: '2026-11-01', articleId: 'a1', title: 'A', at: '2026-11-01T00:00:00.000Z'),
        ],
        writingHistory: <Map<String, Object?>>[
          <String, Object?>{'at': '2026-11-01T00:00:00.000Z', 'articleId': 'a1', 'text': 'hi'},
        ],
        backTranslations: <Map<String, Object?>>[
          <String, Object?>{
            'id': 'bt1',
            'at': '2026-11-01T00:00:00.000Z',
            'sourceZh': '我们每天看新闻。',
          },
        ],
        retells: <RetellRecord>[
          const RetellRecord(at: '2026-11-01T00:00:00.000Z', articleId: 'a1', text: '复述', words: 2),
        ],
        activity: <DayActivity>[
          const DayActivity(day: '2026-11-01', counts: <ActivityCat, int>{ActivityCat.read: 2, ActivityCat.write: 1}),
        ],
        studyDays: <StudyDay>[const StudyDay(day: '2026-11-01', seconds: 600, cards: 20)],
        sessions: <PickSession>[const PickSession(at: '2026-11-01T00:00:00.000Z', seconds: 60, picked: 10)],
        studiedDays: <StudiedDay>[const StudiedDay(day: '2026-11-01', ids: <String>['w1'])],
        skimmed: <String>['a1'],
        kindStats: <String, Map<String, KindStat>>{
          'a1': <String, KindStat>{'choice': const KindStat(total: 5, correct: 3)},
        },
        answerEvents: <AnswerEvent>[
          const AnswerEvent(
            at: '2026-11-01T00:00:00.000Z',
            day: '2026-11-01',
            articleId: 'a1',
            source: PracticeKind.quiz,
            kind: 'choice',
            cat: ActivityCat.vocab,
            correct: true,
            questionId: 'q1',
          ),
        ],
        goldenDrills: <Map<String, Object?>>[
          <String, Object?>{'id': 'a1|s1|k', 'articleId': 'a1', 'sentenceId': 's1', 'drillKey': 'k', 'at': '2026-11-01T00:00:00.000Z'},
        ],
        writingErrorProgress: <Map<String, Object?>>[
          <String, Object?>{'key': 'k1', 'updatedAt': '2026-11-01T00:00:00.000Z', 'stage': 2},
        ],
        productionProgress: <Map<String, Object?>>[
          <String, Object?>{'key': 'p1', 'updatedAt': '2026-11-01T00:00:00.000Z', 'hits': 1},
        ],
      );

  test('导出 → 解析往返：16 段学习记录一段不丢', () {
    final payload = backupPayload(
      learning: sample(),
      readGoal: 3,
      goalMemo: '每天读一篇',
      exportedAt: '2026-11-09T00:00:00.000Z',
    );
    final text = encodeBackupJson(payload);
    final parsed = parseBackupPayload(jsonDecode(text));

    expect(parsed.learning.practice, hasLength(1));
    expect(parsed.learning.mistakes, hasLength(1));
    expect(parsed.learning.mistakes.single.count, 2);
    expect(parsed.learning.readDone, hasLength(1));
    expect(parsed.learning.writingHistory, hasLength(1));
    expect(parsed.learning.backTranslations, hasLength(1));
    expect(parsed.learning.retells, hasLength(1));
    expect(parsed.learning.activity, hasLength(1));
    expect(parsed.learning.activity.single.countOf(ActivityCat.read), 2);
    expect(parsed.learning.studyDays, hasLength(1));
    expect(parsed.learning.studyDays.single.cards, 20);
    expect(parsed.learning.sessions, hasLength(1));
    expect(parsed.learning.studiedDays, hasLength(1));
    expect(parsed.learning.skimmed, <String>['a1']);
    expect(parsed.learning.kindStats['a1']!['choice']!.correct, 3);
    expect(parsed.learning.answerEvents, hasLength(1));
    expect(parsed.learning.goldenDrills, hasLength(1));
    expect(parsed.learning.writingErrorProgress, hasLength(1));
    expect(parsed.learning.productionProgress, hasLength(1));
    expect(parsed.readGoal, 3);
    expect(parsed.goalMemo, '每天读一篇');
    expect(parsed.dropped, 0, reason: '自己写出来的备份不该被自己的守卫丢弃');
  });

  test('顶层键名沿用历史名（studyStats / stats），不是 section 名', () {
    final payload = backupPayload(learning: sample(), exportedAt: '2026-11-09T00:00:00.000Z');
    expect(payload.containsKey('studyStats'), isTrue);
    expect(payload.containsKey('stats'), isTrue);
    expect(payload.containsKey('studyDays'), isFalse);
    expect(payload.containsKey('sessions'), isFalse);
    expect(payload['version'], 1);
  });

  test('词库与文章一起导出后能被解析回来', () {
    final library = VocabLibrary(items: <VocabItem>[
      VocabItem(
        id: 'w1',
        word: 'keep up with',
        lemma: 'keep up with',
        createdAt: '2026-11-01T00:00:00.000Z',
        updatedAt: '2026-11-01T00:00:00.000Z',
      ),
    ]);
    const article = SavedArticle(
      id: 'a1',
      title: 'A',
      text: 'We keep up with the news.',
      paragraphs: <Paragraph>[Paragraph(id: 'p01', sentenceIds: <String>['s1'])],
      sentences: <Sentence>[Sentence(id: 's1', paraId: 'p01', text: 'We keep up with the news.')],
      updatedAt: '2026-11-01T00:00:00.000Z',
    );
    final parsed = parseBackupPayload(
      jsonDecode(
        encodeBackupJson(
          backupPayload(
            library: library,
            articles: const <SavedArticle>[article],
            learning: emptyLearning(),
            exportedAt: '2026-11-09T00:00:00.000Z',
          ),
        ),
      ),
    );
    expect(parsed.library, isNotNull);
    expect(parsed.library!.items.single.word, 'keep up with');
    expect(parsed.articles, hasLength(1));
    expect(parsed.articles.single.sentences.single.id, 's1');
  });

  test('空学习记录也写成空数组（不是缺键）', () {
    final payload = backupPayload(learning: emptyLearning(), exportedAt: '2026-11-09T00:00:00.000Z');
    for (final key in backupLearningKeys.values) {
      expect(payload.containsKey(key), isTrue, reason: '缺键会让导入侧以为「这段没导」');
    }
    expect(payload['kindStats'], isA<Map<String, Object?>>());
  });

  test('没有词库 / 目标 / 备忘录时不写这些键（不覆盖本机）', () {
    final payload = backupPayload(learning: emptyLearning(), exportedAt: '2026-11-09T00:00:00.000Z');
    expect(payload.containsKey('library'), isFalse);
    expect(payload.containsKey('readGoal'), isFalse);
    expect(payload.containsKey('goalMemo'), isFalse);
    expect(payload.containsKey('productionDraft'), isFalse);
  });

  test('空串备忘录当没有', () {
    final payload = backupPayload(learning: emptyLearning(), goalMemo: '', exportedAt: '2026-11-09T00:00:00.000Z');
    expect(payload.containsKey('goalMemo'), isFalse);
  });

  test('缩进 JSON 可被 jsonDecode 回读（转义没写坏）', () {
    final text = encodeBackupJson(
      backupPayload(
        learning: LearningData(goldenDrills: <Map<String, Object?>>[
          <String, Object?>{'id': 'x', 'note': '带"引号"和\n换行\\反斜杠'},
        ]),
        exportedAt: '2026-11-09T00:00:00.000Z',
      ),
    );
    final back = jsonDecode(text) as Map<String, Object?>;
    final drills = back['goldenDrills']! as List<Object?>;
    expect((drills.single! as Map<String, Object?>)['note'], '带"引号"和\n换行\\反斜杠');
  });

  test('文件名按天给（与 Web 版同款）', () {
    expect(backupFileName('2026-11-09'), 'economist-backup-2026-11-09.json');
  });
}
