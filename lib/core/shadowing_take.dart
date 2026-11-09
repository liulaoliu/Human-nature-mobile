/// 判断「这句跟读完了没有」的小状态机。
///
/// 对应 Web 版 `src/state/recordingController.ts` 里那段「看电平、静了就收」的判断，
/// 抽成纯函数是为了能不碰麦克风就把边界测透：底噪怎么估、什么时候算说过话、
/// 静多久算读完。
///
/// 三个量各司其职（都来自 `recording.dart`，与 Web 版逐字一致）：
///   - 底噪 `noiseFloor`：开录给个初值，之后**只往低走**（取见过的最低电平）。
///   - 阈值：`voiceThreshold(底噪)` = max(绝对下限, 底噪 + 余量)，用加不用乘 ——
///     安静房间和吵房间都能用同一条式子。
///   - 静音时长 `hangoverMs`：最后一次「听到说话」之后安静这么久，就收。
///
/// 一条硬规则：**没听到过声音就不自动收**。否则一按录音就判定读完（房间里
/// 一开始恰好没声音），人会以为自己读完了。
library;

import 'recording.dart';

/// 一次录音的判定状态。
class TakeTracker {
  TakeTracker({
    this.hangoverMs = voiceHangoverMs,
    double noiseFloor = noiseFloorInit,
  }) : _floor = noiseFloor > 0 ? noiseFloor : noiseFloorInit;

  /// 说完静多久算读完（毫秒）。
  final int hangoverMs;

  double _floor;
  double _peak = 0;
  bool _voiceHeard = false;
  Duration? _lastVoiceAt;
  Duration? _startedAt;

  /// 当前估计的底噪。
  double get noiseFloor => _floor;

  /// 见过的最高电平（用来判断「真的开口了」而不是电流噪声）。
  double get peak => _peak;

  /// 有没有听到过说话（超过阈值的样本）。
  bool get voiceHeard => _voiceHeard;

  /// 当前说话判定阈值。
  double get threshold => voiceThreshold(_floor);

  /// 开始计时。
  void start(Duration at) {
    _startedAt = at;
  }

  /// 喂一个电平样本（0–1，取绝对值；坏值当 0）。
  void observe(double level, Duration at) {
    final v = level.isFinite ? level.abs() : 0.0;
    if (v > _peak) _peak = v;
    // 只在「低于当前估计」时才更新 —— 一次咳嗽的尖峰不该把底噪抬上去。
    if (v > 0 && v < _floor) _floor = v;
    if (v >= voiceThreshold(_floor)) {
      _voiceHeard = true;
      _lastVoiceAt = at;
    }
  }

  /// 从开录到现在过了多久。
  Duration elapsedAt(Duration at) =>
      _startedAt == null ? Duration.zero : at - _startedAt!;

  /// 该收了吗：听到过声音，并且已经静了够久。
  bool shouldStop(Duration at) {
    if (!_voiceHeard || _lastVoiceAt == null) return false;
    return (at - _lastVoiceAt!).inMilliseconds >= hangoverMs;
  }

  /// 到硬上限了吗（`recordCapMs` 给的那个兜底时长）。
  bool reachedCap(Duration at, int capMs) =>
      elapsedAt(at).inMilliseconds >= capMs;
}

/// 一句话「读得算不算过」：检测到声音 + 时长落在参考的 [low, high] 倍区间里。
///
/// 不判内容 —— 没有语音识别，就不假装判了内容。这里只回答两个能确定的问题：
/// 你有没有真的开口、你有没有读完（差太多说明漏读/读快了）。
enum TakeVerdict { ok, tooShort, tooLong, silent }

/// 参考时长的宽容区间：读得比参考快一半以上算漏读，慢一倍以上算卡住。
const double takeLowRatio = 0.5;
const double takeHighRatio = 2.0;

TakeVerdict judgeTake({
  required int elapsedMs,
  required bool voiceHeard,
  required double estimatedSec,
}) {
  if (!voiceHeard) return TakeVerdict.silent;
  final refMs = estimatedSec * 1000;
  if (refMs <= 0) return TakeVerdict.ok;
  if (elapsedMs < refMs * takeLowRatio) return TakeVerdict.tooShort;
  if (elapsedMs > refMs * takeHighRatio) return TakeVerdict.tooLong;
  return TakeVerdict.ok;
}

/// 判定的人话说明（界面直接显示）。
String takeVerdictLabel(TakeVerdict v) => switch (v) {
      TakeVerdict.ok => '这句读完了',
      TakeVerdict.tooShort => '比原文短不少，可能漏读了',
      TakeVerdict.tooLong => '停得久了点，下次一口气读完',
      TakeVerdict.silent => '没听到声音，检查一下麦克风',
    };
