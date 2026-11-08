/// EPUB / HTML 抽取的纯函数部分：HTML → {标题, 正文}，OPF → 章节文件顺序。
///
/// 对应 Web 版 `src/reader/importers.ts` 的 `htmlToText` / `parseOpf`。
/// Web 版用 `DOMParser`，这里没有 DOM，只能用正则做「够用就好」的解析 ——
/// 目标是从 XHTML 里抠出**按块分段的纯文本**，不做完整 HTML 解析。
/// 解 zip 的动作在 `lib/data/`（`archive` 包），core 不碰平台依赖。
library;

/// HTML 实体表（只覆盖 XHTML 里常见的那些）。
const Map<String, String> _entities = <String, String>{
  'amp': '&',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': "'",
  'nbsp': ' ',
  'mdash': '—',
  'ndash': '–',
  'hellip': '…',
  'ldquo': '“',
  'rdquo': '”',
  'lsquo': '‘',
  'rsquo': '’',
  'copy': '©',
  'middot': '·',
};

/// 块级标签：每个算一段。
const List<String> _blockTags = <String>[
  'p',
  'h1',
  'h2',
  'h3',
  'h4',
  'li',
  'blockquote',
];

/// HTML / XHTML → `{标题, 正文}`（按块元素分段，段间空行）。
///
/// · 先去掉 `<script>` / `<style>` / `<head>` 整段，免得把 CSS 当正文；
/// · 标题依次找 `h1` → `h2` → `h3` → `title`，都没有就是空串；
/// · 有块级标签就按块拼（每块内部空白压成一个空格）；
/// · 一个块都没有（比如纯 `<div>文本</div>`）就整段兜底。
({String title, String text}) htmlToText(String html) {
  // 标题要在丢掉 head 之前取，否则 `<title>` 永远读不到。
  var title = '';
  for (final tag in <String>['h1', 'h2', 'h3', 'title']) {
    final m = RegExp('<$tag\\b[^>]*>([\\s\\S]*?)</$tag>', caseSensitive: false)
        .firstMatch(html);
    if (m == null) continue;
    final t = _squash(_stripTags(m.group(1)!));
    if (t.isNotEmpty) {
      title = t;
      break;
    }
  }

  var s = html;
  for (final tag in <String>['script', 'style', 'head']) {
    s = s.replaceAll(
      RegExp('<$tag\\b[^>]*>[\\s\\S]*?</$tag>', caseSensitive: false),
      ' ',
    );
  }

  final blocks = <String>[];
  final pattern = RegExp(
    '<(${_blockTags.join('|')})\\b[^>]*>([\\s\\S]*?)</\\1>',
    caseSensitive: false,
  );
  for (final m in pattern.allMatches(s)) {
    final t = _squash(_stripTags(m.group(2)!));
    if (t.isNotEmpty) blocks.add(t);
  }
  if (blocks.isNotEmpty) return (title: title, text: blocks.join('\n\n'));

  final fallback = _squash(_stripTags(s).replaceAll(RegExp(r'[ \t]+'), ' '))
      .trim();
  return (title: title, text: fallback);
}

/// OPF 的 spine + manifest → 按阅读顺序排好的章节文件路径（相对 zip 根）。
///
/// `opfPath` 用来补相对路径（OPF 里的 href 是相对 OPF 自己所在目录的）。
List<String> parseOpf(String opf, String opfPath) {
  final base = opfPath.contains('/')
      ? opfPath.substring(0, opfPath.lastIndexOf('/') + 1)
      : '';
  final manifest = <String, String>{};
  final itemRe = RegExp(r'<item\b([^>]*)>', caseSensitive: false);
  for (final m in itemRe.allMatches(opf)) {
    final attrs = m.group(1)!;
    final id = _attr(attrs, 'id');
    final href = _attr(attrs, 'href');
    if (id != null && href != null) manifest[id] = base + href;
  }
  final out = <String>[];
  final refRe = RegExp(r'<itemref\b([^>]*)>', caseSensitive: false);
  for (final m in refRe.allMatches(opf)) {
    final idref = _attr(m.group(1)!, 'idref');
    if (idref == null) continue;
    final href = manifest[idref];
    if (href != null) out.add(href);
  }
  return out;
}

/// 从一段标签属性里取属性值（`"` 或 `'` 都认）。
String? _attr(String attrs, String name) {
  final m = RegExp(
    '\\b$name\\s*=\\s*(?:"([^"]*)"|\'([^\']*)\')',
    caseSensitive: false,
  ).firstMatch(attrs);
  if (m == null) return null;
  return m.group(1) ?? m.group(2);
}

/// 去掉所有标签（含自闭合），顺便还原实体。
String _stripTags(String html) {
  final noTags = html.replaceAll(RegExp(r'<[^>]*>'), ' ');
  return _decodeEntities(noTags);
}

String _decodeEntities(String text) {
  return text.replaceAllMapped(
    RegExp(r'&(#x?[0-9a-fA-F]+|[a-zA-Z]+);'),
    (m) {
      final body = m.group(1)!;
      if (body.startsWith('#x') || body.startsWith('#X')) {
        final code = int.tryParse(body.substring(2), radix: 16);
        return code == null ? m.group(0)! : String.fromCharCode(code);
      }
      if (body.startsWith('#')) {
        final code = int.tryParse(body.substring(1));
        return code == null ? m.group(0)! : String.fromCharCode(code);
      }
      return _entities[body.toLowerCase()] ?? m.group(0)!;
    },
  );
}

/// 空白压成一个空格并 trim（HTML 里换行/缩进都不算内容）。
String _squash(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();
