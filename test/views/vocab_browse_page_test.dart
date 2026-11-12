// 词库浏览页的 smoke：空库给搜索框与空态文案。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dlaoshi_app/core/vocab_browse.dart';
import 'package:dlaoshi_app/views/vocab_browse_page.dart';
import 'smoke_harness.dart';

void main() {
  setUpAll(smokeInitFfi);

  testWidgets('VocabBrowsePage 空库：词库计数、搜索框与空态', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);

    await smokePump(tester, smokeApp(db, const VocabBrowsePage()));

    expect(find.text('词库（0）'), findsOneWidget);
    expect(find.text('搜单词 / 释义 / 笔记'), findsOneWidget);
    expect(find.text('这个筛选下没有词。换个范围或清掉日期试试。'),
        findsOneWidget);

    await smokeFinish(tester);
  });

  testWidgets('VocabBrowsePage 一键处理：五步都在，按钮禁用', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);

    await smokePump(tester, smokeApp(db, const VocabBrowsePage()));

    await tester.tap(find.byTooltip('一键处理（还没做）'));
    await tester.pumpAndSettle();

    expect(find.text('⚡ 一键处理'), findsOneWidget);
    for (final label in [
      '本篇挑词',
      '补齐生词本',
      '补离线例句',
      '校正原形',
      '补混淆项',
    ]) {
      expect(find.text(label), findsOneWidget, reason: '五步清单缺了「$label」');
    }
    // 每步都标「未实现」，且总按钮是禁用的（不是隐藏）。
    expect(find.text('未实现'), findsNWidgets(5));
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '一键处理（还没做）'),
    );
    expect(button.onPressed, isNull, reason: '动作没实现，按钮必须是禁用的');

    await smokeFinish(tester);
  });

  testWidgets('VocabBrowsePage 筛选：平时收着，点一下滑出面板，四组条件分块摆',
      (tester) async {
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

  testWidgets('VocabBrowsePage 筛选：点「全部」和「忘记」会立刻生效并写盘',
      (tester) async {
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
    expect(find.byKey(const ValueKey('filter-scope-all')), findsNothing,
        reason: '面板关掉后条件控件要收起来');

    await smokeFinish(tester);
  });
}
