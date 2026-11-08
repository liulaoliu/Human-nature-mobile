import 'package:dlaoshi_app/core/vocab/meaning_options.dart';
import 'package:dlaoshi_app/models/vocab.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/vocab_fixture.dart';

VocabItem item(String id, String? meaning) =>
    vocabItem(id: id, word: id, lemma: id, meaning: meaning);

final card = item('a', '放弃');
final others = [
  item('b', '勇敢'),
  item('c', '取消'),
  item('d', '遗弃'),
  item('e', '抛弃'),
];

void main() {
  group('meaningOptions：选中文释义的四个选项', () {
    test('正确 + 3 个干扰项，共 4 条', () {
      final opts = meaningOptions(card, [card, ...others]);
      expect(opts, hasLength(4));
      expect(opts.where((o) => o.correct), hasLength(1));
      expect(opts.firstWhere((o) => o.correct).text, '放弃');
    });

    test('干扰项来自别的词，不含正确释义本身', () {
      final opts = meaningOptions(card, [card, ...others]);
      expect(opts.where((o) => !o.correct).map((o) => o.text), isNot(contains('放弃')));
      expect(opts.map((o) => o.text).toSet(), hasLength(4));
    });

    test('同一张卡顺序稳定（词库增删也不跳位置）', () {
      final a = meaningOptions(card, [card, ...others]).map((o) => o.text).toList();
      final b = meaningOptions(card, [card, ...others, item('f', '离别')]).map((o) => o.text).toList();
      expect(a, b);
    });

    test('正确项下标能取到（学习模式揭示答案要用）', () {
      final opts = meaningOptions(card, [card, ...others]);
      expect(opts[correctOptionIndex(card, [card, ...others])].correct, isTrue);
    });

    test('词库不足 3 个干扰项 → 出不了题（调用方退回普通卡）', () {
      expect(meaningOptions(card, [card, item('b', '勇敢')]), isEmpty);
      expect(correctOptionIndex(card, [card, item('b', '勇敢')]), -1);
    });

    test('没有释义的词也出不了题', () {
      final noMeaning = item('a', null);
      expect(meaningOptions(noMeaning, [noMeaning, ...others]), isEmpty);
    });

    test('FNV-1a 与 Web 版逐位一致（顺序才不会两端不同）', () {
      // 期望值由 Web 版的 `Math.imul(h ^ c, 16777619) >>> 0` 算出
      expect(optionHash('a|放弃'), 3133226731);
      expect(optionHash('a#放弃'), 373022830);
      expect(optionHash('a|勇敢'), 2219915221);
      expect(optionHash('a#勇敢'), 3257624868);
      expect(optionHash('zzz'), 2813343901);
      expect(optionHash('x|y'), 3281726344);
    });
  });
}
