import 'package:flutter_test/flutter_test.dart';

import 'package:dlaoshi_app/core/vocab/review.dart';
import 'package:dlaoshi_app/core/vocab/study_card.dart';
import 'package:dlaoshi_app/models/vocab.dart';

VocabItem mkWord(
  String word, {
  ReviewState? reviewState,
  List<String> tags = const [],
  String? priorityUntil,
}) =>
    VocabItem(
      id: 'item-$word',
      word: word,
      lemma: word,
      reviewState: reviewState ?? const ReviewState(),
      tags: tags,
      priorityUntil: priorityUntil,
      createdAt: '2026-11-01T00:00:00.000Z',
      updatedAt: '2026-11-01T00:00:00.000Z',
    );

void main() {
  group('热度', () {
    test('越停越热：0 / 12 / 30 / 阈值 / 90', () {
      expect(cardHeat(seconds: 0, drillAfter: 60), 0);
      expect(cardHeat(seconds: 11, drillAfter: 60), 0);
      expect(cardHeat(seconds: 12, drillAfter: 60), 1);
      expect(cardHeat(seconds: 29, drillAfter: 60), 1);
      expect(cardHeat(seconds: 30, drillAfter: 60), 2);
      expect(cardHeat(seconds: 59, drillAfter: 60), 2);
      expect(cardHeat(seconds: 60, drillAfter: 60), 3);
      expect(cardHeat(seconds: 89, drillAfter: 60), 3);
      expect(cardHeat(seconds: 90, drillAfter: 60), 4);
    });

    test('关了锤炼（drillAfter = 0）：只剩 30 / 90 两档，不会因为阈值为 0 直接变红', () {
      expect(cardHeat(seconds: 5, drillAfter: 0), 0);
      expect(cardHeat(seconds: 40, drillAfter: 0), 2);
      expect(cardHeat(seconds: 120, drillAfter: 0), 4);
    });

    test('阈值比 90 还大：90 秒仍然是 4（先看 90，再看阈值）', () {
      expect(cardHeat(seconds: 90, drillAfter: 120), 4);
      expect(cardHeat(seconds: 100, drillAfter: 120), 4);
      expect(cardHeat(seconds: 119, drillAfter: 120), 4);
    });
  });

  test('计时文案：25 秒起提醒别墨迹', () {
    expect(cardTimerLabel(0), '0s');
    expect(cardTimerLabel(24), '24s');
    expect(cardTimerLabel(25), '25s · 别墨迹');
    expect(cardTimerLabel(95), '95s · 别墨迹');
  });

  group('fmtDue', () {
    final now = DateTime.utc(2026, 11, 11, 8);

    test('没排期 / 坏字符串 → 空串', () {
      expect(fmtDue(null, now: now), '');
      expect(fmtDue('', now: now), '');
      expect(fmtDue('不是时间', now: now), '');
    });

    test('已经过期 → 现在', () {
      expect(fmtDue(now.subtract(const Duration(days: 3)).toIso8601String(), now: now), '现在');
    });

    test('差几小时也算 1 天 → 明天（向上取整，与 Web 同口径）', () {
      expect(fmtDue(now.add(const Duration(hours: 3)).toIso8601String(), now: now), '明天');
    });

    test('一天半 → 2 天后', () {
      expect(fmtDue(now.add(const Duration(hours: 36)).toIso8601String(), now: now), '2 天后');
    });
  });

  group('SRS 行', () {
    final now = DateTime.utc(2026, 11, 11, 8);

    test('新词：复习 0 次 + 还没排期，没有「忘记」那一段', () {
      final line = cardSrsLine(card: mkWord('introvert'), now: now);
      expect(line, '复习 0 次 · 还没排期');
      expect(line.contains('忘记'), isFalse);
    });

    test('忘记过：带上次数与到期日', () {
      final card = mkWord(
        'introvert',
        reviewState: ReviewState(
          repetitions: 3,
          lapses: 2,
          interval: 6,
          due: now.add(const Duration(days: 1)).toIso8601String(),
        ),
      );
      final line = cardSrsLine(card: card, now: now);
      expect(line.startsWith('复习 3 次 · 忘记 2 次 · 下次 明天'), isTrue);
    });

    test('可以评分且不是复习模式：给三档「预计下次」', () {
      final line = cardSrsLine(card: mkWord('introvert'), gradeable: true, now: now);
      expect(line.contains('预计下次：认识'), isTrue);
      expect(line.contains('/ 模糊'), isTrue);
      expect(line.contains('/ 忘记了'), isTrue);
    });

    test('复习模式 / 不可评分：不给「预计下次」（那套三键判定是另一条路）', () {
      expect(
        cardSrsLine(card: mkWord('introvert'), gradeable: true, reviewMode: true, now: now)
            .contains('预计下次'),
        isFalse,
      );
      expect(cardSrsLine(card: mkWord('introvert'), now: now).contains('预计下次'), isFalse);
    });

    test('标记：优先重练 / 重学中 / 标为不认识', () {
      final card = mkWord(
        'introvert',
        tags: const [spellingMissTag],
        priorityUntil: now.add(const Duration(days: 2)).toIso8601String(),
        reviewState: const ReviewState(relearn: 2),
      );
      final line = cardSrsLine(card: card, relearning: true, now: now);
      expect(line.contains('🔥 优先重练'), isTrue);
      expect(line.contains('♻️ 重学中'), isTrue);
      expect(line.contains('🆕 标为不认识'), isTrue);
    });
  });
}
