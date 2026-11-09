import 'package:dlaoshi_app/core/activity/activity.dart';
import 'package:dlaoshi_app/core/answer_events.dart';
import 'package:dlaoshi_app/core/goals.dart';
import 'package:dlaoshi_app/core/kind_stats.dart';
import 'package:dlaoshi_app/core/learning.dart';
import 'package:dlaoshi_app/core/merge_backup.dart';
import 'package:dlaoshi_app/core/mistakes.dart';
import 'package:dlaoshi_app/core/practice.dart';
import 'package:dlaoshi_app/core/vocab_stats.dart';
import 'package:dlaoshi_app/models/vocab.dart';
import 'package:flutter_test/flutter_test.dart';

/// 备份「合并导入」的口径。
///
/// 记这些用例是因为合并的承诺和覆盖导入相反：**覆盖 = 还原**，
/// **合并 = 什么都不删、也不重复计数**。每条用例守住一个「重复导入同一份备份
/// 不应该改变结果」的性质。
void main() {
  VocabItem mkWord(String word, String day) => VocabItem(
        id: 'item-$word',
        word: word,
        lemma: word,
        createdAt: '${day}T00:00:00.000Z',
        updatedAt: '${day}T00:00:00.000Z',
      );

  MistakeEntry mkMistake({required String id, required String at, required int count}) =>
      MistakeEntry(
        id: id,
        kind: MistakeKind.vocab,
        at: at,
        count: count,
        label: 'label-$id',
      );

  group('词库合并', () {
    test('同键原文冲突时保留本机，新键照常补进来', () {
      final merged = mergeSentenceTexts(
        <String, String>{'a\u0000s1': '本机原文'},
        <String, String>{'a\u0000s1': '别人的原文', 'b\u0000s1': '新文章'},
      );
      expect(merged['a\u0000s1'], '本机原文');
      expect(merged['b\u0000s1'], '新文章');
    });

    test('一边为空时直接返回另一边（不复制内存）', () {
      final only = <String, String>{'a\u0000s1': 'x'};
      expect(mergeSentenceTexts(const <String, String>{}, only), same(only));
      expect(mergeSentenceTexts(only, const <String, String>{}), same(only));
    });

    test('词条按 lemma 去重互补，两边的词都在', () {
      final current = VocabLibrary(items: <VocabItem>[mkWord('keep up with', '2026-11-01')]);
      final incoming = VocabLibrary(items: <VocabItem>[
        mkWord('keep up with', '2026-11-02'),
        mkWord('come up with', '2026-11-02'),
      ]);
      final merged = mergeLibraries(current, incoming);
      expect(
        merged.items.map((VocabItem i) => i.word).toList()..sort(),
        <String>['come up with', 'keep up with'],
      );
    });

    test('合并后仍然应用两边的墓碑（删掉的词不会复活）', () {
      final deleted = mkWord('deleted', '2026-11-01');
      final current = VocabLibrary(items: <VocabItem>[mkWord('kept', '2026-11-01')]);
      final incoming = VocabLibrary(
        items: <VocabItem>[deleted],
        tombstones: <VocabTombstone>[
          VocabTombstone(
            kind: VocabTombstoneKind.item,
            key: 'item:${deleted.id}',
            at: '2026-11-02T00:00:00.000Z',
            lemma: deleted.lemma,
          ),
        ],
      );
      final merged = mergeLibraries(current, incoming);
      expect(merged.items.map((VocabItem i) => i.word), <String>['kept']);
    });
  });

  group('按时段累计的记录', () {
    test('会话按字段去重，重复导入不翻倍', () {
      const a = PickSession(at: '2026-11-01T00:00:00.000Z', seconds: 60, picked: 10);
      const b = PickSession(at: '2026-11-02T00:00:00.000Z', seconds: 30, picked: 5);
      final once = mergeSessions(<PickSession>[a], <PickSession>[a, b]);
      expect(once, hasLength(2));
      final twice = mergeSessions(once, <PickSession>[a, b]);
      expect(twice, hasLength(2));
      expect(twice.map((PickSession s) => s.at), <String>[a.at, b.at]);
    });

    test('背单词按天相加（两台机器的同一天要合起来）', () {
      final merged = mergeStudyDays(
        const <StudyDay>[StudyDay(day: '2026-11-01', seconds: 60, cards: 10)],
        const <StudyDay>[
          StudyDay(day: '2026-11-01', seconds: 30, cards: 5),
          StudyDay(day: '2026-11-02', seconds: 20, cards: 4),
        ],
      );
      expect(merged.map((StudyDay d) => d.day), <String>['2026-11-01', '2026-11-02']);
      expect(merged.first.seconds, 90);
      expect(merged.first.cards, 15);
      expect(merged.last.seconds, 20);
    });

    test('活动热力图同一天同类累加，且不会出现两条同一天', () {
      final merged = mergeActivity(
        <DayActivity>[const DayActivity(day: '2026-11-01', counts: <ActivityCat, int>{ActivityCat.read: 2})],
        <DayActivity>[const DayActivity(day: '2026-11-01', counts: <ActivityCat, int>{ActivityCat.read: 3, ActivityCat.write: 1})],
      );
      expect(merged, hasLength(1));
      expect(merged.single.countOf(ActivityCat.read), 5);
      expect(merged.single.countOf(ActivityCat.write), 1);
    });

    test('活动合并受上限约束（老的先掉）', () {
      final current = <DayActivity>[
        for (var i = 1; i <= 5; i++)
          DayActivity(day: '2026-11-0$i', counts: const <ActivityCat, int>{ActivityCat.read: 1}),
      ];
      final merged = mergeActivity(
        current,
        const <DayActivity>[DayActivity(day: '2026-11-06', counts: <ActivityCat, int>{ActivityCat.read: 1})],
        cap: 3,
      );
      expect(merged.map((DayActivity d) => d.day), <String>['2026-11-04', '2026-11-05', '2026-11-06']);
    });
  });

  group('按记录去重的历史', () {
    test('仿写按「时间 + 文章 + 范句 + 作答」去重，倒序', () {
      final a = <String, Object?>{'at': '2026-11-01T00:00:00.000Z', 'articleId': 'x', 'model': 'm', 'text': 'a'};
      final b = <String, Object?>{'at': '2026-11-02T00:00:00.000Z', 'articleId': 'x', 'model': 'm', 'text': 'b'};
      final merged = mergeWritingHistoryJson(<Map<String, Object?>>[a], <Map<String, Object?>>[a, b]);
      expect(merged, hasLength(2));
      expect(merged.first['text'], 'b');
    });

    test('回译按 id 去重，同一份备份再导一次不重复', () {
      final r = <String, Object?>{'id': 'bt1', 'at': '2026-11-01T00:00:00.000Z'};
      final once = mergeBackTranslations(<Map<String, Object?>>[], <Map<String, Object?>>[r]);
      expect(once, hasLength(1));
      expect(mergeBackTranslations(once, <Map<String, Object?>>[r]), hasLength(1));
    });

    test('练习记录按字段去重，升序，保留最近 N 条', () {
      PracticeRecord p(String at, int total) =>
          PracticeRecord(at: at, kind: PracticeKind.quiz, total: total, correct: total);
      final merged = mergePractice(
        <PracticeRecord>[p('2026-11-01T00:00:00.000Z', 10)],
        <PracticeRecord>[p('2026-11-01T00:00:00.000Z', 10), p('2026-11-02T00:00:00.000Z', 20)],
      );
      expect(merged, hasLength(2));
      expect(merged.last.total, 20);
      expect(mergePractice(merged, merged, cap: 1), hasLength(1));
    });

    test('复述按「时间 + 文章 + 正文」去重，倒序，受上限约束', () {
      RetellRecord r(String at, String text) => RetellRecord(at: at, articleId: 'x', text: text, words: 3);
      final merged = mergeRetells(
        <RetellRecord>[r('2026-11-01T00:00:00.000Z', 'a')],
        <RetellRecord>[r('2026-11-01T00:00:00.000Z', 'a'), r('2026-11-02T00:00:00.000Z', 'b')],
      );
      expect(merged.map((RetellRecord x) => x.text), <String>['b', 'a']);
      expect(mergeRetells(merged, const <RetellRecord>[], cap: 1), hasLength(1));
    });

    test('答题事件按字段去重，受 cap 约束', () {
      AnswerEvent e(String at, String q, {bool correct = true}) => AnswerEvent(
            at: at,
            day: '2026-11-01',
            articleId: 'x',
            source: PracticeKind.quiz,
            kind: 'choice',
            cat: ActivityCat.vocab,
            correct: correct,
            questionId: q,
          );
      final merged = mergeAnswerEvents(
        <AnswerEvent>[e('2026-11-01T00:00:00.000Z', 'q1')],
        <AnswerEvent>[e('2026-11-01T00:00:00.000Z', 'q1'), e('2026-11-02T00:00:00.000Z', 'q2', correct: false)],
      );
      expect(merged, hasLength(2));
      expect(merged.last.correct, isFalse);
      expect(mergeAnswerEvents(merged, const <AnswerEvent>[], cap: 1), hasLength(1));
    });
  });

  group('计数与派生状态', () {
    test('错题同 id 累加次数，保留更近的一条', () {
      final older = mkMistake(id: 'm1', at: '2026-11-01T00:00:00.000Z', count: 1);
      final newer = mkMistake(id: 'm1', at: '2026-11-02T00:00:00.000Z', count: 2);
      final merged = mergeMistakes(<MistakeEntry>[older], <MistakeEntry>[newer]);
      expect(merged, hasLength(1));
      expect(merged.single.count, 3);
      expect(merged.single.at, newer.at);
    });

    test('错题：同一份备份再导一次不重复计数（字段完全一致的视为重复）', () {
      final m = mkMistake(id: 'm1', at: '2026-11-01T00:00:00.000Z', count: 2);
      final once = mergeMistakes(<MistakeEntry>[], <MistakeEntry>[m]);
      expect(once.single.count, 2);
      expect(mergeMistakes(once, <MistakeEntry>[m]).single.count, 2);
    });

    test('错题：倒序 + 上限', () {
      final list = <MistakeEntry>[
        for (var i = 1; i <= 4; i++)
          mkMistake(id: 'm$i', at: '2026-11-0$i' 'T00:00:00.000Z', count: 1),
      ];
      final merged = mergeMistakes(const <MistakeEntry>[], list, cap: 2);
      expect(merged.map((MistakeEntry m) => m.id), <String>['m4', 'm3']);
    });

    test('每天背过哪些词取并集，不重复计数', () {
      final merged = mergeStudiedDays(
        const <StudiedDay>[StudiedDay(day: '2026-11-01', ids: <String>['a', 'b'])],
        const <StudiedDay>[
          StudiedDay(day: '2026-11-01', ids: <String>['b', 'c']),
          StudiedDay(day: '2026-11-02', ids: <String>['d']),
        ],
      );
      expect(merged, hasLength(2));
      expect(merged.first.ids..sort(), <String>['a', 'b', 'c']);
    });

    test('略读标记取并集', () {
      expect(mergeSkimmed(<String>['a', 'b'], <String>['b', 'c']), <String>['a', 'b', 'c']);
    });

    test('正确率取题数更多的口径（不能把总题数翻倍）', () {
      final current = <String, Map<String, KindStat>>{
        'choice': <String, KindStat>{'meaning': const KindStat(total: 10, correct: 8)},
      };
      final incoming = <String, Map<String, KindStat>>{
        'choice': <String, KindStat>{
          'meaning': const KindStat(total: 4, correct: 4),
          'spelling': const KindStat(total: 3, correct: 1),
        },
      };
      final merged = mergeKindStats(current, incoming);
      expect(merged['choice']!['meaning']!.total, 10);
      expect(merged['choice']!['meaning']!.correct, 8);
      expect(merged['choice']!['spelling']!.total, 3);
    });

    test('读完记录按篇去重（同一篇两天都读过只算一次）', () {
      final merged = mergeLearningData(
        LearningData(readDone: <ReadDone>[
          const ReadDone(day: '2026-11-01', articleId: 'a', title: 'A', at: '2026-11-01T00:00:00.000Z'),
        ]),
        LearningData(readDone: <ReadDone>[
          const ReadDone(day: '2026-11-02', articleId: 'a', title: 'A', at: '2026-11-02T00:00:00.000Z'),
        ]),
      );
      expect(merged.readDone, hasLength(1));
    });
  });

  group('两段原始 JSON', () {
    test('金句进度走强类型合并后写回 JSON（掌握不降级、首次标记两边 OR）', () {
      Map<String, Object?> rec({required String id, required String at, required bool first}) =>
          <String, Object?>{
            'id': id,
            'articleId': 'a',
            'sentenceId': 's1',
            'drillKey': 'k',
            'at': at,
            'fillTries': 1,
            'assembleTries': 1,
            'recallTries': 1,
            'summarySeen': true,
            'fillFirst': first,
            'assembleFirst': first,
            'recallFirst': first,
            'mastered': first,
          };
      final merged = mergeGoldenDrillsJson(
        <Map<String, Object?>>[rec(id: 'a|s1|k', at: '2026-11-01T00:00:00.000Z', first: true)],
        <Map<String, Object?>>[rec(id: 'a|s1|k', at: '2026-11-02T00:00:00.000Z', first: false)],
      );
      expect(merged, hasLength(1));
      expect(merged.single['mastered'], isTrue);
      expect(merged.single['fillFirst'], isTrue);
      expect(merged.single['assembleFirst'], isTrue);
    });

    test('错因复习状态按 key 取更晚更新的那条', () {
      final merged = mergeKeyedProgress(
        <Map<String, Object?>>[
          <String, Object?>{'key': 'k1', 'updatedAt': '2026-11-01T00:00:00.000Z', 'stage': 1},
        ],
        <Map<String, Object?>>[
          <String, Object?>{'key': 'k1', 'updatedAt': '2026-11-03T00:00:00.000Z', 'stage': 3},
          <String, Object?>{'key': 'k2', 'updatedAt': '2026-11-02T00:00:00.000Z', 'stage': 2},
        ],
      );
      expect(merged, hasLength(2));
      expect(merged.firstWhere((Map<String, Object?> m) => m['key'] == 'k1')['stage'], 3);
    });

    test('没有 key 的行直接丢掉（坏数据不污染）', () {
      final merged = mergeKeyedProgress(
        <Map<String, Object?>>[],
        <Map<String, Object?>>[
          <String, Object?>{'key': '', 'updatedAt': '2026-11-01'},
          <String, Object?>{'nokey': 1},
        ],
      );
      expect(merged, isEmpty);
    });
  });

  test('整体合并：12 段都过一遍，可重复导入的段落幂等', () {    final base = LearningData(
      activity: <DayActivity>[const DayActivity(day: '2026-11-01', counts: <ActivityCat, int>{ActivityCat.read: 1})],
      studyDays: const <StudyDay>[StudyDay(day: '2026-11-01', seconds: 60, cards: 10)],
      skimmed: <String>['a'],
      kindStats: <String, Map<String, KindStat>>{
        'choice': <String, KindStat>{'meaning': const KindStat(total: 5, correct: 3)},
      },
    );
    final once = mergeLearningData(emptyLearning(), base);
    final twice = mergeLearningData(once, base);
    expect(twice.skimmed, <String>['a']);
    expect(twice.kindStats['choice']!['meaning']!.total, 5);
    // 活动与背单词按天累加，因此**同一份备份导两次会翻倍** —— 与 Web 版口径一致
    // （两台机器同一天本来就该合起来），不是 bug。
    expect(once.activity.single.countOf(ActivityCat.read), 1);
    expect(twice.activity.single.countOf(ActivityCat.read), 2);
    expect(once.studyDays.single.seconds, 60);
    expect(twice.studyDays.single.seconds, 120);
  });
}
