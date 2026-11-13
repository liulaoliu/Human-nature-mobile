// 阅读页顶部的「AI-Batch Work」横条：默认收起、点开是进度 + 清单、开始跑批真的发请求。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:dlaoshi_app/core/ai_config.dart';
import 'package:dlaoshi_app/data/prefs_store.dart';
import 'package:dlaoshi_app/data/repositories/vocab_repository.dart';
import 'package:dlaoshi_app/models/vocab.dart';
import 'package:dlaoshi_app/services/ai_client.dart' show AiReply;
import 'package:dlaoshi_app/viewmodels/ai_batch_view_model.dart';
import 'package:dlaoshi_app/views/ai_batch_bar.dart';
import 'smoke_harness.dart';

const String _aid = 'a1';

/// 一篇收了一个缺释义的词。
Future<void> _seed(VocabRepository repo) async {
  await repo.save(VocabLibrary(
    items: <VocabItem>[
      VocabItem(
        id: 'vocab:run',
        word: 'run',
        lemma: 'run',
        createdAt: '2026-11-13T00:00:00.000Z',
        updatedAt: '2026-11-13T00:00:00.000Z',
      ),
    ],
    articleEntries: <ArticleVocabEntry>[
      ArticleVocabEntry(
        articleId: _aid,
        lemma: 'run',
        origin: VocabOrigin.manual,
        addedAt: '2026-11-13T00:00:00.000Z',
      ),
    ],
  ));
}

String get _table => 'run | /rʌn/ | v. | 跑步 | 用法 | 例句。 — 例句。 | def';

Widget _wrap(AiBatchViewModel vm) => ChangeNotifierProvider<AiBatchViewModel>.value(
      value: vm,
      child: const MaterialApp(
        home: Scaffold(body: SafeArea(child: AiBatchBar(articleId: _aid))),
      ),
    );

void main() {
  setUpAll(smokeInitFfi);

  testWidgets('默认收起：只有一行摘要，没有进度条和按钮', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);
    final repo = VocabRepository(db);
    await tester.runAsync(() => _seed(repo));

    final vm = AiBatchViewModel(
      vocab: repo,
      complete: (config, prompt) async => AiReply.ok(_table),
      prefsStore: PrefsStore.memory(),
    );
    addTearDown(vm.dispose);

    await smokePump(tester, _wrap(vm));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await tester.pump();

    expect(find.textContaining('AI-Batch Work'), findsOneWidget);
    // 收起状态下这些都不在。
    expect(find.text('开始跑批'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('任务清单'), findsNothing);

    await smokeFinish(tester);
  });

  testWidgets('点开：进度、开始按钮、任务清单都出来', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);
    final repo = VocabRepository(db);
    await tester.runAsync(() => _seed(repo));

    final vm = AiBatchViewModel(
      vocab: repo,
      complete: (config, prompt) async => AiReply.ok(_table),
      prefsStore: PrefsStore.memory(),
    );
    addTearDown(vm.dispose);

    await smokePump(tester, _wrap(vm));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('ai-batch-toggle')));
    await tester.pump();

    expect(find.text('开始跑批'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('任务清单'), findsOneWidget);
    expect(vm.jobs, hasLength(1));

    await smokeFinish(tester);
  });

  testWidgets('点「开始跑批」真的发请求，词都带上释义', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);
    final repo = VocabRepository(db);
    await tester.runAsync(() => _seed(repo));

    final prompts = <String>[];
    final vm = AiBatchViewModel(
      vocab: repo,
      complete: (config, prompt) async {
        prompts.add(prompt);
        return AiReply.ok(_table);
      },
      prefsStore: PrefsStore.memory(),
    );
    addTearDown(vm.dispose);
    await vm.updateConfig(const AiConfig(apiKey: 'sk-test'));

    await smokePump(tester, _wrap(vm));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('ai-batch-toggle')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('ai-batch-run')));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 120)));
    await tester.pump();

    expect(prompts, hasLength(1));
    expect(vm.outcome.doneCount, 1);
    final library = await tester.runAsync(() => repo.load());
    final byWord = <String, VocabItem>{
      for (final it in library!.items) it.word: it,
    };
    expect(byWord['run']?.meaning, '跑步');

    await smokeFinish(tester);
  });

  testWidgets('没填 key：点开始给出提示，不发请求', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);
    final repo = VocabRepository(db);
    await tester.runAsync(() => _seed(repo));

    final prompts = <String>[];
    final vm = AiBatchViewModel(
      vocab: repo,
      complete: (config, prompt) async {
        prompts.add(prompt);
        return AiReply.ok(_table);
      },
      prefsStore: PrefsStore.memory(),
    );
    addTearDown(vm.dispose);

    await smokePump(tester, _wrap(vm));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('ai-batch-toggle')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('ai-batch-run')));
    await tester.pump();

    expect(prompts, isEmpty);
    expect(vm.error, contains('API key'));

    await smokeFinish(tester);
  });
}
