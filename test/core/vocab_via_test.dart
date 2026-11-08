import 'package:dlaoshi_app/core/vocab_via.dart';
import 'package:dlaoshi_app/models/vocab.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isVocabVia：外部输入来源守卫', () {
    test('七个合法来源都认', () {
      for (final via in vocabVias) {
        expect(isVocabVia(via.name), isTrue, reason: via.name);
        expect(parseVocabVia(via.name), via);
      }
    });

    test('非字符串 / 乱写 / 大小写不符 → 不认', () {
      expect(isVocabVia(null), isFalse);
      expect(isVocabVia(''), isFalse);
      expect(isVocabVia('乱写'), isFalse);
      expect(isVocabVia('AI'), isFalse);
      expect(isVocabVia(1), isFalse);
      expect(isVocabVia(<String, String>{}), isFalse);
    });

    test('受控清单与枚举一一对应（加枚举必须同步这里）', () {
      expect(vocabVias.toSet(), VocabVia.values.toSet());
      expect(vocabVias, hasLength(7));
    });
  });
}
