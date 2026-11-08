import 'package:flutter_test/flutter_test.dart';

import 'package:dlaoshi_app/core/ecdict.dart';
import 'package:dlaoshi_app/core/vocab/analysis.dart' show WordAnalysis;
import 'package:dlaoshi_app/core/vocab/analysis_fill.dart';
import 'package:dlaoshi_app/core/vocab/library.dart' show createLibrary;
import 'package:dlaoshi_app/models/vocab.dart' show VocabField, VocabFieldSource;

/// 词汇表：word / phonetic / pos / en / zh（zh 里的 `\n` 是转义，解析时展开）。
const String _words = 'word\tphonetic\tpos\ten\tzh\t\t\t\t\n'
    'rival\trˈaɪvəl\tn\tperson competing\tn. 竞争对手\\nvt. 与……匹敌\n'
    'vow\tvˈaʊ\tv\tpromise\tn. 誓约\\nvi. 起誓\n'
    'slow\tslˈoʊ\t\t\tadj. 慢的\n';

Ecdict _dict() => parseEcdict(_words, '');

void main() {
  group('音标归一', () {
    test('AI 没给音标：用词典的，来源记 dict', () {
      final out = fillFromDict(const WordAnalysis(word: 'rival'), _dict());
      expect(out.phonetic, '/rˈaɪvəl/');
      expect(out.fieldSources?[VocabField.phonetic], VocabFieldSource.dict);
    });

    test('AI 给了音标：保留，来源记 ai', () {
      final out = fillFromDict(
        const WordAnalysis(word: 'rival', phonetic: 'raivl'),
        _dict(),
      );
      expect(out.phonetic, '/raivl/');
      expect(out.fieldSources?[VocabField.phonetic], VocabFieldSource.ai);
    });

    test('没有词典：不补任何字段', () {
      final out = fillFromDict(const WordAnalysis(word: 'rival'), null);
      expect(out.word, 'rival');
      expect(out.phonetic, isNull);
      expect(out.partOfSpeech, isNull);
      expect(out.meaning, isNull);
      expect(out.fieldSources, isNull);
    });
  });

  group('词性 / 释义同源', () {
    test('释义来自词典：词性取同一行的标记', () {
      final out = fillFromDict(
        const WordAnalysis(word: 'vow', partOfSpeech: 'v.'),
        _dict(),
      );
      expect(out.meaning, 'vi. 起誓');
      expect(out.partOfSpeech, 'v.');
      expect(out.fieldSources?[VocabField.meaning], VocabFieldSource.dict);
    });

    test('AI 给了释义却没给词性：词性留空，不拿词典顶上', () {
      final out = fillFromDict(const WordAnalysis(word: 'rival', meaning: '对手'), _dict());
      expect(out.meaning, '对手');
      expect(out.partOfSpeech, isNull);
      expect(out.fieldSources?[VocabField.meaning], VocabFieldSource.ai);
      expect(out.fieldSources?.containsKey(VocabField.partOfSpeech), isFalse);
    });

    test('AI 释义自带词性标记：词性跟着释义走', () {
      final out = fillFromDict(const WordAnalysis(word: 'rival', meaning: 'n. 对手'), _dict());
      expect(out.partOfSpeech, isNull, reason: '没有 AI 词性时不该凭空加');
    });

    test('AI 同时给释义和词性：两个都记 ai', () {
      final out = fillFromDict(
        const WordAnalysis(word: 'rival', meaning: '对手', partOfSpeech: 'n.'),
        _dict(),
      );
      expect(out.meaning, '对手');
      expect(out.partOfSpeech, 'n.');
      expect(out.fieldSources?[VocabField.meaning], VocabFieldSource.ai);
      expect(out.fieldSources?[VocabField.partOfSpeech], VocabFieldSource.ai);
    });
  });

  group('原形归一与英英释义', () {
    test('词形归到原形（走 forms 表）', () {
      final dict = parseEcdict(_words, 'rivals\trival\n');
      final out = fillFromDict(const WordAnalysis(word: 'rivals'), dict);
      expect(out.word, 'rival');
      expect(out.meaning, 'n. 竞争对手');
    });

    test('英英释义从 en 列按词性挑', () {
      final out = fillFromDict(const WordAnalysis(word: 'vow'), _dict());
      expect(out.definition, 'promise');
      expect(out.fieldSources?[VocabField.definition], VocabFieldSource.dict);
    });

    test('AI 给了英英：保留 AI 的', () {
      final out = fillFromDict(
        const WordAnalysis(word: 'vow', definition: 'to make a promise'),
        _dict(),
      );
      expect(out.definition, 'to make a promise');
      expect(out.fieldSources?[VocabField.definition], VocabFieldSource.ai);
    });
  });

  group('批量与守恒', () {
    test('批量补全保序，usage / examples 原样带过去', () {
      final out = fillAllFromDict(const [
        WordAnalysis(word: 'rival'),
        WordAnalysis(word: 'vow', usage: ['vow to do']),
      ], _dict());
      expect(out.map((w) => w.word), ['rival', 'vow']);
      expect(out[1].usage, ['vow to do']);
      expect(out[1].meaning, isNotNull);
    });

    test('空单词不炸', () {
      final out = fillFromDict(const WordAnalysis(word: ''), _dict());
      expect(out.word, '');
    });
  });

  group('写回词库', () {
    test('逐词写、带上本篇来源，最后去重', () {
      final at = DateTime.utc(2026, 11, 8);
      final lib = applyFilledWords(
        createLibrary(),
        fillAllFromDict(const [WordAnalysis(word: 'rival'), WordAnalysis(word: 'vow')], _dict()),
        articleId: 'a1',
        fileName: 'Book A',
        sentenceId: 's1',
        sentenceText: 'He is my rival, he vowed.',
        now: at,
      );
      expect(lib.items.length, 2);
      final rival = lib.items.firstWhere((it) => it.lemma == 'rival');
      expect(rival.meaning, 'n. 竞争对手');
      expect(rival.source?.articleId, 'a1');
      expect(rival.source?.sentenceId, 's1');
      // 查词不负责「本篇收录」—— 那是 markWord 的事，这里不建按篇条目。
      expect(lib.articleEntries, isEmpty);
    });

    test('句子没提到这个词：不挂句级来源，但照样进词库', () {
      final lib = applyFilledWords(
        createLibrary(),
        const [WordAnalysis(word: 'slow', meaning: '慢的')],
        articleId: 'a1',
        sentenceId: 's1',
        sentenceText: 'He is my rival.',
      );
      final slow = lib.items.single;
      expect(slow.meaning, '慢的');
      expect(slow.source?.sentenceId, isNull);
    });

    test('重复写同一个词不会变成两条', () {
      var lib = createLibrary();
      for (var i = 0; i < 3; i++) {
        lib = applyFilledWords(
          lib,
          const [WordAnalysis(word: 'rival', meaning: '对手')],
          articleId: 'a1',
        );
      }
      expect(lib.items.length, 1);
    });
  });
}
