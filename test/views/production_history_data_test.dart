// 产出历史页的派生数据：有记录时统计 / 分组要出得来。
//
// 之前这条视图只有「空库出空态」一个用例（`production_history_view_test.dart`），
// 统计卡、常错卡、逐题分组在测试里从未渲染过 —— 这里从「有记录」一侧补行为。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:dlaoshi_app/core/learning.dart';
import 'package:dlaoshi_app/core/production.dart';
import 'package:dlaoshi_app/core/production_task.dart';
import 'package:dlaoshi_app/core/writing_record.dart';
import 'package:dlaoshi_app/core/writing_record_json.dart';
import 'package:dlaoshi_app/core/writing_types.dart';
import 'package:dlaoshi_app/data/prefs_store.dart';
import 'package:dlaoshi_app/data/repositories/learning_repository.dart';
import 'package:dlaoshi_app/data/repositories/vocab_repository.dart';
import 'package:dlaoshi_app/viewmodels/production_view_model.dart';
import 'package:dlaoshi_app/views/production_history_view.dart';
import 'smoke_harness.dart';

/// 一条产出记录；两稿合起来平均分 85。
WritingRecord _record({
  required String at,
  required ProductionMode mode,
  required String text,
  required String topic,
  required int total,
}) {
  return WritingRecord(
    at: at,
    articleId: 'manual',
    text: text,
    feedback: WritingFeedback(
      scores: <WritingScore>[
        WritingScore(dimension: '意思到位', score: total, max: 100),
      ],
      total: total,
      max: 100,
      summary: '还行',
    ),
    task: ProductionTask(
      task: '$topic 的题目',
      mode: mode,
      topic: topic,
      goal: '说明进度',
      promptId: 'p-${mode.name}',
      sessionId: 's-${mode.name}',
    ),
    source: WritingSource.production,
  );
}

void main() {
  setUpAll(smokeInitFfi);

  testWidgets('有记录：总览 / 逐题记录 / 吃法筛选都渲染出来', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);
    final vocab = VocabRepository(db);
    final learning = LearningRepository(db);
    final vm = ProductionViewModel(
      vocab: vocab,
      learning: learning,
      prefsStore: PrefsStore.memory(),
    );
    addTearDown(vm.dispose);

    await tester.runAsync(() async {
      final data = await learning.load();
      data.writingHistory = writingRecordsToJson(<WritingRecord>[
        _record(
          at: '2026-11-09T02:00:00.000Z',
          mode: ProductionMode.full,
          text: 'I will follow up with the client.',
          topic: '面试',
          total: 80,
        ),
        _record(
          at: '2026-11-10T02:00:00.000Z',
          mode: ProductionMode.skim,
          text: 'I went to the interview yesterday.',
          topic: '面试',
          total: 90,
        ),
      ]);
      await learning.writeSection(data, LearningSection.writingHistory);
      await vm.bootstrap();
    });

    await smokePump(
      tester,
      ChangeNotifierProvider<ProductionViewModel>.value(
        value: vm,
        child: const MaterialApp(
          home: Scaffold(body: SafeArea(child: ProductionHistoryView())),
        ),
      ),
    );

    // 空态不该再出现，三块内容都要在。
    expect(find.text('还没有产出记录。练几题，这里就会有统计。'), findsNothing);
    expect(find.text('总览'), findsOneWidget);
    expect(find.text('逐题记录'), findsOneWidget);
    // 两稿平均 (80 + 90) / 2 = 85.0。
    expect(find.text('85.0'), findsOneWidget);
    // 吃法筛选：全部 + 全脂 + 脱脂奶。
    expect(find.text('全部'), findsOneWidget);
    expect(find.text(productionModeLabel[ProductionMode.full]!), findsWidgets);
    expect(find.text(productionModeLabel[ProductionMode.skim]!), findsWidgets);

    await smokeFinish(tester);
  });
}
