/// `core/production_settings.dart` 的测试：设置守卫、序列化往返、枚举标签。
library;

import 'package:dlaoshi_app/core/production.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalizeProductionSettings：坏字段逐项回默认', () {
    test('非 Map / null 一律回默认', () {
      expect(normalizeProductionSettings(null), defaultProductionSettings);
      expect(normalizeProductionSettings('nope'), defaultProductionSettings);
      expect(normalizeProductionSettings(<Object?>[]), defaultProductionSettings);
    });

    test('认不出的枚举值保持默认', () {
      final out = normalizeProductionSettings(<String, Object?>{
        'mode': 'nope',
        'angle': 'nope',
        'tone': 'nope',
        'level': 'nope',
        'variant': 'nope',
        'scope': 'nope',
        'yogurtDirection': 'nope',
        'yogurtSplit': 'nope',
      });
      expect(out, defaultProductionSettings);
    });

    test('认得出的枚举值照收', () {
      final out = normalizeProductionSettings(<String, Object?>{
        'mode': 'yogurt',
        'angle': 'story',
        'tone': 'casual',
        'level': 'c1',
        'variant': 'reorder',
        'scope': 'weak',
        'yogurtDirection': 'enZh',
        'yogurtSplit': 'line',
      });
      expect(out.mode, ProductionMode.yogurt);
      expect(out.angle, ProductionAngle.story);
      expect(out.tone, ProductionTone.casual);
      expect(out.level, ProductionLevel.c1);
      expect(out.variant, ProductionVariant.reorder);
      expect(out.scope, ProductionScope.weak);
      expect(out.yogurtDirection, ProductionDirection.enZh);
      expect(out.yogurtSplit, YogurtSplitMode.line);
    });

    test('题数 / 每题目标数 / 薄弱比例只认白名单里的值', () {
      final ok = normalizeProductionSettings(<String, Object?>{
        'promptCount': 8,
        'targetsPerPrompt': 3,
        'weakRatio': 70,
      });
      expect(ok.promptCount, 8);
      expect(ok.targetsPerPrompt, 3);
      expect(ok.weakRatio, 70);

      final bad = normalizeProductionSettings(<String, Object?>{
        'promptCount': 4,
        'targetsPerPrompt': 9,
        'weakRatio': 31,
      });
      expect(bad.promptCount, defaultProductionSettings.promptCount);
      expect(bad.targetsPerPrompt, defaultProductionSettings.targetsPerPrompt);
      expect(bad.weakRatio, defaultProductionSettings.weakRatio);
    });

    test('字符串数字不认；整数值的小数认（JS 里都是 number）', () {
      final out = normalizeProductionSettings(<String, Object?>{
        'promptCount': '8',
        'weakRatio': 70.0,
      });
      expect(out.promptCount, defaultProductionSettings.promptCount);
      expect(out.weakRatio, 70);
    });

    test('类型列表去掉认不出的与重复项；空列表保持默认', () {
      final out = normalizeProductionSettings(<String, Object?>{
        'types': <Object?>['word', 'nope', 'word', 'idiom'],
      });
      expect(
        out.types,
        <ProductionTargetKind>[
          ProductionTargetKind.word,
          ProductionTargetKind.idiom,
        ],
      );
      expect(
        normalizeProductionSettings(<String, Object?>{'types': <Object?>['nope']})
            .types,
        defaultProductionSettings.types,
      );
      expect(
        normalizeProductionSettings(<String, Object?>{'types': 'word'}).types,
        defaultProductionSettings.types,
      );
    });

    test('主题截到 200 字，原文 / 参考译文截到 50000 字', () {
      final out = normalizeProductionSettings(<String, Object?>{
        'topic': '  ${'x' * 300}  ',
        'sourceText': 'a' * 60000,
        'referenceText': 'b' * 60000,
      });
      expect(out.topic.length, 200);
      expect(out.sourceText.length, 50000);
      expect(out.referenceText.length, 50000);
    });

    test('布尔字段只认 bool', () {
      final out = normalizeProductionSettings(<String, Object?>{
        'fullUseChunks': false,
        'skimUseChunks': true,
        'yogurtParagraph': false,
      });
      expect(out.fullUseChunks, isFalse);
      expect(out.skimUseChunks, isTrue);
      expect(out.yogurtParagraph, isFalse);

      final bad = normalizeProductionSettings(<String, Object?>{
        'fullUseChunks': 'false',
        'skimUseChunks': 1,
      });
      expect(bad.fullUseChunks, defaultProductionSettings.fullUseChunks);
      expect(bad.skimUseChunks, defaultProductionSettings.skimUseChunks);
    });
  });

  group('productionSettingsToJson：往返', () {
    test('默认设置往返不变', () {
      expect(
        normalizeProductionSettings(
          productionSettingsToJson(defaultProductionSettings),
        ),
        defaultProductionSettings,
      );
    });

    test('每改一个字段都能往返', () {
      final s = defaultProductionSettings.copyWith(
        mode: ProductionMode.yogurt,
        topic: '远程办公',
        angle: ProductionAngle.email,
        tone: ProductionTone.formal,
        level: ProductionLevel.c1,
        variant: ProductionVariant.cloze,
        scope: ProductionScope.mistakes,
        types: const <ProductionTargetKind>[
          ProductionTargetKind.idiom,
          ProductionTargetKind.phrase,
        ],
        promptCount: 3,
        targetsPerPrompt: 1,
        weakRatio: 50,
        fullUseChunks: false,
        skimUseChunks: true,
        sourceText: '中文原文',
        referenceText: 'English reference',
        yogurtDirection: ProductionDirection.enZh,
        yogurtSplit: YogurtSplitMode.line,
        yogurtParagraph: false,
      );
      expect(
        normalizeProductionSettings(productionSettingsToJson(s)),
        s,
      );
    });
  });

  group('ProductionSettings：等值与 copyWith', () {
    test('默认值口径', () {
      const s = defaultProductionSettings;
      expect(s.mode, ProductionMode.full);
      expect(s.scope, ProductionScope.article);
      expect(s.promptCount, 5);
      expect(s.targetsPerPrompt, 2);
      expect(s.weakRatio, 30);
      expect(s.fullUseChunks, isTrue);
      expect(s.skimUseChunks, isFalse);
      expect(s.yogurtParagraph, isTrue);
      expect(s.types, hasLength(3));
    });

    test('copyWith 不改原对象', () {
      const s = defaultProductionSettings;
      final t = s.copyWith(topic: 'x');
      expect(s.topic, isEmpty);
      expect(t.topic, 'x');
      expect(t, isNot(s));
    });

    test('types 按顺序比较，顺序不同就不等', () {
      final a = defaultProductionSettings.copyWith(
        types: const <ProductionTargetKind>[
          ProductionTargetKind.word,
          ProductionTargetKind.phrase,
        ],
      );
      final b = defaultProductionSettings.copyWith(
        types: const <ProductionTargetKind>[
          ProductionTargetKind.phrase,
          ProductionTargetKind.word,
        ],
      );
      expect(a, isNot(b));
      expect(
        a,
        defaultProductionSettings.copyWith(
          types: const <ProductionTargetKind>[
            ProductionTargetKind.word,
            ProductionTargetKind.phrase,
          ],
        ),
      );
    });
  });

  group('枚举标签与常量', () {
    test('每个枚举都有中文名', () {
      for (final m in ProductionMode.values) {
        expect(productionModeLabel[m], isNotNull);
        expect(productionModeDesc[m], isNotNull);
      }
      for (final s in ProductionScope.values) {
        expect(productionScopeLabel[s], isNotNull);
      }
      for (final l in ProductionLevel.values) {
        expect(productionLevelLabel[l], isNotNull);
      }
      for (final v in ProductionVariant.values) {
        expect(productionVariantLabel[v], isNotNull);
      }
      for (final a in ProductionAngle.values) {
        expect(productionAngleLabel[a], isNotNull);
      }
      for (final t in ProductionTone.values) {
        expect(productionToneLabel[t], isNotNull);
      }
    });

    test('白名单常量', () {
      expect(productionPromptCounts, <int>[3, 5, 8]);
      expect(productionTargetsPerPrompt, <int>[1, 2, 3]);
      expect(productionWeakRatios, <int>[0, 30, 50, 70]);
      expect(productionDueDailyCap, 6);
    });

    test('三种吃法的中文名与说明都不为空', () {
      for (final m in ProductionMode.values) {
        expect(productionModeLabel[m]!.isNotEmpty, isTrue);
        expect(productionModeDesc[m]!.isNotEmpty, isTrue);
      }
    });
  });
}
