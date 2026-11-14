// 文章级出题（对应 Web src/core/articleQuiz.ts）：六种题型 + 数据不足时不出题。
import 'package:dlaoshi_app/core/article_quiz.dart';
import 'package:dlaoshi_app/core/quiz.dart';
import 'package:dlaoshi_app/models/document.dart';
import 'package:flutter_test/flutter_test.dart';

double Function() _seq(List<double> values) {
  var i = 0;
  return () => values[(i++) % values.length];
}

Sentence _s(
  String id,
  String paraId,
  String text, {
  String? translation,
  SentenceLanguage? language,
  List<SentenceLanguage>? languages,
}) =>
    Sentence(
      id: id,
      paraId: paraId,
      text: text,
      translation: translation,
      language: language,
      languages: languages,
    );

const List<Sentence> _sents = <Sentence>[
  Sentence(id: 's1', paraId: 'p1', text: 'Global growth is slowing down.',
      translation: '全球增长正在放缓。'),
  Sentence(id: 's2', paraId: 'p1', text: 'The outlook is uncertain.',
      translation: '前景不确定。'),
  Sentence(id: 's3', paraId: 'p1', text: 'Markets fell across the world.',
      translation: '各地市场都下跌了。'),
  Sentence(id: 's4', paraId: 'p2', text: 'Policy makers met in the capital.',
      translation: '政策制定者在首都开会。'),
];

void main() {
  group('buildArticleQuestions：题型', () {
    test('英译中：给英文原句选中文，答案与干扰项都是译文', () {
      final qs = buildArticleQuestions(
        _sents,
        kinds: const <QuizKind>[QuizKind.translate],
        rnd: _seq(<double>[0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9]),
      );
      expect(qs, isNotEmpty);
      final q = qs.first;
      expect(q.kind, QuizKind.translate);
      expect(q.prompt, isNotEmpty); // 英文原句
      expect(q.source, 'article');
      expect(q.options!.length, 4);
      expect(q.options, contains(q.answer));
    });

    test('中译英：给中文选英文原句', () {
      final qs = buildArticleQuestions(
        _sents,
        kinds: const <QuizKind>[QuizKind.translate2],
        rnd: _seq(<double>[0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9]),
      );
      expect(qs, isNotEmpty);
      expect(qs.first.kind, QuizKind.translate2);
      // 题干是中文译文，答案是英文原句。
      expect(qs.first.prompt, isNotEmpty);
      expect(qs.first.answer, isNotEmpty);
      expect(qs.first.answer.contains(RegExp('[A-Za-z]')), isTrue);
    });

    test('功能词填空：挖掉介词/冠词/连词', () {
      final qs = buildArticleQuestions(
        <Sentence>[
          _s('s1', 'p1', 'The outlook in the market is uncertain.',
              translation: '市场前景不确定。'),
          _s('s2', 'p1', 'Growth in Asia slowed again.',
              translation: '亚洲增长又放缓了。'),
          _s('s3', 'p1', 'Prices of goods and services rose.',
              translation: '商品价格与服务上涨。'),
        ],
        kinds: const <QuizKind>[QuizKind.functionWord],
        rnd: _seq(<double>[0.1, 0.5, 0.9, 0.2, 0.4, 0.6, 0.3, 0.7]),
      );
      expect(qs, isNotEmpty);
      expect(qs.every((q) => q.prompt.contains('____')), isTrue);
      expect(qs.every((q) => q.kind == QuizKind.functionWord), isTrue);
      expect(qs.every((q) => q.options!.length == 4), isTrue);
    });

    test('句子排序：一段至少 3 句才出，答案是 A/B/C 排列', () {
      final qs = buildArticleQuestions(
        _sents,
        kinds: const <QuizKind>[QuizKind.ordering],
        rnd: _seq(<double>[0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9]),
      );
      // p1 有 3 句 → 出题；p2 只有 1 句 → 不出。
      expect(qs.length, 1);
      expect(qs.single.kind, QuizKind.ordering);
      expect(qs.single.prompt, contains('排回原文顺序'));
      expect(qs.single.answer.split(' ').length, 3);
      expect(qs.single.options!.length, 4);
    });

    test('语法题：依语言点的 grammar 字段', () {
      final qs = buildArticleQuestions(
        <Sentence>[
          _s('s1', 'p1', 'If I were you, I would go.',
              translation: '如果我是你，我会去。',
              language: const SentenceLanguage(grammar: '虚拟语气')),
          _s('s2', 'p1', 'The report was written by her.',
              translation: '报告是她写的。',
              language: const SentenceLanguage(grammar: '被动语态')),
          _s('s3', 'p1', 'He has worked here for years.',
              translation: '他在这里工作多年。',
              language: const SentenceLanguage(grammar: '现在完成时')),
          _s('s4', 'p1', 'Rarely do we see such growth.',
              translation: '我们很少见到这种增长。',
              language: const SentenceLanguage(grammar: '倒装')),
        ],
        kinds: const <QuizKind>[QuizKind.grammar],
        rnd: _seq(<double>[0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9]),
      );
      expect(qs.length, 4);
      expect(qs.every((q) => q.kind == QuizKind.grammar), isTrue);
      expect(qs.map((q) => q.answer).toSet().length, 4);
    });

    test('词组/习语填空：依语言点的 phrases/idioms，且句子里真的出现', () {
      final qs = buildArticleQuestions(
        <Sentence>[
          _s('s1', 'p1', 'We keep up with the news every morning.',
              translation: '我们每天早上跟上新闻。',
              language: const SentenceLanguage(phrases: <String>['keep up with'])),
          _s('s2', 'p1', 'It is a blessing in disguise for the team.',
              translation: '这对团队是塞翁失马。',
              language: const SentenceLanguage(idioms: <String>['blessing in disguise'])),
          _s('s3', 'p1', 'They look after the children.',
              translation: '他们照看孩子。',
              language: const SentenceLanguage(phrases: <String>['look after'])),
          _s('s4', 'p1', 'The plan came to nothing in the end.',
              translation: '计划最终落空。',
              language: const SentenceLanguage(idioms: <String>['came to nothing'])),
        ],
        kinds: const <QuizKind>[QuizKind.phraseBlank],
        rnd: _seq(<double>[0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9]),
      );
      expect(qs, isNotEmpty);
      expect(qs.every((q) => q.kind == QuizKind.phraseBlank), isTrue);
      expect(qs.every((q) => q.prompt.contains('____')), isTrue);
      expect(qs.every((q) => q.options!.length == 4), isTrue);
    });
  });

  group('数据不足时不出题', () {
    test('没译文：英译中/中译英都不出', () {
      final qs = buildArticleQuestions(
        <Sentence>[
          _s('s1', 'p1', 'No translation here.'),
          _s('s2', 'p1', 'Another bare sentence.'),
        ],
        kinds: const <QuizKind>[QuizKind.translate, QuizKind.translate2],
      );
      expect(qs, isEmpty);
    });

    test('没语言点：语法/词组填空都不出', () {
      final qs = buildArticleQuestions(
        <Sentence>[
          _s('s1', 'p1', 'A plain sentence.', translation: '一个普通句子。'),
        ],
        kinds: const <QuizKind>[QuizKind.grammar, QuizKind.phraseBlank],
      );
      expect(qs, isEmpty);
    });

    test('空句子列表返回空', () {
      expect(buildArticleQuestions(const <Sentence>[]), isEmpty);
    });
  });

  test('默认题型是五种（不含 phraseBlank）', () {
    // 用够多句子 + 译文 + 语言点，确保默认能出题且不依赖 phraseBlank。
    final qs = buildArticleQuestions(
      <Sentence>[
        for (var i = 0; i < 6; i++)
          _s('s$i', 'p1', 'Sentence number $i is here and has words.',
              translation: '第 $i 句在这里。'),
      ],
      rnd: _seq(<double>[0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9]),
    );
    expect(qs, isNotEmpty);
    expect(qs.every((q) => q.kind != QuizKind.phraseBlank), isTrue);
  });
}
