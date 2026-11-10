/// `core/writing_prompt.dart` 的薄测试：提示词拼装从 writing.dart 拆出来后仍自洽。
///
/// 完整的行为测试在 `writing_test.dart`（那边 import 伞）；这里只验证
/// 「单独 import 本模块」也能用，满足 core 文件必须有同名测试的门禁。
library;

import 'package:dlaoshi_app/core/writing_error_rules.dart' show WritingRule;
import 'package:dlaoshi_app/core/writing_prompt.dart';
import 'package:dlaoshi_app/core/writing_types.dart' show ImitationTask, RubricItem;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('writing_prompt', () {
    test('出题提示词含范句、结构、JSON schema', () {
      final p = buildImitationTaskPrompt(
        model: 'The more we learn, the less we know.',
        structure: 'the more… the more…',
        mustUse: const <String>['the more'],
      );
      expect(p, contains('The more we learn, the less we know.'));
      expect(p, contains('"rubric"'));
      expect(p, contains('结构提示：the more… the more…'));
    });

    test('批改提示词含评分标准、学生作答、错因闭集', () {
      const task = ImitationTask(
        task: '写 3 句',
        model: 'M',
        rubric: <RubricItem>[RubricItem(dimension: '语法准确', weight: 40)],
      );
      final p = buildWritingFeedbackPrompt(task, 'I go to school yesterday.');
      expect(p, contains('语法准确（满分 40）'));
      expect(p, contains('I go to school yesterday.'));
      expect(p, contains('"version":2'));
      expect(p, contains('"polished"'));
    });

    test('第二稿提示词要求逐条复查上一稿问题', () {
      const task = ImitationTask(task: 't', model: 'm');
      final p = buildWritingFeedbackPrompt(
        task,
        'I went to school.',
        const WritingFeedbackPromptOptions(
          previousIssues: <PreviousIssue>[
            PreviousIssue(
              original: 'go',
              suggestion: 'went',
              rule: WritingRule.tenseChoice,
              key: 'tense-choice',
            ),
          ],
        ),
      );
      expect(p, contains('上一稿批改指出过这些问题'));
      expect(p, contains('已经改掉的不要再报'));
    });
  });
}
