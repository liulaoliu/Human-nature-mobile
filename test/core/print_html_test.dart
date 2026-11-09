import 'package:dlaoshi_app/core/print_html.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('escapeHtml', () {
    test('转义 & < > "，且 & 先换不重复转义', () {
      expect(escapeHtml('a & b'), 'a &amp; b');
      expect(escapeHtml('<b>"x"</b>'), '&lt;b&gt;&quot;x&quot;&lt;/b&gt;');
      expect(escapeHtml('&lt;'), '&amp;lt;');
    });

    test('普通文本原样返回', () {
      expect(escapeHtml('In response to the pandemic.'), 'In response to the pandemic.');
      expect(escapeHtml('中文（括号）'), '中文（括号）');
    });
  });

  group('a4Document', () {
    test('外壳含 doctype / 标题 / A4 页边距 / 正文', () {
      final html = a4Document(title: '全库金句本', body: '<p>hi</p>');
      expect(html, startsWith('<!doctype html>'));
      expect(html, contains('<title>全库金句本</title>'));
      expect(html, contains('@page { size: A4; margin: 10mm; }'));
      expect(html, contains('<p>hi</p>'));
      expect(html, contains('font-size: 9pt'));
      expect(html, contains('line-height: 1.4'));
    });

    test('标题被转义；参数可覆盖', () {
      final html = a4Document(
        title: 'A & B',
        body: 'x',
        margin: '8mm',
        fontSize: '10pt',
        lineHeight: '1.6',
      );
      expect(html, contains('<title>A &amp; B</title>'));
      expect(html, contains('margin: 8mm'));
      expect(html, contains('font-size: 10pt'));
      expect(html, contains('line-height: 1.6'));
    });

    test('调用方样式追加在基础样式之后（同名选择器后写的赢）', () {
      final html = a4Document(
        title: 't',
        body: 'x',
        css: '.items { columns: 2; }',
      );
      expect(html, contains('.items { columns: 2; }'));
      expect(
        html.indexOf('.items { columns: 2; }'),
        greaterThan(html.indexOf('html, body { margin: 0; }')),
      );
    });

    test('空 css 不多出空行', () {
      final html = a4Document(title: 't', body: 'x');
      expect(html, isNot(contains('\n\n</style>')));
    });
  });
}
