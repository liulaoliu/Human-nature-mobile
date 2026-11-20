/// 把 `LicenseRegistry` 里的许可条目排成一段「片头字幕」。
///
/// 为什么要单独一个文件：许可页要好看，但「哪些包、按什么顺序、摘要取多少字」
/// 是数据问题不是画面问题。把它拆出来就能脱离 widget 直接测，页面那边只负责
/// 把 [CrawlLine] 画成斜着往后退的字。
///
/// 一句话口径：字幕只做「引子」。GPL v3 全文三万多字符，塞进爬行字幕既没人
/// 看得完也没法复制，所以完整文本仍然走「许可全文」那个入口（Flutter 自带的
/// `LicensePage`）。这里给每个包留一段摘要，让人知道包里到底收了什么。
library;

import 'package:flutter/foundation.dart' show LicenseEntry, immutable;

/// 一行字幕的语气。
enum CrawlKind {
  /// 大标题（片名）。
  title,

  /// 副标题（谁的东西）。
  subtitle,

  /// 空行，只占高度。
  gap,

  /// 包名。
  packageName,

  /// 包名下面那行灰色摘要。
  body,
}

/// 字幕里的一行。
@immutable
class CrawlLine {
  const CrawlLine(this.text, this.kind);

  final String text;
  final CrawlKind kind;

  @override
  bool operator ==(Object other) =>
      other is CrawlLine && other.text == text && other.kind == kind;

  @override
  int get hashCode => Object.hash(text, kind);

  @override
  String toString() => 'CrawlLine(${kind.name}, $text)';
}

/// 摘要最多留多少字符。
///
/// 120 大约是手机上一行半（字号随透视缩到很小，实际看着是「一串小字」）。
/// 再长会拖慢爬行速度，也没信息量。
const int crawlExcerptChars = 120;

/// 把许可条目排成字幕。
///
/// 同一个包可能有多条 `LicenseEntry`（Flutter 会把同一 license 的多个段落
/// 合并，但不同来源仍可能重复），这里按出现顺序去重，保留第一条非空摘要。
List<CrawlLine> buildLicenseScript(
  Iterable<LicenseEntry> entries, {
  String appName = 'D哥帮你办',
}) {
  final seen = <String>{};
  final packages = <String, String>{};
  for (final entry in entries) {
    final excerpt = _excerpt(entry);
    for (final name in entry.packages) {
      if (name.trim().isEmpty) continue;
      final key = name.trim();
      if (seen.add(key)) packages[key] = excerpt;
    }
  }

  final lines = <CrawlLine>[
    const CrawlLine('开 源 许 可', CrawlKind.title),
    const CrawlLine('', CrawlKind.gap),
    CrawlLine('$appName 随包第三方组件', CrawlKind.subtitle),
    const CrawlLine('', CrawlKind.gap),
    CrawlLine('共 ${packages.length} 项', CrawlKind.subtitle),
    const CrawlLine('', CrawlKind.gap),
    const CrawlLine('', CrawlKind.gap),
  ];

  for (final entry in packages.entries) {
    lines
      ..add(CrawlLine(entry.key, CrawlKind.packageName))
      ..add(CrawlLine(entry.value, CrawlKind.body))
      ..add(const CrawlLine('', CrawlKind.gap));
  }

  lines
    ..add(const CrawlLine('', CrawlKind.gap))
    ..add(const CrawlLine('以上组件的许可全文', CrawlKind.subtitle))
    ..add(const CrawlLine('在「许可全文」里可以逐条展开', CrawlKind.subtitle))
    ..add(const CrawlLine('', CrawlKind.gap))
    ..add(const CrawlLine('GPL v3 的完整文本随包附带', CrawlKind.body))
    ..add(const CrawlLine('', CrawlKind.gap));

  return lines;
}

/// 取一条许可的前 [crawlExcerptChars] 个字符，空白折叠成单个空格。
///
/// 折叠是必须的：GPL 全文里有大量缩进和换行，原样截 120 字可能只剩几个词。
String _excerpt(LicenseEntry entry) {
  final buffer = StringBuffer();
  for (final paragraph in entry.paragraphs) {
    buffer.write(' ${paragraph.text}');
  }
  final flat = buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  if (flat.isEmpty) return '（没有正文）';
  if (flat.length <= crawlExcerptChars) return flat;
  return '${flat.substring(0, crawlExcerptChars)}…';
}
