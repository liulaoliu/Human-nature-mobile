// 离线例句（数据来自 Tatoeba，经 Web 版 tools/build-tatoeba.mjs 预处理）。
//
// 对应 Web 版 `src/core/tatoeba.ts`：解析紧凑 TSV（`word ⇥ en ⇥ zh`）、
// 按词查例句。网络 / asset 加载在 `lib/data/tatoeba_loader.dart`。
// 数据文件不存在时调用方自动降级（返回空），不影响其它功能。
library;

/// 一条离线例句：英文 + 中文翻译。
class TatoebaExample {
  const TatoebaExample({required this.en, required this.zh});

  final String en;
  final String zh;

  @override
  bool operator ==(Object other) =>
      other is TatoebaExample && other.en == en && other.zh == zh;

  @override
  int get hashCode => Object.hash(en, zh);
}

/// 解析好的例句库：小写词形 → 例句（每个词最多几条）。
class Tatoeba {
  const Tatoeba({required this.byWord});

  final Map<String, List<TatoebaExample>> byWord;
}

/// 每个词默认最多保留几条（与 Web 版一致）。
const int tatoebaLimit = 6;

/// 解析构建脚本产出的 TSV。[cap] = 每个词最多保留几条。
Tatoeba parseTatoeba(String tsv, {int cap = tatoebaLimit}) {
  final byWord = <String, List<TatoebaExample>>{};
  for (final line in tsv.split('\n')) {
    if (line.isEmpty) continue;
    final c = line.split('\t');
    if (c.length < 3) continue;
    final w = c[0].trim().toLowerCase();
    final en = c[1].trim();
    final zh = c[2].trim();
    if (w.isEmpty || en.isEmpty) continue;
    if (_hasNonAsciiLetter(w)) continue; // 中文/符号行不要
    final arr = byWord[w];
    if (arr == null) {
      byWord[w] = [TatoebaExample(en: en, zh: zh)];
      continue;
    }
    if (arr.length >= cap || arr.any((x) => x.en == en)) continue;
    arr.add(TatoebaExample(en: en, zh: zh));
  }
  return Tatoeba(byWord: byWord);
}

/// 只抽需要的词（给后台 isolate 用：6.5MB 全表不必搬回主 isolate）。
///
/// [words] 里放词形和原形都行；大小写不敏感。
Map<String, List<TatoebaExample>> examplesForWords(
  String tsv,
  Set<String> words, {
  int cap = tatoebaLimit,
}) {
  final want = <String>{
    for (final w in words)
      if (w.trim().isNotEmpty) w.trim().toLowerCase(),
  };
  if (want.isEmpty) return const {};
  final out = <String, List<TatoebaExample>>{};
  for (final line in tsv.split('\n')) {
    if (line.isEmpty) continue;
    final c = line.split('\t');
    if (c.length < 3) continue;
    final w = c[0].trim().toLowerCase();
    if (!want.contains(w)) continue;
    final en = c[1].trim();
    final zh = c[2].trim();
    if (en.isEmpty || _hasNonAsciiLetter(w)) continue;
    final arr = out[w];
    if (arr == null) {
      out[w] = [TatoebaExample(en: en, zh: zh)];
      continue;
    }
    if (arr.length >= cap || arr.any((x) => x.en == en)) continue;
    arr.add(TatoebaExample(en: en, zh: zh));
  }
  return out;
}

/// 按词形 / 原形查例句（先词形、后原形）。查不到返回 []。
List<TatoebaExample> examplesFor(
  Tatoeba t,
  String word, {
  String? lemma,
}) {
  for (final raw in <String>[word, lemma ?? '']) {
    final k = raw.trim().toLowerCase();
    if (k.isEmpty) continue;
    final hit = t.byWord[k];
    if (hit != null && hit.isNotEmpty) return hit;
  }
  return const [];
}

/// 第一列只接受字母 / 连字符 / 撇号 —— 防止数据里混进中文行。
bool _hasNonAsciiLetter(String w) => !RegExp(r"^[a-z][a-z'\-]*$").hasMatch(w);
