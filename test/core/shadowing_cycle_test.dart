// 复读的一圈：标准音 → 录音 → 回放 → 收尾。
import 'package:dlaoshi_app/core/shadowing_cycle.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('步骤顺序', () {
    test('一圈走完：标准音 → 录音 → 回放 → 结束', () {
      var step = ShadowCycleStep.idle;
      final seen = <ShadowCycleStep>[step];
      for (var i = 0; i < 4; i++) {
        step = shadowCycleNext(step, hasTake: true);
        seen.add(step);
      }
      expect(seen, <ShadowCycleStep>[
        ShadowCycleStep.idle,
        ShadowCycleStep.reference,
        ShadowCycleStep.record,
        ShadowCycleStep.playback,
        ShadowCycleStep.idle,
      ]);
    });

    test('没录成（比如没给麦克风权限）：跳过回放直接收尾', () {
      final step = shadowCycleNext(ShadowCycleStep.record, hasTake: false);
      expect(step, ShadowCycleStep.idle, reason: '不能卡在「听你读的」等一个不会响的播放器');
    });

    test('idle 开始一圈一定是先放标准音', () {
      expect(shadowCycleNext(ShadowCycleStep.idle, hasTake: true), ShadowCycleStep.reference);
      expect(shadowCycleNext(ShadowCycleStep.idle, hasTake: false), ShadowCycleStep.reference);
    });
  });

  group('状态文案', () {
    test('四个步骤都有中文文案', () {
      for (final step in ShadowCycleStep.values) {
        expect(shadowCycleStepLabel[step], isNotNull, reason: '$step 应该有一句人话');
        expect(shadowCycleStepLabel[step]!.trim(), isNotEmpty);
      }
    });

    test('idle 不算进行中，其余三步算', () {
      expect(shadowCycleBusy(ShadowCycleStep.idle), isFalse);
      expect(shadowCycleBusy(ShadowCycleStep.reference), isTrue);
      expect(shadowCycleBusy(ShadowCycleStep.record), isTrue);
      expect(shadowCycleBusy(ShadowCycleStep.playback), isTrue);
    });
  });
}
