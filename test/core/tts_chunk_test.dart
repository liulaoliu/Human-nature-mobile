import 'package:dlaoshi_app/core/tts_chunk.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('按官方口径切块', () {
    test('短句整块保留，结尾标点不动', () {
      final chunks = ttsChunkText('Reading makes perfect.');
      expect(chunks, ['Reading makes perfect.']);
    });

    test('多句切成多块，句末标点跟着句子走', () {
      final chunks = ttsChunkText('One thing. Two things! Three?');
      expect(chunks, ['One thing.', 'Two things!', 'Three?']);
    });

    test('结尾没有标点的块补逗号（官方 ensure_punctuation）', () {
      final chunks = ttsChunkText('a sentence without stop');
      expect(chunks.single, 'a sentence without stop,');
    });

    test('超长句按词切，每块都不超过 400', () {
      final long = List<String>.generate(200, (i) => 'word$i').join(' ');
      final chunks = ttsChunkText(long);
      expect(chunks.length, greaterThan(1));
      for (final c in chunks) {
        expect(c.length, lessThanOrEqualTo(ttsChunkMaxLen));
        // 不能切在词中间：每一块去掉尾部补的逗号后，都只由完整单词组成。
        final body = c.endsWith(',') ? c.substring(0, c.length - 1) : c;
        for (final word in body.split(' ')) {
          expect(RegExp(r'^word\d+$').hasMatch(word), isTrue, reason: word);
        }
      }
    });

    test('空白与空串切不出块', () {
      expect(ttsChunkText(''), isEmpty);
      expect(ttsChunkText('   '), isEmpty);
      expect(ttsChunkText('...'), isEmpty);
    });

    test('多句连写时标点不被吃掉（曾经的 split 会丢句号）', () {
      final chunks = ttsChunkText('MOST companies worry. They also fret.');
      expect(chunks, ['MOST companies worry.', 'They also fret.']);
    });
  });

  group('ensureTtsPunctuation', () {
    test('已有标点就原样返回', () {
      for (final t in ['a.', 'a!', 'a?', 'a,', 'a;', 'a:']) {
        expect(ensureTtsPunctuation(t), t);
      }
    });

    test('没有标点补逗号，并去掉首尾空白', () {
      expect(ensureTtsPunctuation('  a  '), 'a,');
      expect(ensureTtsPunctuation(''), '');
    });
  });
}
