import 'package:dlaoshi_app/core/vocab/sense.dart';
import 'package:dlaoshi_app/models/vocab.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/vocab_fixture.dart';

VocabItem item({
  String word = 'x',
  VocabItemKind? kind,
  String? partOfSpeech,
  String? meaning,
  Map<VocabField, VocabFieldSource>? fieldSources,
}) =>
    vocabItem(
      id: 'vocab:x',
      word: word,
      lemma: word,
      kind: kind,
      partOfSpeech: partOfSpeech,
      meaning: meaning,
      fieldSources: fieldSources,
    );

void main() {
  group('posClassOf / posFromGloss', () {
    test('词性归类：缩写、全称、并写', () {
      expect(posClassOf('n.'), 'n');
      expect(posClassOf('noun'), 'n');
      expect(posClassOf('vt.'), 'v');
      expect(posClassOf('a.'), 'adj');
      expect(posClassOf('adv'), 'adv');
      expect(posClassOf('n./v.'), 'n');
      expect(posClassOf(''), '');
    });

    test('释义开头的词性标记', () {
      expect(posFromGloss('n. 誓约, 誓言'), 'n.');
      expect(posFromGloss('vt. 引起, 触发'), 'v.');
      expect(posFromGloss('a. 微小的'), 'adj.');
      expect(posFromGloss('与……匹敌'), isNull);
      expect(posFromGloss('a word or phrase'), isNull);
      expect(posFromGloss(''), isNull);
    });
  });

  group('reconcileSense', () {
    test('释义带着词性标记时，词性跟它走（v. 却写着 n. 的释义 → 改回 n.）', () {
      final out = reconcileSense(item(
        partOfSpeech: 'v.',
        meaning: 'n. 誓约, 誓言',
        fieldSources: {
          VocabField.partOfSpeech: VocabFieldSource.ai,
          VocabField.meaning: VocabFieldSource.dict,
        },
      ));
      expect(out.partOfSpeech, 'n.');
      expect(out.fieldSources![VocabField.partOfSpeech], VocabFieldSource.dict);
    });

    test('释义标记与词性一致时原样返回（同一个引用，调用方据此跳过写库）', () {
      final cur = item(
        partOfSpeech: 'n.',
        meaning: 'n. 誓约',
        fieldSources: {
          VocabField.partOfSpeech: VocabFieldSource.ai,
          VocabField.meaning: VocabFieldSource.ai,
        },
      );
      expect(identical(reconcileSense(cur), cur), isTrue);
    });

    test('释义没带标记就不猜（词性为空也不硬凑）', () {
      final cur = item(partOfSpeech: 'n.', meaning: '与……匹敌');
      expect(identical(reconcileSense(cur), cur), isTrue);
    });

    test('用户手填的词性不动', () {
      final cur = item(
        partOfSpeech: 'v.',
        meaning: 'n. 誓约',
        fieldSources: {
          VocabField.partOfSpeech: VocabFieldSource.manual,
          VocabField.meaning: VocabFieldSource.dict,
        },
      );
      expect(identical(reconcileSense(cur), cur), isTrue);
    });

    test('词组 / 用法笔记没有词性可言，原样返回', () {
      final phrase = item(word: 'take off', meaning: 'n. 起飞');
      expect(identical(reconcileSense(phrase), phrase), isTrue);
      final usage = item(word: 'x', kind: VocabItemKind.usage, meaning: 'n. 誓约');
      expect(identical(reconcileSense(usage), usage), isTrue);
    });
  });

  group('senseConflict', () {
    test('词典占位词性 + AI 语境释义 → 报出来', () {
      expect(
        senseConflict(item(
          partOfSpeech: 'n.',
          meaning: '与……匹敌',
          fieldSources: {
            VocabField.partOfSpeech: VocabFieldSource.dict,
            VocabField.meaning: VocabFieldSource.ai,
          },
        )),
        'dict-pos-with-ai-meaning',
      );
    });

    test('词性与释义首标打架 → 报出来', () {
      expect(senseConflict(item(partOfSpeech: 'v.', meaning: 'n. 誓约')), 'pos-gloss-mismatch');
    });

    test('AI 同时给词性和释义（同一行答案）不算冲突', () {
      expect(
        senseConflict(item(
          partOfSpeech: 'v.',
          meaning: '与……匹敌',
          fieldSources: {
            VocabField.partOfSpeech: VocabFieldSource.ai,
            VocabField.meaning: VocabFieldSource.ai,
          },
        )),
        isNull,
      );
    });
  });
}
