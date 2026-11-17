import 'package:dlaoshi_app/core/tts_number_words.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('expandTtsNumbers（把数字读成正确的英文单词）', () {
    test('普通整数与千分位', () {
      expect(expandTtsNumbers('There are 5 apples.'), 'There are five apples.');
      expect(
        expandTtsNumbers('It rose to 30000 megawatts.'),
        'It rose to thirty thousand megawatts.',
      );
    });

    test('年份读成 nineteen ninety，不是 one thousand nine hundred ninety', () {
      expect(expandTtsNumbers('in 1990'), 'in nineteen ninety');
      expect(expandTtsNumbers('in 2008'), 'in twenty oh eight');
      expect(expandTtsNumbers('in 2010'), 'in twenty ten');
      expect(expandTtsNumbers('in 2000'), 'in twenty hundred');
    });

    test('序数', () {
      expect(expandTtsNumbers('the 1st time'), 'the first time');
      expect(expandTtsNumbers('the 2nd try'), 'the second try');
      expect(expandTtsNumbers('the 3rd one'), 'the third one');
      expect(expandTtsNumbers('the 45th'), 'the forty-fifth');
      expect(expandTtsNumbers('the 21st'), 'the twenty-first');
    });

    test('小数与百分比', () {
      expect(expandTtsNumbers(' 3.7 percent'), 'three point seven percent');
      // number_to_words_english 带连字符（forty-five），espeak 词典认连字符词，不用拆
      expect(expandTtsNumbers('rose 45%'), 'rose forty-five percent');
    });

    test('货币', () {
      expect(expandTtsNumbers(r'costs $14.50'), 'costs fourteen dollars and fifty cents');
      expect(expandTtsNumbers(r'a $1 bill'), 'a one dollar bill');
    });

    test('没有数字时原样返回（幂等）', () {
      const plain = 'Reading makes perfect.';
      expect(expandTtsNumbers(plain), plain);
      expect(expandTtsNumbers(''), '');
      final once = expandTtsNumbers('in 1990 there were 2 things');
      expect(expandTtsNumbers(once), once);
    });

    test('电话号码逐位读', () {
      expect(
        expandTtsNumbers('call 555-123-4567'),
        'call five five five one two three four five six seven',
      );
    });
  });
}
