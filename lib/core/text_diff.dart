/// 词级文本比对：回答与原句「有多像」、逐词对照。
///
/// 事实来源是 Web 版 `src/core/backTranslate.ts` 里的 `compareToReference` /
/// `diffWords`；这里只搬纯算法，不带回译的提示词 / 批改 / 记录。
/// 金句课的「逆向默写」判分要用它，二期回译也复用同一份口径。
library;

/// 与原句的接近度。只用于「像不像原文」的展示，**不参与评分**。
class Closeness {
  const Closeness({
    required this.exact,
    required this.ratio,
    required this.tier,
  });

  /// 去掉标点 / 大小写 / 空白差异后是否完全一样。
  final bool exact;

  /// 词级重合度 0–1（保留三位小数）。
  final double ratio;

  /// `exact` / `near`(≥0.9) / `fair`(≥0.6) / `loose`
  final String tier;

  @override
  String toString() => 'Closeness(exact: $exact, ratio: $ratio, tier: $tier)';
}

/// 词级对照的一段。
class DiffPart {
  const DiffPart({required this.kind, required this.text});

  /// `same` / `add` / `del`
  final String kind;
  final String text;

  @override
  bool operator ==(Object other) =>
      other is DiffPart && other.kind == kind && other.text == text;

  @override
  int get hashCode => Object.hash(kind, text);

  @override
  String toString() => 'DiffPart($kind, "$text")';
}

final RegExp _curlySingle = RegExp('[\u2018\u2019]');
final RegExp _curlyDouble = RegExp('[\u201C\u201D]');
final RegExp _dashes = RegExp('[\u2013\u2014]');
final RegExp _spaces = RegExp(r'\s+');
final RegExp _trailingPunct = RegExp(r'[.!?]+$');
final RegExp _wordRun = RegExp(r"[\p{L}\p{N}]+(?:'[\p{L}]+)*", unicode: true);

String _foldQuotes(String text) => text
    .replaceAll(_curlySingle, "'")
    .replaceAll(_curlyDouble, '"');

/// 词级归一化：只保留字母/数字词（含内部撇号），大小写和弯引号不敏感。
List<String> wordsOf(String text) {
  final normalized = _foldQuotes(text).toLowerCase();
  return <String>[
    for (final m in _wordRun.allMatches(normalized)) m.group(0)!,
  ];
}

/// 严格到「标点/大小写之外完全一样」才算 exact；差一个词只算 near。
String normalizeExact(String text) => _foldQuotes(text)
    .replaceAll(_dashes, '-')
    .replaceAll(_spaces, ' ')
    .trim()
    .replaceAll(_trailingPunct, '')
    .toLowerCase();

int _lcsLength(List<String> a, List<String> b) {
  if (a.isEmpty || b.isEmpty) return 0;
  var prev = List<int>.filled(b.length + 1, 0);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0);
    for (var j = 1; j <= b.length; j++) {
      cur[j] = a[i - 1] == b[j - 1]
          ? prev[j - 1] + 1
          : (prev[j] > cur[j - 1] ? prev[j] : cur[j - 1]);
    }
    prev = cur;
  }
  return prev[b.length];
}

/// 和原句的接近度。
Closeness compareToReference(String answer, String reference) {
  final a = wordsOf(answer);
  final b = wordsOf(reference);
  final exact = normalizeExact(answer) == normalizeExact(reference);
  final ratio =
      (a.isEmpty && b.isEmpty) ? 1.0 : (2 * _lcsLength(a, b)) / (a.length + b.length);
  final clamped = ratio.clamp(0.0, 1.0);
  final tier = exact
      ? 'exact'
      : clamped >= 0.9
          ? 'near'
          : clamped >= 0.6
              ? 'fair'
              : 'loose';
  return Closeness(
    exact: exact,
    ratio: (clamped * 1000).round() / 1000,
    tier: tier,
  );
}

/// 词级对照。以原文为基准：
///   - `add`：原文有、你的答案没有（漏了 / 换了词）
///   - `del`：你的答案有、原文没有（多写 / 换了词）
///   - `same`：两边都有
List<DiffPart> diffWords(String answer, String reference) {
  final a = wordsOf(answer);
  final b = wordsOf(reference);
  final dp = List<List<int>>.generate(
    a.length + 1,
    (_) => List<int>.filled(b.length + 1, 0),
  );
  for (var i = a.length - 1; i >= 0; i--) {
    for (var j = b.length - 1; j >= 0; j--) {
      dp[i][j] = a[i] == b[j]
          ? dp[i + 1][j + 1] + 1
          : (dp[i + 1][j] > dp[i][j + 1] ? dp[i + 1][j] : dp[i][j + 1]);
    }
  }
  final out = <DiffPart>[];
  void push(String kind, String text) {
    if (out.isNotEmpty && out.last.kind == kind) {
      final last = out.removeLast();
      out.add(DiffPart(kind: kind, text: '${last.text} $text'));
    } else {
      out.add(DiffPart(kind: kind, text: text));
    }
  }

  var i = 0;
  var j = 0;
  while (i < a.length && j < b.length) {
    if (a[i] == b[j]) {
      push('same', a[i]);
      i++;
      j++;
    } else if (dp[i + 1][j] >= dp[i][j + 1]) {
      push('del', a[i]);
      i++;
    } else {
      push('add', b[j]);
      j++;
    }
  }
  while (i < a.length) {
    push('del', a[i]);
    i++;
  }
  while (j < b.length) {
    push('add', b[j]);
    j++;
  }
  return out;
}
