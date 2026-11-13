/// 复读的编排器：**放一句 → 我读一句 → 听我读的**，一圈一圈往下走。
///
/// 为什么不写在 `ShadowingViewModel` 里：那个类的方法数已经顶到 40 的门禁上限。
/// 这里只做「按顺序调用几个回调 + 能被取消」，不认识界面也不认识存储。
///
/// 三条硬规矩：
///   1. **随时能停**：`stop()` 之后不再触发任何回调（每个 await 之后都查 `_stopped`）；
///   2. **切句 / 换篇 / 录新音 / 页面退出都要停** —— 由调用方在这些钩子里调 `stop()`；
///   3. **不自己造计时器轮询**：录音的收尾由 ViewModel 的 `TakeTracker` 管，
///      这里只等一个「录完了」的 Future。
library;

import 'dart:async';

import '../core/shadowing_cycle.dart';

/// 一圈里各步要做的事，由调用方注入。
///
/// 全是 `Future<void>`：实现方要 `await` 到「这一步真的完了」再返回
/// （比如标准音读完、录音收完、回放播完），否则步与步之间会叠在一起出声。
class ShadowCycleHooks {
  const ShadowCycleHooks({
    required this.speakReference,
    required this.recordOnce,
    required this.playTake,
    this.onStep,
    this.onDone,
  });

  /// 放标准音（要等到读完）。
  final Future<void> Function() speakReference;

  /// 录一遍并等到录完；返回 false 表示没录成（没权限 / 出错）。
  final Future<bool> Function() recordOnce;

  /// 放我刚读的那一遍（要等到播完）。
  final Future<void> Function() playTake;

  /// 每一步变化时通知界面。
  final void Function(ShadowCycleStep step)? onStep;

  /// 一圈走完（正常收尾或被 stop 打断都会调，`completed` 区分）。
  final void Function(bool completed)? onDone;
}

/// 复读编排器。一个实例管一圈；要再跑一圈就再 `start()`。
class ShadowCycleRunner {
  ShadowCycleRunner({required this.hooks});

  final ShadowCycleHooks hooks;

  ShadowCycleStep _step = ShadowCycleStep.idle;
  bool _stopped = false;
  bool _running = false;

  /// 当前走到哪一步。
  ShadowCycleStep get step => _step;

  /// 正在跑一圈。
  bool get running => _running;

  /// 跑一圈：标准音 → 录音 → 回放 → 收尾。
  ///
  /// 返回 true 表示这一圈走完了；被 [stop] 打断返回 false。
  Future<bool> start() async {
    if (_running) return false;
    _running = true;
    _stopped = false;
    var completed = false;
    try {
      _setStep(ShadowCycleStep.reference);
      if (_stopped) return false;
      await hooks.speakReference();
      if (_stopped) return false;

      _setStep(ShadowCycleStep.record);
      final ok = await hooks.recordOnce();
      if (_stopped) return false;

      // 没录成就直接收尾（照 `shadowCycleNext` 的口径，别卡在回放上）。
      final next = shadowCycleNext(ShadowCycleStep.record, hasTake: ok);
      if (next == ShadowCycleStep.idle) return false;

      _setStep(ShadowCycleStep.playback);
      await hooks.playTake();
      if (_stopped) return false;
      completed = true;
      return true;
    } finally {
      _running = false;
      _setStep(ShadowCycleStep.idle);
      // completed 只在「真的走完回放」时为 true —— 没录成 / 被打断都算没走完，
      // 否则调用方会以为可以接着自动下一句。
      hooks.onDone?.call(completed);
    }
  }

  /// 停下（幂等）。
  void stop() {
    if (_stopped) return;
    _stopped = true;
    _running = false;
    _setStep(ShadowCycleStep.idle);
  }

  void _setStep(ShadowCycleStep step) {
    if (_step == step) return;
    _step = step;
    hooks.onStep?.call(step);
  }
}
