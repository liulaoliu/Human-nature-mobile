// AI 跑批页的 smoke + 一条真交互（「测试连接」必须测框里刚敲的配置）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:dlaoshi_app/core/ai_config.dart';
import 'package:dlaoshi_app/core/ai_jobs.dart' show AiScope;
import 'package:dlaoshi_app/data/prefs_store.dart';
import 'package:dlaoshi_app/data/repositories/vocab_repository.dart';
import 'package:dlaoshi_app/services/ai_client.dart' show AiReply;
import 'package:dlaoshi_app/viewmodels/ai_batch_view_model.dart';
import 'package:dlaoshi_app/views/ai_batch_page.dart';
import 'smoke_harness.dart';

void main() {
  setUpAll(smokeInitFfi);

  testWidgets('AiBatchPage：标题、连接设置与开始跑批', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);

    await smokePump(tester, smokeApp(db, const AiBatchPage()));

    expect(find.text('AI 跑批'), findsOneWidget);
    expect(find.text('连接设置'), findsOneWidget);
    expect(find.text('本轮进度'), findsOneWidget);
    expect(find.text('保存到本机'), findsOneWidget);
    expect(find.text('测试连接'), findsOneWidget);
    expect(find.text('开始跑批'), findsOneWidget);

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

    await smokePump(
      tester,
      ChangeNotifierProvider<AiBatchViewModel>.value(
        value: vm,
        child: const MaterialApp(home: AiBatchPage()),
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
    vm.dispose();
  });

  testWidgets('默认范围是「本篇」，切到「全库」会重算待办', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);

    final vm = AiBatchViewModel(
      vocab: VocabRepository(db),
      complete: (config, prompt) async => const AiReply.ok('正常'),
      prefsStore: PrefsStore.memory(),
    );

    await smokePump(
      tester,
      ChangeNotifierProvider<AiBatchViewModel>.value(
        value: vm,
        child: const MaterialApp(home: AiBatchPage()),
      ),
    );

    expect(find.text('跑批范围'), findsOneWidget);
    expect(find.text('本篇'), findsOneWidget);
    expect(find.text('全库'), findsOneWidget);
    expect(vm.scope, AiScope.article);

    await tester.tap(find.text('全库'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump();

    expect(vm.scope, AiScope.all);

    await smokeFinish(tester);
    vm.dispose();
  });
}
