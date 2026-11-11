import 'package:flutter_test/flutter_test.dart';

import 'package:dlaoshi_app/core/vocab/drill.dart';
import 'package:dlaoshi_app/core/vocab/drill_step.dart';
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

void main() {
  group('标题', () {
    test('超时与重学补考措辞不同', () {
      expect(drillHeadOf(DrillReason.timeout).title, '⏱ 超时锤炼');
      expect(drillHeadOf(DrillReason.timeout).hint.contains('停太久'), isTrue);
      expect(drillHeadOf(DrillReason.relearn).title, '♻️ 重学补考');
      expect(drillHeadOf(DrillReason.relearn).hint.contains('忘过'), isTrue);
    });
  });

  group('要过哪几步', () {
    final others = <VocabItem>[
      for (final w in const ['alpha', 'beta', 'gamma', 'delta'])
        mkWord(w, meaning: '意思-$w'),
    ];

    test('词 + 释义 + 搭配：三步全过', () {
      final card = mkWord('introvert', meaning: '内向者', usage: const ['be an introvert']);
      expect(
        buildDrillSteps(card, [...others, card]),
        [DrillStep.spell, DrillStep.meaning, DrillStep.usage],
      );
    });

    test('没搭配：跳过写搭配那一步', () {
      final card = mkWord('introvert', meaning: '内向者');
      expect(
        buildDrillSteps(card, [...others, card]),
        [DrillStep.spell, DrillStep.meaning],
      );
    });

    test('没释义：跳过选义那一步（出不了四选一）', () {
      final card = mkWord('introvert', usage: const ['be an introvert']);
      expect(buildDrillSteps(card, [...others, card]), [DrillStep.spell, DrillStep.usage]);
    });

    test('词库太薄出不了四选一：只剩拼写', () {
      final card = mkWord('introvert', meaning: '内向者');
      expect(buildDrillSteps(card, [card]), [DrillStep.spell]);
    });

    test('词组也算搭配（用法在前，词组在后）', () {
      final card = mkWord('look after', meaning: '照顾', phrases: const ['look after sb']);
      expect(collocationsOf(card), ['look after sb']);
      final both = mkWord('x', usage: const ['use it'], phrases: const ['x y z']);
      expect(collocationsOf(both), ['use it', 'x y z']);
    });
  });

  group('写搭配判对', () {
    const colls = ['be an introvert', 'come out of one’s shell'];

    test('整句包含搭配就算过', () {
      expect(matchesCollocation('I am an introvert', const ['an introvert']), isTrue);
      expect(matchesCollocation('BE AN INTROVERT', colls), isTrue);
    });

    test('大小写与多余空格不影响', () {
      expect(matchesCollocation('  be   an  introvert  ', colls), isTrue);
    });

    test('没写到 / 空输入 / 太短的搭配都不算', () {
      expect(matchesCollocation('introvert', colls), isFalse);
      expect(matchesCollocation('', colls), isFalse);
      expect(matchesCollocation('anything', const ['to']), isFalse);
    });
  });
}
