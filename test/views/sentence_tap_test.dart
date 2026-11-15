// 句子的两种手势：点一下朗读、长按复制整句（精读页与速读页共用）。
//
// 用户 2026-11-15 要求：精读/速读「点句子朗读、长按复制」，不要老的点句弹取词面板。
import 'package:dlaoshi_app/views/sentence_tap.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'smoke_harness.dart';

void main() {
  setUpAll(smokeInitFfi);

  testWidgets('点一下触发朗读回调', (tester) async {
    smokeUseTallScreen(tester);
    var tapped = 0;

    await smokePump(
      tester,
      MaterialApp(
        home: Scaffold(
          body: SentenceTapRegion(
            text: 'Global growth is slowing.',
            onSpeak: () => tapped++,
            child: const Text('Global growth is slowing.'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Global growth is slowing.'));
    await tester.pump();

    expect(tapped, 1);
    await smokeFinish(tester);
  });

  testWidgets('长按复制整句（复制的是这一句，不是整篇）', (tester) async {
    smokeUseTallScreen(tester);
    String? copied;

    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SentenceTapRegion(
            text: '  Companies would benefit from helping introverts.  ',
            onSpeak: () {},
            child: const Text('Companies would benefit from helping introverts.'),
          ),
        ),
      ),
    );

    await tester.longPress(find.byType(GestureDetector).first);
    await tester.pump();

    // 首尾空白要去掉，中间原样。
    expect(copied, 'Companies would benefit from helping introverts.');
    expect(find.text('已复制这一句'), findsOneWidget);

    await smokeFinish(tester);
  });

  testWidgets('没有朗读回调时点一下不做事，长按仍能复制', (tester) async {
    smokeUseTallScreen(tester);
    String? copied;

    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SentenceTapRegion(
            text: 'MOST companies worry.',
            child: Text('MOST companies worry.'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('MOST companies worry.'));
    await tester.pump();
    expect(copied, isNull);

    await tester.longPress(find.text('MOST companies worry.'));
    await tester.pump();
    expect(copied, 'MOST companies worry.');

    await smokeFinish(tester);
  });
}
