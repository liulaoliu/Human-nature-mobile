import 'package:dlaoshi_app/core/word_select.dart';
import 'package:flutter_test/flutter_test.dart';

const s = 'abandon back check deaf ear fish';
//          0      7    12    18   22  26

void main() {
  group('wordSpans', () {
    test('切出所有词，标点空白不算', () {
      expect(wordSpans(s).map((w) => w.text).toList(),
          ['abandon', 'back', 'check', 'deaf', 'ear', 'fish']);
    });

    test('连字符复合词并成一个词', () {
      expect(wordSpans('bad-tempered burqa-clad').map((w) => w.text).toList(), ['bad-tempered', 'burqa-clad']);
      expect(wordSpans('well-known word, end.'), [
        const WordSpan(start: 0, end: 10, text: 'well-known'),
        const WordSpan(start: 11, end: 15, text: 'word'),
        const WordSpan(start: 17, end: 20, text: 'end'),
      ]);
    });

    test('带空格的连字符 / 破折号不并', () {
      expect(wordSpans('a - b').map((w) => w.text).toList(), ['a', 'b']);
      expect(wordSpans('a — b').map((w) => w.text).toList(), ['a', 'b']);
    });
  });

  group('snapSelection', () {
    test('落在单个词里 → 那个整词', () {
      expect(snapSelection(s, 2, 5)?.text, 'abandon');
    });

    test('光标（起止相同）→ 所在整词', () {
      expect(snapSelection(s, 3, 3)?.text, 'abandon');
    });

    test('拖过 back 的任意位置 → abandon back（碰到 b 也算）', () {
      expect(snapSelection(s, 0, 9)?.text, 'abandon back');
      expect(snapSelection(s, 0, 12)?.text, 'abandon back');
    });

    test('只到 back 词边界之前 → 仍是 abandon', () {
      expect(snapSelection(s, 0, 8)?.text, 'abandon');
    });

    test('拖到 deaf 就含 check / deaf（中间全包）', () {
      expect(snapSelection(s, 0, 21)?.text, 'abandon back check deaf');
    });

    test('起点终点反着选也一样', () {
      expect(snapSelection(s, 12, 0)?.text, 'abandon back');
    });

    test('没有词返回 null', () {
      expect(snapSelection('  , . !  ', 2, 4), isNull);
    });

    test('返回的 start/end 是整词边界', () {
      final r = snapSelection(s, 1, 9)!;
      expect(s.substring(r.start, r.end), r.text);
      expect(r.start, 0);
      expect(r.end, 12);
    });
  });

  group('snapSelection 连字符复合词', () {
    const t = 'a bad-tempered man';

    test('落在复合词任意位置都整个选中', () {
      expect(snapSelection(t, 3, 3)?.text, 'bad-tempered');
      expect(snapSelection(t, 10, 10)?.text, 'bad-tempered');
      expect(snapSelection(t, 2, 13)?.text, 'bad-tempered');
    });
  });

  group('wordIndexRange（字符区间 → 词下标区间）', () {
    test('覆盖单个词 → 那个词的下标', () {
      expect(wordIndexRange(s, 8, 12), (start: 1, end: 2));
    });

    test('跨多个词 → 首词到末词（中间全包）', () {
      expect(wordIndexRange(s, 0, 12), (start: 0, end: 2));
      expect(wordIndexRange(s, 8, 21), (start: 1, end: 4));
    });

    test('终点正好停在词边界 → 不多包下一个词', () {
      expect(wordIndexRange(s, 0, 7), (start: 0, end: 1));
    });

    test('起点在最后一个词之后 / 整句没词 → null', () {
      expect(wordIndexRange(s, 100, 120), isNull);
      expect(wordIndexRange('  , . !  ', 2, 4), isNull);
    });
  });

  group('toggleIndex / wordsAtIndex（按位置而非词形选中）', () {
    const text = 'a big something makes a terrible';
    final spans = wordSpans(text);
    // a(0) big(1) something(2) makes(3) a(4) terrible(5)

    test('同一个词的不同位置互不影响', () {
      final sel = toggleIndex(<int>[], 4);
      expect(sel, [4]);
      expect(wordsAtIndex(spans, sel), ['a']);
    });

    test('按位置切换：选中/取消各自的词', () {
      var sel = toggleIndex(<int>[], 0);
      sel = toggleIndex(sel, 5);
      expect(wordsAtIndex(spans, sel), ['a', 'terrible']);
      sel = toggleIndex(sel, 0);
      expect(wordsAtIndex(spans, sel), ['terrible']);
    });

    test('合成词组带上各自位置的词，不会把同形词都算进来', () {
      const sel = [5, 4];
      expect(wordsAtIndex(spans, sel).join(' '), 'a terrible');
    });

    test('下标越界不产生空串', () {
      expect(wordsAtIndex(spans, const [99, 1]), ['big']);
    });
  });

  group('wordSpans：结果缓存', () {
    test('同一段文本第二次调用直接复用同一个结果（不重新分词）', () {
      const text = 'the quick brown fox jumps over the lazy dog — repeatedly';
      final a = wordSpans(text);
      final b = wordSpans(text);
      expect(identical(b, a), isTrue); // 同一引用 = 命中缓存
      expect(b.map((w) => w.text).toList(),
          ['the', 'quick', 'brown', 'fox', 'jumps', 'over', 'the', 'lazy', 'dog', 'repeatedly']);
    });

    test('不同文本不会串味', () {
      expect(wordSpans('alpha beta').map((w) => w.text).toList(), ['alpha', 'beta']);
      expect(wordSpans('gamma delta').map((w) => w.text).toList(), ['gamma', 'delta']);
      expect(wordSpans('alpha beta').map((w) => w.text).toList(), ['alpha', 'beta']);
    });

    test('超过上限会淘汰最久未用的，结果仍然正确', () {
      for (var i = 0; i < 520; i++) {
        wordSpans('sentence number $i here');
      }
      expect(wordSpans('sentence number 0 here').map((w) => w.text).toList(),
          ['sentence', 'number', '0', 'here']);
    });
  });
}
