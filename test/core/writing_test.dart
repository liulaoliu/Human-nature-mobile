/// `core/writing.dart` 的测试：出题 / 批改提示词、任务解析、批改解析（含推断补全）。
///
/// 用例对齐 Web 版 `src/core/writing.test.ts`（369 行）的前 171 行。
library;

import 'dart:convert';

import 'package:dlaoshi_app/core/writing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildImitationTaskPrompt', () {
    test('含范句、rubric、必须用上的词、JSON schema', () {
      final p = buildImitationTaskPrompt(
        model: 'The more we learn, the less we know.',
        structure: 'the more… the more…',
        mustUse: const <String>['the more', 'the less'],
      );
      expect(p, contains('The more we learn, the less we know.'));
      expect(p, contains('the more'));
      expect(p, contains('"rubric"'));
      expect(p, contains('结构提示：the more… the more…'));
    });

    test('没给 mustUse 时让它自己挑 2–3 个', () {
      final p = buildImitationTaskPrompt(model: 'M');
      expect(p, contains('从范句里挑 2–3 个'));
      expect(p, contains('（自定）'));
      expect(p, isNot(contains('结构提示')));
    });
  });

  group('parseImitationTask', () {
    test('解析合法 JSON（含栅栏）', () {
      const raw = '```json\n{"task":"写 3 句","model":"M","structure":"S",'
          '"mustUse":["a","b"],"rubric":[{"dimension":"语法","weight":40,"description":"..."}]}\n```';
      final t = parseImitationTask(raw);
      expect(t, isNotNull);
      expect(t!.task, '写 3 句');
      expect(t.model, 'M');
      expect(t.structure, 'S');
      expect(t.mustUse, <String>['a', 'b']);
      expect(t.rubric.first.dimension, '语法');
      expect(t.rubric.first.weight, 40);
    });

    test('缺 task/model → null', () {
      expect(parseImitationTask(jsonEncode(<String, Object?>{'task': 'x'})), isNull);
      expect(parseImitationTask('not json'), isNull);
      expect(parseImitationTask(''), isNull);
      expect(parseImitationTask('[1,2]'), isNull);
    });

    test('rubric 里没 dimension 的项丢掉，weight 非数字按 0', () {
      final t = parseImitationTask(jsonEncode(<String, Object?>{
        'task': 't',
        'model': 'm',
        'rubric': <Object?>[
          <String, Object?>{'dimension': '', 'weight': 40},
          <String, Object?>{'dimension': '连贯', 'weight': 'abc'},
        ],
      }));
      expect(t!.rubric, hasLength(1));
      expect(t.rubric.first.weight, 0);
    });
  });

  group('buildWritingFeedbackPrompt', () {
    const task = ImitationTask(
      task: '写 3 句',
      model: 'M',
      mustUse: <String>['a'],
      rubric: <RubricItem>[RubricItem(dimension: '语法准确', weight: 40)],
    );

    test('含严格规则、评分标准、学生作答、JSON schema', () {
      final p = buildWritingFeedbackPrompt(task, 'I go to school yesterday.');
      expect(p, contains('不要客套'));
      expect(p, contains('语法准确（满分 40）'));
      expect(p, contains('I go to school yesterday.'));
      expect(p, contains('"polished"'));
      expect(p, contains('"version":2'));
      expect(p, contains('chunk-sense'));
      expect(p, contains('"recommendations"'));
    });

    test('没有范句时只写「要求用上」，不留空的「范句：」', () {
      final p = buildWritingFeedbackPrompt(
        task.copyWith(model: ''),
        'I run every day.',
      );
      expect(p, contains('（要求用上：a）'));
      expect(p, isNot(contains('范句：')));
    });

    test('给可选语言点时，把 id 和 from=article 的约束写进提示词', () {
      final p = buildWritingFeedbackPrompt(
        task,
        'I go to school.',
        const WritingFeedbackPromptOptions(
          availablePoints: <AvailablePoint>[
            AvailablePoint(id: 'lp:s1:come-to-an-end', en: 'come to an end', zh: '结束', kind: 'chunk'),
          ],
        ),
      );
      expect(p, contains('lp:s1:come-to-an-end'));
      expect(p, contains('from=article'));
      expect(p, contains('结束'));
      expect(p, contains('chunk'));
    });

    test('没有可选语言点时写「本题没有可选语言点」', () {
      final p = buildWritingFeedbackPrompt(task, 'x');
      expect(p, contains('本题没有可选语言点'));
    });

    test('第二稿带上一轮 issues，要求逐条检查改了没', () {
      final p = buildWritingFeedbackPrompt(
        task,
        'I went to school.',
        const WritingFeedbackPromptOptions(
          previousIssues: <PreviousIssue>[
            PreviousIssue(
              original: 'go',
              suggestion: 'went',
              reason: '过去时间用过去式',
              rule: WritingRule.tenseChoice,
              key: 'tense-choice',
            ),
          ],
        ),
      );
      expect(p, contains('上一稿批改指出过这些问题'));
      expect(p, contains('tense-choice/tense-choice'));
      expect(p, contains('已经改掉的不要再报'));
    });

    test('rubric 为空时用三条默认评分维度', () {
      final p = buildWritingFeedbackPrompt(
        const ImitationTask(task: 't', model: 'm'),
        'x',
      );
      expect(p, contains('语法准确（满分 40）'));
      expect(p, contains('用词与搭配（满分 30）'));
      expect(p, contains('结构与连贯（满分 30）'));
    });
  });

  group('parseWritingFeedback', () {
    test('解析分数 + issues + polished', () {
      final raw = jsonEncode(<String, Object?>{
        'version': 2,
        'scores': <Object?>[
          <String, Object?>{'dimension': '语法准确', 'score': 30, 'max': 40, 'comment': '时态错'},
        ],
        'total': 30,
        'max': 40,
        'issues': <Object?>[
          <String, Object?>{
            'original': 'go',
            'suggestion': 'went',
            'reason': '过去时间用过去式',
            'rule': 'tense-choice',
            'key': 'tense-choice',
            'severity': 'must-fix',
          },
        ],
        'recommendations': <Object?>[
          <String, Object?>{
            'kind': 'chunk',
            'point': 'go to school',
            'zh': '上学',
            'why': '这次时态错在 go，顺便把这个搭配练熟',
            'priority': 2,
            'from': 'error',
            'issueKey': 'tense-choice',
          },
        ],
        'polished': 'I went to school yesterday.',
        'summary': '注意时态。',
      });
      final f = parseWritingFeedback(raw);
      expect(f, isNotNull);
      expect(f!.version, 2);
      expect(f.total, 30);
      expect(f.issues.first.original, 'go');
      expect(f.issues.first.rule, WritingRule.tenseChoice);
      expect(f.issues.first.type, WritingIssueType.grammar);
      expect(f.recommendations.first.point, 'go to school');
      expect(f.recommendations.first.issueKey, 'tense-choice');
      expect(f.polished, contains('went'));
      expect(f.summary, '注意时态。');
      expect(isWritingFeedbackV2(f), isTrue);
    });

    test('缺 rule/key 时用闭集补全，并计入 inferred', () {
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

    test('original 不在学生原文里 → 丢弃并计数', () {
      final raw = jsonEncode(<String, Object?>{
        'issues': <Object?>[
          <String, Object?>{
            'original': '编的原文',
            'suggestion': 'x',
            'rule': 'other',
            'key': 'other',
            'severity': 'must-fix',
          },
        ],
      });
      final parsed = parseWritingFeedbackDetailed(
        raw,
        const WritingFeedbackParseOptions(answer: 'I go to school.'),
      );
      expect(parsed, isNull);
    });

    test('文章语言点 pointId 不在白名单 → 丢弃 recommendation', () {
      final raw = jsonEncode(<String, Object?>{
        'scores': <Object?>[
          <String, Object?>{'dimension': '语法', 'score': 1, 'max': 2},
        ],
        'issues': const <Object?>[],
        'recommendations': <Object?>[
          <String, Object?>{
            'kind': 'chunk',
            'point': 'x',
            'why': 'y',
            'from': 'article',
            'pointId': 'lp:missing',
          },
        ],
      });
      final parsed = parseWritingFeedbackDetailed(
        raw,
        const WritingFeedbackParseOptions(availablePointIds: <String>{'lp:ok'}),
      );
      expect(parsed!.feedback.recommendations, isEmpty);
      expect(parsed.dropped.recommendations, 1);
    });

    test('没有 scores/issues → null；非法 JSON → null', () {
      expect(parseWritingFeedback(jsonEncode(<String, Object?>{'summary': 'x'})), isNull);
      expect(parseWritingFeedback('nope'), isNull);
    });

    test('issues 缺 suggestion 丢弃；重复条目只留一条', () {
      final raw = jsonEncode(<String, Object?>{
        'issues': <Object?>[
          <String, Object?>{'original': 'a', 'rule': 'other', 'key': 'other'},
          <String, Object?>{
            'original': 'go',
            'suggestion': 'went',
            'rule': 'tense-choice',
            'key': 'tense-choice',
          },
          <String, Object?>{
            'original': 'go',
            'suggestion': 'went',
            'rule': 'tense-choice',
            'key': 'tense-choice',
          },
        ],
      });
      final parsed = parseWritingFeedbackDetailed(raw)!;
      expect(parsed.feedback.issues, hasLength(1));
      expect(parsed.dropped.issues, 2);
    });

    test('total/max 缺省时按各维求和；recommendation 的 issueKey 悬空会被摘掉', () {
      final raw = jsonEncode(<String, Object?>{
        'scores': <Object?>[
          <String, Object?>{'dimension': '语法', 'score': 20, 'max': 40},
          <String, Object?>{'dimension': '用词', 'score': 15, 'max': 30},
        ],
        'issues': <Object?>[
          <String, Object?>{
            'original': 'a',
            'suggestion': 'b',
            'rule': 'other',
            'key': 'other',
          },
        ],
        'recommendations': <Object?>[
          <String, Object?>{
            'kind': 'chunk',
            'point': 'x',
            'why': 'y',
            'issueKey': 'not-exist',
          },
        ],
      });
      final parsed = parseWritingFeedbackDetailed(raw)!;
      expect(parsed.feedback.total, 35);
      expect(parsed.feedback.max, 70);
      expect(parsed.feedback.recommendations.first.issueKey, isNull);
      expect(parsed.dropped.reasons.join(), contains('issueKey 没对应 issue'));
    });

    test('recommendation kind 不在白名单 → 丢弃并记原因', () {
      final raw = jsonEncode(<String, Object?>{
        'scores': <Object?>[
          <String, Object?>{'dimension': '语法', 'score': 1, 'max': 2},
        ],
        'recommendations': <Object?>[
          <String, Object?>{'kind': 'sentence', 'point': 'x', 'why': 'y'},
        ],
      });
      final parsed = parseWritingFeedbackDetailed(raw)!;
      expect(parsed.feedback.recommendations, isEmpty);
      expect(parsed.dropped.recommendations, 1);
      expect(parsed.dropped.reasons.join(), contains('kind 不在白名单'));
    });
  });
}
