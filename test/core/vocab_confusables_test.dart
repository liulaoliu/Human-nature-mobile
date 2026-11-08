import 'package:dlaoshi_app/core/vocab_confusables.dart';
import 'package:dlaoshi_app/models/vocab.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('易混项来源', () {
    test('只认 ai / dict，其它一律当未记录', () {
      expect(parseVocabConfusableSource('ai'), VocabConfusableSource.ai);
      expect(parseVocabConfusableSource('dict'), VocabConfusableSource.dict);
      expect(parseVocabConfusableSource('manual'), isNull);
      expect(parseVocabConfusableSource(''), isNull);
      expect(parseVocabConfusableSource(null), isNull);
      expect(parseVocabConfusableSource(3), isNull);
    });

    test('界面标签；旧数据（null）不显示来源', () {
      expect(confusableSourceLabel(VocabConfusableSource.ai), 'AI');
      expect(confusableSourceLabel(VocabConfusableSource.dict), '词典');
      expect(confusableSourceLabel(null), '');
    });

    test('受控清单与枚举一一对应', () {
      expect(vocabConfusableSources.toSet(), VocabConfusableSource.values.toSet());
    });
  });
}
