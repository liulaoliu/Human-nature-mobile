// 「一键处理」：五步清单、可用性判定、缺什么。
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

    test('只有本篇挑词要当前文章', () {
      final needsArticle = {
        for (final s in dictToolSteps)
          if (s.needsArticle) s.id,
      };
      expect(needsArticle, {'pick'});
    });
  });

  group('能不能跑', () {
    test('数据齐了：五步都能点', () {
      for (final step in dictToolSteps) {
        expect(
          dictStepEnabled(
            step,
            dictionaryReady: true,
            examplesReady: true,
          ),
          isTrue,
          reason: step.id,
        );
      }
    });

    test('没选文章：只有挑词禁用', () {
      for (final step in dictToolSteps) {
        expect(
          dictStepEnabled(
            step,
            dictionaryReady: true,
            examplesReady: true,
            hasArticle: false,
          ),
          step.id != 'pick',
          reason: step.id,
        );
      }
    });

    test('词典没加载：依赖词典的四步禁用，补例句仍可点', () {
      for (final step in dictToolSteps) {
        expect(
          dictStepEnabled(
            step,
            dictionaryReady: false,
            examplesReady: true,
          ),
          !step.needsDictionary,
          reason: step.id,
        );
      }
    });

    test('例句库没加载：只有补例句禁用', () {
      for (final step in dictToolSteps) {
        expect(
          dictStepEnabled(
            step,
            dictionaryReady: true,
            examplesReady: false,
          ),
          !step.needsExamples,
          reason: step.id,
        );
      }
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

    test('都齐了：没有提示行', () {
      expect(
        dictToolsBlocker(dictionaryReady: true, examplesReady: true),
        isEmpty,
      );
    });
  });
}
