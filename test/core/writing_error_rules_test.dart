/// `core/writing_error_rules.dart` 的测试：闭集与标签、key 生成、旧批改归类。
///
/// 用例对齐 Web 版 `src/core/writingErrorRules.test.ts`（81 行）。
library;

import 'package:dlaoshi_app/core/writing_error_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('writingErrorRules：闭集与标签', () {
    test('每条 rule 都有 type；catalog 覆盖全部 rule', () {
      for (final rule in WritingRule.values) {
        expect(writingTypeOf(rule), isA<WritingIssueType>());
      }
      final catalog = writingRuleCatalog();
      for (final rule in WritingRule.values) {
        expect(catalog, contains(rule.id));
        expect(catalog, contains(rule.label));
      }
    });

    test('rule / key 的形状校验', () {
      expect(isWritingRule('chunk-sense'), isTrue);
      expect(isWritingRule('Chunk Sense'), isFalse);
      expect(isWritingRule(null), isFalse);
      expect(isWritingIssueKey('chunk-an-end-to'), isTrue);
      expect(isWritingIssueKey('Chunk'), isFalse);
      expect(isWritingIssueKey('ab'), isFalse);
      expect(writingKeySlug('an end to'), 'an-end-to');
      expect(writingKeySlug('  '), 'x');
      expect(WritingRule.byId('chunk-sense'), WritingRule.chunkSense);
      expect(WritingRule.byId('nope'), isNull);
    });

    test('机械规则用规则级 key，词汇错因用具体片段', () {
      expect(
        writingKeyFor(WritingRule.sentenceInitialCapital, 'this new policy', 'This new policy'),
        'sentence-initial-capital',
      );
      expect(
        writingKeyFor(WritingRule.wordSpelling, 'bureacracy', 'bureaucracy'),
        'spelling-bureaucracy',
      );
      expect(
        writingKeyFor(WritingRule.chunkSense, 'come to an end', 'bring an end to'),
        'chunk-bring-an-end-to',
      );
    });

    test('type 只从 rule 推导（AI 写错 type 也不会把趋势带歪）', () {
      expect(writingTypeOf(WritingRule.commaFollowedBySpace), WritingIssueType.punctuation);
      expect(writingTypeOf(WritingRule.chunkSense), WritingIssueType.chunk);
      expect(writingTypeLabel(WritingIssueType.punctuation), '标点 / 空格');
    });
  });

  group('classifyLegacyIssue：把旧批改映射到新标签', () {
    const cases = <(String, String, String, WritingRule)>[
      ('this new policy', 'This new policy', '句首单词首字母必须大写。',
          WritingRule.sentenceInitialCapital),
      ('devotees,but', 'devotees, but', '逗号后缺少空格，标点格式不规范。',
          WritingRule.commaFollowedBySpace),
      ('bureacracy', 'bureaucracy', '拼写错误，正确拼写为 bureaucracy。',
          WritingRule.wordSpelling),
      ('compared to pretentious performance', 'compared to religious worship',
          '未使用题目要求必须使用的词块 religious worship；', WritingRule.chunkMissing),
      ('advocates to slow', 'advocates slowing', '搭配错误：advocate 作动词不能接不定式 to do。',
          WritingRule.verbPattern),
      ('Much as what has been told.', 'Much as we were told last year, ...',
          'much as 是连词，须引导完整的从句；且原句缺少主句，不成句。',
          WritingRule.incompleteClause),
      ('my personal things', 'my private matters', '搭配问题：personal things 偏中式、过于笼统。',
          WritingRule.literalTranslation),
      ('his handsome elf friend', 'his tall, handsome elf friend', '补一个形容词后指代更清晰，句子更顺。',
          WritingRule.unclearReference),
    ];

    for (final c in cases) {
      test(c.$4.id, () {
        final got = classifyLegacyIssue(
          LegacyIssueLike(original: c.$1, suggestion: c.$2, reason: c.$3),
        );
        expect(got.rule, c.$4);
        expect(got.type, c.$4.type);
        expect(got.key.length, greaterThan(2));
      });
    }

    test('纯风格建议算 improvement，硬错算 must-fix', () {
      final style = classifyLegacyIssue(
        const LegacyIssueLike(
          original: 'this drilling process',
          suggestion: 'the era of routine drilling exercises',
          reason: '搭配范围过窄，语义不自然；可改为抽象名词短语。',
        ),
      );
      expect(style.severity, 'improvement');
      expect(style.isImprovement, isTrue);

      final hard = classifyLegacyIssue(
        const LegacyIssueLike(
          original: 'an en',
          suggestion: 'an end',
          reason: '拼写错误：词块是 an end to，en 不是英语单词。',
        ),
      );
      expect(hard.severity, 'must-fix');
      expect(hard.isImprovement, isFalse);
    });

    test('三样都给不出线索时落到 other，且 key 仍然合法', () {
      final got = classifyLegacyIssue(const LegacyIssueLike());
      expect(got.rule, WritingRule.other);
      expect(got.type, WritingIssueType.other);
      expect(isWritingIssueKey(got.key), isTrue);
    });
  });
}
