/// Model 层的边界（框架无关）。
///
/// 这里只有**纯数据类型与纯接口**：切块、手动锚点，以及跟读要用的朗读 / 录音端口。
/// 真正的存储实现在 `data/`、平台能力实现（`flutter_tts` / `record`）在 `services/`，
/// 由调用方注入（测试时给假实现）。
///
/// 对应 Web 版 `src/core/ports.ts` 里 `Chunk` / `ManualAnchor` 两个定义。
///
/// 说明：本文件是纯接口 / 纯数据声明，没有可执行逻辑，所以
/// `tool/check_core_tests.dart` 把它登记为「无需同名测试」的例外。
library;

import 'tts_engine.dart' show SpeechEngine;

/// 音频切块（VAD 或等分档位切出来的）。
class Chunk {
  const Chunk({required this.index, required this.start, required this.end});

  final int index;

  /// 起始秒。
  final double start;

  /// 结束秒。
  final double end;

  @override
  String toString() => 'Chunk($index, $start-$end)';
}

/// 手动对齐锚点：记 `atSec` 而不是块号，是为了换切块粒度后还能找回是哪一块
/// （块号会变，音频时间不会）。
class ManualAnchor {
  const ManualAnchor({
    required this.atSec,
    required this.startWord,
    required this.endWord,
    this.text,
  });

  /// 锚定时那一块在音频里的起始秒。
  final double atSec;

  /// 这段词在原文里的起止词序号 `[startWord, endWord)`。
  final int startWord;
  final int endWord;

  /// 锚定时选中的那段原文（词用空格连）。
  ///
  /// 改文本后词序号会整体挪位，靠它在新的词表里重新定位，
  /// 这样「改别处的错字」不会把已标好的进度打乱。
  final String? text;
}

/// 朗读端口（跟读用）。
abstract class SpeechPort {
  /// 读一段文字。实现方要保证 `await` 到「读完了」再返回，
  /// 否则界面会以为读瞬时结束、紧接着就开录。
  Future<void> speak(String text);

  /// 立刻停掉（用户点「停」、切句、退出页面时都要调）。
  Future<void> stop();

  /// 调语速（0–1 档，跟读一般 0.4–0.5）。实现方自己夹到合法区间。
  Future<void> setRate(double rate);

  /// 当前是否在朗读。
  bool get isSpeaking;
}

/// 「能挑合成引擎」的附加能力。
///
/// 为什么和 [SpeechPort] 分开：语速 / 朗读是任何实现都给得了的，
/// 而「这台机器上有几个合成器」只有系统 TTS 知道（网页、假实现都没有）。
/// 调用方用 `speech is SpeechEnginePort` 判断，判不到就不显示引擎选项，
/// 而不是要求每个实现都写两个空的 `throw UnimplementedError()`。
abstract class SpeechEnginePort {
  /// 现在装了哪些合成引擎；拿不到就给空表。
  Future<List<SpeechEngine>> engines();

  /// 换引擎；null = 系统默认（用户在手机设置里选的那个）。
  Future<void> setEngine(String? name);
}

/// 「朗读时按词回报进度」的附加能力（跟读高亮用）。
///
/// 安卓 26+ 的系统 TTS 有 `onRangeStart`，报的是**字符区间**（不是毫秒）；
/// 老系统只回一条整句区间，网页 / 假实现则完全没有。所以和 [SpeechPort] 分开：
/// 调用方用 `speech is SpeechProgressPort` 判断，判不到就是「这台设备不亮词」。
abstract class SpeechProgressPort {
  /// 订阅逐词进度；传 null 取消订阅。
  ///
  /// [start] / [end] 是相对**传给 `speak()` 的文本**的字符区间（左闭右开）。
  void setWordListener(void Function(int start, int end)? listener);
}

/// 录音端口（跟读用）。
///
/// 硬约束：**录音只在当场听，不留档**。`stop()` 之后临时文件会保留到最后一次
/// `clearTake()` / `discard()`（要让用户回放自己刚读的那一遍），但绝不上传、
/// 也不进任何存储 —— 跟读记录里只有时长。
abstract class RecorderPort {
  /// 申请麦克风权限；拿到 true 才能开始录。
  Future<bool> ensurePermission();

  /// 开始录。实现方自己决定临时文件放哪，调用方不关心。
  /// 上一次没清掉的临时文件会在这里顺带删掉。
  Future<void> start();

  /// 当前电平 0–1（给 `TakeTracker` 用）。没在录的时候返回 0。
  Future<double> amplitude();

  /// 停止录音，返回这次录了多久（毫秒）。失败返回 null。
  ///
  /// **不删临时文件** —— 上层要拿 [lastPath] 回放；清由 `clearTake()` 负责。
  Future<int?> stop();

  /// 上次录音的文件路径（没录过 / 已清掉时为 null）。
  String? get lastPath;

  /// 删掉上次录的临时文件（换句、放弃、退出页面时调）。
  Future<void> clearTake();

  /// 放弃这次录音（同样要删临时文件）。
  Future<void> discard();
}

/// 回放端口（跟读时听自己刚读的那一遍）。
abstract class PlaybackPort {
  /// 播一个本地文件。
  Future<void> play(String path);

  /// 停掉回放。
  Future<void> stop();

  /// 当前是否在放。
  bool get isPlaying;

  /// 播放进度 0–1；没有已知时长时返回 null。
  double? get progress;

  /// 释放底层播放器。
  Future<void> dispose();
}
