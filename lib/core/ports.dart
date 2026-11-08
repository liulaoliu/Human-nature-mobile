/// Model 层的边界（框架无关）。
///
/// 这里只有**纯数据类型**：切块与手动锚点。真正的存储 / 播放端口在 `data/` 里，
/// 由各仓储自己声明（测试时注入假实现）。
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
