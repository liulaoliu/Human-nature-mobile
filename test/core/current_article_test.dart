import 'package:flutter_test/flutter_test.dart';

import 'package:dlaoshi_app/core/current_article.dart';

void main() {
  group('parseCurrentArticleId：读回来收拾干净', () {
    test('正常 id 原样返回', () {
      expect(parseCurrentArticleId('a1'), 'a1');
    });

    test('首尾空白被 trim', () {
      expect(parseCurrentArticleId('  a1\t'), 'a1');
    });

    test('null / 空串 / 全空白都算没选', () {
      expect(parseCurrentArticleId(null), isNull);
      expect(parseCurrentArticleId(''), isNull);
      expect(parseCurrentArticleId('   '), isNull);
    });
  });

  group('resolveCurrentArticleId：拿现有列表校验', () {
    test('存的 id 还在：原样返回', () {
      expect(resolveCurrentArticleId('a2', ['a1', 'a2', 'a3']), 'a2');
    });

    test('存的那篇被删了：当没选', () {
      expect(resolveCurrentArticleId('a9', ['a1', 'a2']), isNull);
    });

    test('没存过：当没选', () {
      expect(resolveCurrentArticleId(null, ['a1']), isNull);
    });

    test('一篇都没有：即使存了 id 也算没选', () {
      expect(resolveCurrentArticleId('a1', const <String>[]), isNull);
    });

    test('列表里有脏数据也不影响匹配', () {
      expect(
        resolveCurrentArticleId('  a2 ', ['a1', '', 'a2']),
        'a2',
      );
    });
  });

  group('存储键', () {
    test('键名固定，改名会让老用户的当前文章丢失', () {
      expect(currentArticleKey, 'reader:currentArticle');
    });
  });
}
