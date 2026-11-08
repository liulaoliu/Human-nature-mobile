/// 清洗模块：把任意来源的原始文本，清成「每段一行、段间空行」的规范文本。
///
/// 输入都是**用户粘进来的**字符串（从网页、PDF 阅读器、Word 里复制），
/// 所以伪影是「复制粘贴」那一类：
///
/// 实测两期的伪影正好相反，都要覆盖：
///   - 2021-06-12：软连字符 U+00AD 2807 个、ligature 1105 个、词内莫名空格
///   - 2016-09-10：行末连字符 + 换行 2048 个、ligature 1042 个、词粘连
///
/// 这里只处理「字符级 + 行结构」的确定性清理。词粘连（`emergingeconomies`）
/// 不在这里猜 —— 交给 `buildCleanupPrompt` 让 AI 修。
///
/// 对应 Web 版 `src/core/cleaner.ts`。
library;

import 'dictionary.dart';

/// 复制粘贴里常见连字（ligature），NFKC 也会转，但显式映射更可控、可测。
const Map<String, String> _ligatures = {
  '\ufb00': 'ff',
  '\ufb01': 'fi',
  '\ufb02': 'fl',
  '\ufb03': 'ffi',
  '\ufb04': 'ffl',
  '\ufb05': 'ft',
  '\ufb06': 'st',
};

final RegExp _crlf = RegExp('\r\n?');
final RegExp _ligRun = RegExp('[\ufb00-\ufb06]');
final RegExp _softHyphen = RegExp('\u00ad');
final RegExp _weirdSpace = RegExp('[\u00a0\u2007\u202f\u2009\u2028\u2029]');
final RegExp _lineTailHyphen = RegExp(r'([A-Za-z]+)-[ \t]*$');
final RegExp _lineHeadWord = RegExp(r'^[ \t]*([A-Za-z]+)');
final RegExp _trailingHyphen = RegExp(r'-[ \t]*$');
final RegExp _leadingSpace = RegExp(r'^[ \t]+');
final RegExp _trailingSpace = RegExp(r'[ \t]*$');
final RegExp _markerLine = RegExp(r'^[【〖［]');

/// 字符级归一化：
///   1. 统一换行
///   2. ligature → 普通字母
///   3. 软连字符 U+00AD 删除并直接接合（它是「可选断点」，本不该占字符）
///   4. 不换行空格 / 窄空格 → 普通空格
///
/// 注意：软连字符若实为实义连字符（如 `shake\u00adup`），删掉会丢连字符，
/// 由人工通读修正；后续可用词典兜。
String normalizeTypography(String input) {
  var s = input.replaceAll(_crlf, '\n');
  s = s.replaceAllMapped(_ligRun, (m) => _ligatures[m[0]] ?? m[0]!);
  s = s.replaceAll(_softHyphen, '');
  s = s.replaceAll(_weirdSpace, ' ');
  return s;
}

/// 行末连字符断词修复。
///   `com-\npared`  → `compared`（去掉连字符后是词典里的词）
///   `co-\nfounder` → `co-founder`（去掉连字符后不是词，保留连字符）
/// 下一行是空行时不合并（那是段落边界）。
List<String> _dehyphenateLines(List<String> lines) {
  final out = <String>[];
  for (final line in lines) {
    final prev = out.isEmpty ? null : out.last;
    final tail = prev == null ? null : _lineTailHyphen.firstMatch(prev);
    if (prev != null && tail != null && line.trim().isNotEmpty) {
      final stem = tail[1] ?? '';
      final nextWord = _lineHeadWord.firstMatch(line)?[1] ?? '';
      final joined = '$stem$nextWord';
      final withoutDash = prev.replaceAll(_trailingHyphen, '');
      final rest = line.replaceAll(_leadingSpace, '');
      out[out.length - 1] = nextWord.isNotEmpty && inDictionary(joined)
          ? '$withoutDash$rest'
          : '${prev.replaceAll(_trailingSpace, '')}$rest';
      continue;
    }
    out.add(line);
  }
  return out;
}

/// 手动加的「【…】」标记行（标题 / 导语）。这些行单独成段，不与相邻正文合并，
/// 免得清洗时把标题/导语和正文粘成一段。
bool _isMarkerLine(String line) => _markerLine.hasMatch(line.trim());

/// 按空行切段落：段内所有物理行合成一行（用空格连接），段间空一行。
///
/// 这同时覆盖了「合并行内硬换行」那条规则：既然每段最终输出为一行，
/// 段内的换行一律用空格接上，句末标点不会被粘掉字符。
String _groupParagraphs(List<String> lines) {
  final paras = <String>[];
  var cur = <String>[];
  void flush() {
    if (cur.isNotEmpty) {
      paras.add(cur.join(' '));
      cur = <String>[];
    }
  }

  for (final line in lines) {
    if (line.trim().isEmpty) {
      flush();
      continue;
    }
    final t = line.trim();
    if (_isMarkerLine(t)) {
      flush();
      paras.add(t);
      continue;
    }
    cur.add(t);
  }
  flush();
  return paras.join('\n\n');
}

/// 清洗主入口：原始文本 → 规范文本（每段一行、段间空行）。
///
/// 边界：空输入 / 纯空白 → `''`；单行原样返回；末尾有无换行都行。
String cleanText(String raw) {
  if (raw.isEmpty) return '';
  final normalized = normalizeTypography(raw);
  if (normalized.trim().isEmpty) return '';
  final lines = normalized.split('\n');
  return _groupParagraphs(_dehyphenateLines(lines));
}
