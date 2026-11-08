import '../../models/vocab.dart';
import 'review.dart';

/// 拼写判定的规则（纯函数）。
///
/// 产品口径：拼写是「能不能写出来」的硬门槛，不宽容、不重试。
/// 错一次就判「不认识」：SRS 记 again（进入重学）、打上「不认识」标签，
/// 由会话把它重排回队列，从头走一遍学习流程。
/// 与 Web 版 `src/core/vocab/spelling.ts` 一一对应。

// 标签常量定义在 `review.dart`（`needsMeaningCheck` 也要用），这里转出，
// 方便调用方只 import 一个文件。
export 'review.dart' show spellingMissTag;

String _norm(String s) => s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// 拼写比对：忽略大小写与首尾/连续空格，**不忽略字母错误**。
/// 不用 `lemmaOf` 兜底：拼成别的词形（ran / run）在拼写题里就是错。
bool spellingMatches(String input, String word) => _norm(input) == _norm(word);

/// 拼错后的词库：记 again（repetitions 归零 + 进入重学）并打「不认识」标签。
/// 只改这一条，其它条目保持原引用。
VocabLibrary markSpellingMiss(VocabLibrary library, String id, [DateTime? now]) {
  final reviewed = reviewItem(library, id, ReviewGrade.again, now);
  return reviewed.copyWith(
    items: [
      for (final it in reviewed.items)
        if (it.id == id && !it.tags.contains(spellingMissTag))
          it.copyWith(tags: [...it.tags, spellingMissTag])
        else
          it,
    ],
  );
}
