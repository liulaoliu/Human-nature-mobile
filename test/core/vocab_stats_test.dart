import 'package:dlaoshi_app/core/vocab_stats.dart';
import 'package:dlaoshi_app/models/vocab.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/vocab_fixture.dart';

/// 本地时刻 → ISO（用例里都用本地日期，避免时区把结算日推走）。
String iso(DateTime local) => local.toUtc().toIso8601String();

PickSession pick(DateTime at, int picked, {int seconds = 0}) =>
    PickSession(at: iso(at), seconds: seconds, picked: picked);

VocabItem withDue(String? due) => vocabItem(reviewState: ReviewState(due: due));

VocabSource src(String articleId) => VocabSource(
      articleId: articleId,
      fileName: '$articleId.json',
      sentenceText: '',
    );

void main() {
  group('sessionTotals', () {
    test('累加词数与秒数', () {
      final out = sessionTotals([
        const PickSession(at: 'x', seconds: 10, picked: 3),
        const PickSession(at: 'y', seconds: 5, picked: 2),
      ]);
      expect(out, const SessionTotals(picked: 5, seconds: 15));
    });

    test('空数组为 0', () {
      expect(sessionTotals(const []), const SessionTotals());
    });
  });

  group('studyTotals', () {
    test('累计 / 今日', () {
      final days = [
        const StudyDay(day: '2026-10-04', seconds: 60, cards: 5),
        const StudyDay(day: '2026-10-05', seconds: 30, cards: 2),
      ];
      expect(
        studyTotals(days, todayKey: '2026-10-05'),
        const StudyTotals(totalSeconds: 90, totalCards: 7, todaySeconds: 30),
      );
      // 今天没有记录 → todaySeconds 0
      expect(studyTotals(days, todayKey: '2026-10-09').todaySeconds, 0);
    });
  });

  group('pickDayStats / last7Days', () {
    final now = DateTime(2026, 10, 5, 10);
    final sessions = [
      pick(DateTime(2026, 10, 5, 10), 4),
      pick(DateTime(2026, 10, 4, 10), 6),
      pick(DateTime(2026, 10, 3, 10), 1),
    ];

    test('今日词数 + 连续天数', () {
      expect(pickDayStats(sessions, now: now), const PickDayStats(todayPicked: 4, streak: 3));
    });

    test('今天没选则从昨天起算', () {
      final s = [pick(DateTime(2026, 10, 4, 10), 6)];
      expect(pickDayStats(s, now: now), const PickDayStats(todayPicked: 0, streak: 1));
    });

    test('断链后只数到断点', () {
      final s = [
        pick(DateTime(2026, 10, 5, 10), 1),
        pick(DateTime(2026, 10, 3, 10), 1),
      ];
      expect(pickDayStats(s, now: now).streak, 1);
    });

    test('最近 7 天按日期升序，含今天', () {
      final out = last7Days(sessions, now: now);
      expect(out, hasLength(7));
      expect(out[6].key, '2026-10-05');
      expect(out[6].count, 4);
      expect(out[5].key, '2026-10-04');
      expect(out[0].key, '2026-09-29');
      expect(out[0].label, '29');
    });
  });

  group('dueForecast', () {
    test('未来 N 天到期计数，首日标签「今天」', () {
      final now = DateTime(2026, 10, 5, 10);
      final items = [
        withDue(iso(DateTime(2026, 10, 5, 8))),
        withDue(iso(DateTime(2026, 10, 7, 8))),
        withDue(null),
      ];
      final out = dueForecast(items, now: now, days: 30);
      expect(out, hasLength(30));
      expect(out[0], const DayBar(key: '2026-10-05', label: '今天', count: 1));
      expect(out[2].count, 1);
      expect(out[2].label, '7');
    });

    test('逾期词并入首行「今天」', () {
      final now = DateTime(2026, 10, 5, 10);
      final items = [
        withDue(iso(DateTime(2026, 10, 4, 8))),
        withDue(iso(DateTime(2026, 10, 5, 8))),
      ];
      final out = dueForecast(items, now: now, days: 30);
      expect(out[0], const DayBar(key: '2026-10-05', label: '今天', count: 2));
      expect(out[1].count, 0);
    });

    test('坏 due 字符串忽略，不抛', () {
      final out = dueForecast([withDue('not-a-date')], now: DateTime(2026, 10, 5), days: 2);
      expect(out.map((d) => d.count).toList(), [0, 0]);
    });
  });

  group('wordsByArticle', () {
    test('按来源文章计数，取前 N，同数保持插入顺序', () {
      final items = [
        vocabItem(id: 'a', word: 'a', source: src('X')),
        vocabItem(id: 'b', word: 'b', source: src('X')),
        vocabItem(id: 'c', word: 'c', source: src('Y')),
        vocabItem(id: 'd', word: 'd'),
      ];
      expect(wordsByArticle(items), [
        const ArticleWordCount(articleId: 'X', count: 2),
        const ArticleWordCount(articleId: 'Y', count: 1),
        const ArticleWordCount(articleId: untaggedArticleId, count: 1),
      ]);
      expect(wordsByArticle(items, top: 1), hasLength(1));
      expect(wordsByArticle(items, top: 1).single.articleId, 'X');
    });
  });
}
