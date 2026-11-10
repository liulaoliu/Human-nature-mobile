/// `core/writing_types.dart` 的薄测试：类型声明从 writing.dart 拆出来后仍自洽。
///
/// 完整的行为测试在 `writing_test.dart`（那边 import 伞）；这里只验证
/// 「单独 import 本模块」也能用，满足 core 文件必须有同名测试的门禁。
library;

import 'package:dlaoshi_app/core/writing_error_rules.dart' show WritingIssueType, WritingRule;
import 'package:dlaoshi_app/core/writing_types.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('writing_types', () {
    test('ImitationTask.copyWith 能清掉可空字段', () {
      const t = ImitationTask(
        task: '写 3 句',
        model: 'M',
        structure: 'S',
        focus: 'come to an end',
        round: 2,
      );
      final cleared = t.copyWith(
        model: '',
        structure: () => null,
        focus: () => null,
        round: () => null,
      );
      expect(cleared.model, '');
      expect(cleared.structure, isNull);
      expect(cleared.focus, isNull);
      expect(cleared.round, isNull);
      expect(cleared.task, '写 3 句');
    });

    test('ImitationTask.toJson 带上 focus/round，省略空的可空字段', () {
      const t = ImitationTask(
        task: 't',
        mustUse: <String>['a'],
        rubric: <RubricItem>[RubricItem(dimension: '语法', weight: 40)],
        focus: 'f',
        round: 2,
      );
      final j = t.toJson();
      expect(j['task'], 't');
      expect(j['focus'], 'f');
      expect(j['round'], 2);
      expect(j.containsKey('structure'), isFalse);
      expect((j['rubric'] as List).first, isA<Map<String, Object?>>());
    });

    test('isWritingFeedbackV2 与 WritingIssue.type 都只从 rule 推导', () {
      const f = WritingFeedback();
      expect(isWritingFeedbackV2(f), isTrue);
      expect(isWritingFeedbackV2(null), isFalse);
      expect(isWritingFeedbackV2(const WritingFeedback(version: 1)), isFalse);
      const issue = WritingIssue(
        original: 'go',
        suggestion: 'went',
        rule: WritingRule.tenseChoice,
        key: 'tense-choice',
      );
      expect(issue.type, WritingIssueType.grammar);
      expect(issue.isImprovement, isFalse);
    });
  });
}
