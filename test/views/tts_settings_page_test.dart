// 朗读设置页的页面级测试（33.15）。
//
// 这一页以前只有 VM 层的用例，页面自己（切档、换音色、拖滑块、恢复默认、
// 系统合成器入口、试听按钮）没人盯。这里按用户的操作路径补上：
//   1. 起来显示存过的档位与语速；
//   2. 点档位卡换档 → 语速换成新档自己那份；
//   3. 点音色行换音色 → 只影响当前档；
//   4. 拖滑块 → 改当前档语速、推给朗读实现；
//   5. 「恢复默认」默认值时不可点，改过之后点回默认；
//   6. 系统合成器入口只在系统档出现；
//   7. 跨 VM：这里的语速进了跟读页也不能被它打回去（33.2 的回归）。
//
// 试听不点：测试环境没有 `flutter_tts` 平台通道，`SystemSpeech.speak` 必然抛，
// 点了会让用例红在一个和本页无关的地方。语速是否真的推给朗读实现，由第 4 条
// 断言 `smokeTts.speech.rate` 覆盖。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dlaoshi_app/core/tts_provider.dart';
import 'package:dlaoshi_app/data/prefs_store.dart';
import 'package:dlaoshi_app/views/shadowing_page.dart';
import 'package:dlaoshi_app/views/tts_settings_page.dart';
import 'smoke_harness.dart';

void main() {
  setUpAll(smokeInitFfi);

  /// 起页面。[seed] 用来预置本机偏好（档位 / 语速 / 音色）。
  Future<void> pumpPage(WidgetTester tester, {Map<String, String>? seed}) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);
    await smokePump(
      tester,
      smokeApp(
        db,
        const TtsSettingsPage(),
        prefsStore: seed == null ? null : PrefsStore.memory(seed),
      ),
    );
  }

  testWidgets('起来显示存过的档位与语速（设置页显示已保存值）', (tester) async {
    await pumpPage(
      tester,
      seed: <String, String>{
        ttsProviderKey: 'kitten',
        ttsRateKey(TtsProvider.kitten): '0.900',
      },
    );

    expect(smokeTts.provider, TtsProvider.kitten, reason: '构造时就读偏好');
    expect(find.text('朗读语速 90%'), findsOneWidget);
    expect(
      tester
          .widget<Slider>(find.byKey(const ValueKey<String>('tts-rate-slider')))
          .value,
      0.9,
    );
    expect(
      find.textContaining('试听：离线神经朗读（Kitten）'),
      findsOneWidget,
      reason: '试听条上的档位名也要对得上，否则用户以为没读到偏好',
    );
  });

  testWidgets('点档位卡换档：语速换成新档自己那份，界面跟着变', (tester) async {
    await pumpPage(
      tester,
      seed: <String, String>{
        ttsProviderKey: 'kitten',
        ttsRateKey(TtsProvider.kitten): '0.900',
      },
    );

    // 切到 Kokoro：它没存过语速，应该用默认 0.45，而不是沿用 Kitten 的 0.9。
    await tester.tap(find.byKey(const ValueKey<String>('tts-provider-kokoro')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump();

    expect(smokeTts.provider, TtsProvider.kokoro);
    expect(smokeTts.rate, defaultTtsRateOf(TtsProvider.kokoro));
    expect(find.text('朗读语速 45%'), findsOneWidget);

    // 切回 Kitten：它存过 0.9，要读回来。
    await tester.tap(find.byKey(const ValueKey<String>('tts-provider-kitten')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump();

    expect(smokeTts.provider, TtsProvider.kitten);
    expect(smokeTts.rate, 0.9);
    expect(find.text('朗读语速 90%'), findsOneWidget);
  });

  testWidgets('点音色行换音色：只影响当前档，试听条跟着改口', (tester) async {
    await pumpPage(tester);

    // 系统档没有音色列表，切到 Kitten 才有。
    await tester.runAsync(() => smokeTts.setProvider(TtsProvider.kitten));
    await tester.pump();

    final options = smokeTts.voiceOptions;
    expect(options.length, greaterThan(1), reason: 'Kitten 有多个音色可选');
    final target = options.first.id;
    await tester.tap(find.byKey(ValueKey<String>('tts-voice-$target')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump();

    expect(smokeTts.voice, target);
    expect(find.textContaining(smokeTts.voiceLabel), findsWidgets);
  });

  testWidgets('拖滑块改语速：当前档立刻变，并推给朗读实现', (tester) async {
    await pumpPage(tester);

    await tester.runAsync(() => smokeTts.setProvider(TtsProvider.kitten));
    await tester.pump();
    final before = smokeTts.rate;

    await tester.drag(
      find.byKey(const ValueKey<String>('tts-rate-slider')),
      const Offset(-200, 0),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump();

    expect(smokeTts.rate, lessThan(before), reason: '往左拖是变慢');
    expect(
      find.text('朗读语速 ${(smokeTts.rate * 100).round()}%'),
      findsOneWidget,
    );
    expect(
      smokeTts.speech.rate,
      smokeTts.rate,
      reason: '光改 VM 不够，要真的推给朗读实现',
    );
  });

  testWidgets('「恢复默认」：默认值时不可点，改过之后点回默认', (tester) async {
    await pumpPage(tester);

    TextButton resetButton() => tester.widget<TextButton>(
      find.byKey(const ValueKey<String>('tts-rate-reset')),
    );

    expect(resetButton().onPressed, isNull, reason: '本来就在默认值，按钮该灰掉');

    await tester.runAsync(() => smokeTts.setRate(0.9));
    await tester.pump();
    expect(resetButton().onPressed, isNotNull);

    await tester.tap(find.byKey(const ValueKey<String>('tts-rate-reset')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump();

    expect(smokeTts.rate, defaultTtsRateOf(TtsProvider.system));
  });

  testWidgets('系统合成器入口只在系统档出现', (tester) async {
    await pumpPage(tester);

    // 测试环境没有 flutter_tts 通道，`engines()` 回空表，这一块退化成
    // 「这台手机只有一个系统合成器…」那句说明 —— 两种形态都算「入口在」。
    expect(
      find.textContaining('系统合成器'),
      findsOneWidget,
      reason: '默认是系统档',
    );

    await tester.runAsync(() => smokeTts.setProvider(TtsProvider.edge));
    await tester.pump();

    expect(
      find.textContaining('系统合成器'),
      findsNothing,
      reason: '在线档的音色不是手机装的合成器',
    );
  });

  testWidgets('跨 VM：这里的语速进了跟读页也不会被打回去', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);

    // 先把 TTS 调到 Kitten 150%（用户 m10515 要的那档）。
    final prefs = PrefsStore.memory(<String, String>{
      ttsProviderKey: 'kitten',
      ttsRateKey(TtsProvider.kitten): '1.500',
    });
    await smokePump(
      tester,
      smokeApp(db, const ShadowingPage(), prefsStore: prefs),
    );

    // 跟读页 bootstrap 会写一圈偏好；它以前会把全局语速打回旧值（33.2）。
    expect(smokeTts.provider, TtsProvider.kitten);
    expect(
      smokeTts.rate,
      1.5,
      reason: '进跟读页不能改朗读语速 —— 只有一个写入方',
    );
    expect(
      prefs.read(ttsRateKey(TtsProvider.kitten)),
      '1.500',
      reason: '本机偏好也不能被反向覆盖',
    );
  });
}
