import 'package:flutter_test/flutter_test.dart';

import 'package:dlaoshi_app/core/analyzer_prompt.dart';
import 'package:dlaoshi_app/core/analyzer_shared.dart';
import 'package:dlaoshi_app/core/ecdict.dart' show EcdictLevel;

void main() {
  group('buildPrompt', () {
    test('每个任务都以统一口吻打头，并用围栏包住原文', () {
      for (final task in const [
        AnalysisTask.translate,
        AnalysisTask.grammar,
        AnalysisTask.collocations,
        AnalysisTask.summarize,
        AnalysisTask.extractVocab,
      ]) {
        final p = buildPrompt(BuildPromptInput(task: task, text: '  He runs.  '));
        expect(p.startsWith(header), isTrue, reason: '$task 缺 HEADER');
        expect(p.contains(fence), isTrue, reason: '$task 缺围栏');
        expect(p.contains('He runs.'), isTrue);
        expect(p.contains('  He runs.  '), isFalse, reason: '原文要 trim');
      }
    });

    test('lookup 用 words 列表，没有就用原文', () {
      final withWords = buildPrompt(
        const BuildPromptInput(
          task: AnalysisTask.lookup,
          text: 'context text',
          words: ['run', 'sprint'],
        ),
      );
      expect(withWords.contains('单词：run, sprint'), isTrue);
      final without = buildPrompt(
        const BuildPromptInput(task: AnalysisTask.lookup, text: 'run'),
      );
      expect(without.contains('单词：run'), isTrue);
    });

    test('lookup 提示词带七列要求与原形还原规则', () {
      final p = buildPrompt(
        const BuildPromptInput(task: AnalysisTask.lookup, text: 'run'),
      );
      expect(p.contains('单词 | 音标 | 词性 | 中文含义 | 用法/搭配 | 例句(英+中) | 英文释义'), isTrue);
      expect(p.contains('unchallenged'), isFalse);
      expect(p.contains('companies→company'), isTrue);
    });

    test('auto_vocab 走 level 参数', () {
      final p = buildPrompt(
        const BuildPromptInput(task: AnalysisTask.autoVocab, text: 'a text'),
      );
      expect(p.contains(levelDesc[EcdictLevel.cet6]!), isTrue);
    });
  });

  group('批量提示词', () {
    test('批量查词去重并带上上下文', () {
      final p = buildBatchLookupPrompt([
        (word: 'run', context: 'He runs fast.'),
        (word: 'Run', context: null),
        (word: 'sprint', context: '  '),
      ]);
      expect(p.contains('- run  （上下文：He runs fast.）'), isTrue);
      expect(p.contains('- sprint'), isTrue);
      expect('Run'.allMatches(p).length, 0, reason: '小写去重后不再出现大写版本');
    });

    test('例句 / 词组 / 语法标记提示词都按「词（含义）」列词', () {
      for (final builder in [
        buildExamplePrompt,
        buildPhrasePrompt,
        buildGrammarMarkPrompt,
        buildConfusablePrompt,
      ]) {
        final p = builder([
          (word: 'run', meaning: '跑'),
          (word: 'mrs', meaning: null),
        ]);
        expect(p.contains('- run（跑）'), isTrue);
        expect(p.contains('- mrs'), isTrue);
      }
    });

    test('语法标记提示词限定了六种标记', () {
      final p = buildGrammarMarkPrompt([(word: 'run', meaning: null)]);
      for (final mark in ['可数', '不可数', '及物', '不及物', '可分级', '不可分级']) {
        expect(p.contains(mark), isTrue, reason: '缺 $mark');
      }
      expect(p.contains('单词 | 标记1；标记2'), isTrue);
    });

    test('原形提示词强调派生词不还原', () {
      final p = buildLemmaPrompt([(word: 'unchallenged', context: 'x')]);
      expect(p.contains('unchallenged → unchallenged'), isTrue);
      expect(p.contains('原词形 | 原形'), isTrue);
      expect(p.contains('- unchallenged  （语境：x）'), isTrue);
    });

    test('辨析提示词要 8 列', () {
      final p = buildPosPrompt([(word: 'sliding', context: null)]);
      expect(
        p.contains('原形 | 当前形式 | 当前词性 | 语法身份 | 修饰对象/句子成分 | 具体含义 | 判断理由 | 最准确词性标注'),
        isTrue,
      );
    });
  });

  group('其它', () {
    test('全文翻译提示词按「id | 原文」列出句子', () {
      final p = buildTranslateAllPrompt([
        (id: 's1', text: 'He runs.'),
        (id: 's2', text: 'She swims.'),
      ]);
      expect(p.contains('s1 | He runs.'), isTrue);
      expect(p.contains('s2 | She swims.'), isTrue);
      expect(p.contains('id | 中文翻译'), isTrue);
    });

    test('清洗提示词保留【…】标记的说明', () {
      final p = buildCleanupPrompt('  raw text  ');
      expect(p.contains('【……】'), isTrue);
      expect(p.contains('$fence\nraw text\n$fence'), isTrue);
    });

    test('五种词汇水平都有描述', () {
      expect(levelDesc.keys.length, EcdictLevel.values.length);
      for (final level in EcdictLevel.values) {
        expect(levelDesc[level], isNotNull);
      }
    });

    test('自动标词提示词用围栏包住文章', () {
      final p = buildAutoVocabPrompt('  an article  ', level: EcdictLevel.ielts);
      expect(p.contains(levelDesc[EcdictLevel.ielts]!), isTrue);
      expect(p.contains('$fence\nan article\n$fence'), isTrue);
    });
  });
}
