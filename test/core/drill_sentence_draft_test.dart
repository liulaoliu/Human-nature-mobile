import 'package:dlaoshi_app/core/drill_sentence.dart';
import 'package:dlaoshi_app/core/drill_sentence_draft.dart';
import 'package:dlaoshi_app/core/writing.dart';
import 'package:flutter_test/flutter_test.dart';

/// 一个作答 + 批改的草稿。
DrillAnswerDraft _draft({String answer = 'hi', bool withFeedback = false}) =>
    DrillAnswerDraft(
      answer: answer,
      feedback: withFeedback
          ? const <String, Object?>{'version': 2, 'total': 80}
          : null,
    );

void main() {
  group('空草稿', () {
    test('空草稿是空的，answerOf 给空作答', () {
      expect(emptyDrillSentenceDraft.isEmpty, isTrue);
      expect(emptyDrillSentenceDraft.answerOf('x').isEmpty, isTrue);
      expect(emptyDrillSentenceDraft.activeIndex, 0);
    });

    test('非 Map / 坏结构一律回空', () {
      expect(normalizeDrillSentenceDraft(null).isEmpty, isTrue);
      expect(normalizeDrillSentenceDraft('oops').isEmpty, isTrue);
      expect(normalizeDrillSentenceDraft(<Object?>[1, 2]).isEmpty, isTrue);
      expect(
        normalizeDrillSentenceDraft(<String, Object?>{'answers': 'nope'}).isEmpty,
        isTrue,
      );
    });
  });

  group('写入与读回', () {
    test('写一条作答能读回来', () {
      final d = emptyDrillSentenceDraft
          .copyWith(batchId: 'drill:memory:abc')
          .withAnswer('t1', _draft(answer: 'I follow up.'));
      expect(d.answers, hasLength(1));
      expect(d.answerOf('t1').answer, 'I follow up.');

      final back = normalizeDrillSentenceDraft(d.toJson());
      expect(back.batchId, 'drill:memory:abc');
      expect(back.answerOf('t1').answer, 'I follow up.');
    });

    test('空的作答会把这一题删掉，不留空壳', () {
      final d = emptyDrillSentenceDraft
          .withAnswer('t1', _draft(answer: 'x'))
          .withAnswer('t1', const DrillAnswerDraft());
      expect(d.answers, isEmpty);
    });

    test('批改跟着题走：写回去再读回来还在', () {
      final d = emptyDrillSentenceDraft
          .withAnswer('t1', _draft(answer: 'x', withFeedback: true));
      final back = normalizeDrillSentenceDraft(d.toJson());
      expect(back.answerOf('t1').feedback?['total'], 80);
    });

    test('多题各存一份，互不覆盖', () {
      final d = emptyDrillSentenceDraft
          .withAnswer('t1', _draft(answer: 'one'))
          .withAnswer('t2', _draft(answer: 'two'));
      expect(d.answers, hasLength(2));
      expect(d.answerOf('t1').answer, 'one');
      expect(d.answerOf('t2').answer, 'two');
    });

    test('activeIndex 记着停在第几题；负数归 0', () {
      final d = emptyDrillSentenceDraft.copyWith(activeIndex: 3);
      expect(normalizeDrillSentenceDraft(d.toJson()).activeIndex, 3);
      expect(
        normalizeDrillSentenceDraft(<String, Object?>{'activeIndex': -2})
            .activeIndex,
        0,
      );
    });

    test('坏键 / 坏值跳过，好的一条留下', () {
      final back = normalizeDrillSentenceDraft(<String, Object?>{
        'batchId': 'b',
        'answers': <Object?, Object?>{
          1: <String, Object?>{'answer': 'numeric key'},
          'ok': <String, Object?>{'answer': 'kept'},
          'bad': 'not a map',
        },
      });
      expect(back.answers, hasLength(1));
      expect(back.answerOf('ok').answer, 'kept');
    });

    test('answer 不是字符串时当空串', () {
      final back = normalizeDrillSentenceDraft(<String, Object?>{
        'answers': <String, Object?>{
          't1': <String, Object?>{'answer': 42},
        },
      });
      expect(back.answerOf('t1').answer, '');
    });
  });

  group('题 id', () {
    test('drillTaskIdOf 取任务上的 focus', () {
      const task = ImitationTask(task: '写一句', focus: 'drill:memory:x');
      expect(drillTaskIdOf(task), 'drill:memory:x');
      expect(drillTaskIdOf(const ImitationTask(task: '写一句')), '');
    });

    test('从记录反查题 id', () {
      const task = ImitationTask(task: '写一句', focus: 'drill:chunk:y');
      final rec = WritingRecord(
        at: '2026-11-09T00:00:00.000Z',
        articleId: 'manual',
        text: 'x',
        feedback: const WritingFeedback(),
        task: task,
      );
      expect(drillTaskIdOfRecord(rec), 'drill:chunk:y');
    });

    test('记录没有任务时给空串', () {
      final rec = WritingRecord(
        at: '2026-11-09T00:00:00.000Z',
        articleId: 'manual',
        text: 'x',
        feedback: const WritingFeedback(),
      );
      expect(drillTaskIdOfRecord(rec), '');
    });
  });

  group('与造句素材接得上', () {
    test('每个点各一道题，题 id（focus）就是草稿的键', () {
      const points = <DrillSentencePoint>[
        DrillSentencePoint(id: 'p1', itemId: 'v1', en: 'follow up'),
        DrillSentencePoint(id: 'p2', itemId: 'v2', en: 'set aside'),
      ];
      final tasks = buildDrillSentenceTasks(DrillSentenceKind.chunk, points);
      expect(tasks, hasLength(2));
      // focus 是「一个点算出来的批改身份」，不是素材 id：同一句内容永远同一条。
      expect(tasks.first.focus, drillSentenceId(DrillSentenceKind.chunk,
          <DrillSentencePoint>[points.first]));
      expect(tasks.first.mustUse, <String>['follow up']);
      expect(tasks.last.mustUse, <String>['set aside']);

      // 草稿按这个 focus 存，能一一对上。
      final draft = emptyDrillSentenceDraft.withAnswer(
        drillTaskIdOf(tasks.first),
        _draft(answer: 'I will follow up with him.'),
      );
      expect(draft.answerOf(drillTaskIdOf(tasks.last)).isEmpty, isTrue);
      expect(draft.answerOf(drillTaskIdOf(tasks.first)).answer,
          'I will follow up with him.');
    });
  });
}
