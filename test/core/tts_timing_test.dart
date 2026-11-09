// TTS 逐词时间对齐的用例（对应 Web 版 `src/core/ttsTiming.test.ts` 43 行的逐条口径）。
import 'package:dlaoshi_app/core/tts_timing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('alignTimings：TTS 逐词时间对齐', () {
    test('同序对齐；大小写与标点归一化后比较', () {
      final out = alignTimings('Hello, WORLD!', const <TimingPart>[
        TimingPart(part: 'hello', start: 0, end: 100),
        TimingPart(part: 'world', start: 100, end: 240),
      ]);
      expect(out, const <WordTiming>[
        WordTiming(start: 0, end: 100),
        WordTiming(start: 100, end: 240),
      ]);
    });

    test('时间戳缺一个词：用同位置兜底，避免整体错位', () {
      final out = alignTimings('one two three', const <TimingPart>[
        TimingPart(part: 'one', start: 0, end: 10),
        TimingPart(part: 'three', start: 20, end: 30),
      ]);
      // 第二个词没返回：拿同位置的 third 时间兜底；第三个词已无时间戳 → 0（不高亮）
      expect(out[0], const WordTiming(start: 0, end: 10));
      expect(out[1], const WordTiming(start: 20, end: 30));
      expect(out[2], const WordTiming(start: 0, end: 0));
    });

    test('时间戳多于词数：多余的忽略；完全没时间戳：全 0', () {
      final extra = alignTimings('one', const <TimingPart>[
        TimingPart(part: 'one', start: 0, end: 10),
        TimingPart(part: 'two', start: 10, end: 20),
      ]);
      expect(extra, const <WordTiming>[WordTiming(start: 0, end: 10)]);

      expect(alignTimings('one two', const <TimingPart>[]), const <WordTiming>[
        WordTiming(start: 0, end: 0),
        WordTiming(start: 0, end: 0),
      ]);
    });

    test('空句子 → 空数组', () {
      expect(
        alignTimings('   ', const <TimingPart>[TimingPart(part: 'x', start: 0, end: 1)]),
        isEmpty,
      );
    });

    test('时间戳没有 part 时只靠同位置兜底', () {
      final out = alignTimings('a b', const <TimingPart>[
        TimingPart(start: 0, end: 5),
        TimingPart(start: 5, end: 9),
      ]);
      expect(out, const <WordTiming>[
        WordTiming(start: 0, end: 5),
        WordTiming(start: 5, end: 9),
      ]);
    });

    test('词序被打乱时按「往后找」匹配，游标越过就回不了头', () {
      // 时间戳顺序是 b、a，但原文是 a、b：第一个词 a 往后找到 timings[1] 的 a，
      // 游标跳到 2（越过 b），第二个词 b 已经没时间戳了 → 0。
      // 这是 Web 版的既定行为：宁可后一个词不高亮，也不把时间戳倒着配回去。
      final out = alignTimings('a b', const <TimingPart>[
        TimingPart(part: 'b', start: 0, end: 5),
        TimingPart(part: 'a', start: 5, end: 9),
      ]);
      expect(out[0], const WordTiming(start: 5, end: 9));
      expect(out[1], const WordTiming(start: 0, end: 0));
    });

    test('连字符复合词整体算一个词', () {
      final out = alignTimings('a well-known fact', const <TimingPart>[
        TimingPart(part: 'a', start: 0, end: 10),
        TimingPart(part: 'well-known', start: 10, end: 50),
        TimingPart(part: 'fact', start: 50, end: 70),
      ]);
      expect(out, const <WordTiming>[
        WordTiming(start: 0, end: 10),
        WordTiming(start: 10, end: 50),
        WordTiming(start: 50, end: 70),
      ]);
    });
  });
}
