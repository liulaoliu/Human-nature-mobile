/// `core/production_yogurt.dart` 的测试：反推断句、改断句后保住进度、比对键。
///
/// 用例对齐 Web 版 `src/core/productionYogurt.test.ts`（92 行）。
library;

import 'package:dlaoshi_app/core/production.dart';
import 'package:dlaoshi_app/core/production_prompts.dart';
import 'package:dlaoshi_app/core/production_yogurt.dart';
import 'package:flutter_test/flutter_test.dart';

typedef Rows = List<(String, String)>;

List<YogurtPair> _toPairs(Rows rows) => <YogurtPair>[
      for (final row in rows) YogurtPair(source: row.$1, reference: row.$2),
    ];

List<ProductionPrompt> _compile(Rows rows, {bool paragraph = false}) {
  final result = remapYogurtPrompts(
    const <ProductionPrompt>[],
    0,
    _toPairs(rows),
    paragraph: paragraph,
  );
  if (result == null) throw StateError('应当能编译出 prompts');
  return result.prompts;
}

const Rows base = <(String, String)>[
  ('今天下雨了。', 'It rained today.'),
  ('我没带伞。', 'I forgot my umbrella.'),
  ('只好打车。', 'So I took a taxi.'),
];

void main() {
  group('yogurtPairsOf：从会话 prompts 反推断句', () {
    test('逐句那一题变成对子，整段连写不算', () {
      final prompts = _compile(base, paragraph: true);
      expect(prompts, hasLength(4));
      expect(yogurtPairsOf(prompts), _toPairs(base));
      expect(isYogurtPairPrompt(prompts[0]), isTrue);
      expect(prompts[3].id, yogurtParagraphId);
      expect(isYogurtPairPrompt(prompts[3]), isFalse);
    });

    test('没有逐句题时返回空', () {
      expect(yogurtPairsOf(const <ProductionPrompt>[]), isEmpty);
      final onlyParagraph = <ProductionPrompt>[
        const ProductionPrompt(
          id: yogurtParagraphId,
          zh: '整段',
          goal: '整段中译英',
          targets: <ProductionTarget>[],
        ),
      ];
      expect(yogurtPairsOf(onlyParagraph), isEmpty);
    });
  });

  group('remapYogurtPrompts：中途改断句时保住进度', () {
    test('对子没变就停在原题', () {
      final prompts = _compile(base);
      final result = remapYogurtPrompts(prompts, 2, _toPairs(base))!;
      expect(result.index, 2);
      expect(
        result.prompts.map((p) => p.id).toList(),
        prompts.map((p) => p.id).toList(),
      );
    });

    test('删掉当前题之前的一对：题号跟着同一句前移', () {
      final prompts = _compile(base);
      final result = remapYogurtPrompts(
        prompts,
        2,
        _toPairs(base.sublist(1)),
      )!;
      expect(result.index, 1);
      expect(result.prompts[1].zh, '只好打车。');
    });

    test('当前这句被合并进上一对：退到原下标，不越界', () {
      final prompts = _compile(base);
      final merged = <(String, String)>[
        ('今天下雨了。', 'It rained today.'),
        ('我没带伞。 只好打车。', 'I forgot my umbrella. So I took a taxi.'),
      ];
      final result = remapYogurtPrompts(prompts, 2, _toPairs(merged))!;
      expect(result.index, 1);
      expect(result.prompts, hasLength(2));
    });

    test('原来停在整段连写：改完断句仍停在整段', () {
      final prompts = _compile(base, paragraph: true);
      final result = remapYogurtPrompts(
        prompts,
        3,
        _toPairs(base.sublist(0, 2)),
        paragraph: true,
      )!;
      expect(result.index, 2);
      expect(result.prompts[2].id, yogurtParagraphId);
    });

    test('一对有内容的都没有：返回 null，界面不该应用', () {
      expect(
        remapYogurtPrompts(
          _compile(base),
          0,
          <YogurtPair>[const YogurtPair()],
        ),
        isNull,
      );
      expect(
        remapYogurtPrompts(_compile(base), 0, const <YogurtPair>[]),
        isNull,
      );
    });

    test('句数对不上时把 warning 带回来', () {
      final built = remapYogurtPrompts(
        const <ProductionPrompt>[],
        0,
        _toPairs(base),
        warning: '3 句 / 2 句',
      )!;
      expect(built.warning, '3 句 / 2 句');
    });

    test('题号越界时夹到合法范围', () {
      final prompts = _compile(base);
      expect(
        remapYogurtPrompts(prompts, 99, _toPairs(base))!.index,
        2,
      );
      expect(
        remapYogurtPrompts(prompts, -5, _toPairs(base))!.index,
        0,
      );
    });

    test('英译中方向原样带过去', () {
      final result = remapYogurtPrompts(
        const <ProductionPrompt>[],
        0,
        _toPairs(base),
        direction: ProductionDirection.enZh,
      )!;
      expect(result.prompts[0].answerLang, ProductionAnswerLang.zh);
      expect(result.prompts[0].goal, '逐句英译中');
    });
  });

  group('yogurtTextKey：比对用的键', () {
    test('忽略首尾和连续空白，改动字词仍算不同', () {
      expect(yogurtTextKey('  今天 下雨了。 '), '今天 下雨了。');
      expect(yogurtTextKey('今天下雨了。'), isNot(yogurtTextKey('昨天 下雨了。')));
    });

    test('标点不同就是不同一句', () {
      expect(yogurtTextKey('你好'), isNot(yogurtTextKey('你好。')));
    });
  });
}
