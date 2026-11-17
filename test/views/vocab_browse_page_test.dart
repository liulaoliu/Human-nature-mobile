// 词库浏览页的 smoke：空库给搜索框与空态文案。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dlaoshi_app/core/ports.dart' show SpeechPort;
import 'package:dlaoshi_app/core/vocab_browse.dart';
import 'package:dlaoshi_app/models/vocab.dart';
import 'package:dlaoshi_app/views/vocab_browse_page.dart';
import 'smoke_harness.dart';

/// 假朗读：只记账，不碰平台通道。
class _FakeSpeech implements SpeechPort {
  final List<String> spoken = [];

  @override
  Future<void> speak(String text) async => spoken.add(text);

  @override
  Future<void> stop() async {}

  @override
  Future<void> setRate(double rate) async {}

  @override
  bool get isSpeaking => false;
}

VocabItem _word(String word, {String? meaning}) => VocabItem(
  id: 'item-$word',
  word: word,
  lemma: word,
  meaning: meaning,
  createdAt: '2026-11-01T00:00:00.000Z',
  updatedAt: '2026-11-01T00:00:00.000Z',
  // 词库默认筛「复习」，给个过去的 due 才看得见（不是要测筛选）。
  reviewState: const ReviewState(due: '2026-11-01T00:00:00.000Z'),
);

void main() {
  setUpAll(smokeInitFfi);

  testWidgets('VocabBrowsePage 空库：词库计数、搜索框与空态', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);

    await smokePump(tester, smokeApp(db, const VocabBrowsePage()));

    expect(find.text('词库（0）'), findsOneWidget);
    expect(find.text('搜单词 / 释义 / 笔记'), findsOneWidget);
    expect(find.text('这个筛选下没有词。换个范围或清掉日期试试。'), findsOneWidget);

    await smokeFinish(tester);
  });

  testWidgets('VocabBrowsePage 一键处理：五步都在，能单独跑也能一键跑', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);

    await smokePump(tester, smokeApp(db, const VocabBrowsePage()));

    await tester.tap(find.byTooltip('一键处理'));
    await tester.pumpAndSettle();

    expect(find.text('⚡ 一键处理'), findsOneWidget);
    for (final label in ['本篇挑词', '补齐生词本', '补离线例句', '校正原形', '补混淆项']) {
      expect(find.text(label), findsOneWidget, reason: '五步清单缺了「$label」');
    }

    // 没选文章：挑词禁用，其余四步可点；总按钮可点。
    TextButton runButton(String id) =>
        tester.widget<TextButton>(find.byKey(ValueKey('dict-tools-run-$id')));
    expect(runButton('pick').onPressed, isNull);
    for (final id in ['enrich', 'examples', 'lemma', 'confuse']) {
      expect(runButton(id).onPressed, isNotNull, reason: id);
    }
    final all = tester.widget<FilledButton>(
      find.byKey(const ValueKey('dict-tools-run-all')),
    );
    expect(all.onPressed, isNotNull);

    // 真点一步：空库时「补齐生词本」应给出「没有可补齐的」。
    await tester.tap(find.byKey(const ValueKey('dict-tools-run-enrich')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    final outcome = tester.widget<Text>(
      find.byKey(const ValueKey('dict-tools-outcome-enrich')),
    );
    expect(outcome.data, contains('没有可补齐的'));

    await smokeFinish(tester);
  });

  testWidgets('VocabBrowsePage 筛选：平时收着，点一下滑出面板，四组条件分块摆', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);

    await smokePump(tester, smokeApp(db, const VocabBrowsePage()));

    // 平时只看得到一行摘要，条件控件不在页面上。
    // 空库没有「本篇」，bootstrap 会把范围退回「全部」。
    expect(find.byKey(const ValueKey('vocab-filter-open')), findsOneWidget);
    expect(find.text('筛选：全部 · 单词 · 复习'), findsOneWidget);
    expect(find.byKey(const ValueKey('filter-scope-article')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('vocab-filter-open')));
    await tester.pumpAndSettle();

    for (final title in ['来源', '类型', '学习状态', '按日期（入库日）']) {
      expect(find.text(title), findsOneWidget, reason: '面板缺了「$title」这一块');
    }
    // 来源三选 + 类型三选 + 状态五选，都不是 button / chip。
    expect(find.byKey(const ValueKey('filter-scope-article')), findsOneWidget);
    expect(find.byKey(const ValueKey('filter-scope-picked')), findsOneWidget);
    expect(find.byKey(const ValueKey('filter-scope-all')), findsOneWidget);
    expect(find.byKey(const ValueKey('filter-kind-lang')), findsOneWidget);
    expect(find.byKey(const ValueKey('filter-status-lapsed')), findsOneWidget);

    await smokeFinish(tester);
  });

  testWidgets('VocabBrowsePage 筛选：点「全部」和「忘记」会立刻生效并写盘', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);

    await smokePump(tester, smokeApp(db, const VocabBrowsePage()));
    final vm = smokeBrowseVm(tester);

    await tester.tap(find.byKey(const ValueKey('vocab-filter-open')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('filter-scope-all')));
    await tester.pumpAndSettle();
    expect(vm.scope, BrowseScope.all);

    await tester.tap(find.byKey(const ValueKey('filter-status-lapsed')));
    await tester.pumpAndSettle();
    expect(vm.status, BrowseStatus.lapsed);

    // 面板开着时页面还在树下（只是被盖住），所以摘要已经跟着变了；
    // 关掉面板后同一行仍然在。
    expect(find.text('筛选：全部 · 单词 · 忘记'), findsOneWidget);

    await tester.tapAt(const Offset(10, 10)); // 点面板外关掉
    await tester.pumpAndSettle();
    expect(find.text('筛选：全部 · 单词 · 忘记'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('filter-scope-all')),
      findsNothing,
      reason: '面板关掉后条件控件要收起来',
    );

    await smokeFinish(tester);
  });

  testWidgets('词库：点单词本身、点小喇叭都会读一遍', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);
    await tester.runAsync(
      () => smokeVocabRepo(
        db,
      ).save(VocabLibrary(items: [_word('serendipity', meaning: '意外发现')])),
    );

    final speech = _FakeSpeech();
    await smokePump(tester, smokeApp(db, VocabBrowsePage(speech: speech)));
    // bootstrap 是真实异步 IO，多等一轮再断言。
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await tester.pumpAndSettle();

    expect(find.text('serendipity'), findsOneWidget);
    expect(find.byIcon(Icons.volume_up_outlined), findsOneWidget);

    // 点喇叭。
    await tester.tap(find.byTooltip('读一遍'));
    await tester.pump();
    expect(speech.spoken, ['serendipity']);

    // 点单词本身（整行可点）。
    await tester.tap(find.text('serendipity'));
    await tester.pump();
    expect(speech.spoken, ['serendipity', 'serendipity']);

    await smokeFinish(tester);
  });
}
