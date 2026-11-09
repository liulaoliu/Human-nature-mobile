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

/// 录音端口（跟读用）。
///
/// 硬约束：**录音只是当场听，不留文件**。`stop()` 实现方在返回之前就把临时文件
/// 删掉，只把时长交出去 —— 跟读记录里不存音频。
abstract class RecorderPort {
  /// 申请麦克风权限；拿到 true 才能开始录。
  Future<bool> ensurePermission();

  /// 开始录。实现方自己决定临时文件放哪，调用方不关心。
  Future<void> start();

  /// 当前电平 0–1（给 `TakeTracker` 用）。没在录的时候返回 0。
  Future<double> amplitude();

  /// 停止并**删除**临时文件，返回这次录了多久（毫秒）。失败返回 null。
  Future<int?> stop();

  /// 放弃这次录音（同样要删临时文件）。
  Future<void> discard();
}
