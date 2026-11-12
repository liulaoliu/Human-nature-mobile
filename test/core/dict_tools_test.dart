// 「一键处理」的框架：五步清单、禁用判定、缺什么。
import 'package:flutter_test/flutter_test.dart';

import 'package:dlaoshi_app/core/dict_tools.dart';

void main() {
  group('清单', () {
    test('五步，顺序与 Web 一致', () {
      expect(dictToolSteps.map((s) => s.id).toList(), [
        'pick',
        'enrich',
        'examples',
        'lemma',
        'confuse',
      ]);
    });

    test('每步都有文案与说明', () {
      for (final step in dictToolSteps) {
        expect(step.label, isNotEmpty);
        expect(step.hint, isNotEmpty);
      }
    });

    test('只有补例句那步不要词典', () {
      final needsDict = {
        for (final s in dictToolSteps)
          if (s.needsDictionary) s.id,
      };
      expect(needsDict, {'pick', 'enrich', 'lemma', 'confuse'});
    });

    test('只有补例句那步要例句库', () {
      final needsExamples = {
        for (final s in dictToolSteps)
          if (s.needsExamples) s.id,
      };
      expect(needsExamples, {'examples'});
    });
  });

  group('能不能跑', () {
    test('动作没实现：数据再齐也别让点', () {
      for (final step in dictToolSteps) {
        expect(
          dictStepEnabled(
            step,
            dictionaryReady: true,
            examplesReady: true,
          ),
          isFalse,
          reason: '${step.id} 的动作还没写，按钮必须是禁用的',
        );
      }
    });

    test('数据缺失时同样是禁用', () {
      expect(
        dictStepEnabled(
          dictToolSteps.first,
          dictionaryReady: false,
          examplesReady: false,
        ),
        isFalse,
      );
    });
  });

  group('缺什么', () {
    test('两样都没', () {
      final text =
          dictToolsBlocker(dictionaryReady: false, examplesReady: false);
      expect(text, contains('词典'));
      expect(text, contains('例句'));
    });

    test('只缺词典', () {
      final text =
          dictToolsBlocker(dictionaryReady: false, examplesReady: true);
      expect(text, contains('词典'));
    });

    test('只缺例句库', () {
      final text =
          dictToolsBlocker(dictionaryReady: true, examplesReady: false);
      expect(text, contains('例句'));
    });

    test('都齐了：老实说函数没接', () {
      final text = dictToolsBlocker(dictionaryReady: true, examplesReady: true);
      expect(text, contains('框架'));
    });
  });
}
