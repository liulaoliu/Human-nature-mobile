// 「AI-deepseek 设置」页：连接设置从跑批页搬过来之后的 smoke + 一条真交互。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:dlaoshi_app/core/ai_config.dart';
import 'package:dlaoshi_app/data/prefs_store.dart';
import 'package:dlaoshi_app/data/repositories/vocab_repository.dart';
import 'package:dlaoshi_app/services/ai_client.dart' show AiReply;
import 'package:dlaoshi_app/viewmodels/ai_batch_view_model.dart';
import 'package:dlaoshi_app/views/ai_settings_page.dart';
import 'smoke_harness.dart';

void main() {
  setUpAll(smokeInitFfi);

  testWidgets('AiSettingsPage：连接设置三项 + 保存 / 测试连接', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);

    final vm = AiBatchViewModel(
      vocab: VocabRepository(db),
      complete: (config, prompt) async => const AiReply.ok('正常'),
      prefsStore: PrefsStore.memory(),
    );
    addTearDown(vm.dispose);

    await smokePump(
      tester,
      ChangeNotifierProvider<AiBatchViewModel>.value(
        value: vm,
        child: const MaterialApp(home: AiSettingsPage()),
      ),
    );

    expect(find.text('AI-deepseek 设置'), findsOneWidget);
    expect(find.text('连接设置'), findsOneWidget);
    expect(find.text('服务地址'), findsOneWidget);
    expect(find.text('API key'), findsOneWidget);
    expect(find.text('模型'), findsOneWidget);
    expect(find.text('保存到本机'), findsOneWidget);
    expect(find.text('测试连接'), findsOneWidget);

    await smokeFinish(tester);
  });

  testWidgets('点「测试连接」测的是输入框里刚敲的 key，不是上次保存的', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);

    final seen = <AiConfig>[];
    final vm = AiBatchViewModel(
      vocab: VocabRepository(db),
      complete: (config, prompt) async {
        seen.add(config);
        return const AiReply.ok('正常');
      },
      prefsStore: PrefsStore.memory(),
    );
    addTearDown(vm.dispose);

    await smokePump(
      tester,
      ChangeNotifierProvider<AiBatchViewModel>.value(
        value: vm,
        child: const MaterialApp(home: AiSettingsPage()),
      ),
    );

    // 字段顺序固定：服务地址 / API key / 模型。
    await tester.enterText(find.byType(TextField).at(1), 'sk-just-typed');
    await tester.pump();
    await tester.tap(find.text('测试连接'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump();

    expect(seen, hasLength(1));
    expect(seen.single.apiKey, 'sk-just-typed');
    expect(find.textContaining('连接正常'), findsOneWidget);

    await smokeFinish(tester);
  });
}
