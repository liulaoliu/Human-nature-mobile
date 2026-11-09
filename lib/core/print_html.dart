/// A4 打印页的**公共外壳**（对应 Web `src/core/printHtml.ts`）：转义 + HTML 骨架 + 基础排版。
///
/// 为什么收口：词表、金句本、仿写批改导出各自抄一遍转义函数和同一段
/// `@page / font-family / .meta` 样式，三份实现必然漂。各导出器只保留自己那块
/// 布局样式（分栏数、条目间距），公共部分走这里。
///
/// 纯函数：不读环境、不碰文件，可直接单测。
library;

/// 转义 HTML 文本节点 / 属性值里的特殊字符（导出内容一律过这一层）。
///
/// 顺序要紧：`&` 必须第一个换，否则后面换出来的 `&lt;` 会被再转一次。
String escapeHtml(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

/// 包一层 A4 打印文档外壳；返回完整 HTML 字符串。
///
/// [css] 是调用方自己的布局样式，追加在基础样式之后 —— 要覆盖基础样式，
/// 直接写同名选择器即可（后写的赢）。
String a4Document({
  required String title,
  required String body,
  String css = '',
  String margin = '10mm',
  String fontSize = '9pt',
  String lineHeight = '1.4',
}) {
  final own = css.trim();
  return '''<!doctype html>
<html lang="zh"><head><meta charset="utf-8"><title>${escapeHtml(title)}</title>
<style>
@page { size: A4; margin: $margin; }
html, body { margin: 0; }
body { font-family: "Helvetica Neue", Arial, "PingFang SC", "Microsoft YaHei", sans-serif; color: #111; font-size: $fontSize; line-height: $lineHeight; }
${own.isEmpty ? '' : '$own\n'}</style></head><body>
$body
</body></html>''';
}
