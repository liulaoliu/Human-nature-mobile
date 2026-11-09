import 'package:dlaoshi_app/core/recording.dart';
import 'package:dlaoshi_app/core/shadowing_take.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TakeTracker：底噪只往低走，静够了才收', () {
    test('没听到声音时永远不收（哪怕一开始就很安静）', () {
      final t = TakeTracker()..start(Duration.zero);
      for (var ms = 0; ms <= 10000; ms += 40) {
        t.observe(0.001, Duration(milliseconds: ms));
      }
      expect(t.voiceHeard, isFalse);
      expect(t.shouldStop(const Duration(seconds: 10)), isFalse);
    });

    test('开口之后安静到阈值时长就收', () {
      final t = TakeTracker(hangoverMs: 2500)..start(Duration.zero);
      t.observe(0.05, const Duration(milliseconds: 200));
      expect(t.voiceHeard, isTrue);
      expect(t.shouldStop(const Duration(milliseconds: 2400)), isFalse);
      expect(t.shouldStop(const Duration(milliseconds: 2700)), isTrue);
    });

    test('说话中间停一下不算结束 —— 持续有新样本就一直在往后推', () {
      final t = TakeTracker(hangoverMs: 1000)..start(Duration.zero);
      t.observe(0.05, const Duration(milliseconds: 100));
      t.observe(0.05, const Duration(milliseconds: 900));
      expect(t.shouldStop(const Duration(milliseconds: 1500)), isFalse);
      expect(t.shouldStop(const Duration(milliseconds: 1950)), isTrue);
    });

    test('底噪只往低走：尖峰不抬、更低的样本会压下来', () {
      final t = TakeTracker()..start(Duration.zero);
      t.observe(0.4, const Duration(milliseconds: 40));
      expect(t.noiseFloor, noiseFloorInit);
      t.observe(0.0005, const Duration(milliseconds: 80));
      expect(t.noiseFloor, 0.0005);
      t.observe(0.3, const Duration(milliseconds: 120));
      expect(t.noiseFloor, 0.0005);
      expect(t.peak, 0.4);
    });

    test('阈值跟着底噪抬，但不低于绝对下限', () {
      final quiet = TakeTracker()..start(Duration.zero);
      expect(quiet.threshold, voiceThreshold(noiseFloorInit));
      final noisy = TakeTracker(noiseFloor: 0.02)..start(Duration.zero);
      expect(noisy.threshold, voiceThreshold(0.02));
      expect(noisy.threshold, greaterThan(quiet.threshold));
    });

    test('坏电平（NaN）当 0，不会把底噪写成 NaN', () {
      final t = TakeTracker()..start(Duration.zero);
      t.observe(double.nan, const Duration(milliseconds: 40));
      expect(t.noiseFloor.isNaN, isFalse);
      expect(t.peak.isNaN, isFalse);
    });

    test('到达硬上限就算没收也停', () {
      final t = TakeTracker()..start(Duration.zero);
      final cap = recordCapMs(3);
      expect(t.reachedCap(Duration(milliseconds: cap - 1), cap), isFalse);
      expect(t.reachedCap(Duration(milliseconds: cap), cap), isTrue);
    });

    test('没 start 过的话 elapsed 是 0', () {
      final t = TakeTracker();
      expect(t.elapsedAt(const Duration(seconds: 3)), Duration.zero);
    });
  });

  group('judgeTake：只判「开口了没」和「读完没」，不装作懂内容', () {
    test('没声音说 silent', () {
      expect(
        judgeTake(elapsedMs: 3000, voiceHeard: false, estimatedSec: 3),
        TakeVerdict.silent,
      );
    });

    test('时长差不多算 ok', () {
      expect(
        judgeTake(elapsedMs: 3000, voiceHeard: true, estimatedSec: 3),
        TakeVerdict.ok,
      );
      expect(
        judgeTake(elapsedMs: 2000, voiceHeard: true, estimatedSec: 3),
        TakeVerdict.ok,
      );
    });

    test('短一半以上算漏读，长一倍以上算卡住', () {
      expect(
        judgeTake(elapsedMs: 1000, voiceHeard: true, estimatedSec: 3),
        TakeVerdict.tooShort,
      );
      expect(
        judgeTake(elapsedMs: 7000, voiceHeard: true, estimatedSec: 3),
        TakeVerdict.tooLong,
      );
    });

    test('没有参考时长时不瞎判', () {
      expect(
        judgeTake(elapsedMs: 100, voiceHeard: true, estimatedSec: 0),
        TakeVerdict.ok,
      );
    });

    test('四种判定都有人话', () {
      for (final v in TakeVerdict.values) {
        expect(takeVerdictLabel(v), isNotEmpty);
      }
      expect(takeVerdictLabel(TakeVerdict.silent), contains('麦克风'));
    });
  });
}
