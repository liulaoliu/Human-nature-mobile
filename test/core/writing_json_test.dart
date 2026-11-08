/// 仿写任务 / 批改结果的反序列化：往返、坏值丢弃、旧版本兼容。
library;

import 'package:dlaoshi_app/core/writing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('imitationTaskFromJson', () {
    test('往返：toJson 之后能原样读回来', () {
      const task = ImitationTask(
        task: '写三句描述你的周末',
        model: 'I spent the whole morning cleaning up.',
        structure: 'spend + 时间 + doing',
        mustUse: <String>['spend', 'clean up'],
        rubric: <RubricItem>[
          RubricItem(dimension: '语法准确', weight: 40, description: '时态一致'),
          RubricItem(dimension: '结构运用', weight: 30),
        ],
        focus: 'clean up',
        round: 2,
      );

      final back = imitationTaskFromJson(task.toJson())!;

      expect(back.task, task.task);
      expect(back.model, task.model);
      expect(back.structure, task.structure);
      expect(back.mustUse, task.mustUse);
      expect(back.rubric, hasLength(2));
      expect(back.rubric.first.dimension, '语法准确');
      expect(back.rubric.first.weight, 40);
      expect(back.rubric.first.description, '时态一致');
      expect(back.rubric.last.description, isNull);
      expect(back.focus, 'clean up');
      expect(back.round, 2);
    });

    test('缺 task / 非对象 / 空串一律 null', () {
      expect(imitationTaskFromJson(null), isNull);
      expect(imitationTaskFromJson('not a map'), isNull);
      expect(imitationTaskFromJson(<String, Object?>{}), isNull);
      expect(imitationTaskFromJson(<String, Object?>{'task': '   '}), isNull);
    });

    test('rubric 里的坏行跳过，缺 description 落 null', () {
      final back = imitationTaskFromJson(<String, Object?>{
        'task': '写两句',
        'rubric': <Object?>[
          <String, Object?>{'dimension': '语法', 'weight': 50},
          <String, Object?>{'weight': 30},
          'not a map',
          <String, Object?>{'dimension': '用词', 'weight': '20', 'description': ' 地道 '},
        ],
      })!;
      expect(back.rubric, hasLength(2));
      expect(back.rubric.first.description, isNull);
      expect(back.rubric.last.weight, 20);
      expect(back.rubric.last.description, '地道');
    });

    test('round 缺省 / 0 都当首稿（null）', () {
      expect(
        imitationTaskFromJson(<String, Object?>{'task': 'x'})!.round,
        isNull,
      );
      expect(
        imitationTaskFromJson(<String, Object?>{'task': 'x', 'round': 0})!.round,
        isNull,
      );
    });
  });

  group('writingFeedbackFromJson', () {
    test('往返：分数 / 错因 / 建议 / polished 都读得回来', () {
      const feedback = WritingFeedback(
        version: 2,
        scores: <WritingScore>[
          WritingScore(dimension: '语法准确', score: 32, max: 40, comment: '时态错一处'),
          WritingScore(dimension: '结构运用', score: 26, max: 30),
        ],
        total: 82,
        max: 100,
        issues: <WritingIssue>[
          WritingIssue(
            original: 'I runed',
            suggestion: 'I ran',
            rule: WritingRule.tenseChoice,
            key: 'grammar-tense-choice',
            reason: '不规则动词',
          ),
          WritingIssue(
            original: 'very good',
            suggestion: 'excellent',
            rule: WritingRule.styleImprovement,
            key: 'naturalness-very-good',
            severity: 'improvement',
          ),
        ],
        recommendations: <WritingRecommendation>[
          WritingRecommendation(
            kind: WritingRecommendationKind.chunk,
            point: 'come to an end',
            zh: '结束',
            why: '你这次把 an end 当成了独立词块',
            example: 'The meeting came to an end.',
            priority: 1,
            from: WritingRecommendationFrom.error,
            issueKey: 'chunk-come-to-an-end',
          ),
        ],
        polished: 'I ran.',
        summary: '时态要小心。',
      );

      final back = writingFeedbackFromJson(feedback.toJson());

      expect(back.version, 2);
      expect(back.scores, hasLength(2));
      expect(back.scores.first.comment, '时态错一处');
      expect(back.scores.last.comment, isNull);
      expect(back.total, 82);
      expect(back.max, 100);
      expect(back.issues, hasLength(2));
      expect(back.issues.first.rule, WritingRule.tenseChoice);
      expect(back.issues.first.reason, '不规则动词');
      expect(back.issues.last.isImprovement, isTrue);
      expect(back.recommendations, hasLength(1));
      expect(back.recommendations.first.kindLabel, '词块');
      expect(back.recommendations.first.priority, 1);
      expect(back.recommendations.first.issueKey, 'chunk-come-to-an-end');
      expect(back.polished, 'I ran.');
      expect(back.summary, '时态要小心。');
    });

    test('不校验 original 是否在作答里（读回记录不二次丢数据）', () {
      final back = writingFeedbackFromJson(<String, Object?>{
        'version': 2,
        'issues': <Object?>[
          <String, Object?>{
            'original': '这句根本不在原文里',
            'suggestion': 'whatever',
            'rule': 'tense-choice',
            'key': 'grammar-tense-choice',
          },
        ],
      });
      expect(back.issues, hasLength(1));
    });

    test('rule 认不出 / key 空 / suggestion 空 → 只丢那一条', () {
      final back = writingFeedbackFromJson(<String, Object?>{
        'version': 2,
        'total': 60,
        'max': 100,
        'issues': <Object?>[
          <String, Object?>{
            'suggestion': 'ok',
            'rule': 'no-such-rule',
            'key': 'grammar-x',
          },
          <String, Object?>{
            'suggestion': 'ok',
            'rule': 'tense-choice',
            'key': '',
          },
          <String, Object?>{
            'suggestion': '',
            'rule': 'tense-choice',
            'key': 'grammar-tense-choice',
          },
          <String, Object?>{
            'suggestion': 'I ran',
            'rule': 'tense-choice',
            'key': 'grammar-tense-choice',
          },
        ],
      });
      expect(back.issues, hasLength(1));
      expect(back.total, 60);
    });

    test('建议缺 kind / point / why 的跳过；priority 归到 1/2/3', () {
      final back = writingFeedbackFromJson(<String, Object?>{
        'version': 2,
        'recommendations': <Object?>[
          <String, Object?>{'point': 'x', 'why': 'y'},
          <String, Object?>{'kind': 'chunk', 'why': 'y'},
          <String, Object?>{'kind': 'chunk', 'point': 'x'},
          <String, Object?>{'kind': 'chunk', 'point': 'a', 'why': 'b', 'priority': 9},
        ],
      });
      expect(back.recommendations, hasLength(1));
      expect(back.recommendations.first.priority, 2);
    });

    test('缺 version 当旧记录（1），空对象给空批改', () {
      expect(writingFeedbackFromJson(null).version, 2);
      final old = writingFeedbackFromJson(<String, Object?>{'total': 10});
      expect(old.version, 1);
      expect(old.issues, isEmpty);
      expect(old.scores, isEmpty);
    });
  });
}
