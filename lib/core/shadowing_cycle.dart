/// 连续跟读（复读）的一圈：**放一句 → 我读一句 → 听我读的**，然后下一句。
///
/// 这里只有「一圈有哪几步、下一步是什么」的纯规则，不碰计时器、不碰端口：
///   - 真正的编排在 `services/shadowing_cycler.dart`（要 Timer / await / 取消）；
///   - 界面只读当前步决定按钮文案。
///
/// 为什么单独一个文件：`ShadowingViewModel` 的方法数已经顶到 40 的门禁上限，
/// 再往里加「开始 / 停止 / 下一步」就会超标；而这一步序本身是纯逻辑，抽出来正好。
///
/// 对应 Web 版 `src/ui/CycleRow.tsx` 的「连续跟读（标准音 → 录音 → 回放）」。
library;

/// 复读走到哪一步。
enum ShadowCycleStep {
  /// 没在复读。
  idle,

  /// 正在放标准音。
  reference,

  /// 正在录我读的。
  record,

  /// 正在放我刚读的。
  playback,
}

/// 每一步给用户看的字。
const Map<ShadowCycleStep, String> shadowCycleStepLabel = <ShadowCycleStep, String>{
  ShadowCycleStep.idle: '复读',
  ShadowCycleStep.reference: '正在放标准音…',
  ShadowCycleStep.record: '该你读了',
  ShadowCycleStep.playback: '听你读的…',
};

/// 这一步是不是「正在进行」（用来决定按钮要不要显示「停」）。
bool shadowCycleBusy(ShadowCycleStep step) => step != ShadowCycleStep.idle;

/// 一圈的下一步。
///
/// 顺序固定：标准音 → 录音 → 回放 → 结束。
/// [hasTake] 为 false（这轮没录成，比如没给麦克风权限）时跳过回放直接收尾 ——
/// 否则会卡在「听你读的…」上等一个永远不会响的播放器。
ShadowCycleStep shadowCycleNext(ShadowCycleStep step, {required bool hasTake}) {
  return switch (step) {
    ShadowCycleStep.idle => ShadowCycleStep.reference,
    ShadowCycleStep.reference => ShadowCycleStep.record,
    ShadowCycleStep.record =>
      hasTake ? ShadowCycleStep.playback : ShadowCycleStep.idle,
    ShadowCycleStep.playback => ShadowCycleStep.idle,
  };
}
