// 词库浏览页的 smoke：空库给搜索框与空态文案。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
