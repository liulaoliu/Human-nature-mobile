import 'package:flutter_test/flutter_test.dart';

import 'package:dlaoshi_app/core/ecdict.dart';
import 'package:dlaoshi_app/core/vocab/analysis.dart' show WordAnalysis;
import 'package:dlaoshi_app/core/vocab/analysis_fill.dart';
import 'package:dlaoshi_app/models/vocab.dart' show VocabField, VocabFieldSource;

/// 词汇表：word / phonetic / pos / en / zh（zh 里的 `\n` 是转义，解析时展开）。
const String _words = 'word\tphonetic\tpos\ten\tzh\t\t\t\t\n'
    'rival\trˈaɪvəl\tn\tperson competing\tn. 竞争对手\\nvt. 与……匹敌\n'
    'vow\tvˈaʊ\tv\tpromise\tn. 誓约\\nvi. 起誓\n'
    'slow\tslˈoʊ\t\t\tadj. 慢的\n'
    'blank\tblæŋk\tadj\t\t\n';

Ecdict _dict() => parseEcdict(_words, '');

void main() {
  group('wordAnalysisFromDict：只靠词典查一个词', () {
    test('查得到：音标包斜杠、词性与释义同源、来源全记 dict', () {
      final out = wordAnalysisFromDict(_dict(), 'rival');
      expect(out, isNotNull);
      expect(out!.word, 'rival');
      expect(out.phonetic, '/rˈaɪvəl/');
      expect(out.partOfSpeech, 'n.');
      expect(out.meaning, 'n. 竞争对手');
      expect(out.definition, 'person competing');
      expect(out.fieldSources?[VocabField.phonetic], VocabFieldSource.dict);
      expect(out.fieldSources?[VocabField.partOfSpeech], VocabFieldSource.dict);
      expect(out.fieldSources?[VocabField.meaning], VocabFieldSource.dict);
      expect(out.fieldSources?[VocabField.definition], VocabFieldSource.dict);
    });

    test('大小写与首尾空白不敏感', () {
      expect(wordAnalysisFromDict(_dict(), '  Rival ')?.word, 'rival');
    });

    test('词性取释义行的标记，不硬取 pos 列', () {
      // pos 列写 v，但中文释义第一行是 n. 誓约 —— 取释义那一行才自洽。
      final out = wordAnalysisFromDict(_dict(), 'vow');
      expect(out!.partOfSpeech, 'n.');
      expect(out.meaning, 'n. 誓约');
    });

    test('词条没有释义 / 英英：对应字段空着，不编', () {
      final out = wordAnalysisFromDict(_dict(), 'blank');
      expect(out!.phonetic, '/blæŋk/');
      expect(out.meaning, isNull);
      expect(out.definition, isNull);
      expect(out.partOfSpeech, 'adj.');
      expect(out.fieldSources?.containsKey(VocabField.meaning), isFalse);
    });

    test('词典里没有这个词：返回 null', () {
      expect(wordAnalysisFromDict(_dict(), 'zzzz'), isNull);
    });

    test('没有词典：返回 null 而不是空壳', () {
      expect(wordAnalysisFromDict(null, 'rival'), isNull);
    });

    test('空词返回 null', () {
      expect(wordAnalysisFromDict(_dict(), '   '), isNull);
    });

    test('变形词查到原形，word 用原形', () {
      final dict = parseEcdict(_words, 'rivals\trival\n');
      final out = wordAnalysisFromDict(dict, 'rivals');
      expect(out!.word, 'rival');
      expect(out.meaning, 'n. 竞争对手');
    });
  });

  group('fillFromDict：AI 结果 + 词典兜底', () {
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
      final out = fillFromDict(
        const WordAnalysis(word: 'rival', meaning: '对手'),
        _dict(),
      );
      expect(out.meaning, '对手');
      expect(out.partOfSpeech, isNull);
      expect(out.fieldSources?[VocabField.meaning], VocabFieldSource.ai);
      expect(out.fieldSources?.containsKey(VocabField.partOfSpeech), isFalse);
    });

    test('AI 释义自带词性标记：也不凭空加词性', () {
      final out = fillFromDict(
        const WordAnalysis(word: 'rival', meaning: 'n. 对手'),
        _dict(),
      );
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

    test('AI 的 usage / 例句不被词典覆盖', () {
      final out = fillFromDict(
        const WordAnalysis(
          word: 'rival',
          meaning: '对手',
          partOfSpeech: 'n.',
          usage: ['rival for'],
          examples: [(text: 'Two rivals met.', translation: '两个对手相遇了。')],
        ),
        _dict(),
      );
      expect(out.usage, ['rival for']);
      expect(out.examples!.single.text, 'Two rivals met.');
    });

    test('批量补：保序且逐个独立', () {
      final out = fillAllFromDict(
        const [
          WordAnalysis(word: 'rival'),
          WordAnalysis(word: 'zzzz'),
          WordAnalysis(word: 'vow'),
        ],
        _dict(),
      );
      expect(out.map((w) => w.word).toList(), ['rival', 'zzzz', 'vow']);
      expect(out[0].meaning, 'n. 竞争对手');
      expect(out[1].meaning, isNull);
      expect(out[2].meaning, 'n. 誓约');
    });
  });
}
