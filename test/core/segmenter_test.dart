import 'package:dlaoshi_app/core/segmenter.dart';
import 'package:dlaoshi_app/models/document.dart';
import 'package:dlaoshi_app/models/vocab.dart';
import 'package:flutter_test/flutter_test.dart';

/// 拆句：用例逐条对照 Web 版 `src/core/segmenter.test.ts`。
///
/// 与 Web 版的唯一差别：Dart 没有 `Intl.Segmenter`，这里只跑正则那条路
/// （Web 版同样保留它作兜底，所以断言完全一致）。
void main() {
  group('splitSentences', () {
    test('基本句切分', () {
      expect(splitSentences('He left. She stayed.'), ['He left.', 'She stayed.']);
    });

    test('问号感叹号也切', () {
      expect(splitSentences('Really? Yes! Fine.'), ['Really?', 'Yes!', 'Fine.']);
    });

    test('缩写不误切：Mr.', () {
      expect(splitSentences('Mr. Smith went home. He was tired.'), [
        'Mr. Smith went home.',
        'He was tired.',
      ]);
    });

    test('缩写不误切：U.S.', () {
      expect(splitSentences('The U.S. economy grew. Then it slowed.'), [
        'The U.S. economy grew.',
        'Then it slowed.',
      ]);
    });

    test('缩写不误切：e.g.', () {
      expect(splitSentences('Some plans, e.g. the new one, failed. It was costly.'), [
        'Some plans, e.g. the new one, failed.',
        'It was costly.',
      ]);
    });

    test('单句', () {
      expect(splitSentences('Just one sentence.'), ['Just one sentence.']);
    });

    test('收尾引号跟着上一句走', () {
      expect(splitSentences('He said "go." She left.'), ['He said "go."', 'She left.']);
    });

    test('空串没有句子', () {
      expect(splitSentences(''), isEmpty);
      expect(splitSentences('   '), isEmpty);
    });
  });

  group('segment', () {
    const text = 'First sentence. Second sentence.\n\nAnother paragraph here.';

    test('按空行生成段落，段内切句', () {
      final out = segment(text);
      expect(out.paragraphs, hasLength(2));
      expect(out.sentences, hasLength(3));
      expect(out.paragraphs[0], const Paragraph(id: 'p01', sentenceIds: ['s001', 's002']));
      expect(out.paragraphs[1], const Paragraph(id: 'p02', sentenceIds: ['s003']));
    });

    test('句子顺序与原文一致，paraId 正确', () {
      final out = segment(text);
      expect(out.sentences.map((s) => s.text), [
        'First sentence.',
        'Second sentence.',
        'Another paragraph here.',
      ]);
      expect(out.sentences[2].paraId, 'p02');
    });

    test('句子的默认字段正确', () {
      final s = segment('Hello there.').sentences.first;
      expect(s.id, 's001');
      expect(s.paraId, 'p01');
      expect(s.text, 'Hello there.');
      expect(s.audio, isNull);
      expect(s.translation, isNull);
      expect(s.grammarNote, isNull);
      expect(s.collocations, isEmpty);
      expect(s.vocab, isEmpty);
      expect(s.tags, isEmpty);
      expect(s.reviewState, const ReviewState(ease: 2.5));
    });

    test('空输入没有段落和句子', () {
      expect(segment('').isEmpty, isTrue);
    });

    test('只有空白也没有段落', () {
      expect(segment('   \n\n  ').isEmpty, isTrue);
    });

    test('id 补零到两位 / 三位', () {
      final many = List.generate(12, (i) => 'Sentence number $i.').join(' ');
      final out = segment(many);
      expect(out.paragraphs.first.id, 'p01');
      expect(out.sentences[11].id, 's012');
    });
  });

  group('carryAnalysis', () {
    Sentence base(String text) => Sentence(
          id: 'x',
          paraId: 'p01',
          text: text,
          audio: const AudioSegment(start: 1, end: 2),
          translation: '译',
          grammarNote: '语法',
          language: const SentenceLanguage(structure: '主谓', phrases: ['a b']),
          collocations: const ['c'],
          vocab: const ['v'],
          tags: const ['t'],
        );

    test('句文相同就搬分析结果', () {
      final out = carryAnalysis([base('Hello world.')], segment('Hello world.').sentences).first;
      expect(out.translation, '译');
      expect(out.grammarNote, '语法');
      expect(out.language?.structure, '主谓');
      expect(out.language?.phrases, ['a b']);
      expect(out.collocations, ['c']);
      expect(out.audio, const AudioSegment(start: 1, end: 2));
    });

    test('句文变了就不搬', () {
      final out = carryAnalysis([base('Hello world.')], segment('Goodbye moon.').sentences).first;
      expect(out.translation, isNull);
    });

    test('同一句文出现多次按顺序一一对应', () {
      final prev = [
        base('Same.'),
        base('Same.').copyWith(translation: () => '第二处'),
      ];
      final out = carryAnalysis(prev, segment('Same. Same.').sentences);
      expect(out[0].translation, '译');
      expect(out[1].translation, '第二处');
    });
  });
}
