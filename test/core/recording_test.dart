// 录音参数与电平判定的用例（对应 Web 版 `src/core/recording.test.ts` 37 行的逐条口径）。
import 'package:dlaoshi_app/core/recording.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('recordCapMs', () {
    test('短块按「两倍块长 + 3 秒」给，留够慢慢读的余地', () {
      expect(recordCapMs(3), 9000);
    });

    test('再短的块也至少给 4 秒（块只有 0.2 秒也不至于一句都读不完）', () {
      expect(recordCapMs(0), 4000);
      expect(recordCapMs(0.1), 4000);
    });

    test('长块封顶 90 秒：静音检测失灵时总得能自己停下来', () {
      expect(recordCapMs(60), 90000);
      expect(recordCapMs(600), 90000);
    });

    test('块长带小数时四舍五入到毫秒', () {
      expect(recordCapMs(2.5), 8000);
      expect(recordCapMs(1.2345), 5469);
    });
  });

  group('voiceThreshold', () {
    test('底噪为 0 时取「0 + 余量」，不是 0 —— 否则房间里的杂音都算说话', () {
      expect(voiceThreshold(0), voiceMargin);
    });

    test('底噪高时跟着往上抬（小增益设备的底噪本来就高）', () {
      expect(voiceThreshold(0.02), closeTo(0.02 + voiceMargin, 1e-10));
    });

    test('开录初值下阈值 = 初值底噪 + 余量（比刚开录的底噪高，先保守）', () {
      expect(voiceThreshold(noiseFloorInit), closeTo(noiseFloorInit + voiceMargin, 1e-10));
    });

    test('可以覆盖绝对下限（会话里让 deps.voiceLevel 优先）', () {
      expect(voiceThreshold(0, 0.05), 0.05);
      expect(voiceThreshold(0.1, 0.05), closeTo(0.1 + voiceMargin, 1e-10));
    });
  });

  test('常量与 Web 版逐字一致', () {
    expect(voiceHangoverMs, 2500);
    expect(autoCycleGapMs, 600);
    expect(voiceLevel, 0.006);
    expect(voiceMargin, 0.008);
    expect(noiseFloorInit, 0.005);
    expect(levelPushMs, 40);
  });
}
