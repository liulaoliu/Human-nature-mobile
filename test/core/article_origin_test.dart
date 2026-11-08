import 'package:dlaoshi_app/core/article_origin.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parseArticleOrigin：只认四个白名单值', () {
    expect(parseArticleOrigin('library'), ArticleOrigin.library);
    expect(parseArticleOrigin('paste'), ArticleOrigin.paste);
    expect(parseArticleOrigin('epub'), ArticleOrigin.epub);
    expect(parseArticleOrigin('file'), ArticleOrigin.file);
  });

  test('旧数据 / 坏值保持未知，不猜', () {
    expect(parseArticleOrigin(null), isNull);
    expect(parseArticleOrigin(''), isNull);
    expect(parseArticleOrigin('legacy'), isNull);
    expect(parseArticleOrigin('Paste'), isNull, reason: '大小写不宽容');
    expect(parseArticleOrigin(3), isNull);
    expect(parseArticleOrigin(<String, Object?>{}), isNull);
  });

  test('isArticleOrigin 与 parseArticleOrigin 同口径', () {
    for (final name in articleOriginName.values) {
      expect(isArticleOrigin(name), isTrue);
    }
    expect(isArticleOrigin('unknown'), isFalse);
    expect(isArticleOrigin(null), isFalse);
  });

  test('中文名：已知来源给中文，未知返回 null', () {
    expect(articleOriginLabelOf('epub'), 'EPUB');
    expect(articleOriginLabelOf('library'), '原文库');
    expect(articleOriginLabelOf('file'), '文件');
    expect(articleOriginLabelOf('paste'), '粘贴');
    expect(articleOriginLabelOf('legacy'), isNull);
    expect(articleOriginLabelOf(null), isNull);
  });

  test('枚举与字符串表一一对应，别漏一个', () {
    expect(articleOriginName.length, ArticleOrigin.values.length);
    expect(articleOriginLabel.length, ArticleOrigin.values.length);
    expect(articleOriginName.values.toSet().length, ArticleOrigin.values.length);
  });
}
