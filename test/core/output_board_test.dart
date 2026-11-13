import 'package:dlaoshi_app/core/kind_stats.dart';
import 'package:dlaoshi_app/core/output_board.dart';
import 'package:flutter_test/flutter_test.dart';

KindStat ks(int total, int correct) => KindStat(total: total, correct: correct);

OutputInput input({
  KindStat? chunkStats,
  KindStat? grammarStats,
  OutputWords? words,
  OutputWrites? writes,
  OutputRetells? retells,
  int streak = 0,
}) =>
    OutputInput(
      chunkStats: chunkStats ?? const KindStat(),
      grammarStats: grammarStats ?? const KindStat(),
      words: words ?? const OutputWords(),
      writes: writes ?? const OutputWrites(),
      retells: retells ?? const OutputRetells(),
      streak: streak,
    );

OutputRow rowOf(OutputBoard b, String key) => b.rows.firstWhere((r) => r.key == key);

void main() {
  group('buildOutputBoard：空数据', () {
    test('什么都没有：0 分、还没产出、七行都在', () {
      final b = buildOutputBoard(input());
      expect(b.score, 0);
      expect(b.grade, '还没产出');
      expect(b.rows, hasLength(7));
      expect(b.rows.map((r) => r.key), [
        'chunkAcc',
        'grammarAcc',
        'chunkCover',
        'write',
        'retell',
        'memory',
        'streak',
      ]);
      expect(rowOf(b, 'chunkAcc').value, '还没测过');
      expect(rowOf(b, 'write').value, '0 条');
      expect(rowOf(b, 'retell').value, '0 条');
      expect(rowOf(b, 'chunkCover').value, '—');
      expect(rowOf(b, 'memory').value, '—');
      expect(b.next, '先建生词（选词 / 自动标词），产出才有原料');
    });

    test('没有生词时没有任何一行达标', () {
      final b = buildOutputBoard(input());
      expect(b.rows.every((r) => !r.good), isTrue);
    });
  });

  group('buildOutputBoard：各项口径', () {
    test('词块正确率 80 才算达标', () {
      final ok = buildOutputBoard(input(words: const OutputWords(total: 10), chunkStats: ks(10, 8)));
      expect(rowOf(ok, 'chunkAcc').good, isTrue);
      expect(rowOf(ok, 'chunkAcc').value, '80%（8/10）');
      final no = buildOutputBoard(input(words: const OutputWords(total: 10), chunkStats: ks(10, 7)));
      expect(rowOf(no, 'chunkAcc').good, isFalse);
      expect(rowOf(no, 'chunkAcc').value, '70%（7/10）');
    });

    test('仿写没批改过不给分，均分要 75 才达标', () {
      final pending = buildOutputBoard(input(
        words: const OutputWords(total: 10),
        writes: const OutputWrites(count: 2),
      ));
      expect(rowOf(pending, 'write').value, '2 条 · 待批改');
      expect(rowOf(pending, 'write').good, isFalse);
      expect(rowOf(pending, 'write').level, 23); // 只靠条数：min(2,4)/4*100*0.45 ≈ 22.5 → 23

      final good = buildOutputBoard(input(
        words: const OutputWords(total: 10),
        writes: const OutputWrites(count: 2, avgScore: 80),
      ));
      expect(rowOf(good, 'write').good, isTrue);
      expect(rowOf(good, 'write').value, '2 条 · 均分 80');
    });

    test('复述有一条就达标', () {
      final b = buildOutputBoard(input(
        words: const OutputWords(total: 10),
        retells: const OutputRetells(count: 1, words: 30),
      ));
      expect(rowOf(b, 'retell').good, isTrue);
      expect(rowOf(b, 'retell').value, '1 条 · 30 词');
    });

    test('记忆分 = 学过 60% + 稳定 40%，70 才算达标', () {
      final b = buildOutputBoard(input(words: const OutputWords(
        total: 10,
        studied: 10,
        stable: 5,
      )));
      expect(rowOf(b, 'memory').level, 80); // 100*0.6 + 50*0.4
      expect(rowOf(b, 'memory').good, isTrue);
      expect(rowOf(b, 'memory').value, '学过 10/10 · 稳定 5');
    });

    test('连续 3 天达标，7 天封顶', () {
      expect(rowOf(buildOutputBoard(input(streak: 2)), 'streak').good, isFalse);
      final b = buildOutputBoard(input(streak: 30));
      expect(rowOf(b, 'streak').good, isTrue);
      expect(rowOf(b, 'streak').level, 100);
      expect(rowOf(b, 'streak').value, '30 天');
    });
  });

  group('buildOutputBoard：总分与等级', () {
    test('全项满分是 100、等级实打实', () {
      final b = buildOutputBoard(input(
        chunkStats: ks(10, 10),
        grammarStats: ks(10, 10),
        words: const OutputWords(total: 10, withChunks: 10, studied: 10, stable: 10),
        writes: const OutputWrites(count: 4, avgScore: 100),
        retells: const OutputRetells(count: 3, words: 120),
        streak: 7,
      ));
      expect(b.score, 100);
      expect(b.grade, '实打实');
      expect(b.rows.every((r) => r.good), isTrue);
      expect(b.next, '词块 · 产出 · 记忆都在线，隔天复习即可 ✅');
    });

    test('等级四档的边界', () {
      expect(buildOutputBoard(input()).grade, '还没产出');
      final s30 = buildOutputBoard(input(
        words: const OutputWords(total: 10, withChunks: 5),
        chunkStats: ks(10, 8),
      ));
      expect(s30.score >= 25, isTrue);
      expect(s30.grade, isNot('还没产出'));
    });

    test('next 按优先级给：没生词 → 没测过词块 → 没仿写 → 没复述', () {
      expect(buildOutputBoard(input()).next, contains('先建生词'));
      expect(
        buildOutputBoard(input(words: const OutputWords(total: 5))).next,
        contains('词块拷打'),
      );
      expect(
        buildOutputBoard(input(
          words: const OutputWords(total: 5),
          chunkStats: ks(5, 4),
        )).next,
        contains('仿写 1 句'),
      );
      expect(
        buildOutputBoard(input(
          words: const OutputWords(total: 5),
          chunkStats: ks(5, 4),
          writes: const OutputWrites(count: 1, avgScore: 80),
        )).next,
        contains('复述一遍'),
      );
    });

    test('词块正确率低时指向「再来一轮词块拷打」', () {
      final b = buildOutputBoard(input(
        words: const OutputWords(total: 5, studied: 5),
        chunkStats: ks(10, 5),
        writes: const OutputWrites(count: 1, avgScore: 80),
        retells: const OutputRetells(count: 1, words: 30),
      ));
      expect(b.next, contains('搭配正确率还偏低'));
    });
  });

  group('sumKindStats', () {
    test('按名单求和，缺的题型跳过', () {
      final stats = <String, Map<String, KindStat>>{
        'a1': {'usage': ks(3, 2), 'collocation': ks(2, 2), 'spell': ks(9, 9)},
      };
      expect(sumKindStats(stats, 'a1', outputChunkKinds), ks(5, 4));
      expect(sumKindStats(stats, 'a1', outputGrammarKinds), const KindStat());
      expect(sumKindStats(stats, 'nope', outputChunkKinds), const KindStat());
    });

    test('名单常量与 drill 的题型对得上', () {
      expect(outputChunkKinds, containsAll(<String>['usage', 'collocation', 'prep', 'idiom']));
      expect(outputGrammarKinds, containsAll(<String>['grammar', 'functionWord', 'ordering']));
    });
  });
}
