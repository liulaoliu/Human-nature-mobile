import 'package:dlaoshi_app/core/vocab/sentence_texts.dart';
import 'package:dlaoshi_app/models/vocab.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/vocab_fixture.dart';

const sentence = 'The bank raised its rate.';

VocabSource source([String text = sentence]) => VocabSource(
      articleId: 'art-1',
      sentenceId: 's1',
      sentenceText: text,
    );

VocabLibrary libraryWithDuplicates() => VocabLibrary(
      items: [
        vocabItem(id: 'a', lemma: 'bank', source: source()),
        vocabItem(
          id: 'b',
          lemma: 'rate',
          source: source(),
          contexts: const [
            VocabContext(
              articleId: 'art-1',
              sentenceId: 's1',
              sentenceText: sentence,
              at: '2026-10-24T00:00:00.000Z',
            ),
          ],
        ),
      ],
      articleEntries: [
        articleEntry(
          articleId: 'art-1',
          lemma: 'bank',
          addedAt: '2026-10-24T00:00:00.000Z',
          sentenceId: 's1',
          sentenceText: sentence,
        ),
      ],
    );

void main() {
  group('sentenceTexts：同一句只存一份', () {
    final key = sentenceTextKey(const VocabSource(articleId: 'art-1', sentenceId: 's1'));

    test('compact 把 source / contexts / articleEntries 的原文收进共享表', () {
      final next = compactSentenceTexts(libraryWithDuplicates());

      expect(next.sentenceTexts, {key: sentence});
      expect(next.items[0].source!.sentenceText, '');
      expect(next.items[1].source!.sentenceText, '');
      expect(next.items[1].contexts![0].sentenceText, '');
      expect(next.articleEntries[0].sentenceText, '');
    });

    test('hydrate 再把原文补回所有引用', () {
      final back = hydrateSentenceTexts(compactSentenceTexts(libraryWithDuplicates()));
      expect(back.items[0].source!.sentenceText, sentence);
      expect(back.items[1].contexts![0].sentenceText, sentence);
      expect(back.articleEntries[0].sentenceText, sentence);
    });

    test('compact 幂等：第二次不会越压越少', () {
      final once = compactSentenceTexts(libraryWithDuplicates());
      final twice = compactSentenceTexts(once);
      expect(twice.sentenceTexts, once.sentenceTexts);
      expect(twice.items[0].source!.sentenceText, '');
      expect(twice.articleEntries[0].sentenceText, '');
    });

    test('同一句 id 文本不一致（比如改过正文）→ 不共享，保留各自原文', () {
      final lib = libraryWithDuplicates();
      final items = [...lib.items];
      items[1] = items[1].copyWith(source: () => source('The bank raised its rates.'));
      final next = compactSentenceTexts(lib.copyWith(items: items));

      expect(next.sentenceTexts, isEmpty);
      expect(next.items[0].source!.sentenceText, sentence);
      expect(next.items[1].source!.sentenceText, 'The bank raised its rates.');
    });

    test('没有 sentenceId 的引用不参与共享', () {
      final lib = VocabLibrary(
        items: [
          vocabItem(
            id: 'a',
            lemma: 'bank',
            source: const VocabSource(articleId: 'art-1', sentenceText: sentence),
          ),
        ],
      );
      final next = compactSentenceTexts(lib);
      expect(next.sentenceTexts, isEmpty);
      expect(next.items[0].source!.sentenceText, sentence);
    });

    test('旧数据只有共享表、引用里没有原文 → hydrate 能补回来', () {
      final lib = VocabLibrary(
        items: [
          vocabItem(
            id: 'a',
            lemma: 'bank',
            source: const VocabSource(articleId: 'art-1', sentenceId: 's1'),
          ),
        ],
        sentenceTexts: {key: sentence},
      );
      expect(hydrateSentenceTexts(lib).items[0].source!.sentenceText, sentence);
    });

    test('fileName 兜底当文章标识（没有 articleId 时）', () {
      final k = sentenceTextKey(
        const VocabSource(articleId: '', fileName: 'x.md', sentenceId: 's9'),
      );
      expect(k, 'x.md\u0000s9');
    });
  });
}
