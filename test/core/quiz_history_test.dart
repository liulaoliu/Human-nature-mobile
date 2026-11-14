// 考试历史：序列化往返、坏数据逐条丢弃、上限、日期分组。
import 'package:flutter_test/flutter_test.dart';

import 'package:dlaoshi_app/core/quiz.dart' show QuizKind;
import 'package:dlaoshi_app/core/quiz_history.dart';
import 'package:dlaoshi_app/core/quiz_pool.dart' show QuizMode;

QuizRoundRow _round({
  String at = '2026-11-14T10:00:00.000Z',
  QuizMode mode = QuizMode.vocab,
  int total = 3,
  int correct = 2,
  int seconds = 42,
  String? articleId,
  String articleTitle = '',
  List<QuizAnswerRow> entries = const <QuizAnswerRow>[],
}) =>
    QuizRoundRow(
      at: at,
      mode: mode,
      total: total,
      correct: correct,
      seconds: seconds,
      articleId: articleId,
      articleTitle: articleTitle,
      entries: entries,
    );

void main() {
  group('摘要', () {
    test('正确率与一行摘要', () {
      final r = _round(total: 3, correct: 2);
      expect(r.accuracy, closeTo(2 / 3, 1e-9));
      expect(r.summary, '3 题 · 对 2 · 67%');
    });

    test('total 为 0 不除零', () {
      expect(_round(total: 0, correct: 0).accuracy, 0);
    });

    test('明细的题型有中文名', () {
      const row = QuizAnswerRow(
        word: 'alpha',
        kind: QuizKind.spell,
        correct: true,
        answer: 'alpha',
      );
      expect(row.kindLabel, '拼写');
    });
  });

  group('序列化往返', () {
    test('一轮带明细存了再读回来一模一样', () {
      final r = _round(
        mode: QuizMode.article,
        articleId: 'a1',
        articleTitle: 'Growth',
        entries: const [
          QuizAnswerRow(
            word: 'alpha',
            kind: QuizKind.spell,
            correct: true,
            answer: 'alpha',
            input: 'alpha',
          ),
          QuizAnswerRow(
            word: 'bravo',
            kind: QuizKind.translate,
            correct: false,
            answer: '喝彩',
            input: '勇敢',
          ),
        ],
      );
      final back = parseQuizHistoryPayload(quizHistoryToJson([r]));
      expect(back, hasLength(1));
      final b = back.single;
      expect(b.at, r.at);
      expect(b.mode, QuizMode.article);
      expect(b.articleId, 'a1');
      expect(b.articleTitle, 'Growth');
      expect(b.total, 3);
      expect(b.correct, 2);
      expect(b.seconds, 42);
      expect(b.entries, hasLength(2));
      expect(b.entries.first.word, 'alpha');
      expect(b.entries.first.correct, isTrue);
      expect(b.entries.last.kind, QuizKind.translate);
      expect(b.entries.last.input, '勇敢');
    });

    test('直接给一个 List 也认（旧格式兼容）', () {
      final raw = [for (final r in [_round()]) r.toJson()];
      expect(parseQuizHistoryPayload(raw), hasLength(1));
    });
  });

  group('坏数据', () {
    test('不是 List / Map → 空历史', () {
      for (final bad in <Object?>[null, '', 42, <String>['x']]) {
        expect(parseQuizHistoryPayload(bad), isEmpty);
      }
    });

    test('坏轮次整条丢，好的留着', () {
      final rows = parseQuizHistory(<Object?>[
        <String, Object?>{'at': '2026-11-14T10:00:00.000Z', 'total': 3, 'correct': 2},
        <String, Object?>{'total': 3}, // 没时间 → 丢
        'not-a-map',
        <String, Object?>{'at': '2026-11-13T10:00:00.000Z', 'total': 1, 'correct': 1},
      ]);
      expect(rows, hasLength(2));
      expect(rows.first.at, '2026-11-14T10:00:00.000Z');
    });

    test('明细里坏的只丢那一条', () {
      final rows = parseQuizHistory(<Object?>[
        <String, Object?>{
          'at': '2026-11-14T10:00:00.000Z',
          'total': 2,
          'correct': 1,
          'entries': [
            {'word': 'alpha', 'kind': 'spell', 'correct': true},
            {'word': 'bravo', 'kind': 'not-a-kind'},
            {'kind': 'spell'},
            'nope',
          ],
        },
      ]);
      expect(rows.single.entries, hasLength(1));
      expect(rows.single.entries.single.word, 'alpha');
    });

    test('明细缺 input / answer 也读得出来', () {
      final rows = parseQuizHistory(<Object?>[
        <String, Object?>{
          'at': '2026-11-14T10:00:00.000Z',
          'total': 1,
          'correct': 0,
          'entries': [
            {'word': 'alpha', 'kind': 'spell', 'correct': false},
          ],
        },
      ]);
      expect(rows.single.entries.single.input, '');
      expect(rows.single.entries.single.answer, '');
    });
  });

  group('上限', () {
    test('追加：新的在前，超过 cap 丢最旧的', () {
      var rows = const <QuizRoundRow>[];
      for (var i = 0; i < 5; i++) {
        rows = addQuizRound(rows, _round(at: '2026-11-1${i}T00:00:00.000Z'), cap: 3);
      }
      expect(rows, hasLength(3));
      expect(rows.first.at, '2026-11-14T00:00:00.000Z');
      expect(rows.last.at, '2026-11-12T00:00:00.000Z');
    });

    test('解析时超上限只留前 maxQuizHistoryRounds 条', () {
      final raw = <Object?>[
        for (var i = 0; i < maxQuizHistoryRounds + 10; i++)
          <String, Object?>{
            'at': '2026-11-14T10:00:00.000Z',
            'total': 1,
            'correct': 1,
          },
      ];
      expect(parseQuizHistory(raw), hasLength(maxQuizHistoryRounds));
    });

    test('单轮明细超上限截断', () {
      final raw = <Object?>[
        <String, Object?>{
          'at': '2026-11-14T10:00:00.000Z',
          'total': 100,
          'correct': 100,
          'entries': [
            for (var i = 0; i < maxQuizHistoryEntries + 5; i++)
              {'word': 'w$i', 'kind': 'spell', 'correct': true},
          ],
        },
      ];
      expect(
        parseQuizHistory(raw).single.entries,
        hasLength(maxQuizHistoryEntries),
      );
    });
  });

  group('日期分组', () {
    test('按本地日给 key', () {
      final iso = DateTime(2026, 11, 14, 9, 30).toUtc().toIso8601String();
      expect(quizHistoryDayKey(iso), '2026-11-14');
    });

    test('坏时间回空串', () {
      expect(quizHistoryDayKey('not-a-date'), '');
    });
  });
}
