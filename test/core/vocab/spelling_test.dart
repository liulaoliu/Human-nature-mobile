import 'package:dlaoshi_app/core/vocab/library.dart';
import 'package:dlaoshi_app/core/vocab/spelling.dart';
import 'package:dlaoshi_app/models/vocab.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/vocab_fixture.dart';

final now = DateTime.parse('2026-10-02T00:00:00.000Z');

void main() {
  group('拼写比对', () {
    test('忽略大小写与首尾 / 连续空格', () {
      expect(spellingMatches('  Run ', 'run'), isTrue);
      expect(spellingMatches('take   off', 'take off'), isTrue);
      expect(spellingMatches('TAKE OFF', 'take off'), isTrue);
    });

    test('字母错就是错，不做词形还原', () {
      expect(spellingMatches('runs', 'run'), isFalse);
      expect(spellingMatches('ran', 'run'), isFalse);
      expect(spellingMatches('runn', 'run'), isFalse);
    });
  });

  group('拼错 → 记 again + 打「不认识」标签', () {
    test('拼错后进入重学并补标签', () {
      final lib = createLibrary().copyWith(
        items: [
          vocabItem(
            id: 'v1',
            word: 'run',
            lemma: 'run',
            reviewState: ReviewState(ease: 2.5, due: '2026-10-02T00:00:00Z', interval: 15, repetitions: 3),
          ),
        ],
      );
      final out = markSpellingMiss(lib, 'v1', now);
      final it = out.items.single;
      expect(it.tags, contains(spellingMissTag));
      expect(it.reviewState.relearn, 1);
      expect(it.reviewState.repetitions, 0);
      expect(it.reviewState.interval, 1);
      expect(it.updatedAt, now.toUtc().toIso8601String());
    });

    test('已有「不认识」标签不重复加', () {
      final lib = createLibrary().copyWith(
        items: [vocabItem(id: 'v1', word: 'run', lemma: 'run', tags: const [spellingMissTag])],
      );
      final out = markSpellingMiss(lib, 'v1', now);
      expect(out.items.single.tags.where((t) => t == spellingMissTag), hasLength(1));
    });

    test('只改这一条，其它条目保持原样', () {
      final lib = createLibrary().copyWith(
        items: [
          vocabItem(id: 'v1', word: 'run', lemma: 'run'),
          vocabItem(id: 'v2', word: 'walk', lemma: 'walk'),
        ],
      );
      final out = markSpellingMiss(lib, 'v1', now);
      expect(out.items[1], lib.items[1]);
    });
  });
}
