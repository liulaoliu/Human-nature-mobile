import 'package:dlaoshi_app/core/article_build.dart';
import 'package:dlaoshi_app/models/document.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildArticle：新建文章', () {
    test('清洗 + 切句 + 时间戳一起给出', () {
      final a = buildArticle(
        raw: 'The com-\npared figures rose.\n\nSecond paragraph.',
        title: '  Global  ',
        book: '  ',
        now: DateTime.utc(2026, 11, 8, 10),
      );
      expect(a.title, 'Global');
      expect(a.book, isNull);
      expect(a.text, 'The compared figures rose.\n\nSecond paragraph.');
      expect(a.paragraphs, hasLength(2));
      expect(a.sentences, hasLength(2));
      expect(a.sentences.first.id, 's001');
      expect(a.paragraphs.first.id, 'p01');
      expect(a.paragraphs.last.id, 'p02');
      expect(a.origin, ArticleOrigin.paste);
      expect(a.createdAt, '2026-11-08T10:00:00.000Z');
      expect(a.updatedAt, a.createdAt);
    });

    test('标题为空用「未命名」；空白标题也当空', () {
      expect(buildArticle(raw: 'Hello.').title, '未命名');
      expect(buildArticle(raw: 'Hello.', title: '   ').title, '未命名');
    });

    test('来源可以指定，id 可以指定', () {
      final a = buildArticle(
        raw: 'Hi.',
        origin: ArticleOrigin.epub,
        id: 'saved:7',
      );
      expect(a.origin, ArticleOrigin.epub);
      expect(a.id, 'saved:7');
    });

    test('空正文也能建（切句结果为空，不抛）', () {
      final a = buildArticle(raw: '   ');
      expect(a.text, '');
      expect(a.paragraphs, isEmpty);
      expect(a.sentences, isEmpty);
    });
  });

  group('rebuildArticleText：改正文重切句', () {
    test('重新切句后按句文把分析结果搬回来', () {
      final a = buildArticle(
        raw: 'First line.\n\nSecond line.',
        now: DateTime.utc(2026, 11, 8, 10),
      );
      final analyzed = a.copyWith(
        sentences: [
          a.sentences.first.copyWith(
            translation: () => '第一行。',
            languages: () => const <SentenceLanguage>[
              SentenceLanguage(structure: 'SV'),
            ],
          ),
          a.sentences.last,
        ],
      );

      // 前面插一句，原来的两句顺序不变（句文相同才好搬）。
      final next = rebuildArticleText(
        analyzed,
        'Intro. First line.\n\nSecond line.',
        now: DateTime.utc(2026, 11, 8, 11),
      );
      expect(next.sentences, hasLength(3));
      expect(next.sentences[1].translation, '第一行。');
      expect(next.sentences[1].languages, hasLength(1));
      // 新句没有分析结果。
      expect(next.sentences.first.translation, isNull);
      expect(next.updatedAt, '2026-11-08T11:00:00.000Z');
      // 建立时间不动。
      expect(next.createdAt, '2026-11-08T10:00:00.000Z');
    });

    test('正文没变时切句结果稳定', () {
      final a = buildArticle(raw: 'One. Two.', now: DateTime.utc(2026, 11, 8, 10));
      final again = rebuildArticleText(a, 'One. Two.', now: DateTime.utc(2026, 11, 8, 12));
      expect(again.sentences.map((s) => s.text), a.sentences.map((s) => s.text));
      expect(again.paragraphs.first.sentenceIds, a.paragraphs.first.sentenceIds);
    });
  });
}
