import 'package:dlaoshi_app/core/align_text.dart';
import 'package:dlaoshi_app/core/ports.dart';
import 'package:flutter_test/flutter_test.dart';

/// 逐条对照 Web 版 `src/core/alignText.test.ts`（271 行）。
List<Chunk> chunks(List<List<double>> spec) => [
      for (var i = 0; i < spec.length; i++)
        Chunk(index: i, start: spec[i][0], end: spec[i][1]),
    ];

const text =
    'The Kenyan government has a problem. Its banks will not lend cheaply to the private sector. '
    'Tired of asking nicely, the government has taken matters into its own hands. This month it '
    'will put a cap on commercial banks interest rates: charging borrowers more than four '
    'percentage points above the central bank base rate will be illegal. Shares plummeted by 10%.';

List<String> wordsOf(String s) => splitWords(s);

void main() {
  group('alignTextToChunks', () {
    test('空文本时每块都是空串', () {
      final r = alignTextToChunks('   ', chunks([
        [0, 5],
        [5, 10],
      ]));
      expect(r, hasLength(2));
      expect(r.every((c) => c.text.isEmpty), isTrue);
    });

    test('没有块时返回空数组', () {
      expect(alignTextToChunks('hello world', const []), isEmpty);
    });

    test('单块时拿到全部文本', () {
      final r = alignTextToChunks(text, chunks([
        [0, 10],
      ]));
      expect(r[0].text, text);
    });

    test('把所有块拼起来能还原原始词序，不丢词也不重复', () {
      final r = alignTextToChunks(text, chunks([
        [0, 3],
        [3, 7],
        [7, 9],
        [9, 14],
      ]));
      expect(wordsOf(r.map((c) => c.text).join(' ')), wordsOf(text));
    });

    test('按时长比例分配词数：长块拿到的词明显更多', () {
      // 第 1 块 1 秒，第 2 块 9 秒
      final r = alignTextToChunks(text, chunks([
        [0, 1],
        [1, 10],
      ]));
      final w = wordsOf(text).length;
      final first = wordsOf(r[0].text).length;
      final second = wordsOf(r[1].text).length;
      expect(second, greaterThan(first * 3));
      expect(first + second, w);
    });

    test('没有句号可吸附时，严格按比例切', () {
      const flat = 'a b c d e f g h i j k l'; // 12 词，无任何句末标点
      final r = alignTextToChunks(flat, chunks([
        [0, 5],
        [5, 10],
        [10, 15],
      ]));
      expect(r.map((c) => wordsOf(c.text).length), [4, 4, 4]);
    });

    test('边界尽量落在句末', () {
      final r = alignTextToChunks(text, chunks([
        [0, 2],
        [2, 8],
        [8, 14],
      ]));
      // 第一块应该以一个完整的句子收尾
      expect(RegExp(r'''[.!?]["']?$''').hasMatch(r[0].text), isTrue);
    });

    test('句子吸附不会导致某块拿到零词（除非总词数就那么多少）', () {
      final r = alignTextToChunks(text, chunks([
        [0, 1],
        [1, 2],
        [2, 3],
        [3, 14],
      ]));
      expect(r.take(3).every((c) => c.text.isNotEmpty), isTrue);
    });

    test('词数少于块数时不报错，后面几块留空', () {
      final r = alignTextToChunks('one two', chunks([
        [0, 1],
        [1, 2],
        [2, 3],
      ]));
      expect(r, hasLength(3));
      expect(r[0].text, isNotEmpty);
      expect(r[2].text, isEmpty);
    });

    test('保留括号引号里的句号不误切', () {
      const t = 'The U.S. economy grew (see page 4. Note this). Analysts agreed. Growth continued.';
      final r = alignTextToChunks(t, chunks([
        [0, 5],
        [5, 10],
      ]));
      // 理想切点落在 4. 附近，但不能切在那儿——括号还没闭合
      expect(RegExp(r'this\)\.$').hasMatch(r[0].text), isTrue);
      // 也不能切在 "U.S." 后面，因为下一句不是大写开头
      expect(RegExp(r'U\.S\.$').hasMatch(r[0].text), isFalse);
    });

    test('忽略多余空白和换行', () {
      const messy = '  The   Kenyan\n\n  government   has   a   problem.  ';
      final r = alignTextToChunks(messy, chunks([
        [0, 5],
        [5, 10],
      ]));
      final joined = r.map((c) => c.text).where((s) => s.isNotEmpty).join(' ');
      expect(joined, 'The Kenyan government has a problem.');
    });

    test('每块带上起止词序号，方便定位', () {
      final r = alignTextToChunks(text, chunks([
        [0, 5],
        [5, 14],
      ]));
      expect(r[0].wordRange, [0, wordsOf(r[0].text).length]);
      expect(r[1].wordRange[0], r[0].wordRange[1]);
    });

    test('最后一块一定收完所有词', () {
      final r = alignTextToChunks(text, chunks([
        [0, 1],
        [1, 2],
        [2, 14],
      ]));
      expect(r.last.wordRange[1], wordsOf(text).length);
    });

    test('不按比例也能对齐：块时长全为 0 时不崩', () {
      final r = alignTextToChunks(text, chunks([
        [3, 3],
        [3, 3],
      ]));
      expect(r.map((c) => c.text), ['', '']);
    });
  });

  group('整体平移 offsetWords', () {
    // 10 块，每块等长，共 40 词 → 不偏移时每块 4 词
    List<List<double>> ch() => [for (var i = 0; i < 10; i++) [i.toDouble(), i + 1.0]];
    final words = [for (var i = 0; i < 40; i++) 'w$i'];
    final t = '${words.join(' ')}.';

    List<String> join(List<AlignedChunk> r) => wordsOf(r.map((c) => c.text).join(' '));

    test('不传平移量时和不加这个参数时一模一样', () {
      final a = alignTextToChunks(t, chunks(ch()));
      final b = alignTextToChunks(t, chunks(ch()), offsetWords: 0);
      expect(a.map((c) => '${c.index}:${c.text}:${c.wordRange}'),
          b.map((c) => '${c.index}:${c.text}:${c.wordRange}'));
    });

    test('平移后仍然「拼起来等于原文」，一个词不丢不重', () {
      for (final off in [-30, -7, -1, 0, 1, 7, 30]) {
        final r = alignTextToChunks(t, chunks(ch()), offsetWords: off);
        expect(join(r), wordsOf(t), reason: 'offset=$off');
      }
    });

    test('正的平移把词窗往后推：第一块拿到更多词', () {
      final base = alignTextToChunks(t, chunks(ch()))[0];
      final up = alignTextToChunks(t, chunks(ch()), offsetWords: 8)[0];
      expect(up.wordRange[1], base.wordRange[1] + 8);
    });

    test('负的平移把词窗往前拉：第一块被压到最薄但不为空', () {
      final r = alignTextToChunks(t, chunks(ch()), offsetWords: -20);
      expect(r[0].wordRange[0], 0);
      expect(r[0].wordRange[1], greaterThan(0));
      // 中间的块确实跟着往前挪了
      expect(r[5].wordRange[0], lessThan(alignTextToChunks(t, chunks(ch()))[5].wordRange[0]));
    });

    test('词序号始终单调不减、不出界', () {
      for (final off in [-99, -13, 0, 13, 99]) {
        final r = alignTextToChunks(t, chunks(ch()), offsetWords: off);
        var prev = 0;
        for (final c in r) {
          expect(c.wordRange[0], greaterThanOrEqualTo(prev), reason: 'offset=$off');
          expect(c.wordRange[1], greaterThanOrEqualTo(c.wordRange[0]));
          expect(c.wordRange[1], lessThanOrEqualTo(40));
          prev = c.wordRange[1];
        }
        expect(r.last.wordRange[1], 40);
      }
    });

    test('平移量超过总词数也不丢词（全挤到首尾块）', () {
      final big = alignTextToChunks(t, chunks(ch()), offsetWords: 999);
      expect(join(big), wordsOf(t));
      expect(big.last.wordRange[1], 40);
    });
  });

  group('alignTextToChunksWithAnchors', () {
    final words = [for (var i = 0; i < 40; i++) 'w$i'];
    final t = '${words.join(' ')}.';
    final total = wordsOf(t).length;
    final ch = chunks([for (var i = 0; i < 10; i++) [i.toDouble(), i + 1.0]]);

    List<String> join(List<AlignedChunk> r) => wordsOf(r.map((c) => c.text).join(' '));

    test('没有锚点时和纯比例对齐一致', () {
      final a = alignTextToChunksWithAnchors(t, ch, const []);
      final b = alignTextToChunks(t, ch);
      expect(a.map((c) => '${c.index}:${c.text}:${c.wordRange}'),
          b.map((c) => '${c.index}:${c.text}:${c.wordRange}'));
    });

    test('中间一块锚定后，那一块刚好是选中的词，拼回来还是原文', () {
      final r = alignTextToChunksWithAnchors(t, ch, const [
        ManualAnchor(atSec: 4.5, startWord: 16, endWord: 20),
      ]);
      expect(r[4].wordRange, [16, 20]);
      expect(join(r), wordsOf(t));
    });

    test('多个锚点都生效，中间按比例摊', () {
      final r = alignTextToChunksWithAnchors(t, ch, const [
        ManualAnchor(atSec: 2.5, startWord: 8, endWord: 12),
        ManualAnchor(atSec: 7.5, startWord: 30, endWord: 34),
      ]);
      expect(r[2].wordRange, [8, 12]);
      expect(r[7].wordRange, [30, 34]);
      expect(join(r), wordsOf(t));
    });

    test('锚点顺带把正文起点定了：前面的块留空', () {
      final r = alignTextToChunksWithAnchors(t, ch, const [
        ManualAnchor(atSec: 3.5, startWord: 0, endWord: 5),
      ]);
      expect(r[0].text, '');
      expect(r[2].text, '');
      expect(r[3].wordRange, [0, 5]);
      expect(join(r), wordsOf(t));
    });

    test('重叠的锚点靠前的赢，不丢词不重复', () {
      final r = alignTextToChunksWithAnchors(t, ch, const [
        ManualAnchor(atSec: 1.5, startWord: 4, endWord: 12),
        ManualAnchor(atSec: 2.5, startWord: 8, endWord: 16),
      ]);
      expect(r[1].wordRange, [4, 12]);
      expect(r[2].wordRange[0], greaterThanOrEqualTo(12));
      expect(join(r), wordsOf(t));
    });

    test('按时间认块：换切块粒度后锚点还认得原来那段音频', () {
      final coarse = chunks([
        [0, 4],
        [4, 8],
        [8, 12],
      ]);
      final fine = chunks([
        [0, 2],
        [2, 4],
        [4, 6],
        [6, 8],
        [8, 10],
        [10, 12],
      ]);
      const a = ManualAnchor(atSec: 4.5, startWord: 0, endWord: 6);
      expect(alignTextToChunksWithAnchors(t, fine, const [a])[2].wordRange, [0, 6]);
      expect(alignTextToChunksWithAnchors(t, coarse, const [a])[1].wordRange, [0, 6]);
    });

    test('词序号单调不出界，末尾收完', () {
      final r = alignTextToChunksWithAnchors(t, ch, [
        const ManualAnchor(atSec: 0.5, startWord: 0, endWord: 3),
        ManualAnchor(atSec: 9.5, startWord: 35, endWord: total),
      ]);
      var prev = 0;
      for (final c in r) {
        expect(c.wordRange[0], greaterThanOrEqualTo(prev));
        expect(c.wordRange[1], greaterThanOrEqualTo(c.wordRange[0]));
        prev = c.wordRange[1];
      }
      expect(r.last.wordRange[1], total);
      expect(join(r), wordsOf(t));
    });

    test('钉过的块带 anchored 标记，没钉的没有', () {
      final r = alignTextToChunksWithAnchors(t, ch, const [
        ManualAnchor(atSec: 4.5, startWord: 16, endWord: 20),
      ]);
      expect(r[4].anchored, isTrue);
      expect(r[3].anchored, isFalse);
      expect(r[5].anchored, isFalse);
    });

    test('改别处的文字后，带 text 的锚点能在新词表里找回原位置', () {
      // 原锚点钉在第 5 块，读 w16..w19
      final anchor = ManualAnchor(
        atSec: 4.5,
        startWord: 16,
        endWord: 20,
        text: words.sublist(16, 20).join(' '),
      );
      // 前面插入 3 个词（相当于删掉了别处一段/补了漏字）
      final edited = '${['x', 'y', 'z', ...words].join(' ')}.';
      final r = alignTextToChunksWithAnchors(edited, ch, [anchor]);
      expect(r[4].wordRange, [19, 23]);
    });

    test('text 在新文本里找不到时退回存下的词序号（夹紧）', () {
      final r = alignTextToChunksWithAnchors(t, ch, const [
        ManualAnchor(atSec: 4.5, startWord: 16, endWord: 20, text: '这里根本没有这几个词'),
      ]);
      expect(r[4].wordRange, [16, 20]);
    });

    test('锚点文字重复出现时，认离原来位置最近的那处', () {
      final zz = [for (var i = 0; i < 20; i++) 'zz'];
      // "aa bb" 在 0 和 22 都出现，存的顺序号是 22，应该认后面那处
      final dup = ['aa', 'bb', ...zz, 'aa', 'bb', ...zz];
      final cs = chunks([
        [0, 10],
        [10, 20],
        [20, 30],
        [30, 40],
        [40, 50],
        [50, 60],
      ]);
      final r = resolveAnchors(dup, cs, const [
        ManualAnchor(atSec: 55, startWord: 22, endWord: 24, text: 'aa bb'),
      ]);
      expect(r[0].startWord, 22);
      expect(r[0].endWord, 24);
    });
  });
}
