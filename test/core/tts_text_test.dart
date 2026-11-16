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
    expect(normalizeTtsText('3.7% growth'), '3.7 percent growth');
    expect(normalizeTtsText('\$14.7 billion'), '14.7 billion dollars');
    expect(normalizeTtsText('R&D'), 'R and D');
  });

  // 2026-11-16：Kokoro 把「1990s」读成一个 s。根因不在我们这层，也不在
  // IPA 映射，而在 phonemize 自带的年份展开被正则 \b 卡住（`1990` 后面粘着
  // `s`，词边界不成立）。加个撇号让那条规则看得见数字，它自己就会读成
  // 「nineteen nineties」—— 所以这里不自己实现数字拼写。
  test('年代：数字后粘 s 会整段被吞，补撇号让音素化器的年份规则生效', () {
    expect(normalizeTtsText('the 1950s'), "the 1950's");
    expect(normalizeTtsText('the 1990s'), "the 1990's");
    expect(normalizeTtsText('the 2000s'), "the 2000's");
    expect(normalizeTtsText('in the 80s'), "in the 80's");
    expect(normalizeTtsText('over-65s'), "over-65's");
    // 已经是撇号写法的不重复加。
    expect(normalizeTtsText("the 1990's"), "the 1990's");
  });

  // 单位是唯一必须我们自己维护的映射：音素化器不可能知道 `m` 是 million
  // （它会读成「em」）。只收这套语料里真的会出现的几个，别贪多。
  test('单位缩写展开成词（音素化器只认单词，不认 m / mw / gw）', () {
    expect(normalizeTtsText('2.5m acres'), '2.5 million acres');
    expect(normalizeTtsText('208m people'), '208 million people');
    // 千分位逗号也一并去掉：`30,000` 会读成「thirty, zero」，
    // 去掉后才是「thirty thousand」。
    expect(normalizeTtsText('30,000mw of wind'), '30000 megawatts of wind');
    expect(normalizeTtsText('254gw by 2030'), '254 gigawatts by 2030');
    expect(normalizeTtsText('300km an hour'), '300 kilometres an hour');
    expect(normalizeTtsText('3bn people'), '3 billion people');
  });

  // 字母与数字粘连时同样会被吞（`3D` 读成 d、`5G` 读成 ɡ、`B2B` 读成 bb）。
  // 拆开让它们各自成词，音素化器就都读得对。
  test('字母与数字粘连处拆开', () {
    expect(normalizeTtsText('The 3D printer'), 'The 3 D printer');
    expect(normalizeTtsText('5G networks'), '5 G networks');
    expect(normalizeTtsText('B2B sales'), 'B 2 B sales');
    expect(normalizeTtsText('The A4 paper'), 'The A 4 paper');
    expect(normalizeTtsText('A 4x4 truck'), 'A 4 x 4 truck');
  });

  // 序数是这条规则的反面：`1st` 拆成 `1 st` 会读成「one street」、
  // `3rd` 读成「three road」。语料里序数有一千多处，一个都不能拆。
  test('序数不能被拆开（1st 不是 one street）', () {
    expect(normalizeTtsText('1st quarter'), '1st quarter');
    expect(normalizeTtsText('21st century'), '21st century');
    expect(normalizeTtsText('2nd place'), '2nd place');
    expect(normalizeTtsText('3rd time'), '3rd time');
    expect(normalizeTtsText('45th president'), '45th president');
    // 紧挨着字母的非序数还是要拆。
    expect(normalizeTtsText('H1N1'), 'H 1 N 1');
    expect(normalizeTtsText('MP3 player'), 'MP 3 player');
  });
}
