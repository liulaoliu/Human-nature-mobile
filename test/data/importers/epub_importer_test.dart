import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:dlaoshi_app/data/importers/epub_importer.dart';
import 'package:flutter_test/flutter_test.dart';

/// 造一个最小可用的 EPUB：container.xml + OPF + 两章 + 一章没正文。
List<int> _makeEpub({bool withOpf = true}) {
  final archive = Archive();

  void add(String name, String content) {
    archive.addFile(ArchiveFile.string(name, content));
  }

  add('mimetype', 'application/epub+zip');
  add(
    'META-INF/container.xml',
    '<?xml version="1.0"?><container><rootfiles>'
        '<rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>'
        '</rootfiles></container>',
  );
  if (withOpf) {
    add(
      'OEBPS/content.opf',
      '<?xml version="1.0"?><package><manifest>'
          '<item id="c1" href="ch1.xhtml"/><item id="c2" href="ch2.xhtml"/>'
          '</manifest><spine><itemref idref="c2"/><itemref idref="c1"/></spine></package>',
    );
  }
  add(
    'OEBPS/ch1.xhtml',
    '<html><body><h1>Chapter One</h1><p>First &amp; only.</p></body></html>',
  );
  add(
    'OEBPS/ch2.xhtml',
    '<html><body><h1>Chapter Two</h1><p>Second <em>para</em> here.</p></body></html>',
  );
  add('OEBPS/empty.xhtml', '<html><body><p>   </p></body></html>');

  return ZipEncoder().encode(archive);
}

void main() {
  test('按 spine 顺序取章节，标题与正文都解析出来', () {
    final chapters = extractEpub(_makeEpub());
    expect(chapters.map((c) => c.title).toList(), ['Chapter Two', 'Chapter One']);
    expect(chapters.first.text, 'Chapter Two\n\nSecond para here.');
    expect(chapters.last.text, 'Chapter One\n\nFirst & only.');
  });

  test('没有正文的章被跳过', () {
    final chapters = extractEpub(_makeEpub());
    expect(chapters.any((c) => c.text.trim().isEmpty), isFalse);
  });

  test('没有 OPF 时退回按文件名排序扫 html', () {
    final chapters = extractEpub(_makeEpub(withOpf: false));
    expect(chapters.length, 2);
    expect(chapters.first.title, 'Chapter One');
    expect(chapters.last.title, 'Chapter Two');
  });

  test('不是 zip 的字节返回空列表，不抛错', () {
    expect(extractEpub(utf8.encode('not a zip at all')), isEmpty);
  });

  test('空 zip 返回空列表', () {
    expect(extractEpub(ZipEncoder().encode(Archive())), isEmpty);
  });
}
