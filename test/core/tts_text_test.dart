import 'package:dlaoshi_app/core/tts_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('弯单引号归一成 ASCII 撇号（所有格/缩写）', () {
    expect(normalizeTtsText('Saudi Arabia’s envoy'), "Saudi Arabia's envoy");
    expect(normalizeTtsText('don’t stop'), "don't stop");
  });

  test('双引号去掉，长破折号变停顿，短破折号保留连字符', () {
    expect(normalizeTtsText('He said “hello”.'), 'He said hello.');
    expect(normalizeTtsText('growth—slowed—down'), 'growth, slowed, down');
    expect(normalizeTtsText('2012–14'), '2012-14');
  });

  test('中文标题括号 / 省略号 / 零宽字符', () {
    expect(normalizeTtsText('【Britain】'), 'Britain');
    expect(normalizeTtsText('wait… what?'), 'wait... what?');
    expect(normalizeTtsText('a\u200Bb'), 'ab');
  });

  test('空白收敛，标点前不留空格；幂等', () {
    const input = '  The   Group of 20’s  summit .  ';
    final once = normalizeTtsText(input);
    expect(once, "The Group of twenty's summit.");
    expect(normalizeTtsText(once), once);
  });

  test('数字 / 缩写 / 单位先展开，避免音素化器读成怪词', () {
    expect(normalizeTtsText('The G20 and the IMF'), 'The G 20 and the I M F');
    expect(normalizeTtsText('20’s'), "twenty's");
    expect(normalizeTtsText('20s'), 'twenties');
    expect(normalizeTtsText('3.7% growth'), '3.7 percent growth');
    expect(normalizeTtsText('\$14.7 billion'), '14.7 billion dollars');
    expect(normalizeTtsText('R&D'), 'R and D');
  });
}
