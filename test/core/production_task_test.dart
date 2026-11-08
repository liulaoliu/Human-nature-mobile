/// `core/production_task.dart` 的测试：评分任务、批改提示词、跳过稿、命中读取。
///
/// 用例对齐 Web 版 `src/core/productionPrompts.test.ts`（89 行）的
/// `makeProductionTask` / `skippedProductionFeedback` / `buildProductionFeedbackPrompt` 部分，
/// 另补 `isProductionTask` / `productionHits` / `countProductionHits` 的坏形状守卫。
library;

import 'package:dlaoshi_app/core/production.dart';
import 'package:dlaoshi_app/core/production_task.dart';
import 'package:dlaoshi_app/core/writing.dart';
import 'package:flutter_test/flutter_test.dart';

const ProductionTarget _run = ProductionTarget(
  id: 'v1|self|word',
  itemId: 'v1',
  kind: ProductionTargetKind.word,
  text: 'run',
  meaning: '跑',
);

ProductionTarget _phrase() => const ProductionTarget(
      id: 'p1|self|phrase',
      itemId: 'p1',
      kind: ProductionTargetKind.phrase,
      text: 'run out',
      meaning: '用完',
    );

ProductionPrompt _prompt({
  String id = 'p1',
  String zh = 'Hello.',
  String goal = '',
  List<ProductionTarget> targets = const <ProductionTarget>[],
  String? reference,
  ProductionAnswerLang? answerLang,
}) =>
    ProductionPrompt(
      id: id,
      zh: zh,
      goal: goal,
      targets: targets,
      reference: reference,
      answerLang: answerLang,
    );

void main() {
  group('makeProductionTask：目标块题', () {
    test('带目标块时 rubric 是「意思到位 / 目标词块 / 语法与自然度」', () {
      final task = makeProductionTask(
        _prompt(goal: '汇报进度', targets: <ProductionTarget>[_run, _phrase()]),
        '出差',
      );
      expect(task.kind, 'production');
      expect(task.mode, ProductionMode.skim);
      expect(task.topic, '出差');
      expect(task.goal, '汇报进度');
      expect(task.promptId, 'p1');
      expect(task.task, 'Hello.');
      expect(task.model, '（自由表达，没有唯一范句）');
      expect(
        task.rubric.map((r) => '${r.dimension}:${r.weight}').toList(),
        <String>['意思到位:40', '目标词块:30', '语法与自然度:30'],
      );
      expect(task.mustUse, <String>['run', 'run out']);
      expect(task.focus, 'run / run out');
      expect(task.answerLang, isNull);
      expect(task.sessionId, isNull);
      expect(task.targets, hasLength(2));
    });

    test('没有目标块时 rubric 换成「意思到位 / 语法与自然度 / 表达地道」', () {
      final task = makeProductionTask(_prompt(), '出差');
      expect(
        task.rubric.map((r) => '${r.dimension}:${r.weight}').toList(),
        <String>['意思到位:40', '语法与自然度:35', '表达地道:25'],
      );
      expect(task.mustUse, isEmpty);
      expect(task.focus, '主题翻译');
    });

    test('全脂没目标块时 focus 写「随机主题」，并带上 sessionId', () {
      final task = makeProductionTask(
        _prompt(),
        '随机自选',
        mode: ProductionMode.full,
        sessionId: 's1',
      );
      expect(task.focus, '随机主题');
      expect(task.sessionId, 's1');
      expect(task.mode, ProductionMode.full);
    });
  });

  group('makeProductionTask：风味酸奶', () {
    test('英译中任务用中文 rubric，answerLang 记 zh', () {
      final task = makeProductionTask(
        _prompt(
          zh: 'Hello.',
          goal: '英译中',
          reference: '你好。',
          answerLang: ProductionAnswerLang.zh,
        ),
        '风味酸奶',
        mode: ProductionMode.yogurt,
        sessionId: 's1',
      );
      expect(task.answerLang, ProductionAnswerLang.zh);
      expect(task.sessionId, 's1');
      expect(task.rubric.first.dimension, '英文原意');
      expect(
        task.rubric.map((r) => '${r.dimension}:${r.weight}').toList(),
        <String>['英文原意:40', '中文自然度:30', '参考译文差距:30'],
      );
      expect(task.focus, '英译中');
      expect(task.reference, '你好。');
      // 参考译文当范句交给 AI
      expect(task.model, '你好。');
    });

    test('中译英方向 rubric 是「原文意思 / 英文自然度 / 参考译文差距」', () {
      final task = makeProductionTask(
        _prompt(zh: '你好。', reference: 'Hello.'),
        '风味酸奶',
        mode: ProductionMode.yogurt,
      );
      expect(task.answerLang, ProductionAnswerLang.en);
      expect(
        task.rubric.map((r) => r.dimension).toList(),
        <String>['原文意思', '英文自然度', '参考译文差距'],
      );
      expect(task.focus, '逐句翻译');
      expect(task.model, 'Hello.');
    });

    test('没粘参考译文时给占位说明，reference 留空', () {
      final task = makeProductionTask(
        _prompt(zh: '你好。'),
        '风味酸奶',
        mode: ProductionMode.yogurt,
      );
      expect(task.model, '（没有粘贴参考译文）');
      expect(task.reference, isNull);
    });
  });

  group('buildProductionFeedbackPrompt', () {
    test('英译中时前置「按中文批改」的说明', () {
      final task = makeProductionTask(
        _prompt(reference: '你好。', answerLang: ProductionAnswerLang.zh),
        '风味酸奶',
        mode: ProductionMode.yogurt,
      );
      final prompt = buildProductionFeedbackPrompt(task, '你好');
      expect(prompt, contains('英译中'));
      expect(prompt, contains('不要按英文语法规则扣分'));
      // 仍然带原来的批改契约
      expect(prompt, contains('version'));
    });

    test('中译英 / 目标块题不加中文说明', () {
      final yogurt = makeProductionTask(
        _prompt(reference: 'Hello.'),
        '风味酸奶',
        mode: ProductionMode.yogurt,
      );
      expect(buildProductionFeedbackPrompt(yogurt, 'Hello'), isNot(contains('不要按英文语法规则扣分')));

      final normal = makeProductionTask(_prompt(targets: <ProductionTarget>[_run]), '出差');
      expect(buildProductionFeedbackPrompt(normal, 'I ran.'), isNot(contains('不要按英文语法规则扣分')));
    });

    test('第二稿带上上一轮 issues，要求逐条复查', () {
      final task = makeProductionTask(_prompt(targets: <ProductionTarget>[_run]), '出差');
      final prompt = buildProductionFeedbackPrompt(
        task,
        'I ran.',
        previousIssues: const <PreviousIssue>[
          PreviousIssue(
            original: 'I runed.',
            suggestion: 'I ran.',
            rule: WritingRule.tenseChoice,
            key: 'grammar-tense-choice',
          ),
        ],
      );
      expect(prompt, contains('I runed.'));
    });
  });

  group('parseProductionFeedback', () {
    test('合法批改能解析，原文对得上的 issue 全部留下', () {
      const raw = '''
```json
{"version":2,"scores":[{"dimension":"意思到位","score":30,"max":40}],
 "issues":[{"original":"I ran fastly.","suggestion":"I ran fast.","rule":"grammar-other","key":"grammar-other"}],
 "polished":"I ran fast.","summary":"还行"}
```''';
      final parsed = parseProductionFeedback(raw, 'I ran fastly.');
      expect(parsed, isNotNull);
      expect(parsed!.feedback.version, 2);
      expect(parsed.feedback.issues, hasLength(1));
      expect(parsed.feedback.issues.first.suggestion, 'I ran fast.');
      expect(parsed.feedback.total, 30);
      expect(parsed.feedback.max, 40);
      expect(parsed.dropped.isEmpty, isTrue);
    });

    test('编造的 original 会被丢弃并计数（只丢那一条）', () {
      const raw =
          '{"version":2,"scores":[{"dimension":"意思到位","score":30,"max":40}],'
          '"issues":['
          '{"original":"I went home.","suggestion":"I go home.","rule":"tense-choice","key":"grammar-tense-choice"},'
          '{"original":"I ran fastly.","suggestion":"I ran fast.","rule":"grammar-other","key":"grammar-other"}'
          ']}';
      final parsed = parseProductionFeedback(raw, 'I ran fastly.');
      expect(parsed, isNotNull);
      expect(parsed!.feedback.issues, hasLength(1));
      expect(parsed.feedback.issues.first.original, 'I ran fastly.');
      expect(parsed.dropped.issues, 1);
      expect(parsed.dropped.reasons.join(), contains('original 不在学生原文里'));
    });

    test('一条都没剩下时返回 null（和仿写批改同一口径）', () {
      const raw =
          '{"version":2,"issues":[{"original":"I went home.","suggestion":"I go home.","rule":"tense-choice","key":"grammar-tense-choice"}]}';
      expect(parseProductionFeedback(raw, 'I ran fast.'), isNull);
    });

    test('非法 JSON 返回 null', () {
      expect(parseProductionFeedback('不是 JSON', 'x'), isNull);
    });
  });

  group('skippedProductionFeedback', () {
    test('空分数 + 明确摘要，不伪造批改', () {
      final fb = skippedProductionFeedback();
      expect(fb.version, 2);
      expect(fb.total, 0);
      expect(fb.max, 0);
      expect(fb.issues, isEmpty);
      expect(fb.recommendations, isEmpty);
      expect(fb.summary, '跳过（未提交）');
      expect(skippedProductionSummary, '跳过（未提交）');
    });
  });

  group('isProductionTask / productionHits', () {
    Map<String, Object?> taskJson({Object? hits, Object? kind = 'production'}) =>
        <String, Object?>{
          'kind': kind,
          'topic': '出差',
          'promptId': 'p1',
          'targets': <Object?>[],
          'hits': ?hits,
        };

    test('认得出 production 任务，坏形状返回 false', () {
      expect(isProductionTask(taskJson()), isTrue);
      expect(isProductionTask(taskJson(kind: 'writing')), isFalse);
      expect(isProductionTask(<String, Object?>{'kind': 'production'}), isFalse);
      expect(isProductionTask(null), isFalse);
      expect(isProductionTask(<Object?>[]), isFalse);
    });

    test('读命中情况：坏元素跳过，缺 kind 当单词', () {
      final hits = productionHits(taskJson(hits: <Object?>[
        <String, Object?>{'id': 'a', 'kind': 'phrase', 'text': 'run out', 'meaning': '用完', 'used': true},
        <String, Object?>{'id': 'b', 'text': 'run', 'meaning': '跑', 'used': false},
        <String, Object?>{'id': 'c', 'text': 'run', 'used': 'yes'},
        'not a map',
      ]));
      expect(hits, hasLength(2));
      expect(hits.first.kind, ProductionTargetKind.phrase);
      expect(hits.first.used, isTrue);
      expect(hits.last.kind, ProductionTargetKind.word);
      expect(hits.last.meaning, '跑');
      expect(countProductionHits(hits), 1);
    });

    test('不是 production 任务 / 没有 hits 都返回空表', () {
      expect(productionHits(taskJson(kind: 'writing', hits: <Object?>[])), isEmpty);
      expect(productionHits(taskJson()), isEmpty);
      expect(productionHits(null), isEmpty);
      expect(countProductionHits(const <ProductionTargetHit>[]), 0);
    });
  });

  group('ProductionTask.toJson', () {
    test('带上产出训练那几列，能被 isProductionTask 认出来', () {
      final task = makeProductionTask(
        _prompt(targets: <ProductionTarget>[_run]),
        '出差',
        sessionId: 's1',
      );
      final json = task.toJson();
      expect(isProductionTask(json), isTrue);
      expect(json['kind'], 'production');
      expect(json['mode'], 'skim');
      expect(json['topic'], '出差');
      expect(json['promptId'], 'p1');
      expect(json['sessionId'], 's1');
      expect((json['targets']! as List<Object?>), hasLength(1));
      expect(json['answerLang'], isNull);
    });

    test('风味酸奶写 answerLang；跳过的稿写 skipped: true', () {
      final yogurt = makeProductionTask(
        _prompt(reference: '你好。', answerLang: ProductionAnswerLang.zh),
        '风味酸奶',
        mode: ProductionMode.yogurt,
      );
      expect(yogurt.toJson()['answerLang'], 'zh');

      final skipped = yogurt.copyWith(skipped: () => true);
      expect(skipped.toJson()['skipped'], isTrue);
      expect(skipped.skipped, isTrue);
    });

    test('copyWith 能清掉可空字段', () {
      final task = makeProductionTask(
        _prompt(reference: '你好。', answerLang: ProductionAnswerLang.zh),
        '风味酸奶',
        mode: ProductionMode.yogurt,
        sessionId: 's1',
      );
      final cleared = task.copyWith(
        answerLang: () => null,
        sessionId: () => null,
        reference: () => null,
      );
      expect(cleared.answerLang, isNull);
      expect(cleared.sessionId, isNull);
      expect(cleared.reference, isNull);
      expect(cleared.promptId, 'p1');
    });
  });
}
