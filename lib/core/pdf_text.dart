/// PDF 抽文的纯函数部分：页码范围解析 + 文本项拼行。
///
/// 对应 Web 版 `src/reader/importers.ts` 的 `parsePageRange` / `itemsToText`。
/// 真正的 PDF 解码（pdf.js）在浏览器里；安卓侧换成原生库后，仍然把
/// 「一页的文本项」喂进这里拼行，所以这两段逻辑必须与平台无关。
///
/// 注意：整期 Economist 的分篇仍要靠离线工具（字体 + 版面几何），
/// 这里适合单篇 PDF、书、格式规整的文档。
library;

/// `14-16,20` → `[14,15,16,20]`；空则全文（1..total）。
///
/// 越界被夹到 `[1, total]`；认不出的片段直接忽略（比抛错友好）。
List<int> parsePageRange(String? range, int total) {
  if (range == null || range.trim().isEmpty) {
    return List<int>.generate(total, (i) => i + 1);
  }
  final out = <int>{};
  for (final part in range.split(',')) {
    final piece = part.trim();
    final span = RegExp(r'^(\d+)\s*-\s*(\d+)$').firstMatch(piece);
    if (span != null) {
      final a = int.parse(span.group(1)!);
      final b = int.parse(span.group(2)!);
      final lo = a < 1 ? 1 : a;
      final hi = b > total ? total : b;
      for (var i = lo; i <= hi; i++) {
        out.add(i);
      }
    } else if (RegExp(r'^\d+$').hasMatch(piece)) {
      final n = int.parse(piece);
      if (n >= 1 && n <= total) out.add(n);
    }
  }
  final list = out.toList()..sort();
  return list;
}

/// 一页的文本项 → 文本；靠纵向间距断行、大的间距当段落。
///
/// 文本项形状（与 pdf.js 的 `getTextContent().items` 一致）：
/// `{str, transform[5]=y, height, hasEOL}`。没有 `str` 的项直接跳过。
String pdfItemsToText(List<Object?> items) {
  final lines = <String>[];
  var cur = '';
  double? lastY;
  var lastH = 10.0;
  for (final raw in items) {
    if (raw is! Map) continue;
    final str = raw['str'];
    if (str is! String) continue;
    final transform = raw['transform'];
    final y = (transform is List && transform.length > 5)
        ? _numOf(transform[5]) ?? lastY ?? 0
        : lastY ?? 0;
    final h = _numOf(raw['height']) ?? lastH;
    if (lastY != null && (y - lastY).abs() > h * 0.8) {
      final t = cur.trim();
      if (t.isNotEmpty) lines.add(t);
      cur = '';
      if ((y - lastY).abs() > h * 1.8) lines.add('');
    }
    cur += str;
    if (raw['hasEOL'] == true) {
      final t = cur.trim();
      if (t.isNotEmpty) lines.add(t);
      cur = '';
    }
    lastY = y;
    lastH = h;
  }
  final tail = cur.trim();
  if (tail.isNotEmpty) lines.add(tail);
  return lines.join('\n');
}

double? _numOf(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}
