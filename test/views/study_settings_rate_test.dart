// 背诵设置页的「朗读语速」滑块：33.2 之后它读写的是 TtsViewModel（唯一真源）。
//
// 这里盯三件事：
//   1. 滑块显示的是**当前档**的语速，跟朗读设置页是同一个值；
//   2. 拖动它真的会改 TtsViewModel 的状态（不是改跟读自己的旧键）；
//   3. 直接进设置页（没跑过 bootstrap）也能看到引擎列表 —— 补了一次懒加载。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dlaoshi_app/core/tts_provider.dart';
import 'package:dlaoshi_app/views/study_settings_page.dart';
import 'smoke_harness.dart';

void main() {
  setUpAll(smokeInitFfi);

  Future<void> pumpPage(WidgetTester tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);
    // smokeApp 内部自己造 PrefsStore.memory()；断言用不到的，取它装配好的
    // TtsViewModel 就够了（smokeTts 就是那个 Provider 里的同一个实例）。
    await smokePump(tester, smokeApp(db, const StudySettingsPage()));
  }

  testWidgets('滑块显示当前档语速，拖动后 TtsViewModel 跟着变', (tester) async {
    await pumpPage(tester);

    expect(find.text('朗读'), findsOneWidget, reason: '「朗读」标题不能丢');
    expect(
      find.text('朗读语速 系统朗读 45%'),
      findsOneWidget,
      reason: '默认是系统档 45%（defaultTtsRateOf）',
    );

    // 把滑块拖到最右边：系统档上限 1.0。
    await tester.drag(
      find.byKey(const ValueKey<String>('study-rate-slider')),
      const Offset(500, 0),
    );
    await tester.pump();

    expect(smokeTts.provider, TtsProvider.system);
    expect(smokeTts.rate, 1.0, reason: '拖到底 = 系统档上限 1.0');
    expect(
      find.text('朗读语速 系统朗读 100%'),
      findsOneWidget,
      reason: '界面要跟着状态走',
    );
  });

  testWidgets('这一页读的就是朗读设置页那一个值', (tester) async {
    await pumpPage(tester);

    // 模拟「朗读设置页把 Kitten 调到 90%」。
    await tester.runAsync(() => smokeTts.setProvider(TtsProvider.kitten));
    await tester.runAsync(() => smokeTts.setRate(0.9));
    await tester.pump();

    expect(
      find.text('朗读语速 离线神经朗读（Kitten） 90%'),
      findsOneWidget,
      reason: '两个页面共用 TtsViewModel，不能各存一份',
    );
    expect(
      find.textContaining('跟朗读设置页是同一个值'),
      findsOneWidget,
      reason: '界面上要写清楚这一点，别让用户以为又是两套',
    );
  });

  testWidgets('直接进设置页也会去取引擎列表（没跑过 bootstrap）', (tester) async {
    await pumpPage(tester);
    // 取引擎列表是异步的（flutter_tts 在测试环境会抛，实现里 catch 后给空表），
    // 关键是不崩、且下拉框在位。
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('合成引擎'), findsOneWidget);
  });
}
