// 复读编排：标准音 → 录音 → 回放，以及「随时能停」。
//
// 编排器不认识界面也不认识存储，所以这里全用回调替身，不碰平台通道。
import 'package:dlaoshi_app/core/shadowing_cycle.dart';
import 'package:dlaoshi_app/services/shadowing_cycler.dart';
import 'package:flutter_test/flutter_test.dart';

/// 记下每一步被调用的顺序，方便断言「先放标准音再录音」。
class _Log {
  final List<String> calls = <String>[];
  final List<ShadowCycleStep> steps = <ShadowCycleStep>[];
  bool completed = false;
  bool? doneCompleted;

  ShadowCycleHooks hooks({
    bool recordOk = true,
    Future<void> Function()? onSpeak,
    Future<void> Function()? onRecord,
    Future<void> Function()? onPlay,
  }) {
    return ShadowCycleHooks(
      speakReference: () async {
        calls.add('ref');
        if (onSpeak != null) await onSpeak();
      },
      recordOnce: () async {
        calls.add('rec');
        if (onRecord != null) await onRecord();
        return recordOk;
      },
      playTake: () async {
        calls.add('play');
        if (onPlay != null) await onPlay();
      },
      onStep: steps.add,
      onDone: (bool ok) {
        completed = true;
        doneCompleted = ok;
      },
    );
  }
}

void main() {
  test('一圈按顺序走：标准音 → 录音 → 回放', () async {
    final log = _Log();
    final runner = ShadowCycleRunner(hooks: log.hooks());

    final ok = await runner.start();

    expect(ok, isTrue);
    expect(log.calls, <String>['ref', 'rec', 'play']);
    expect(log.steps, <ShadowCycleStep>[
      ShadowCycleStep.reference,
      ShadowCycleStep.record,
      ShadowCycleStep.playback,
      ShadowCycleStep.idle,
    ]);
    expect(runner.running, isFalse);
    expect(runner.step, ShadowCycleStep.idle);
    expect(log.doneCompleted, isTrue);
  });

  test('没录成：跳过回放，直接收尾', () async {
    final log = _Log();
    final runner = ShadowCycleRunner(hooks: log.hooks(recordOk: false));

    final ok = await runner.start();

    expect(ok, isFalse, reason: '没录成不算走完一圈');
    expect(log.calls, <String>['ref', 'rec']);
    expect(log.steps, isNot(contains(ShadowCycleStep.playback)));
    expect(log.doneCompleted, isFalse);
  });

  test('中途 stop：后面的步骤不再执行', () async {
    final log = _Log();
    late ShadowCycleRunner runner;
    runner = ShadowCycleRunner(
      hooks: log.hooks(onSpeak: () async => runner.stop()),
    );

    final ok = await runner.start();

    expect(ok, isFalse);
    expect(log.calls, <String>['ref'], reason: '标准音被 stop 打断后不该开录');
    expect(log.doneCompleted, isFalse);
  });

  test('stop 之后不再触发 onStep 的变化（停在 idle）', () async {
    final log = _Log();
    final runner = ShadowCycleRunner(hooks: log.hooks());

    await runner.start();
    runner.stop();

    expect(runner.step, ShadowCycleStep.idle);
    expect(log.completed, isTrue);
  });

  test('正在跑的时候再 start 会被拒（不叠两圈）', () async {
    final log = _Log();
    late ShadowCycleRunner runner;
    bool second = true;
    runner = ShadowCycleRunner(
      hooks: log.hooks(
        onSpeak: () async {
          // 第一圈还在放标准音时，再点一次开始。
          second = await runner.start();
        },
      ),
    );

    await runner.start();

    expect(second, isFalse, reason: '已经在跑就别再开一圈');
    expect(log.calls, <String>['ref', 'rec', 'play']);
  });

  test('跑完之后可以再 start 一圈', () async {
    final log = _Log();
    final runner = ShadowCycleRunner(hooks: log.hooks());

    expect(await runner.start(), isTrue);
    expect(await runner.start(), isTrue);
    expect(log.calls, <String>['ref', 'rec', 'play', 'ref', 'rec', 'play']);
  });
}
