import 'package:dlaoshi_app/core/quiz.dart';
import 'package:dlaoshi_app/core/quiz_drill.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('分档与题型映射', () {
    test('七档都有中文名与说明', () {
      for (final k in QuizDrillKind.values) {
        expect(quizDrillLabel[k], isNotNull, reason: '$k 缺 label');
        expect(quizDrillLabel[k]!.isNotEmpty, isTrue);
        expect(quizDrillHint[k], isNotNull, reason: '$k 缺 hint');
      }
    });

    test('记忆档：拼写 + 看词选义 + 词形辨析（与 Web 一致）', () {
      expect(quizDrillKinds[QuizDrillKind.memory], [
        QuizKind.spell,
        QuizKind.meaning,
        QuizKind.choice,
      ]);
    });

    test('词块档：搭配 + 例句 + 搭配默写 + 介词 + 习语', () {
      expect(quizDrillKinds[QuizDrillKind.chunk], [
        QuizKind.usage,
        QuizKind.cloze,
        QuizKind.collocation,
        QuizKind.prep,
        QuizKind.idiom,
      ]);
    });

    test('错题包围战：只用词级题（文章级要整篇，错题本里没有句子）', () {
      final kinds = quizDrillKinds[QuizDrillKind.siege]!;
      expect(kinds.every((k) => !k.isArticle), isTrue);
      expect(kinds, isNotEmpty);
    });

    test('每档都有题型（没有空档）', () {
      for (final k in QuizDrillKind.values) {
        expect(quizDrillKinds[k], isNotEmpty, reason: '$k 没配题型');
      }
    });

    test('首批只开三种，其余标待开', () {
      expect(quizDrillReady.length, 3);
      expect(quizDrillImplemented(QuizDrillKind.memory), isTrue);
      expect(quizDrillImplemented(QuizDrillKind.chunk), isTrue);
      expect(quizDrillImplemented(QuizDrillKind.siege), isTrue);
      expect(quizDrillImplemented(QuizDrillKind.grammar), isFalse);
      expect(quizDrillImplemented(QuizDrillKind.listen), isFalse);
    });
  });

  group('题数档位', () {
    test('档位就是 Web 那五个', () {
      expect(drillLimitOptions, [5, 10, 15, 20, 30]);
      expect(defaultDrillLimit, 10);
    });

    test('合法值原样返回', () {
      for (final n in drillLimitOptions) {
        expect(normalizeDrillLimit(n), n);
      }
    });

    test('不在档位里的数字回默认（不做四舍五入）', () {
      expect(normalizeDrillLimit(7), defaultDrillLimit);
      expect(normalizeDrillLimit(0), defaultDrillLimit);
      expect(normalizeDrillLimit(-5), defaultDrillLimit);
    });

    test('字符串也认', () {
      expect(normalizeDrillLimit('20'), 20);
      expect(normalizeDrillLimit(' 15 '), 15);
      expect(normalizeDrillLimit('abc'), defaultDrillLimit);
      expect(normalizeDrillLimit('7'), defaultDrillLimit);
    });

    test('null / 奇怪类型回默认', () {
      expect(normalizeDrillLimit(null), defaultDrillLimit);
      expect(normalizeDrillLimit(<String>[]), defaultDrillLimit);
      expect(normalizeDrillLimit(19.0), defaultDrillLimit);
      expect(normalizeDrillLimit(20.0), 20);
    });
  });

  group('每档题量的存取', () {
    test('没存过：每档都是默认', () {
      final limits = parseDrillLimits(null);
      expect(limits.length, QuizDrillKind.values.length);
      expect(limits.values.every((v) => v == defaultDrillLimit), isTrue);
    });

    test('平铺 int 读得回来', () {
      final limits = parseDrillLimits({'memory': 20, 'siege': 5});
      expect(limits[QuizDrillKind.memory], 20);
      expect(limits[QuizDrillKind.siege], 5);
      expect(limits[QuizDrillKind.chunk], defaultDrillLimit);
    });

    test('旧版嵌套形状也认', () {
      final limits = parseDrillLimits({
        'memory': {'limit': 30},
        'chunk': {'limit': 'bad'},
      });
      expect(limits[QuizDrillKind.memory], 30);
      expect(limits[QuizDrillKind.chunk], defaultDrillLimit);
    });

    test('坏值逐档回默认，不整份丢', () {
      final limits = parseDrillLimits({'memory': 'nope', 'chunk': 999});
      expect(limits[QuizDrillKind.memory], defaultDrillLimit);
      expect(limits[QuizDrillKind.chunk], defaultDrillLimit);
    });

    test('非 Map 回全默认', () {
      final limits = parseDrillLimits(<String>['a']);
      expect(limits.values.every((v) => v == defaultDrillLimit), isTrue);
    });

    test('写出去再读回来不变', () {
      final before = {
        for (final k in QuizDrillKind.values) k: 15,
      };
      final after = parseDrillLimits(drillLimitsToJson(before));
      expect(after, before);
    });

    test('写出去会把非法值洗成默认', () {
      final json = drillLimitsToJson({QuizDrillKind.memory: 7});
      expect(json['memory'], defaultDrillLimit);
    });
  });

  group('drillRoundCount：这一轮出几题', () {
    test('池子够：用档位', () {
      expect(drillRoundCount(10, 48), 10);
    });

    test('池子不够：有多少出多少', () {
      expect(drillRoundCount(10, 3), 3);
    });

    test('池子空：0 题', () {
      expect(drillRoundCount(10, 0), 0);
    });

    test('非法档位按默认 10 算', () {
      expect(drillRoundCount(7, 100), 10);
    });
  });

  test('存储键固定（改名会让用户的选择丢）', () {
    expect(drillLimitsKey, 'reader:drillLimits');
  });
}
