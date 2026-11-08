/// `core/production_prompts.dart` 的测试：出题提示词、解析、拆句配对、硬校验。
///
/// 用例对齐 Web 版 `src/core/productionPrompts.test.ts`（89 行）与
/// `productionYogurt.test.ts`（92 行），并补齐提示词 / 解析的边界。
library;

import 'dart:convert';

import 'package:dlaoshi_app/core/production.dart';
import 'package:dlaoshi_app/core/production_prompts.dart';
import 'package:flutter_test/flutter_test.dart';

ProductionTarget _target({
  String id = 'v1|self|word',
  String itemId = 'v1',
  ProductionTargetKind kind = ProductionTargetKind.word,
  String text = 'run',
  String meaning = '跑',
}) =>
    ProductionTarget(
      id: id,
      itemId: itemId,
      kind: kind,
      text: text,
      meaning: meaning,
    );

void main() {
  group('buildProductionPackPrompt：目标块题', () {
    test('全脂：随机主题、带候选清单、不出现参考文章', () {
      final pack = buildProductionPackPrompt(BuildProductionPackInput(
        mode: ProductionMode.full,
        topic: '',
        angle: ProductionAngle.daily,
        tone: ProductionTone.neutral,
        level: ProductionLevel.b2,
        articleTitle: 'A',
        targets: <ProductionTarget>[_target()],
        promptCount: 1,
        targetsPerPrompt: 1,
      ));
      expect(pack, contains('随机自选'));
      expect(pack, contains('v1|self|word'));
      expect(pack, contains('| word | run | 跑'));
      expect(pack, isNot(contains('参考文章')));
      expect(pack, contains('出 1 道题；每道题必须分配 1 个目标块'));
      expect(pack, contains('不要围绕一个主题'));
      expect(pack, contains('B2 中阶'));
    });

    test('脱脂奶：主题与参考文章都写进去', () {
      final pack = buildProductionPackPrompt(BuildProductionPackInput(
        mode: ProductionMode.skim,
        topic: '远程办公',
        angle: ProductionAngle.work,
        tone: ProductionTone.formal,
        level: ProductionLevel.c1,
        articleTitle: 'The Future of Work',
        targets: <ProductionTarget>[_target()],
        promptCount: 3,
        targetsPerPrompt: 2,
      ));
      expect(pack, contains('主题：远程办公'));
      expect(pack, contains('参考文章：The Future of Work'));
      expect(pack, contains('所有题都围绕上述主题'));
      expect(pack, contains('C1 进阶'));
      expect(pack, isNot(contains('随机自选')));
    });

    test('目标块没释义时不留下空的分隔符', () {
      final pack = buildProductionPackPrompt(BuildProductionPackInput(
        mode: ProductionMode.full,
        topic: '',
        angle: ProductionAngle.daily,
        tone: ProductionTone.neutral,
        level: ProductionLevel.b1,
        targets: <ProductionTarget>[_target(meaning: '')],
        promptCount: 1,
        targetsPerPrompt: 1,
      ));
      expect(pack, contains('- v1|self|word | word | run\n'));
    });
  });

  group('buildTopicPackPrompt：纯主题题', () {
    test('随机主题 + 难度', () {
      final prompt = buildTopicPackPrompt(const BuildTopicPackInput(
        topic: '',
        angle: ProductionAngle.daily,
        tone: ProductionTone.neutral,
        level: ProductionLevel.b1,
        promptCount: 2,
        randomTopic: true,
      ));
      expect(prompt, contains('主题：随机自选'));
      expect(prompt, contains('B1 基础'));
      expect(prompt, contains('出 2 道题'));
      expect(prompt, isNot(contains('参考文章')));
    });

    test('给了主题就写主题与参考文章', () {
      final prompt = buildTopicPackPrompt(const BuildTopicPackInput(
        topic: '读书方法',
        angle: ProductionAngle.opinion,
        tone: ProductionTone.casual,
        level: ProductionLevel.b2,
        articleTitle: 'How to Read',
        promptCount: 3,
      ));
      expect(prompt, contains('主题：读书方法'));
      expect(prompt, contains('参考文章：How to Read'));
      expect(prompt, isNot(contains('随机自选')));
    });
  });

  group('parseProductionPack：只认候选清单里的 id', () {
    final allowed = <ProductionTarget>[
      _target(),
      _target(
        id: 'p1',
        kind: ProductionTargetKind.phrase,
        text: 'run out',
      ),
    ];

    test('坏 id 被丢掉，剩下的照收', () {
      final parsed = parseProductionPack(
        jsonEncode(<String, Object?>{
          'prompts': <Object?>[
            <String, Object?>{
              'zh': '说明进度',
              'goal': '汇报',
              'targetIds': <String>['v1|self|word', 'bad'],
            },
          ],
        }),
        allowed,
      );
      expect(parsed, hasLength(1));
      expect(parsed![0].targets, hasLength(1));
      expect(parsed[0].id, 'prod-1');
      expect(parsed[0].goal, '汇报');
      expect(parsed[0].targets[0].text, 'run');
    });

    test('同一 id 写两遍只算一个；没有目标块的题丢掉', () {
      final parsed = parseProductionPack(
        jsonEncode(<String, Object?>{
          'prompts': <Object?>[
            <String, Object?>{
              'zh': '一',
              'targetIds': <String>['v1|self|word', 'v1|self|word'],
            },
            <String, Object?>{'zh': '二', 'targetIds': <String>[]},
            <String, Object?>{'zh': '三', 'targetIds': <String>['bad']},
          ],
        }),
        allowed,
      );
      expect(parsed, hasLength(1));
      expect(parsed![0].targets, hasLength(1));
      expect(parsed[0].id, 'prod-1');
    });

    test('中文为空的题丢掉', () {
      final parsed = parseProductionPack(
        jsonEncode(<String, Object?>{
          'prompts': <Object?>[
            <String, Object?>{'zh': '   ', 'targetIds': <String>['v1|self|word']},
            <String, Object?>{
              'zh': '有效',
              'targetIds': <String>['p1'],
            },
          ],
        }),
        allowed,
      );
      expect(parsed, hasLength(1));
      expect(parsed![0].zh, '有效');
      expect(parsed[0].id, 'prod-2');
    });

    test('model 有内容才带上', () {
      final withModel = parseProductionPack(
        jsonEncode(<String, Object?>{
          'prompts': <Object?>[
            <String, Object?>{
              'zh': 'x',
              'targetIds': <String>['v1|self|word'],
              'model': '  I run daily.  ',
            },
          ],
        }),
        allowed,
      );
      expect(withModel![0].model, 'I run daily.');

      final without = parseProductionPack(
        jsonEncode(<String, Object?>{
          'prompts': <Object?>[
            <String, Object?>{
              'zh': 'x',
              'targetIds': <String>['v1|self|word'],
              'model': '   ',
            },
          ],
        }),
        allowed,
      );
      expect(without![0].model, isNull);
    });

    test('带 Markdown 围栏也认', () {
      final parsed = parseProductionPack(
        '```json\n'
        '{"prompts":[{"zh":"x","targetIds":["v1|self|word"]}]}\n'
        '```',
        allowed,
      );
      expect(parsed, hasLength(1));
    });

    test('坏 JSON / 不是对象 / 没有 prompts 一律返回 null', () {
      expect(parseProductionPack('not json', allowed), isNull);
      expect(parseProductionPack('[]', allowed), isNull);
      expect(parseProductionPack('{"a":1}', allowed), isNull);
      expect(parseProductionPack('{"prompts":{}}', allowed), isNull);
      expect(
        parseProductionPack('{"prompts":[]}', allowed),
        isNull,
      );
    });

    test('maxPrompts 截断', () {
      final raw = jsonEncode(<String, Object?>{
        'prompts': <Object?>[
          for (var i = 0; i < 5; i++)
            <String, Object?>{
              'zh': '题 $i',
              'targetIds': <String>['v1|self|word'],
            },
        ],
      });
      expect(parseProductionPack(raw, allowed, maxPrompts: 2), hasLength(2));
    });
  });

  group('parseTopicPack', () {
    test('不要求 targetIds', () {
      final parsed = parseTopicPack(
        jsonEncode(<String, Object?>{
          'prompts': <Object?>[
            <String, Object?>{'zh': '中文一', 'goal': '目标一'},
            <String, Object?>{'zh': '中文二'},
            <String, Object?>{'zh': '  '},
          ],
        }),
      );
      expect(parsed, hasLength(2));
      expect(parsed![0].id, 'topic-1');
      expect(parsed[0].targets, isEmpty);
      expect(parsed[0].goal, '目标一');
      expect(parsed[1].id, 'topic-2');
    });

    test('全空返回 null', () {
      expect(parseTopicPack('{"prompts":[]}'), isNull);
      expect(parseTopicPack('{"prompts":[{"zh":""}]}'), isNull);
      expect(parseTopicPack('nope'), isNull);
    });
  });

  group('splitProductionSentences：按句 / 按行', () {
    test('按句号问号分号切，保留标点', () {
      expect(
        splitProductionSentences('我去了。你来了！他呢？'),
        <String>['我去了。', '你来了！', '他呢？'],
      );
    });

    test('英文句号也切；一行多句能拆开', () {
      expect(
        splitProductionSentences('Hello there. How are you?'),
        <String>['Hello there.', 'How are you?'],
      );
    });

    test('按行模式不切句', () {
      expect(
        splitProductionSentences('第一行。还有一句。\n第二行', mode: YogurtSplitMode.line),
        <String>['第一行。还有一句。', '第二行'],
      );
    });

    test('空文本 / 纯空白返回空', () {
      expect(splitProductionSentences(''), isEmpty);
      expect(splitProductionSentences('  \n\n '), isEmpty);
    });

    test('CRLF 也能处理', () {
      expect(
        splitProductionSentences('一\r\n二', mode: YogurtSplitMode.line),
        <String>['一', '二'],
      );
    });
  });

  group('pairYogurtTexts：拆句配对', () {
    test('句数一致：一一配对，没有警告', () {
      final out = pairYogurtTexts('我去了。你来了。', 'I went. You came.');
      expect(out!.pairs, hasLength(2));
      expect(out.pairs[0].source, '我去了。');
      expect(out.pairs[0].reference, 'I went.');
      expect(out.warning, isEmpty);
      expect(out.sourceCount, 2);
      expect(out.referenceCount, 2);
    });

    test('英文多一句：末尾并进最后一对，给警告', () {
      final out = pairYogurtTexts('我去了。', 'I went. It was fun.');
      expect(out!.pairs, hasLength(1));
      expect(out.pairs[0].reference, 'I went. It was fun.');
      expect(out.warning, contains('1 句 / 2 句'));
      expect(out.warning, contains('并入最后一对'));
    });

    test('中文多一句同理', () {
      final out = pairYogurtTexts('我去了。你也去了。', 'I went.');
      expect(out!.pairs, hasLength(1));
      expect(out.pairs[0].source, '我去了。 你也去了。');
      expect(out.warning, contains('2 句 / 1 句'));
    });

    test('一边为空返回 null', () {
      expect(pairYogurtTexts('', 'I went.'), isNull);
      expect(pairYogurtTexts('我去了。', ''), isNull);
    });

    test('按行模式配对', () {
      final out = pairYogurtTexts(
        '我去了。\n你来了。',
        'I went.\nYou came.',
        mode: YogurtSplitMode.line,
      );
      expect(out!.pairs, hasLength(2));
      expect(out.pairs[1].source, '你来了。');
    });
  });

  group('buildYogurtPromptsFromPairs：编译成题目', () {
    final pairs = <YogurtPair>[
      const YogurtPair(source: '我去了。', reference: 'I went.'),
      const YogurtPair(source: '你来了。', reference: 'You came.'),
    ];

    test('中译英：answerLang=en，goal 是逐句中译英', () {
      final out = buildYogurtPromptsFromPairs(pairs)!;
      expect(out.prompts, hasLength(2));
      expect(out.prompts[0].id, 'yogurt-1');
      expect(out.prompts[0].zh, '我去了。');
      expect(out.prompts[0].reference, 'I went.');
      expect(out.prompts[0].answerLang, ProductionAnswerLang.en);
      expect(out.prompts[0].goal, '逐句中译英');
      expect(out.prompts[0].targets, isEmpty);
    });

    test('英译中：answerLang=zh，goal 是逐句英译中', () {
      final out = buildYogurtPromptsFromPairs(
        pairs,
        direction: ProductionDirection.enZh,
      )!;
      expect(out.prompts[0].answerLang, ProductionAnswerLang.zh);
      expect(out.prompts[0].goal, '逐句英译中');
    });

    test('整段连写：追加 yogurt-paragraph，原文用空格拼', () {
      final out = buildYogurtPromptsFromPairs(pairs, paragraph: true)!;
      expect(out.prompts, hasLength(3));
      final para = out.prompts.last;
      expect(para.id, 'yogurt-paragraph');
      expect(para.zh, '我去了。 你来了。');
      expect(para.reference, 'I went. You came.');
      expect(para.goal, '整段中译英');
    });

    test('只有一句时整段题不追加', () {
      final out = buildYogurtPromptsFromPairs(
        <YogurtPair>[pairs[0]],
        paragraph: true,
      )!;
      expect(out.prompts, hasLength(1));
    });

    test('全空对子返回 null', () {
      expect(
        buildYogurtPromptsFromPairs(<YogurtPair>[const YogurtPair()]),
        isNull,
      );
      expect(buildYogurtPromptsFromPairs(const <YogurtPair>[]), isNull);
    });

    test('只有一边有内容也保留（另一边空着）', () {
      final out = buildYogurtPromptsFromPairs(
        <YogurtPair>[const YogurtPair(source: '只有中文')],
      )!;
      expect(out.prompts[0].zh, '只有中文');
      expect(out.prompts[0].reference, isNull);
    });

    test('警告原样带出来', () {
      final out = buildYogurtPromptsFromPairs(pairs, warning: '句数不一致')!;
      expect(out.warning, '句数不一致');
      expect(out.sourceCount, 2);
    });
  });

  group('buildYogurtPrompts：一步到位', () {
    test('拆句 + 配对 + 编译', () {
      final out = buildYogurtPrompts(
        '我去了。你来了。',
        'I went.',
        paragraph: true,
      )!;
      // 两句中文 / 一句英文 → 只配出一对（末尾并入），整段题不再追加。
      expect(out.prompts, hasLength(1));
      expect(out.prompts[0].zh, '我去了。 你来了。');
      expect(out.prompts[0].reference, 'I went.');
      expect(out.warning, contains('2 句 / 1 句'));
    });

    test('一边为空返回 null', () {
      expect(buildYogurtPrompts('', 'I went.'), isNull);
    });
  });

  group('validateProductionPack / validateTopicPack：硬校验', () {
    final target = _target();

    ProductionPrompt prompt({
      String id = 'prod-1',
      List<ProductionTarget>? targets,
      String? model,
    }) =>
        ProductionPrompt(
          id: id,
          zh: '中文',
          goal: '目标',
          targets: targets ?? <ProductionTarget>[target],
          model: model,
        );

    test('数量对不上给中文原因', () {
      final q = validateProductionPack(<ProductionPrompt>[prompt()], 2, 1);
      expect(q.ok, isFalse);
      expect(q.reason, '应出 2 道题，实际 1 道');
    });

    test('每题目标数对不上给中文原因', () {
      final q = validateProductionPack(<ProductionPrompt>[prompt()], 1, 2);
      expect(q.ok, isFalse);
      expect(q.reason, '第 1 题应带 2 个目标块，实际 1 个');
    });

    test('目标块重复给中文原因', () {
      final q = validateProductionPack(
        <ProductionPrompt>[prompt(), prompt(id: 'prod-2')],
        2,
        1,
      );
      expect(q.ok, isFalse);
      expect(q.reason, contains('被重复使用'));
      expect(q.reason, contains('run'));
    });

    test('requireModel 时缺参考句报错', () {
      final q = validateProductionPack(
        <ProductionPrompt>[prompt()],
        1,
        1,
        requireModel: true,
      );
      expect(q.ok, isFalse);
      expect(q.reason, '第 1 题缺少英文参考句 model');

      final ok = validateProductionPack(
        <ProductionPrompt>[prompt(model: 'I run.')],
        1,
        1,
        requireModel: true,
      );
      expect(ok.ok, isTrue);
      expect(ok.reason, isEmpty);
    });

    test('全对时 ok 且 reason 为空', () {
      final q = validateProductionPack(<ProductionPrompt>[prompt()], 1, 1);
      expect(q.ok, isTrue);
      expect(q.reason, isEmpty);
    });

    test('主题包只查数量', () {
      final p = ProductionPrompt(
        id: 'topic-1',
        zh: '中文',
        goal: '',
        targets: const <ProductionTarget>[],
      );
      expect(validateTopicPack(<ProductionPrompt>[p], 1).ok, isTrue);
      expect(validateTopicPack(<ProductionPrompt>[p], 2).ok, isFalse);
      expect(validateTopicPack(<ProductionPrompt>[p], 2).reason, '应出 2 道题，实际 1 道');
    });
  });

  group('YogurtPair 等值', () {
    test('内容相同就相等', () {
      expect(
        const YogurtPair(source: 'a', reference: 'b'),
        const YogurtPair(source: 'a', reference: 'b'),
      );
      expect(
        const YogurtPair(source: 'a'),
        isNot(const YogurtPair(source: 'b')),
      );
    });

    test('copyWith 只改指定字段', () {
      const p = YogurtPair(source: 'a', reference: 'b');
      expect(p.copyWith(source: 'c'), const YogurtPair(source: 'c', reference: 'b'));
    });
  });
}
