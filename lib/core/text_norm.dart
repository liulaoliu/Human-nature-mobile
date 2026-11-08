/// 文本归一化的最小实现。
///
/// Web 版用 `String.prototype.normalize('NFKC')`；Dart 核心库没有 Unicode 归一化，
/// 引一个包只为了「全角转半角 + 连字拆开」不划算，所以这里只实现**对英语词形真正有用**
/// 的那部分：
///
/// - 全角 ASCII（U+FF01–U+FF5E）→ 半角；全角空格 U+3000 → 普通空格；
/// - 常见连字（ﬁ ﬂ ﬀ ﬃ ﬄ）拆成字母；
/// - 上标/下标数字、带圈数字**不处理**（词形里不会出现，处理了反而掩盖脏数据）。
///
/// 差异是已知的、写在文档里的：如果以后要处理带音标的语言或 CJK 兼容字，
/// 再换成真正的 NFKC 实现（届时 `word_test.dart` 要补用例）。
library;

const _fullWidthStart = 0xFF01;
const _fullWidthEnd = 0xFF5E;
const _fullWidthOffset = 0xFF01 - 0x21;

const _ligatures = <String, String>{
  '\uFB00': 'ff',
  '\uFB01': 'fi',
  '\uFB02': 'fl',
  '\uFB03': 'ffi',
  '\uFB04': 'ffl',
  '\uFB05': 'st',
  '\uFB06': 'st',
};

/// 近似 NFKC：只做全角 ASCII 与连字两项（见文件头说明）。
String nfkc(String input) {
  if (input.isEmpty) return input;
  final out = StringBuffer();
  for (final rune in input.runes) {
    if (rune >= _fullWidthStart && rune <= _fullWidthEnd) {
      out.writeCharCode(rune - _fullWidthOffset);
      continue;
    }
    if (rune == 0x3000) {
      out.write(' ');
      continue;
    }
    final ch = String.fromCharCode(rune);
    final lig = _ligatures[ch];
    if (lig != null) {
      out.write(lig);
      continue;
    }
    out.write(ch);
  }
  return out.toString();
}
