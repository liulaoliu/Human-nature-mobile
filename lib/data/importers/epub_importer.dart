/// EPUB 解包：zip 里按 spine 顺序取出每一章的正文。
///
/// 分层：`archive` 是平台无关的纯 Dart 包，但它属于「外部 IO 能力」，
/// 所以放在 `data/` 而不是 `core/`（core 保持能脱离任何包跑测试）。
/// 真正的 HTML → 文本、OPF 解析都在 `core/html_text.dart`，这里只负责解压与排序。
library;

import 'dart:convert';

import 'package:archive/archive.dart';

import '../../core/html_text.dart';

/// 一章：标题 + 正文（已去标签、按块分段）。
typedef EpubChapter = ({String title, String text});

/// 从 EPUB 的字节流里抽出所有章节。
///
/// · 先按 `META-INF/container.xml` 找 OPF，再按 spine 顺序取章节；
/// · 找不到 OPF（或 spine 空了）就退回「所有 .xhtml/.html 按文件名排序」；
/// · 一章都读不出正文时返回空列表，由调用方提示「EPUB 里没读到文本」。
List<EpubChapter> extractEpub(List<int> bytes) {
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    return const [];
  }

  final container = _readString(archive, 'META-INF/container.xml');
  final opfPath = container == null
      ? ''
      : RegExp('full-path="([^"]+)"').firstMatch(container)?.group(1) ?? '';

  var hrefs = <String>[];
  if (opfPath.isNotEmpty) {
    final opf = _readString(archive, opfPath);
    if (opf != null) hrefs = parseOpf(opf, opfPath);
  }
  if (hrefs.isEmpty) {
    hrefs = archive.files
        .map((f) => f.name)
        .where((n) => RegExp(r'\.(x?html?)$', caseSensitive: false).hasMatch(n))
        .toList()
      ..sort();
  }

  final out = <EpubChapter>[];
  for (final href in hrefs) {
    final raw = _readString(archive, href);
    if (raw == null) continue;
    final parsed = htmlToText(raw);
    if (parsed.text.trim().isEmpty) continue;
    out.add((title: parsed.title, text: parsed.text));
  }
  return out;
}

String? _readString(Archive archive, String name) {
  final file = archive.find(name);
  if (file == null || !file.isFile) return null;
  final data = file.readBytes();
  if (data == null) return null;
  // EPUB 规范要求 UTF-8；个别老书是带 BOM 的，`utf8.decode` 会连 BOM 一起解出来，
  // 交给 cleaner 时再处理（它本来就会压掉多余空白）。
  return utf8.decode(data, allowMalformed: true);
}
