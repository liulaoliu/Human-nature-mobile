import 'package:dlaoshi_app/core/activity/activity.dart' show dayKeyLocal;
import 'package:dlaoshi_app/core/golden.dart';
import 'package:dlaoshi_app/core/golden_progress.dart';
import 'package:dlaoshi_app/models/document.dart';
import 'package:flutter_test/flutter_test.dart';

Sentence _s(
  String id,
  String text, {
  String? translation,
  SentenceLanguage? language,
}) =>
    Sentence(
      id: id,
      paraId: 'p01',
      text: text,
      translation: translation,
      language: language,
    );

final Sentence _sentence = _s(
  's1',
  'Team spirit is one of the main factors.',
  translation: '团队精神是主要因素之一。',
  language: const SentenceLanguage(
    phrases: <String>['team spirit — 团队精神'],
  ),
);

GoldenDrillRecord _record() => emptyGoldenRecord(
      'a1',
      '文章',
      's1',
      goldenDrillKey(
        _sentence.text,
        buildLocalGoldenLesson(<Sentence>[_sentence]).sentences.first.targets,
      ),
      '2026-10-27T00:00:00.000Z',
    );

void main() {
  group('金句进度', () {
    test('首次答错后重试不会改回「首次正确」；三步 + 小结才算掌握', () {
      var r = _record();
      r = recordGoldenStep(r, GoldenStep.fill, false, '2026-10-27T00:01:00.000Z');
      r = recordGoldenStep(r, GoldenStep.fill, true, '2026-10-27T00:02:00.000Z');
      expect(r.fillFirst, isFalse);
      expect(r.fillTries, 2);
      r = recordGoldenStep(r, GoldenStep.assemble, true, '2026-10-27T00:03:00.000Z');
      expect(goldenMastered(r), isFalse);
      r = recordGoldenStep(r, GoldenStep.summary, true, '2026-10-27T00:04:00.000Z');
      r = recordGoldenStep(r, GoldenStep.recall, true, '2026-10-27T00:05:00.000Z');
      expect(goldenCompleted(r), isTrue);
      expect(goldenMastered(r), isFalse);
    });

    test('三步首答全对 + 看过小结 = 掌握，完成时间取最后一步', () {
      var r = _record();
      r = recordGoldenStep(r, GoldenStep.fill, true, '2026-10-27T00:01:00.000Z');
      r = recordGoldenStep(r, GoldenStep.assemble, true, '2026-10-27T00:02:00.000Z');
      r = recordGoldenStep(r, GoldenStep.summary, true, '2026-10-27T00:03:00.000Z');
      r = recordGoldenStep(r, GoldenStep.recall, true, '2026-10-27T00:04:00.000Z');
      expect(goldenMastered(r), isTrue);
      expect(r.completedAt, '2026-10-27T00:04:00.000Z');
    });

    test('坏记录逐条丢弃；同 id 合并保留已掌握', () {
      final good = _record();
      final out = normalizeGoldenDrills(<Object?>[
        good.toJson(),
        <String, Object?>{...good.toJson(), 'id': 'bad', 'at': 'not-a-date'},
        <String, Object?>{'foo': 1},
        null,
        'nope',
      ]);
      expect(out, hasLength(1));

      final mastered = good.copyWith(
        mastered: true,
        fillFirst: () => true,
        assembleFirst: () => true,
        recallFirst: () => true,
        summarySeen: () => true,
      );
      final merged = mergeGoldenDrills(<GoldenDrillRecord>[mastered], <GoldenDrillRecord>[good]);
      expect(merged, hasLength(1));
      expect(merged.first.mastered, isTrue);
      expect(merged.first.id, goldenRecordId('a1', 's1', good.drillKey));
    });

    test('再练一次清空首次记录，但已掌握 / 完成时间不降级', () {
      final base = _record().copyWith(
        mastered: true,
        completedAt: () => '2026-10-27T00:04:00.000Z',
        fillFirst: () => true,
        assembleFirst: () => true,
        recallFirst: () => true,
        summarySeen: () => true,
        fillTries: 2,
      );
      final reset = resetGoldenRecord(base, '2026-10-28T00:00:00.000Z');
      expect(reset.mastered, isTrue);
      expect(reset.completedAt, base.completedAt);
      expect(reset.fillTries, 0);
      expect(reset.fillFirst, isNull);
      expect(reset.summarySeen, isFalse);
      expect(reset.at, '2026-10-28T00:00:00.000Z');
    });

    test('待回顾只看已掌握且今天还没回顾', () {
      final today = dayKeyLocal(DateTime(2026, 9, 27, 12));
      final mastered = _record().copyWith(mastered: true);
      expect(
        goldenReviewDue(
          mastered.copyWith(at: DateTime(2026, 9, 26, 12).toIso8601String()),
          today,
        ),
        isTrue,
      );
      expect(
        goldenReviewDue(
          mastered.copyWith(at: DateTime(2026, 9, 27, 12).toIso8601String()),
          today,
        ),
        isFalse,
      );
      expect(
        goldenReviewDue(
          mastered.copyWith(
            mastered: false,
            at: DateTime(2026, 9, 26, 12).toIso8601String(),
          ),
          today,
        ),
        isFalse,
      );
      expect(goldenReviewDue(mastered.copyWith(at: 'bad-date'), today), isFalse);
      expect(goldenReviewDue(null, today), isFalse);
    });

    test('待回顾队列按课文顺序，只留本课到期句', () {
      final today = dayKeyLocal(DateTime(2026, 9, 27, 12));
      final old = DateTime(2026, 9, 26, 12).toIso8601String();
      final r1 = _record().copyWith(id: 'r1', sentenceId: 's1', mastered: true, at: old);
      final r2 = _record().copyWith(
        id: 'r2',
        sentenceId: 's2',
        mastered: true,
        at: DateTime(2026, 9, 27, 12).toIso8601String(),
      );
      final r3 = _record().copyWith(
        id: 'r3',
        sentenceId: 's3',
        mastered: true,
        at: old,
        articleId: 'a2',
      );
      expect(
        goldenReviewSentenceIds(
          <GoldenDrillRecord>[r1, r2, r3],
          'a1',
          <String>['s2', 's1', 's404'],
          today,
        ),
        <String>['s1'],
      );
    });

    test('统计默认按句独立；去重开关只影响计数', () {
      final lesson = buildLocalGoldenLesson(
        <Sentence>[_sentence],
        null,
        const LocalGoldenOptions(selected: <String>['s1']),
      );
      final rec = _record().copyWith(
        mastered: true,
        fillFirst: () => true,
        assembleFirst: () => true,
        recallFirst: () => true,
        summarySeen: () => true,
      );
      final summary = summarizeGolden(
        lesson,
        <GoldenTextMeta>[GoldenTextMeta(id: 's1', text: _sentence.text)],
        <GoldenDrillRecord>[rec],
        'a1',
      );
      expect(summary.selectedSentences, 1);
      expect(summary.masteredSentences, 1);
      expect(summary.totalTargets, lesson.sentences.first.targets.length);
      expect(summary.masteredTargets, summary.totalTargets);
      expect(summary.byKind, isNotEmpty);

      final deduped = summarizeGolden(
        lesson.copyWith(options: const GoldenLessonOptions(dedupe: true)),
        <GoldenTextMeta>[GoldenTextMeta(id: 's1', text: _sentence.text)],
        <GoldenDrillRecord>[rec],
        'a1',
      );
      expect(deduped.selectedSentences, 1);
    });

    test('按段落统计只在 outline 里找得到段落时计入', () {
      final s1 = _s('s1', 'Team spirit is one of the main factors.');
      final s2 = _s('s2', 'The board considers the budget tomorrow.');
      final lesson = buildLocalGoldenLesson(
        <Sentence>[s1, s2],
        <Paragraph>[
          const Paragraph(id: 'p01', sentenceIds: <String>['s1']),
          const Paragraph(id: 'p02', sentenceIds: <String>['s2']),
        ],
        const LocalGoldenOptions(selected: <String>['s1', 's2']),
      );
      final summary = summarizeGolden(
        lesson,
        <GoldenTextMeta>[
          GoldenTextMeta(id: 's1', text: s1.text),
          GoldenTextMeta(id: 's2', text: s2.text),
        ],
        const <GoldenDrillRecord>[],
        'a1',
        <Paragraph>[
          const Paragraph(id: 'p01', sentenceIds: <String>['s1']),
          const Paragraph(id: 'p02', sentenceIds: <String>['s2']),
        ],
      );
      expect(summary.selectedSentences, 2);
      expect(summary.masteredSentences, 0);
      expect(summary.masteredTargets, 0);
      for (final row in summary.bySection) {
        expect(row.mastered, 0);
        expect(row.total, greaterThan(0));
      }
    });

    test('findGoldenRecord 按稳定 id 找，找不到返 null', () {
      final rec = _record();
      expect(findGoldenRecord(<GoldenDrillRecord>[rec], 'a1', 's1', rec.drillKey), same(rec));
      expect(findGoldenRecord(<GoldenDrillRecord>[rec], 'a2', 's1', rec.drillKey), isNull);
      expect(findGoldenRecord(const <GoldenDrillRecord>[], 'a1', 's1', rec.drillKey), isNull);
    });

    test('normalizeGoldenDrills 的 mastered 以实际步骤为准', () {
      //  存档里写 mastered: true，但三步首次根本没全对 → 应该被降回 false。
      final rec = _record().toJson();
      final out = normalizeGoldenDrills(<Object?>[
        <String, Object?>{...rec, 'mastered': true, 'fillFirst': true},
      ]);
      expect(out.single.mastered, isFalse);
    });

    test('mergeGoldenDrills 取各步最大次数并合并首次对错', () {
      final a = _record().copyWith(
        at: '2026-10-27T00:01:00.000Z',
        fillTries: 3,
        fillFirst: () => true,
      );
      final b = _record().copyWith(
        at: '2026-10-27T00:02:00.000Z',
        fillTries: 1,
        assembleTries: 2,
        assembleFirst: () => true,
      );
      final merged = mergeGoldenDrills(<GoldenDrillRecord>[a], <GoldenDrillRecord>[b]).single;
      expect(merged.fillTries, 3);
      expect(merged.assembleTries, 2);
      expect(merged.fillFirst, isTrue);
      expect(merged.assembleFirst, isTrue);
      expect(merged.at, '2026-10-27T00:02:00.000Z');
    });
  });
}
