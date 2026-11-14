import 'package:dlaoshi_app/core/activity/activity.dart';
import 'package:dlaoshi_app/core/answer_events.dart';
import 'package:dlaoshi_app/core/kind_stats.dart';
import 'package:dlaoshi_app/core/practice.dart';
import 'package:dlaoshi_app/core/quiz.dart' show QuizKind;
import 'package:flutter_test/flutter_test.dart';

AnswerEvent ev({
  String at = '2026-10-20T10:00:00.000Z',
  String day = '2026-10-20',
  String articleId = 'art-A',
  PracticeKind source = PracticeKind.quiz,
  String kind = 'cloze',
  ActivityCat cat = ActivityCat.vocab,
  bool correct = true,
  String? questionId,
}) =>
    AnswerEvent(
      at: at,
      day: day,
      articleId: articleId,
      source: source,
      kind: kind,
      cat: cat,
      correct: correct,
      questionId: questionId,
    );

Map<String, Object?> json(AnswerEvent e) => {
      'at': e.at,
      'day': e.day,
      'articleId': e.articleId,
      'source': e.source.name,
      'kind': e.kind,
      'cat': e.cat.name,
      'correct': e.correct,
      if (e.questionId != null) 'questionId': e.questionId,
    };

void main() {
  group('normalizeAnswerEvents', () {
    test('保留合法事件，坏条目丢弃', () {
      final out = normalizeAnswerEvents([
        json(ev()),
        json(ev(correct: false, questionId: 'q1')),
        null,
        'x',
        json(ev(at: 'not-a-date')),
        {...json(ev()), 'source': 'unknown'},
        json(ev(kind: '  ')),
        {...json(ev()), 'cat': 'dance'},
        {...json(ev()), 'correct': 'yes'},
      ]);
      expect(out, hasLength(2));
      expect(out[1].correct, isFalse);
      expect(out[1].questionId, 'q1');
    });

    test('非数组原样丢弃；缺 articleId 补空串', () {
      expect(normalizeAnswerEvents(null), isEmpty);
      expect(normalizeAnswerEvents(<String, Object?>{}), isEmpty);
      final row = json(ev())..remove('articleId');
      expect(normalizeAnswerEvents([row]).single.articleId, '');
    });

    test('questionId 为空串时不写', () {
      expect(normalizeAnswerEvents([json(ev(questionId: ''))]).single.questionId, isNull);
    });

    test('day 缺失时按 at 现算', () {
      final row = json(ev(day: ''))..remove('day');
      expect(normalizeAnswerEvents([row]).single.day, isNotEmpty);
    });
  });

  group('createAnswerEvent', () {
    test('没给时间就用 now；给了就原样保留', () {
      final now = DateTime.utc(2026, 10, 20, 12, 34, 56);
      final filled = createAnswerEvent(ev(at: '', day: ''), now: now);
      expect(filled.at, now.toIso8601String());
      expect(filled.day, '2026-10-20');

      final kept = createAnswerEvent(ev(at: '2026-01-01T00:00:00.000Z', day: ''));
      expect(kept.at, '2026-01-01T00:00:00.000Z');
      expect(kept.day, '2026-01-01');
    });
  });

  group('addAnswerEvent', () {
    test('追加并保留最近 cap 条', () {
      final list = [for (var i = 0; i < 3; i++) ev(questionId: 'q$i')];
      final out = addAnswerEvent(list, ev(questionId: 'q3'), cap: 3);
      expect(out.map((e) => e.questionId).toList(), ['q1', 'q2', 'q3']);
    });

    test('默认上限是 answerEventCap', () {
      final list = [for (var i = 0; i < answerEventCap; i++) ev(questionId: 'q$i')];
      final out = addAnswerEvent(list, ev(questionId: 'last'));
      expect(out, hasLength(answerEventCap));
      expect(out.last.questionId, 'last');
      expect(out.first.questionId, 'q1');
    });
  });

  group('answerEventsToKindStats', () {
    test('只统计考试题，按文章 + 题型累计', () {
      final stats = answerEventsToKindStats([
        ev(kind: 'cloze'),
        ev(kind: 'cloze', correct: false),
        ev(kind: 'spell'),
        ev(source: PracticeKind.dictation, kind: 'dictation', cat: ActivityCat.listen),
        ev(articleId: '', kind: 'usage'),
      ]);
      expect(stats.keys.toList(), ['art-A']);
      expect(stats['art-A']!['cloze'], const KindStat(total: 2, correct: 1));
      expect(stats['art-A']!['spell'], const KindStat(total: 1, correct: 1));
      expect(stats['art-A']!.containsKey('dictation'), isFalse);
    });
  });

  group('answerEventsToActivity', () {
    test('按本地结算日累计分类，同一天合并', () {
      final out = answerEventsToActivity([
        ev(at: '2026-10-20T10:00:00', cat: ActivityCat.vocab),
        ev(at: '2026-10-20T11:00:00', cat: ActivityCat.vocab),
        ev(at: '2026-10-20T12:00:00', cat: ActivityCat.read),
        ev(at: '2026-10-19T12:00:00', day: '2026-10-19', cat: ActivityCat.listen),
      ]);
      expect(out, hasLength(2));
      expect(out[0].day, '2026-10-19');
      expect(out[0].countOf(ActivityCat.listen), 1);
      expect(out[1].day, '2026-10-20');
      expect(out[1].countOf(ActivityCat.vocab), 2);
      expect(out[1].countOf(ActivityCat.read), 1);
    });

    test('凌晨 4 点前算前一天（与 dayKeyLocal 一致）', () {
      final out = answerEventsToActivity([ev(at: '2026-10-20T02:00:00', day: '2026-10-19')]);
      expect(out.single.day, '2026-10-19');
    });
  });

  group('quizActivityCat：考试题的活动分类', () {
    test('文章级题算「读」', () {
      for (final k in [QuizKind.translate, QuizKind.translate2, QuizKind.functionWord, QuizKind.ordering, QuizKind.grammar, QuizKind.phraseBlank]) {
        expect(quizActivityCat(k), ActivityCat.read, reason: k.name);
      }
    });

    test('听音 / 听音拼词算「听」', () {
      expect(quizActivityCat(QuizKind.listen), ActivityCat.listen);
      expect(quizActivityCat(QuizKind.ear), ActivityCat.listen);
    });

    test('其余词级题算「词」', () {
      for (final k in [QuizKind.spell, QuizKind.cloze, QuizKind.usage, QuizKind.choice, QuizKind.meaning, QuizKind.define, QuizKind.mark, QuizKind.idiom]) {
        expect(quizActivityCat(k), ActivityCat.vocab, reason: k.name);
      }
    });
  });
}
