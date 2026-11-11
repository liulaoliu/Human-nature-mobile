import 'package:flutter_test/flutter_test.dart';

import 'package:dlaoshi_app/core/vocab/drill.dart';
import 'package:dlaoshi_app/core/vocab/drill_step.dart';
import 'package:dlaoshi_app/core/vocab/study_drill.dart';
import 'package:dlaoshi_app/models/vocab.dart';

VocabItem mkWord(
  String word, {
  String? meaning,
  List<String> usage = const [],
  List<String>? phrases,
}) =>
    VocabItem(
      id: 'item-$word',
      word: word,
      lemma: word,
      meaning: meaning,
      usage: usage,
      phrases: phrases,
      createdAt: '2026-11-01T00:00:00.000Z',
      updatedAt: '2026-11-01T00:00:00.000Z',
    );

/// 造一个能出「拼写 + 选义 + 搭配」三步的卡，外加三个干扰词。
({VocabItem card, List<VocabItem> items}) scene() {
  final card = mkWord(
    'introvert',
    meaning: '内向的人',
    usage: const ['be an introvert'],
  );
  final others = <VocabItem>[
    for (final w in const ['outgoing', 'gregarious', 'reserved'])
      mkWord(w, meaning: '意思-$w'),
  ];
  return (card: card, items: [...others, card]);
}

void main() {
  group('步骤与题面', () {
    test('三步齐全，从拼写开始', () {
      final s = scene();
      final drill = StudyDrill(reason: DrillReason.timeout, card: s.card, items: s.items);
      expect(drill.steps, [DrillStep.spell, DrillStep.meaning, DrillStep.usage]);
      expect(drill.step, DrillStep.spell);
      expect(drill.cleared, isFalse);
      expect(drill.prompt, '把这个词拼出来');
    });

    test('标题按来路给（超时 / 重学补考）', () {
      final s = scene();
      expect(
        StudyDrill(reason: DrillReason.timeout, card: s.card, items: s.items).head.title,
        '⏱ 超时锤炼',
      );
      expect(
        StudyDrill(reason: DrillReason.relearn, card: s.card, items: s.items).head.title,
        '♻️ 重学补考',
      );
    });

    test('没搭配的卡只有两步；没释义只剩拼写', () {
      final bare = mkWord('introvert', meaning: '内向的人');
      final withMeaning = StudyDrill(
        reason: DrillReason.timeout,
        card: bare,
        items: [
          bare,
          for (final w in const ['outgoing', 'gregarious', 'reserved'])
            mkWord(w, meaning: '意思-$w'),
        ],
      );
      expect(withMeaning.steps, [DrillStep.spell, DrillStep.meaning]);

      final noMeaning = mkWord('introvert', usage: const ['be an introvert']);
      final onlySpell = StudyDrill(
        reason: DrillReason.timeout,
        card: noMeaning,
        items: [noMeaning],
      );
      expect(onlySpell.steps, [DrillStep.spell, DrillStep.usage]);
    });
  });

  group('拼写', () {
    test('拼对进下一步', () {
      final s = scene();
      final drill = StudyDrill(reason: DrillReason.timeout, card: s.card, items: s.items);
      expect(drill.submitSpell('Introvert'), DrillVerdict.passed);
      expect(drill.step, DrillStep.meaning);
      expect(drill.typed, '');
    });

    test('拼错只判一次：整块记 spellMiss，不推进', () {
      final s = scene();
      final drill = StudyDrill(reason: DrillReason.timeout, card: s.card, items: s.items);
      expect(drill.submitSpell('introver'), DrillVerdict.spellMiss);
      expect(drill.spellMiss, isTrue);
      expect(drill.step, DrillStep.spell);
      // 再拼对也不放行（外面已经按「不认识」收尾了）
      expect(drill.submitSpell('introvert'), DrillVerdict.retry);
    });
  });

  group('选义', () {
    StudyDrill atMeaning() {
      final s = scene();
      final drill = StudyDrill(reason: DrillReason.timeout, card: s.card, items: s.items);
      drill.submitSpell('introvert');
      return drill;
    }

    test('四个选项里正好一个正确项', () {
      final drill = atMeaning();
      expect(drill.options.length, 4);
      expect(drill.options.where((o) => o.correct).length, 1);
      expect(drill.prompt, '选出它在这里的意思');
    });

    test('选对进写搭配', () {
      final drill = atMeaning();
      final right = drill.options.indexWhere((o) => o.correct);
      expect(drill.pickMeaning(right), DrillVerdict.passed);
      expect(drill.step, DrillStep.usage);
      expect(drill.wrongPick, isFalse);
    });

    test('选错停在原地标红，再选对还能过', () {
      final drill = atMeaning();
      final right = drill.options.indexWhere((o) => o.correct);
      final wrong = drill.options.indexWhere((o) => !o.correct);
      expect(drill.pickMeaning(wrong), DrillVerdict.retry);
      expect(drill.wrongPick, isTrue);
      expect(drill.step, DrillStep.meaning);
      expect(drill.pickMeaning(right), DrillVerdict.passed);
      expect(drill.wrongPick, isFalse);
    });

    test('下标越界不崩，也不推进', () {
      final drill = atMeaning();
      expect(drill.pickMeaning(-1), DrillVerdict.retry);
      expect(drill.pickMeaning(99), DrillVerdict.retry);
      expect(drill.step, DrillStep.meaning);
    });
  });

  group('写搭配', () {
    StudyDrill atUsage() {
      final s = scene();
      final drill = StudyDrill(reason: DrillReason.timeout, card: s.card, items: s.items);
      drill.submitSpell('introvert');
      drill.pickMeaning(drill.options.indexWhere((o) => o.correct));
      return drill;
    }

    test('写对就整块过完，解锁评分', () {
      final drill = atUsage();
      expect(drill.prompt, '用它写个搭配（写出任意一条用法即可）');
      expect(drill.submitUsage('I tend to be an introvert'), DrillVerdict.passed);
      expect(drill.usageOk, isTrue);
      expect(drill.cleared, isTrue);
      expect(drill.step, isNull);
    });

    test('没写对停在这一步', () {
      final drill = atUsage();
      expect(drill.submitUsage('whatever'), DrillVerdict.retry);
      expect(drill.cleared, isFalse);
      expect(drill.usageOk, isFalse);
    });
  });

  group('走错步骤', () {
    test('不在那一步时提交，一律 retry，不炸', () {
      final s = scene();
      final drill = StudyDrill(reason: DrillReason.timeout, card: s.card, items: s.items);
      expect(drill.pickMeaning(0), DrillVerdict.retry);
      expect(drill.submitUsage('be an introvert'), DrillVerdict.retry);
      expect(drill.step, DrillStep.spell);
      expect(drill.spellMiss, isFalse);
    });
  });
}
