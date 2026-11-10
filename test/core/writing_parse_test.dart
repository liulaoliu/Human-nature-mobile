/// `core/writing_parse.dart` 的薄测试：解析层从 writing.dart 拆出来后仍自洽。
///
/// 完整的行为测试在 `writing_test.dart`（那边 import 伞）；这里只验证
/// 「单独 import 本模块」也能用，满足 core 文件必须有同名测试的门禁。
library;

import 'dart:convert';

import 'package:dlaoshi_app/core/writing_error_rules.dart' show WritingRule, WritingIssueType;
import 'package:dlaoshi_app/core/writing_parse.dart';
import 'package:dlaoshi_app/core/writing_types.dart' show ImitationTask;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('writing_parse', () {
    test('parseImitationTask 认栅栏 JSON，缺 model 返回 null', () {
      const raw = '```json\n{"task":"写 3 句","model":"M","rubric":[]}\n```';
      final t = parseImitationTask(raw);
      expect(t, isNotNull);
      expect(t!.task, '写 3 句');
      expect(t.model, 'M');
      expect(parseImitationTask(jsonEncode(<String, Object?>{'task': 'x'})), isNull);
      // 类型本身可从本模块 + types 组合使用。
      expect(const ImitationTask(task: 't'), isA<ImitationTask>());
    });

    test('parseWritingFeedbackDetailed 缺 rule/key 时补全并计 inferred', () {
      final raw = jsonEncode(<String, Object?>{
        'issues': <Object?>[
          <String, Object?>{
            'original': 'bureacracy',
            'suggestion': 'bureaucracy',
            'reason': '拼写错误',
          },
        ],
      });
      final parsed = parseWritingFeedbackDetailed(raw);
      expect(parsed, isNotNull);
      final issue = parsed!.feedback.issues.first;
      expect(issue.rule, WritingRule.wordSpelling);
      expect(issue.key, 'spelling-bureaucracy');
      expect(issue.type, WritingIssueType.spelling);
      expect(parsed.dropped.inferred, greaterThan(0));
    });

    test('scores 与 issues 都空时返回 null；answer 校验丢掉编造的原文', () {
      expect(parseWritingFeedback(jsonEncode(<String, Object?>{'summary': 'x'})), isNull);
      final raw = jsonEncode(<String, Object?>{
        'issues': <Object?>[
          <String, Object?>{
            'original': '编的原文',
            'suggestion': 'x',
            'rule': 'other',
            'key': 'other',
          },
        ],
      });
      final parsed = parseWritingFeedbackDetailed(
        raw,
        const WritingFeedbackParseOptions(answer: 'I go to school.'),
      );
      expect(parsed, isNull);
    });
  });
}
