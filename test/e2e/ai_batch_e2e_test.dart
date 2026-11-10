// 真机 / 真网络的端到端用例：`AiBatchViewModel` 从词库挑词 → 真调 DeepSeek →
// 解析 → 落库。和 1,700 多例离线测试不同，这一例真的往 api.deepseek.com 发请求。
//
// 默认跳过：只有设置了环境变量 `DLAOSHI_E2E_KEY` 才跑（key 不进仓库）。
//   pwsh: $env:DLAOSHI_E2E_KEY = '<你的 key>'; flutter test test/e2e
// 想换地址 / 模型：`DLAOSHI_E2E_BASE_URL` / `DLAOSHI_E2E_MODEL`。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:dlaoshi_app/core/ai_config.dart';
import 'package:dlaoshi_app/core/ai_jobs.dart' show AiScope;
import 'package:dlaoshi_app/data/db/migrations.dart';
import 'package:dlaoshi_app/data/prefs_store.dart';
import 'package:dlaoshi_app/data/repositories/vocab_repository.dart';
import 'package:dlaoshi_app/models/vocab.dart';
import 'package:dlaoshi_app/services/ai_client.dart';
import 'package:dlaoshi_app/viewmodels/ai_batch_view_model.dart';

String get _key => Platform.environment['DLAOSHI_E2E_KEY'] ?? '';
String get _baseUrl =>
    Platform.environment['DLAOSHI_E2E_BASE_URL'] ?? defaultAiBaseUrl;
String get _model => Platform.environment['DLAOSHI_E2E_MODEL'] ?? defaultAiModel;

/// 这批词挑得刻意：多音节、抽象、词性不同，容易暴露表格错列。
const List<String> _words = <String>[
  'scrutiny',
  'bailout',
  'stagnant',
  'leverage',
  'undermine',
];

VocabItem _item(String word) => VocabItem(
      id: 'vocab:$word',
      word: word,
      lemma: word,
      contexts: <VocabContext>[
        VocabContext(
          articleId: 'e2e',
          sentenceText: 'Regulators questioned the $word behind the bailout.',
          at: '2026-11-10T00:00:00.000Z',
        ),
      ],
      createdAt: '2026-11-10T00:00:00.000Z',
      updatedAt: '2026-11-10T00:00:00.000Z',
    );

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test(
    '[e2e] 真调 DeepSeek：挑缺释义的词 → 跑批 → 释义落进词库',
    () async {
      final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await ensureSchema(db);
      final vocab = VocabRepository(db);
      await vocab.save(VocabLibrary(items: _words.map(_item).toList()));

      final client = AiClient(timeout: const Duration(seconds: 120));
      addTearDown(client.close);
      final vm = AiBatchViewModel(
        vocab: vocab,
        complete: client.complete,
        prefsStore: PrefsStore.memory(),
      );
      addTearDown(vm.dispose);

      await vm.updateConfig(
        AiConfig(apiKey: _key, baseUrl: _baseUrl, model: _model),
      );
      await vm.bootstrap();
      // 这条用例不接 ArticleRepository（没有文章列表可挑），切到全库口径。
      await vm.setScope(AiScope.all);

      // 五个词都在一块里。
      expect(vm.jobs, hasLength(1));
      expect(vm.jobs.single.words.toSet(), _words.toSet());

      // 真请求。
      final reply = await vm.testConnection();
      expect(reply.isOk, isTrue, reason: '连接失败：${reply.error}');

      await vm.run();

      expect(vm.failedIds, isEmpty, reason: '失败的块：${vm.failedIds}');
      expect(vm.phase, AiBatchPhase.done);
      expect(vm.outcome.doneCount, 1);

      // 落库后重新读，每个词都该有释义（这是整条链路的验收点）。
      final after = (await vocab.load())!;
      final byWord = <String, VocabItem>{
        for (final it in after.items) it.lemma: it,
      };
      for (final w in _words) {
        final it = byWord[w];
        expect(it, isNotNull, reason: '$w 没进词库');
        expect(it!.meaning, isNotNull, reason: '$w 没拿到释义');
        expect(it.meaning!.trim(), isNotEmpty, reason: '$w 的释义是空串');
        expect(it.phonetic, isNotNull, reason: '$w 没拿到音标');
        expect(it.status, VocabStatus.queried, reason: '$w 状态没更新');
        // 来源标记要落成 ai，否则界面上分不清是 AI 还是人工填的。
        expect(it.fieldSources?[VocabField.meaning], VocabFieldSource.ai);
      }

      // 顺手把结果打出来，方便人眼扫一眼质量。
      // ignore: avoid_print
      print('── e2e 结果 ──');
      for (final w in _words) {
        final it = byWord[w]!;
        // ignore: avoid_print
        print('$w | ${it.phonetic} | ${it.partOfSpeech} | ${it.meaning}');
      }
    },
    skip: _key.isEmpty
        ? '没有 DLAOSHI_E2E_KEY，跳过真网络用例（这是默认行为）'
        : false,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
