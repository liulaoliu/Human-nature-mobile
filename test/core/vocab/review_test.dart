import 'package:dlaoshi_app/core/vocab/library.dart';
import 'package:dlaoshi_app/core/vocab/review.dart';
import 'package:dlaoshi_app/models/vocab.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/vocab_fixture.dart';

final now = DateTime.parse('2026-10-02T00:00:00.000Z');

ReviewState rs({
  double ease = 2.5,
  String? due,
  int interval = 0,
  int repetitions = 0,
  int lapses = 0,
  int relearn = 0,
}) =>
    ReviewState(
      ease: ease,
      due: due,
      interval: interval,
      repetitions: repetitions,
      lapses: lapses,
      relearn: relearn,
    );

VocabItem item({
  String id = 'v1',
  String? lemma,
  String? meaning,
  String? partOfSpeech,
  List<String> tags = const [],
  ReviewState? reviewState,
  String createdAt = '2026-01-01T00:00:00.000Z',
}) =>
    vocabItem(
      id: id,
      word: lemma ?? id,
      lemma: lemma ?? id,
      meaning: meaning,
      partOfSpeech: partOfSpeech,
      tags: tags,
      reviewState: reviewState ?? rs(),
      createdAt: createdAt,
    );

void main() {
  group('复习排期（SM-2 变体）', () {
    test('第一次 good：1 天后', () {
      final r = review(rs(), ReviewGrade.good, now);
      expect(r.repetitions, 1);
      expect(r.interval, 1);
      expect(r.due, '2026-10-03T00:00:00.000Z');
    });

    test('第二次 good：6 天后', () {
      final r = review(rs(interval: 1, repetitions: 1), ReviewGrade.good, now);
      expect(r.interval, 6);
    });

    test('第三次 good：interval × ease', () {
      final r = review(rs(interval: 6, repetitions: 2), ReviewGrade.good, now);
      expect(r.interval, 15);
    });

    test('easy 提高 ease', () {
      final r = review(rs(), ReviewGrade.easy, now);
      expect(r.ease, closeTo(2.6, 1e-9));
    });

    test('again 重来：repetitions 归零、间隔 1 天、ease 下降', () {
      final r = review(rs(interval: 15, repetitions: 3), ReviewGrade.again, now);
      expect(r.repetitions, 0);
      expect(r.interval, 1);
      expect(r.ease, closeTo(2.3, 1e-9));
    });

    test('ease 下限 1.3', () {
      final r = review(rs(ease: 1.3, interval: 1, repetitions: 1), ReviewGrade.again, now);
      expect(r.ease, 1.3);
    });

    test('reviewItem 写回词条', () {
      final lib = createLibrary();
      final withItem = lib.copyWith(items: [item(lemma: 'run')]);
      final out = reviewItem(withItem, 'v1', ReviewGrade.good, now);
      expect(out.items.single.reviewState.repetitions, 1);
      expect(out.items.single.updatedAt, now.toUtc().toIso8601String());
    });

    test('isDue / dueItems', () {
      final due = item(id: 'd', lemma: 'due', reviewState: rs(due: '2026-09-01T00:00:00.000Z', interval: 1, repetitions: 1));
      final future = item(id: 'e', lemma: 'future', reviewState: rs(due: '2027-01-01T00:00:00.000Z', interval: 1, repetitions: 1));
      expect(isDue(due, now), isTrue);
      expect(isDue(future, now), isFalse);
      expect(dueItems([future, due], now).map((x) => x.lemma), ['due']);
    });
  });

  group('出错加权（lapses）', () {
    test('评「忘记」累计 lapses，其它评分保持', () {
      final base = rs(interval: 1, repetitions: 1, lapses: 2);
      expect(review(base, ReviewGrade.again, now).lapses, 3);
      expect(review(base, ReviewGrade.good, now).lapses, 2);
    });

    test('老数据没有 lapses 时按 0 起算', () {
      expect(review(rs(interval: 1, repetitions: 1), ReviewGrade.again, now).lapses, 1);
    });
  });

  group('不认识 → 复习/加练先选释义', () {
    test('没标过「不认识」不触发', () {
      expect(needsMeaningCheck(item(tags: const [])), isFalse);
      expect(
        needsMeaningCheck(item(tags: const [], reviewState: rs(lapses: 1))),
        isFalse,
      );
    });

    test('标过「不认识」且记忆未重建 → 复习要选释义', () {
      expect(needsMeaningCheck(item(tags: const [spellingMissTag])), isTrue);
    });

    test('已经评过认识/模糊（repetitions > 0）→ 普通复习不再强制', () {
      final learned = item(tags: const [spellingMissTag], reviewState: rs(repetitions: 1));
      expect(needsMeaningCheck(learned), isFalse);
    });

    test('本轮加练 / 收尾重练 → 即使 repetitions > 0 也要选', () {
      final learned = item(tags: const [spellingMissTag], reviewState: rs(repetitions: 1));
      expect(needsMeaningCheck(learned, extra: true), isTrue);
      expect(needsMeaningCheck(learned, retrying: true), isTrue);
    });

    test('词库够 4 个释义才出题；不够就退回普通卡片', () {
      final target = item(id: 'a', meaning: '跑');
      final others = ['走', '说', '看']
          .asMap()
          .entries
          .map((e) => item(id: 'o${e.key}', meaning: e.value))
          .toList();
      expect(canQuizMeaning(target, [target, ...others]), isTrue);
      expect(canQuizMeaning(target, [target, ...others.take(2)]), isFalse);
      expect(canQuizMeaning(item(id: 'n'), [target, ...others]), isFalse);
    });
  });

  group('优先重排（答错 → 次日排最前）', () {
    VocabItem due(String id) => item(
          id: id,
          lemma: id,
          reviewState: rs(due: '2026-10-02T00:00:00Z', interval: 3, repetitions: 2),
        );

    test('prioritizeItems 只标记指定词条', () {
      final lib = VocabLibrary(items: [due('a'), due('b')]);
      final out = prioritizeItems(lib, ['a'], nextDayIso(now));
      expect(
        out.items.firstWhere((x) => x.id == 'a').priorityUntil,
        '2026-10-03T00:00:00.000Z',
      );
      expect(out.items.firstWhere((x) => x.id == 'b').priorityUntil, isNull);
    });

    test('isPriority 未过期才算', () {
      expect(isPriority(item(id: 'a').copyWith(priorityUntil: () => '2026-10-03T00:00:00Z'), now: now), isTrue);
      expect(isPriority(item(id: 'a').copyWith(priorityUntil: () => '2026-10-01T00:00:00Z'), now: now), isFalse);
      expect(isPriority(item(id: 'a'), now: now), isFalse);
    });

    test('复习队列把「优先」排到最前', () {
      final prio = due('p').copyWith(priorityUntil: () => '2026-10-03T00:00:00Z');
      final plain = due('n').copyWith(reviewState: rs(due: '2026-10-01T00:00:00Z', interval: 3, repetitions: 2));
      expect(buildReviewQueue([plain, prio], now).map((x) => x.id), ['p', 'n']);
    });

    test('学习队列同样优先', () {
      final prio = due('p').copyWith(priorityUntil: () => '2026-10-03T00:00:00Z');
      final plain = due('n');
      expect(buildStudyQueue([plain, prio], now).map((x) => x.id), ['p', 'n']);
    });
  });

  group('buildStudyQueue 出场顺序', () {
    test('学习队列：到期 → 新词 → 其它', () {
      final dueItem = item(id: 'd', lemma: 'due', reviewState: rs(due: '2026-09-01T00:00:00Z', interval: 1, repetitions: 2));
      final freshItem = item(id: 'f', lemma: 'fresh');
      final later = item(id: 'l', lemma: 'later', reviewState: rs(due: '2027-01-01T00:00:00Z', interval: 5, repetitions: 3));
      expect(buildStudyQueue([later, freshItem, dueItem], now).map((x) => x.lemma), ['due', 'fresh', 'later']);
    });
  });

  group('每日新词配额', () {
    VocabItem fresh(int n) => item(id: 'f$n', lemma: 'f$n');

    test('限制新词数量', () {
      expect(buildStudyQueue([fresh(1), fresh(2), fresh(3)], now, 2, 0), hasLength(2));
    });

    test('当天额度用完就不出新词', () {
      expect(buildStudyQueue([fresh(1), fresh(2)], now, 2, 2), isEmpty);
    });

    test('不限时不裁剪', () {
      expect(buildStudyQueue([fresh(1), fresh(2), fresh(3)], now, 0, 0), hasLength(3));
    });
  });

  group('新学习 / 复习 两种队列', () {
    VocabItem fresh(String n) => item(id: 'f$n', lemma: 'f$n');
    VocabItem learned(String n, String due, [int reps = 2]) =>
        item(id: 'l$n', lemma: 'l$n', reviewState: rs(due: due, interval: 3, repetitions: reps));

    test('新学习：只取没学过的', () {
      final q = buildLearnQueue([learned('a', '2026-09-01T00:00:00Z'), fresh('b'), fresh('c')], now);
      expect(q.map((x) => x.lemma), ['fb', 'fc']);
    });

    test('新学习：受每日配额限制', () {
      expect(buildLearnQueue([fresh('a'), fresh('b'), fresh('c')], now, 2, 1), hasLength(1));
    });

    test('复习：只取已学过且到期的，按到期升序', () {
      final q = buildReviewQueue([
        learned('later', '2026-12-01T00:00:00Z'),
        learned('overdue', '2026-09-01T00:00:00Z'),
        fresh('new'),
        learned('yesterday', '2026-10-01T00:00:00Z'),
      ], now);
      expect(q.map((x) => x.lemma), ['loverdue', 'lyesterday']);
    });

    test('复习：没到期 / 没学过的不进队', () {
      expect(buildReviewQueue([fresh('a'), learned('b', '2027-01-01T00:00:00Z')], now), isEmpty);
    });
  });

  group('重学（记住过又忘记 / 拼错）', () {
    test('again 进入重学，连续答错累计但封顶 3', () {
      final base = rs(interval: 15, repetitions: 3);
      final first = review(base, ReviewGrade.again, now);
      expect(first.relearn, 1);
      expect(first.repetitions, 0);
      final second = review(first, ReviewGrade.again, now);
      expect(second.relearn, 2);
      final capped = review(second.copyWith(relearn: 3), ReviewGrade.again, now);
      expect(capped.relearn, 3);
    });

    test('重学阶梯：1 天 → 3 天，第二次答对才退出重学', () {
      final failed = review(rs(interval: 15, repetitions: 3), ReviewGrade.again, now);
      final first = review(failed, ReviewGrade.good, now);
      expect(first.interval, 1);
      expect(first.repetitions, 1);
      expect(first.relearn, 1);

      final second = review(first, ReviewGrade.good, now);
      expect(second.interval, 3);
      expect(second.repetitions, 2);
      expect(second.relearn, 0);
    });

    test('重学完成后回到正常间隔（不再按重学阶梯）', () {
      final r = review(rs(interval: 3, repetitions: 2), ReviewGrade.good, now);
      expect(r.interval, 8); // round(3 × 2.5)
      expect(r.relearn, 0);
    });

    test('答错后 repetitions 归零，但不再算「新词」，而是进复习队列最前', () {
      final lapsed = item(
        id: 'v1',
        reviewState: rs(ease: 2.3, due: '2026-10-02T00:00:00Z', interval: 1, repetitions: 0, lapses: 1, relearn: 1),
      );
      final freshItem = item(id: 'v2');
      final overdue = item(id: 'v3', reviewState: rs(due: '2026-09-01T00:00:00Z', interval: 6, repetitions: 2));

      expect(buildLearnQueue([lapsed, freshItem], now).map((x) => x.id), ['v2']);
      expect(buildReviewQueue([overdue, lapsed], now).map((x) => x.id), ['v1', 'v3']);
    });

    test('正在重学的词即使没打「不认识」标签，也要先选释义', () {
      final rel = item(reviewState: rs(due: '2026-10-02T00:00:00Z', interval: 1, relearn: 1));
      expect(needsMeaningCheck(rel), isTrue);
    });
  });

  group('组末边界（学习模式每组 N 词，组末做拼写测试）', () {
    test('size 无效（0 / 负数）按不分组算：整轮一组；小数向下取整', () {
      expect(groupEndOf(5, 10, 0), 10);
      expect(groupEndOf(5, 10, -3), 10);
      expect(groupEndOf(5, 10, 2.9.toInt()), 6); // 每组 2 词
    });

    test('size ≥ 总数也是整轮一组', () {
      expect(groupEndOf(5, 10, 10), 10);
      expect(groupEndOf(5, 10, 99), 10);
    });

    test('每组 N 词：第 i 张卡的组末是下一个 N 的倍数（封顶总数）', () {
      expect(groupEndOf(0, 23, 5), 5);
      expect(groupEndOf(4, 23, 5), 5);
      expect(groupEndOf(5, 23, 5), 10);
      expect(groupEndOf(20, 23, 5), 23);
    });

    test('空轮没有组末', () {
      expect(groupEndOf(0, 0, 5), 0);
    });
  });
}
