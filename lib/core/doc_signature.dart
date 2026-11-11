/// 正文签名与「文章键」。
///
/// 为什么不用文章自己的 `id` 当键：同一篇文章被改过正文之后，按老位置续读
/// 就没有意义了（第 12 句已经变成别的内容）。签名由**正文**算出来，改一个字
/// 键就变，老进度自然作废。
///
/// 为什么键里还要带标识：空标题 / 同名 / 「未命名」的文章可能正文完全一样，
/// 只带签名会串篇。
///
/// 对照 Web 版 `src/core/docSignature.ts`。
library;

/// 正文签名：只由句子文本算（djb2），句间用换行分隔。
///
/// 句间必须分隔，否则「ab|c」与「a|bc」会撞签名。
String docSignature(Iterable<({String text})> sentences) {
  var h = 5381;
  for (final s in sentences) {
    final t = s.text;
    for (var i = 0; i < t.length; i++) {
      h = ((h << 5) + h + t.codeUnitAt(i)) & 0xFFFFFFFF;
    }
    h = ((h << 5) + h + 10) & 0xFFFFFFFF;
  }
  return h.toRadixString(36);
}

/// 文章键：格式 `标识@正文签名`。
///
/// 速读游标、阅读页滚动位置、听写游标这类「按文章记住点什么」的键，
/// 统一用它。
String articleKey(String identity, Iterable<({String text})> sentences) =>
    '$identity@${docSignature(sentences)}';
