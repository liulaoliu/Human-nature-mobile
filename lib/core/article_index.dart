/// 文章标识 ↔ 路由片段（slug）的互相转换。
///
/// 内部标识长这样：`b:005 Leaders - Post-truth politics`、`s:saved:005 Leaders@a1b2c3`。
/// 直接塞进地址栏会出现一堆 `%3A` / `%20`，既不像正规路由也没法手敲。
/// 所以 URL 用 slug（`005-leaders-post-truth-politics`），内部标识留在内存里。
/// slug 不是标识的编码，只是一个**稳定别名**：同一篇文章永远算出同一个 slug。
///
/// 对应 Web 版 `src/core/articleSlug.ts`。
library;

/// 标题 → URL 片段：小写、去重音、非字母数字一律变连字符。
///
/// 只保留 `[a-z0-9-]`，URL 里永远不会出现需要百分号转义的字符。
/// 中文标题会被整段剥掉（返回空串），由调用方退回 `article-<hash>`。
String slugify(String text) {
  var s = _stripDiacritics(text).toLowerCase();
  s = s.replaceAll(RegExp('[^a-z0-9]+'), '-');
  s = s.replaceAll(RegExp('^-+|-+\$'), '');
  if (s.length > 72) s = s.substring(0, 72);
  return s.replaceAll(RegExp('-+\$'), '');
}

/// 去掉组合用变音符号（é → e）。Dart 没有内置 NFKD，这里覆盖拉丁补充段。
String _stripDiacritics(String text) {
  final out = StringBuffer();
  for (final rune in text.runes) {
    final mapped = _diacritics[rune];
    if (mapped != null) {
      out.write(mapped);
    } else if (rune >= 0x0300 && rune <= 0x036F) {
      // 组合用变音符号本身：丢掉
    } else {
      out.writeCharCode(rune);
    }
  }
  return out.toString();
}

const Map<int, String> _diacritics = <int, String>{
  0x00C0: 'A', 0x00C1: 'A', 0x00C2: 'A', 0x00C3: 'A', 0x00C4: 'A', 0x00C5: 'A',
  0x00C7: 'C', 0x00C8: 'E', 0x00C9: 'E', 0x00CA: 'E', 0x00CB: 'E',
  0x00CC: 'I', 0x00CD: 'I', 0x00CE: 'I', 0x00CF: 'I',
  0x00D1: 'N', 0x00D2: 'O', 0x00D3: 'O', 0x00D4: 'O', 0x00D5: 'O',
  0x00D6: 'O', 0x00D8: 'O', 0x00D9: 'U', 0x00DA: 'U', 0x00DB: 'U',
  0x00DC: 'U', 0x00DD: 'Y', 0x00DF: 'ss',
  0x00E0: 'a', 0x00E1: 'a', 0x00E2: 'a', 0x00E3: 'a', 0x00E4: 'a', 0x00E5: 'a',
  0x00E7: 'c', 0x00E8: 'e', 0x00E9: 'e', 0x00EA: 'e', 0x00EB: 'e',
  0x00EC: 'i', 0x00ED: 'i', 0x00EE: 'i', 0x00EF: 'i',
  0x00F1: 'n', 0x00F2: 'o', 0x00F3: 'o', 0x00F4: 'o', 0x00F5: 'o',
  0x00F6: 'o', 0x00F8: 'o', 0x00F9: 'u', 0x00FA: 'u', 0x00FB: 'u',
  0x00FC: 'u', 0x00FD: 'y', 0x00FF: 'y',
};

/// 稳定短哈希（FNV-1a，转 4 位 36 进制）。
///
/// 只用来**消歧**：两篇 slug 撞了（同名标题、或都是中文标题被剥成空串）时，
/// 追加它把两者分开。同一输入永远同一结果，刷新/收藏都不会变。
String shortHash(String text) {
  var h = 0x811C9DC5; // 2166136261
  for (final unit in text.codeUnits) {
    h ^= unit;
    h = (h * 0x01000193) & 0xFFFFFFFF; // Math.imul(h, 16777619)
  }
  final base = h.toRadixString(36);
  final tail = base.length <= 4 ? base : base.substring(base.length - 4);
  return tail.padLeft(4, '0');
}

/// 文章标识 ↔ slug 的双向索引。
///
/// 标识（ref）是内部用的：
///   `b:<文章目录的键>`   内置文章
///   `s:<SavedArticle.id>` 已保存 / 手动粘贴
class ArticleIndex {
  const ArticleIndex(this._byRef, this._bySlug);

  const ArticleIndex.empty()
      : _byRef = const {},
        _bySlug = const {};

  final Map<String, String> _byRef;
  final Map<String, String> _bySlug;

  /// 标识 → slug；没这篇文章返回空串。
  String slugOf(String ref) => _byRef[ref] ?? '';

  /// slug → 标识；认不出来返回空串（说明链接指向的文章已经不在库里）。
  String refOf(String slug) => _bySlug[slug] ?? '';
}

/// 文章目录（键 → 标题）与已保存文章一起建索引。
///
/// 同一组数据永远得到同一套 slug（顺序只影响冲突时谁拿裸 slug，
/// 而这里已按 key/id 排序，所以是确定的）。
///
/// 规则：
///   · 标题能算出 slug 就用它；
///   · 算不出来（纯中文 / 纯符号）→ `article-<hash>`；
///   · 算出来但和别人撞了 → 双方都加 `<hash>` 后缀（不是「先到先得」，
///     否则删掉一篇文章会让另一篇的 URL 悄悄变掉）。
ArticleIndex buildArticleIndex(
  Map<String, String> catalog,
  List<({String id, String title})> saved,
) {
  final entries = <({String ref, String title})>[];
  final keys = catalog.keys.toList()..sort();
  for (final key in keys) {
    final title = (catalog[key] ?? '').isEmpty ? key : catalog[key]!;
    entries.add((ref: 'b:$key', title: title));
  }
  final sortedSaved = [...saved]..sort((a, b) => a.id.compareTo(b.id));
  for (final a in sortedSaved) {
    entries.add((ref: 's:${a.id}', title: a.title));
  }
  if (entries.isEmpty) return const ArticleIndex.empty();

  final bases = entries.map((e) => slugify(e.title)).toList();
  final seen = <String, int>{};
  for (final b in bases) {
    seen[b] = (seen[b] ?? 0) + 1;
  }

  final byRef = <String, String>{};
  final bySlug = <String, String>{};
  for (var i = 0; i < entries.length; i++) {
    final e = entries[i];
    final base = bases[i];
    final dup = base.isEmpty || (seen[base] ?? 0) > 1;
    final slug = dup
        ? '${base.isEmpty ? 'article' : base}-${shortHash(e.ref)}'
        : base;
    byRef[e.ref] = slug;
    bySlug[slug] = e.ref;
  }
  return ArticleIndex(byRef, bySlug);
}
