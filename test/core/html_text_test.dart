import 'package:dlaoshi_app/core/html_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('htmlToText', () {
    test('按块级标签分段，段间空行（标题块也算一段）', () {
      final r = htmlToText(
        '<html><body><h1>The Title</h1><p>First para.</p><p>Second.</p></body></html>',
      );
      expect(r.title, 'The Title');
      expect(r.text, 'The Title\n\nFirst para.\n\nSecond.');
    });

    test('script / style / head 整段丢掉', () {
      final r = htmlToText(
        '<html><head><title>Doc</title><style>p{color:red}</style></head>'
        '<body><script>var x = 1;</script><p>Real text.</p></body></html>',
      );
      expect(r.title, 'Doc');
      expect(r.text, 'Real text.');
    });

    test('标签内多空白压成一个空格', () {
      final r = htmlToText('<p>Hello\n    world   again</p>');
      expect(r.text, 'Hello world again');
    });

    test('实体被还原', () {
      final r = htmlToText('<p>Tom &amp; Jerry &mdash; 5 &lt; 6 &nbsp;done</p>');
      expect(r.text, 'Tom & Jerry — 5 < 6 done');
    });

    test('数字实体（十进制与十六进制）', () {
      final r = htmlToText('<p>&#20320;&#x597d;</p>');
      expect(r.text, '你好');
    });

    test('没有块级标签时整段兜底', () {
      final r = htmlToText('<div><span>Loose</span> <span>text</span></div>');
      expect(r.text, 'Loose text');
    });

    test('标题优先级 h1 > h2 > h3 > title', () {
      expect(
        htmlToText('<title>T</title><h2>H2</h2><h1>H1</h1>').title,
        'H1',
      );
      expect(htmlToText('<title>T</title><h2>H2</h2>').title, 'H2');
      expect(htmlToText('<title>T</title>').title, 'T');
    });

    test('空 HTML 返回空标题空正文', () {
      final r = htmlToText('');
      expect(r.title, '');
      expect(r.text, '');
    });
  });

  group('parseOpf', () {
    const opf = '''
<?xml version="1.0"?>
<package>
  <manifest>
    <item id="c1" href="chap1.xhtml" media-type="application/xhtml+xml"/>
    <item id="c2" href="chap2.xhtml" media-type="application/xhtml+xml"/>
    <item id="nc" href="nav.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine>
    <itemref idref="c2"/>
    <itemref idref="c1"/>
  </spine>
</package>
''';

    test('按 spine 顺序返回，并补上 OPF 所在目录前缀', () {
      final hrefs = parseOpf(opf, 'OEBPS/content.opf');
      expect(hrefs, ['OEBPS/chap2.xhtml', 'OEBPS/chap1.xhtml']);
    });

    test('OPF 在根目录时不加前缀', () {
      expect(parseOpf(opf, 'content.opf'), ['chap2.xhtml', 'chap1.xhtml']);
    });

    test('spine 里认不出的 idref 跳过', () {
      final hrefs = parseOpf(
        '<package><manifest><item id="a" href="a.xhtml"/></manifest>'
        '<spine><itemref idref="zzz"/><itemref idref="a"/></spine></package>',
        'root.opf',
      );
      expect(hrefs, ['a.xhtml']);
    });

    test('属性用单引号也认', () {
      final hrefs = parseOpf(
        "<package><manifest><item id='a' href='a.xhtml'/></manifest>"
        "<spine><itemref idref='a'/></spine></package>",
        'r.opf',
      );
      expect(hrefs, ['a.xhtml']);
    });

    test('空 OPF 返回空列表', () {
      expect(parseOpf('', 'x.opf'), isEmpty);
    });
  });
}
