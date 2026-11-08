import 'dart:convert';

import 'package:dlaoshi_app/core/article_json.dart';
import 'package:dlaoshi_app/core/backup_parse.dart';
import 'package:dlaoshi_app/models/document.dart';
import 'package:dlaoshi_app/models/vocab.dart';
import 'package:flutter_test/flutter_test.dart';

Sentence _sentence({
  String id = 's1',
  String paraId = 'p1',
  String text = 'Global growth is slowing.',
  AudioSegment? audio,
  String? translation,
  String? grammarNote,
  List<String> collocations = const [],
  List<String> vocab = const [],
  SentenceLanguage? language,
  List<SentenceLanguage>? languages,
  List<String> tags = const [],
  ReviewState reviewState = defaultReviewState,
}) =>
    Sentence(
      id: id,
      paraId: paraId,
      text: text,
      audio: audio,
      translation: translation,
      grammarNote: grammarNote,
      collocations: collocations,
      vocab: vocab,
      language: language,
      languages: languages,
      tags: tags,
      reviewState: reviewState,
    );

SavedArticle _article({
  String id = 'saved:1',
  String title = 'The Economist',
  String text = '',
  String? book,
  String? sourceKey,
  ArticleOrigin? origin,
  Map<String, Object?>? golden,
  String? createdAt,
  String updatedAt = '2026-11-01T00:00:00.000Z',
  List<Sentence>? sentences,
  List<Paragraph>? paragraphs,
}) =>
    SavedArticle(
      id: id,
      title: title,
      text: text,
      book: book,
      sourceKey: sourceKey,
      origin: origin,
      golden: golden,
      createdAt: createdAt,
      updatedAt: updatedAt,
      sentences: sentences ?? <Sentence>[_sentence()],
      paragraphs: paragraphs ??
          const <Paragraph>[
            Paragraph(id: 'p1', sentenceIds: <String>['s1']),
          ],
    );

void main() {
  group('sentenceToJson', () {
    test('必写字段齐全，可选字段为空就不写', () {
      final json = sentenceToJson(_sentence());
      expect(json['id'], 's1');
      expect(json['paraId'], 'p1');
      expect(json['text'], 'Global growth is slowing.');
      // 空列表 / null 不占键：落盘小一截，且写两遍结果一样。
      expect(json.containsKey('audio'), isFalse);
      expect(json.containsKey('translation'), isFalse);
      expect(json.containsKey('grammarNote'), isFalse);
      expect(json.containsKey('collocations'), isFalse);
      expect(json.containsKey('vocab'), isFalse);
      expect(json.containsKey('language'), isFalse);
      expect(json.containsKey('languages'), isFalse);
      expect(json.containsKey('tags'), isFalse);
      // reviewState 是算法输入，缺一个字段复习节奏就会漂移，所以总是写。
      expect(json['reviewState'], isA<Map>());
    });

    test('有值的可选字段都写出来', () {
      final json = sentenceToJson(_sentence(
        audio: const AudioSegment(start: 1.5, end: 3.25),
        translation: '全球增长正在放缓。',
        grammarNote: '主谓宾',
        collocations: const ['global growth'],
        vocab: const ['global', 'growth'],
        tags: const ['economy'],
      ));
      expect(json['audio'], <String, Object?>{'start': 1.5, 'end': 3.25});
      expect(json['translation'], '全球增长正在放缓。');
      expect(json['grammarNote'], '主谓宾');
      expect(json['collocations'], ['global growth']);
      expect(json['vocab'], ['global', 'growth']);
      expect(json['tags'], ['economy']);
    });

    test('语言点单条与列表分别写在 language / languages', () {
      const one = SentenceLanguage(
        structure: '主系表',
        grammar: '现在进行时',
        idioms: <String>['be worried about'],
        phrases: <String>['worry about'],
        usage: <String>['worry sb'],
        source: LanguageSource.manual,
        at: '2026-11-01T00:00:00.000Z',
      );
      final single = sentenceToJson(_sentence(language: one));
      final singleJson = single['language']! as Map;
      expect(singleJson['structure'], '主系表');
      expect(singleJson['source'], 'manual');
      expect(singleJson['idioms'], ['be worried about']);

      final many = sentenceToJson(_sentence(languages: const [one, one]));
      expect((many['languages']! as List).length, 2);

      // 空的语言点列表不写。
      expect(
        sentenceToJson(_sentence(languages: const [])).containsKey('languages'),
        isFalse,
      );
    });

    test('语言点全空时只剩一个空对象（不写 null 键）', () {
      expect(languageToJson(const SentenceLanguage()), isEmpty);
    });

    test('reviewState 七个字段全写', () {
      final json = reviewStateJson(const ReviewState(
        ease: 2.7,
        due: '2026-11-05',
        interval: 3,
        repetitions: 2,
        lapses: 1,
        relearn: 0,
        meaningPasses: 4,
      ));
      expect(json, <String, Object?>{
        'ease': 2.7,
        'due': '2026-11-05',
        'interval': 3,
        'repetitions': 2,
        'lapses': 1,
        'relearn': 0,
        'meaningPasses': 4,
      });
    });
  });

  group('articleToJson', () {
    test('必写字段与老字段', () {
      final json = articleToJson(_article());
      expect(json['id'], 'saved:1');
      expect(json['title'], 'The Economist');
      expect(json['updatedAt'], '2026-11-01T00:00:00.000Z');
      expect((json['paragraphs']! as List).length, 1);
      expect((json['sentences']! as List).length, 1);
      // text 即使空也写：编辑模式读它判断「有没有清洗过」。
      expect(json['text'], '');
      expect(json.containsKey('book'), isFalse);
      expect(json.containsKey('sourceKey'), isFalse);
      expect(json.containsKey('origin'), isFalse);
      expect(json.containsKey('createdAt'), isFalse);
      expect(json.containsKey('golden'), isFalse);
    });

    test('可选字段有值才写，origin 用枚举名', () {
      final json = articleToJson(_article(
        book: 'Economist 2026',
        sourceKey: 'eco-1',
        origin: ArticleOrigin.epub,
        createdAt: '2026-10-01T00:00:00.000Z',
        golden: <String, Object?>{'lesson': <Object?>[]},
      ));
      expect(json['book'], 'Economist 2026');
      expect(json['sourceKey'], 'eco-1');
      expect(json['origin'], 'epub');
      expect(json['createdAt'], '2026-10-01T00:00:00.000Z');
      expect(json['golden'], <String, Object?>{'lesson': <Object?>[]});
    });

    test('空的 golden 不写', () {
      expect(articleToJson(_article(golden: const {})).containsKey('golden'),
          isFalse);
      expect(
        articleToJson(_article(golden: null)).containsKey('golden'),
        isFalse,
      );
    });

    test('写两遍结果完全相同（幂等）', () {
      final a = _article(
        book: 'B',
        origin: ArticleOrigin.paste,
        createdAt: '2026-10-01T00:00:00.000Z',
        sentences: [
          _sentence(vocab: const ['global'], tags: const ['economy']),
          _sentence(id: 's2', translation: ' policymakers 很担心。'),
        ],
      );
      expect(jsonEncode(articleToJson(a)), jsonEncode(articleToJson(a)));
    });
  });

  group('往返（写出去再守卫读回来）', () {
    test('整篇逐字段还原', () {
      final a = _article(
        book: 'Economist',
        sourceKey: 'eco-1',
        origin: ArticleOrigin.file,
        text: 'Global growth is slowing.',
        createdAt: '2026-10-01T00:00:00.000Z',
        sentences: [
          _sentence(
            audio: const AudioSegment(start: 0, end: 2.5),
            translation: '全球增长正在放缓。',
            collocations: const ['global growth'],
            vocab: const ['global', 'growth'],
            tags: const ['economy'],
            languages: const [
              SentenceLanguage(
                structure: '主谓',
                source: LanguageSource.ai,
                at: '2026-11-01T00:00:00.000Z',
              ),
            ],
            reviewState: const ReviewState(ease: 2.8, interval: 5, repetitions: 3),
          ),
          _sentence(id: 's2', paraId: 'p2', text: 'Policymakers are worried.'),
        ],
        paragraphs: const [
          Paragraph(id: 'p1', sentenceIds: <String>['s1']),
          Paragraph(id: 'p2', sentenceIds: <String>['s2']),
        ],
      );
      final back = parseSavedArticle(jsonDecode(jsonEncode(articleToJson(a))));
      expect(back, isNotNull);
      expect(back!.id, a.id);
      expect(back.title, a.title);
      expect(back.book, a.book);
      expect(back.sourceKey, a.sourceKey);
      expect(back.origin, ArticleOrigin.file);
      expect(back.text, a.text);
      expect(back.createdAt, a.createdAt);
      expect(back.updatedAt, a.updatedAt);
      expect(back.paragraphs.map((p) => p.id), ['p1', 'p2']);
      expect(back.sentences.length, 2);
      expect(back.sentences.first.audio, const AudioSegment(start: 0, end: 2.5));
      expect(back.sentences.first.vocab, ['global', 'growth']);
      expect(back.sentences.first.languages!.single.source, LanguageSource.ai);
      expect(back.sentences.first.reviewState.ease, 2.8);
      expect(back.sentences.first.reviewState.interval, 5);
    });

    test('golden 原样带过去（P1 只保证是对象）', () {
      final a = _article(golden: <String, Object?>{
        'title': '金句课',
        'items': <Object?>[
          <String, Object?>{'text': 'come to an end'},
        ],
      });
      final back = parseSavedArticle(jsonDecode(jsonEncode(articleToJson(a))));
      expect(back!.golden, a.golden);
    });

    test('写两遍再读回来仍然相等（不会越写越多）', () {
      final a = _article();
      final once = parseSavedArticle(jsonDecode(jsonEncode(articleToJson(a))))!;
      final twice = parseSavedArticle(jsonDecode(jsonEncode(articleToJson(once))))!;
      expect(jsonEncode(articleToJson(twice)), jsonEncode(articleToJson(once)));
    });
  });

  group('parseSavedArticle', () {
    test('非对象 / 缺 id / 缺 updatedAt / 句子形状坏都返回 null', () {
      expect(parseSavedArticle(null), isNull);
      expect(parseSavedArticle('x'), isNull);
      expect(parseSavedArticle(<String, Object?>{}), isNull);
      expect(
        parseSavedArticle(<String, Object?>{
          'id': 'a',
          'updatedAt': 't',
          'paragraphs': <Object?>[],
          'sentences': <Object?>[
            <String, Object?>{'id': 's1'},
          ],
        }),
        isNull,
      );
    });

    test('老文章缺 title / text / createdAt 也能读，补默认值', () {
      final back = parseSavedArticle(<String, Object?>{
        'id': 'old',
        'updatedAt': '2026-01-01T00:00:00.000Z',
        'paragraphs': <Object?>[],
        'sentences': <Object?>[],
      });
      expect(back!.title, '未命名');
      expect(back.text, '');
      expect(back.createdAt, isNull);
      expect(back.sentences, isEmpty);
    });
  });

  group('articleWordCount', () {
    test('按句子里的词形去重', () {
      final a = _article(sentences: [
        _sentence(vocab: const ['global', 'growth']),
        _sentence(id: 's2', vocab: const ['growth', 'policymakers']),
      ]);
      expect(articleWordCount(a), 3);
    });

    test('空白词形不算', () {
      final a = _article(sentences: [
        _sentence(vocab: const ['  ', '', 'global']),
      ]);
      expect(articleWordCount(a), 1);
    });

    test('没有句子就是 0', () {
      expect(
        articleWordCount(_article(sentences: const [], paragraphs: const [])),
        0,
      );
    });
  });
}
