import 'package:dlaoshi_app/core/article_index.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('slugify', () {
    test('小写、非字母数字变连字符、去首尾连字符', () {
      expect(slugify('Post-truth Politics'), 'post-truth-politics');
      expect(slugify('  Hello, World!  '), 'hello-world');
      expect(slugify('a--b'), 'a-b');
    });

    test('去重音（é → e）', () {
      expect(slugify('Café Society'), 'cafe-society');
      expect(slugify('naïve résumé'), 'naive-resume');
    });

    test('纯中文标题剥成空串', () {
      expect(slugify('中文标题'), '');
      expect(slugify('「死马当活马医」'), '');
    });

    test('超过 72 字符截断且不留尾部连字符', () {
      final long = slugify('word ' * 40);
      expect(long.length, lessThanOrEqualTo(72));
      expect(long.endsWith('-'), isFalse);
    });
  });

  group('shortHash', () {
    test('同输入同结果，4 位 36 进制', () {
      final a = shortHash('s:saved:1');
      expect(a, shortHash('s:saved:1'));
      expect(a.length, 4);
      expect(RegExp('^[0-9a-z]{4}\$').hasMatch(a), isTrue);
    });

    test('不同输入不同结果', () {
      expect(shortHash('a'), isNot(shortHash('b')));
    });
  });

  group('buildArticleIndex', () {
    test('空数据 → 空索引，任何查询都空串', () {
      final idx = buildArticleIndex(const {}, const []);
      expect(idx.slugOf('b:x'), '');
      expect(idx.refOf('x'), '');
    });

    test('标题唯一时用裸 slug，能双向查回', () {
      final idx = buildArticleIndex(
        {'005 Leaders': 'Post-truth Politics'},
        [(id: 'a1', title: 'A Cat')],
      );
      expect(idx.slugOf('b:005 Leaders'), 'post-truth-politics');
      expect(idx.slugOf('s:a1'), 'a-cat');
      expect(idx.refOf('post-truth-politics'), 'b:005 Leaders');
      expect(idx.refOf('a-cat'), 's:a1');
    });

    test('中文标题 → article-<hash>，且能反查', () {
      final idx = buildArticleIndex({'k': '中文标题'}, const []);
      final slug = idx.slugOf('b:k');
      expect(slug, startsWith('article-'));
      expect(slug.length, 'article-'.length + 4);
      expect(idx.refOf(slug), 'b:k');
    });

    test('slug 撞了双方都加 hash（删一篇不影响另一篇）', () {
      final idx = buildArticleIndex(
        {'k1': 'Same Title', 'k2': 'Same Title'},
        const [],
      );
      final s1 = idx.slugOf('b:k1');
      final s2 = idx.slugOf('b:k2');
      expect(s1, isNot(s2));
      expect(s1, startsWith('same-title-'));
      expect(s2, startsWith('same-title-'));
      expect(idx.refOf(s1), 'b:k1');
      expect(idx.refOf(s2), 'b:k2');
    });

    test('目录键为空标题时退回用键当标题', () {
      final idx = buildArticleIndex({'005 Leaders': ''}, const []);
      expect(idx.slugOf('b:005 Leaders'), '005-leaders');
    });

    test('两篇中文标题都空 base 也不会互相覆盖', () {
      final idx = buildArticleIndex(
        {'a': '中文甲', 'b': '中文乙'},
        const [],
      );
      final s1 = idx.slugOf('b:a');
      final s2 = idx.slugOf('b:b');
      expect(s1, isNot(s2));
      expect(idx.refOf(s1), 'b:a');
      expect(idx.refOf(s2), 'b:b');
    });

    test('未登记标识返回空串', () {
      final idx = buildArticleIndex({'k': 'T'}, const []);
      expect(idx.slugOf('b:nope'), '');
      expect(idx.refOf('nope'), '');
    });
  });
}
