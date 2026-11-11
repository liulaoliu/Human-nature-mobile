import 'package:dlaoshi_app/core/vocab/replay.dart';
import 'package:dlaoshi_app/models/vocab.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/vocab_fixture.dart';

VocabItem _withReview(String id, String word, {int repetitions = 0}) =>
    vocabItem(id: id, word: word).copyWith(
      reviewState: ReviewState(repetitions: repetitions),
    );

void main() {
  group('touchedIds', () {
    test('复习状态变了就算碰到', () {
      final before = VocabLibrary(items: [_withReview('v1', 'alpha')]);
      final after = VocabLibrary(items: [_withReview('v1', 'alpha', repetitions: 1)]);
      expect(touchedIds(before, after), {'v1'});
    });

    test('标签变了也算（拼错会加「不认识」）', () {
      final before = VocabLibrary(items: [vocabItem(id: 'v1', word: 'alpha')]);
      final after = VocabLibrary(
        items: [vocabItem(id: 'v1', word: 'alpha').copyWith(tags: ['不认识'])],
      );
      expect(touchedIds(before, after), {'v1'});
    });

    test('新加的词条算碰到', () {
      final before = VocabLibrary(items: [_withReview('v1', 'alpha')]);
      final after = VocabLibrary(
        items: [_withReview('v1', 'alpha'), _withReview('v2', 'bravo')],
      );
      expect(touchedIds(before, after), {'v2'});
    });

    test('什么都没改就是空集', () {
      final before = VocabLibrary(items: [_withReview('v1', 'alpha', repetitions: 2)]);
      final after = VocabLibrary(items: [_withReview('v1', 'alpha', repetitions: 2)]);
      expect(touchedIds(before, after), isEmpty);
    });

    test('顺序不影响结果', () {
      final before = VocabLibrary(
        items: [_withReview('v1', 'alpha'), _withReview('v2', 'bravo')],
      );
      final after = VocabLibrary(
        items: [_withReview('v2', 'bravo', repetitions: 1), _withReview('v1', 'alpha')],
      );
      expect(touchedIds(before, after), {'v2'});
    });
  });

  group('replayPatched', () {
    test('只把差集盖上去，别人的改动留着', () {
      // 库里最新一份：v2 被别人改了。
      final fresh = VocabLibrary(
        items: [
          _withReview('v1', 'alpha'),
          _withReview('v2', 'bravo', repetitions: 9),
        ],
      );
      // 本地那份：v1 判过分，v2 还是旧值（没跟上别人的改动）。
      final patched = VocabLibrary(
        items: [
          _withReview('v1', 'alpha', repetitions: 1),
          _withReview('v2', 'bravo'),
        ],
      );

      final merged = replayPatched(fresh, patched, {'v1'});
      expect(merged.items.firstWhere((it) => it.id == 'v1').reviewState.repetitions, 1);
      expect(
        merged.items.firstWhere((it) => it.id == 'v2').reviewState.repetitions,
        9,
        reason: 'v2 不在差集里，必须保留库里那份',
      );
    });

    test('差集里的新词条追加到末尾', () {
      final fresh = VocabLibrary(items: [_withReview('v1', 'alpha')]);
      final patched = VocabLibrary(
        items: [_withReview('v1', 'alpha'), _withReview('v2', 'bravo', repetitions: 1)],
      );
      final merged = replayPatched(fresh, patched, {'v2'});
      expect(merged.items.map((it) => it.id), ['v1', 'v2']);
      expect(merged.items.last.reviewState.repetitions, 1);
    });

    test('差集里的 id 在两边都没有时静默跳过', () {
      final fresh = VocabLibrary(items: [_withReview('v1', 'alpha')]);
      final patched = VocabLibrary(items: [_withReview('v1', 'alpha')]);
      final merged = replayPatched(fresh, patched, {'ghost'});
      expect(merged.items.map((it) => it.id), ['v1']);
    });

    test('空差集等于原样返回 base 的内容', () {
      final fresh = VocabLibrary(items: [_withReview('v1', 'alpha', repetitions: 3)]);
      final patched = VocabLibrary(items: [_withReview('v1', 'alpha')]);
      final merged = replayPatched(fresh, patched, const <String>{});
      expect(merged.items.single.reviewState.repetitions, 3);
    });

    test('不改入参', () {
      final fresh = VocabLibrary(items: [_withReview('v1', 'alpha')]);
      final patched = VocabLibrary(items: [_withReview('v1', 'alpha', repetitions: 2)]);
      replayPatched(fresh, patched, {'v1'});
      expect(fresh.items.single.reviewState.repetitions, 0);
      expect(patched.items.single.reviewState.repetitions, 2);
    });
  });
}
