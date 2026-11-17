/// 朗读用的切块：**切原文**，不是切音素串。
///
/// 为什么要在 Dart 侧切（2026-11-17）：官方 `kittentts/onnx_model.py` 的顺序是
/// `chunk_text(text) → 每块 phonemize → 每块 style 行取 min(len(该块原文), 399)`。
/// 如果先音素化整段再切，块边界会落在音素词中间（`compan|ies`），而且 style 行
/// 会按音素长度取（音素比英文长 10% 左右，systematically 偏后十几行）。
///
/// 这个文件与 `packages/neural_tts/android/.../engines/KittenEngine.kt` 的
/// `chunkText` / `ensurePunctuation` 逐行对齐，判据见
/// `test/core/tts_chunk_test.dart` 与 `test/services/kitten_chunking_test.dart`。
library;

/// 每块**原文**的最大字符数（官方 `chunk_text(max_len=400)`）。
const int ttsChunkMaxLen = 400;

/// 块里至少要有一个字母或数字才值得合成。
///
/// 纯标点的块（`...`、`—`）是分句的副产物：官方 `chunk_text` 里
/// `re.split(r'[.!?]+', text)` 会把连续标点切成空串，然后被 `if` 过滤掉；
/// Dart 的 `(?<=[.!?]+)` 切法保留标点，于是 `...` 会变成三块 `.`。
/// 这类块喂给模型只会拖出一段噪声，直接丢掉。
final RegExp _ttsChunkContent = RegExp(r'[\p{L}\p{N}]', unicode: true);

bool _hasContent(String text) => _ttsChunkContent.hasMatch(text);

/// 按官方口径把 [text] 切成块。
///
/// 规则：按句末标点 `[.!?]+` 分句（**保留**标点，否则每块都得靠补逗号找回来）→
/// 句子本身不超 [maxLen] 就直接用 → 超长按词拼到不超过 [maxLen] →
/// 每块末尾保证有标点。
List<String> ttsChunkText(String text, {int maxLen = ttsChunkMaxLen}) {
  final chunks = <String>[];
  for (final raw in text.split(RegExp(r'(?<=[.!?]+)'))) {
    final sentence = raw.trim();
    if (!_hasContent(sentence)) continue;
    if (sentence.length <= maxLen) {
      chunks.add(ensureTtsPunctuation(sentence));
      continue;
    }
    final buffer = StringBuffer();
    var length = 0;
    for (final word in sentence.split(RegExp(r'\s+'))) {
      if (length == 0) {
        buffer.write(word);
        length = word.length;
      } else if (length + 1 + word.length <= maxLen) {
        buffer.write(' ');
        buffer.write(word);
        length += 1 + word.length;
      } else {
        chunks.add(ensureTtsPunctuation(buffer.toString()));
        buffer
          ..clear()
          ..write(word);
        length = word.length;
      }
    }
    if (length > 0) chunks.add(ensureTtsPunctuation(buffer.toString()));
  }
  return chunks;
}

/// 官方 `ensure_punctuation`：结尾不是 `. ! ? , ; :` 就补一个逗号。
///
/// 没有标点收尾的块，模型容易拖音。
String ensureTtsPunctuation(String text) {
  final s = text.trim();
  if (s.isEmpty) return s;
  const terminators = '.!?,;:';
  return terminators.contains(s[s.length - 1]) ? s : '$s,';
}
