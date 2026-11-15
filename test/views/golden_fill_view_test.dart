// 填空正文：一词一空之后，同一学习点在句子里出现两次时，
// 答案共用一个 controller，但两个空位必须各有 FocusNode / GlobalKey。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dlaoshi_app/core/golden.dart';
import 'package:dlaoshi_app/core/golden_drill.dart';
import 'package:dlaoshi_app/views/golden_fill_view.dart';

void main() {
  testWidgets('重复学习点：答案同步，空位各有一份焦点与 key', (tester) async {
    tester.view.physicalSize = const Size(1080, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final cloze = buildGoldenCloze('Day by day, day by day.', <GoldenTarget>[
      const GoldenTarget(en: 'day by day', kind: GoldenTargetKind.idiom),
    ], const GoldenClozeOptions(splitWords: true))!;
    expect(cloze.blanks, hasLength(3));
    final slots = cloze.parts.where((GoldenClozePart p) => p.blank).length;
    expect(slots, 6);

    final controllers = <TextEditingController>[
      for (var i = 0; i < cloze.blanks.length; i++) TextEditingController(),
    ];
    final focuses = <FocusNode>[for (var i = 0; i < slots; i++) FocusNode()];
    final keys = <GlobalKey>[for (var i = 0; i < slots; i++) GlobalKey()];
    addTearDown(() {
      for (final c in controllers) {
        c.dispose();
      }
      for (final f in focuses) {
        f.dispose();
      }
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GoldenFillView(
            cloze: cloze,
            controllers: controllers,
            focuses: focuses,
            blankKeys: keys,
            progress: '这一轮 3 个空',
            scored: false,
            results: const <bool>[],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(TextField), findsNWidgets(6));

    final first = tester.widget<TextField>(
      find.byKey(const ValueKey<String>('golden-blank-0')),
    );
    final repeated = tester.widget<TextField>(
      find.byKey(const ValueKey<String>('golden-blank-3')),
    );
    expect(
      first.controller,
      same(repeated.controller),
      reason: '同一答案共用一个 controller',
    );
    expect(first.focusNode, isNot(same(repeated.focusNode)), reason: '焦点不能复用');
    expect(keys.toSet(), hasLength(slots), reason: '每个空位一个 GlobalKey');

    first.controller!.text = 'day';
    await tester.pump();
    expect(repeated.controller!.text, 'day');

    first.focusNode!.requestFocus();
    await tester.pump();
    expect(first.focusNode!.hasFocus, isTrue);
    expect(repeated.focusNode!.hasFocus, isFalse);
    repeated.focusNode!.requestFocus();
    await tester.pump();
    expect(repeated.focusNode!.hasFocus, isTrue);
  });
}
