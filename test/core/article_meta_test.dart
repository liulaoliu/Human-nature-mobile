import 'package:dlaoshi_app/core/article_meta.dart';
import 'package:dlaoshi_app/core/segmenter.dart';
import 'package:dlaoshi_app/models/document.dart';
import 'package:flutter_test/flutter_test.dart';

final SegmentResult _seg = segment('Hello.');

SavedArticle _base() => SavedArticle(
      id: 'saved:1',
      title: 'A',
      text: 'Hello.',
      paragraphs: _seg.paragraphs,
      sentences: _seg.sentences,
      createdAt: '2026-10-01T00:00:00.000Z',
      updatedAt: '2026-10-01T00:00:00.000Z',
    );

void main() {
  group('articleFingerprint：内容有没有变', () {
    test('同一份内容（即使对象重新创建）指纹一致', () {
      expect(
        articleFingerprint(_base()),
        articleFingerprint(_base()),
      );
    });

    test('正文 / 标题 / 书名 / 来源 / 句子分析任一变化都会变', () {
      final base = _base();
      final original = articleFingerprint(base);
      expect(articleFingerprint(base.copyWith(text: 'Hello!')), isNot(original));
      expect(articleFingerprint(base.copyWith(title: 'B')), isNot(original));
      expect(articleFingerprint(base.copyWith(book: () => 'Book')), isNot(original));
      expect(
        articleFingerprint(base.copyWith(origin: () => ArticleOrigin.paste)),
        isNot(original),
      );
      final analyzed = <Sentence>[
        base.sentences.first.copyWith(translation: () => '你好'),
      ];
      expect(
        articleFingerprint(base.copyWith(sentences: analyzed)),
        isNot(original),
      );
    });
  });

  group('articleDateKeys：建立 / 修改日期', () {
    final base = _base();

    test('建立与修改是同一天时只显示建立日', () {
      final keys = articleDateKeys(base);
      expect(keys.created, '2026-10-01');
      expect(keys.updated, '2026-10-01');
      expect(keys.edited, isFalse);
    });

    test('真的改过才标出修改日', () {
      final keys = articleDateKeys(base.copyWith(updatedAt: '2026-10-24T00:00:00.000Z'));
      expect(keys.created, '2026-10-01');
      expect(keys.updated, '2026-10-24');
      expect(keys.edited, isTrue);
    });

    test('老数据没有 createdAt：用 updatedAt 兜底，不显示成「改过」', () {
      final keys = articleDateKeysOf(
        createdAt: null,
        updatedAt: '2026-10-01T00:00:00.000Z',
      );
      expect(keys.created, '2026-10-01');
      expect(keys.updated, '2026-10-01');
      expect(keys.edited, isFalse);
    });

    test('坏时间不产出 NaN 日期', () {
      final keys = articleDateKeysOf(createdAt: 'oops', updatedAt: 'bad');
      expect(keys.created, '');
      expect(keys.updated, '');
      expect(keys.edited, isFalse);
    });
  });
}
