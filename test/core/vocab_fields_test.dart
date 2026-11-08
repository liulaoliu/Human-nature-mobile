import 'package:dlaoshi_app/core/vocab_fields.dart';
import 'package:dlaoshi_app/models/vocab.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/vocab_fixture.dart';

void main() {
  test('字段名与来源名和备份 JSON 一致', () {
    expect(vocabFields.map(vocabFieldName).toList(),
        ['phonetic', 'partOfSpeech', 'meaning', 'definition']);
    expect(vocabFieldSources.map(vocabFieldSourceName).toList(),
        ['ai', 'dict', 'manual']);
  });

  test('parseVocabField / parseVocabFieldSource 只认认识的', () {
    expect(parseVocabField('meaning'), VocabField.meaning);
    expect(parseVocabField('bogus'), isNull);
    expect(parseVocabField(1), isNull);
    expect(parseVocabFieldSource('dict'), VocabFieldSource.dict);
    expect(parseVocabFieldSource(''), isNull);
  });

  test('normalizeVocabFieldSources 丢弃不认识的键值，空对象当没有', () {
    expect(
      normalizeVocabFieldSources({
        'meaning': 'manual',
        'phonetic': 'bogus',
        'bogus': 'ai',
      }),
      {VocabField.meaning: VocabFieldSource.manual},
    );
    expect(normalizeVocabFieldSources({'bogus': 'ai'}), isNull);
    expect(normalizeVocabFieldSources(null), isNull);
    expect(normalizeVocabFieldSources(['meaning']), isNull);
  });

  test('isFieldLocked：mastered 整条锁，新数据只看该字段，旧数据按 edited 整条锁', () {
    final fresh = vocabItem(id: 'v1');
    expect(isFieldLocked(fresh, VocabField.meaning), isFalse);

    final manualMeaning = fresh.copyWith(
      fieldSources: () => {VocabField.meaning: VocabFieldSource.manual},
    );
    expect(isFieldLocked(manualMeaning, VocabField.meaning), isTrue);
    expect(isFieldLocked(manualMeaning, VocabField.phonetic), isFalse);

    final aiMeaning = fresh.copyWith(
      fieldSources: () => {VocabField.meaning: VocabFieldSource.ai},
    );
    expect(isFieldLocked(aiMeaning, VocabField.meaning), isFalse);

    final edited = vocabItem(id: 'v2', status: VocabStatus.edited);
    expect(isFieldLocked(edited, VocabField.phonetic), isTrue);

    final mastered = vocabItem(
      id: 'v3',
      status: VocabStatus.mastered,
      fieldSources: const {VocabField.meaning: VocabFieldSource.ai},
    );
    expect(isFieldLocked(mastered, VocabField.meaning), isTrue);
  });

  test('fieldSourceLabel 中文标签', () {
    expect(fieldSourceLabel(VocabFieldSource.ai), 'AI');
    expect(fieldSourceLabel(VocabFieldSource.dict), '词典');
    expect(fieldSourceLabel(VocabFieldSource.manual), '手动');
    expect(fieldSourceLabel(null), '');
  });
}
