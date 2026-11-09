import 'dart:convert';

import 'package:dlaoshi_app/core/activity/activity.dart';
import 'package:dlaoshi_app/core/writing.dart';
import 'package:dlaoshi_app/core/writing_history.dart';
import 'package:dlaoshi_app/core/writing_record_json.dart';
import 'package:dlaoshi_app/data/db/migrations.dart';
import 'package:dlaoshi_app/data/prefs_store.dart';
import 'package:dlaoshi_app/data/repositories/learning_repository.dart';
import 'package:dlaoshi_app/viewmodels/writing_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Database> _openMem() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  await ensureSchema(db);
  return db;
}

/// 一份合法的仿写任务回包。
const String _taskJson = '{"task":"写一句关于跟进的话","model":"I will follow up with the client.",'
    '"structure":"will + 动词原形","mustUse":["follow up"],'
    '"rubric":[{"dimension":"语法准确","weight":40,"description":"硬错"}]}';

/// 一份合法的 v2 批改回包。
String _feedbackJson({int total = 80}) => '{"version":2,'
    '"scores":[{"dimension":"意思到位","score":$total,"max":100}],'
    '"total":$total,"max":100,'
    '"issues":[{"original":"follow up with","suggestion":"follow up on",'
    '"rule":"chunk-sense","key":"follow-up","reason":"介词","severity":"must-fix"}],'
    '"recommendations":[],"polished":"","summary":"不错"}';

void main() {
  late Database db;
  late LearningRepository learningRepo;
  late PrefsStore store;
  late WritingViewModel vm;

  setUp(() async {
    db = await _openMem();
    learningRepo = LearningRepository(db);
    store = PrefsStore.memory();
    vm = WritingViewModel(learning: learningRepo, prefsStore: store);
    await vm.bootstrap();
  });

  tearDown(() async {
    vm.dispose();
    await db.close();
  });

  group('范句与草稿', () {
    test('bootstrap 后是空草稿，没有任务也没有批改', () {
      expect(vm.model, '');
      expect(vm.text, '');
      expect(vm.task, isNull);
      expect(vm.feedback, isNull);
      expect(vm.error, isNull);
    });

    test('没范句时拼提示词报错并返回 null', () {
      expect(vm.buildTaskPrompt(), isNull);
      expect(vm.error, '先选一句范句');
    });

    test('改范句会清掉上一次的任务与批改', () {
      vm.setModel('I will follow up with the client.');
      expect(vm.applyTask(_taskJson), isNull);
      expect(vm.task, isNotNull);
      vm.setModel('Another sentence.');
      expect(vm.task, isNull);
      expect(vm.feedback, isNull);
    });

    test('草稿落盘：换一个 ViewModel 能读回范句 / 作答 / 任务', () async {
      vm.setModel('I will follow up with the client.');
      vm.setText('I will follow up with him.');
      expect(vm.applyTask(_taskJson), isNull);
      final again = WritingViewModel(learning: learningRepo, prefsStore: store);
      await again.bootstrap();
      expect(again.model, 'I will follow up with the client.');
      expect(again.text, 'I will follow up with him.');
      expect(again.task?.task, '写一句关于跟进的话');
      expect(again.task?.mustUse, <String>['follow up']);
      again.dispose();
    });

    test('没范句也能改作答（作答不依赖任务）', () {
      vm.setText('hello');
      expect(vm.text, 'hello');
      expect(vm.error, isNull);
    });
  });

  group('出题与批改', () {
    test('拼出的出题提示词带范句与必须用上的词', () {
      vm.setModel('I will follow up with the client.');
      vm.setMustUse(<String>['follow up']);
      final prompt = vm.buildTaskPrompt();
      expect(prompt, isNotNull);
      expect(prompt!, contains('I will follow up with the client.'));
      expect(prompt, contains('follow up'));
      expect(prompt, contains('JSON'));
    });

    test('粘回坏 JSON 报错且不改任务', () {
      vm.setModel('m');
      expect(vm.applyTask('{oops'), '没认出任务 JSON；请确认粘的是 {"task":...} 那个对象');
      expect(vm.task, isNull);
    });

    test('没任务时拼批改提示词报错', () {
      expect(vm.buildFeedbackPrompt(), isNull);
      expect(vm.error, '先生成仿写任务');
    });

    test('有任务但没作答时拼批改提示词报错', () {
      vm.setModel('m');
      vm.applyTask(_taskJson);
      expect(vm.buildFeedbackPrompt(), isNull);
      expect(vm.error, '先写点东西再批改');
    });

    test('粘回批改：记一条记录并落库，来源是普通仿写', () async {
      vm.setModel('I will follow up with the client.');
      vm.setText('I will follow up with him.');
      vm.applyTask(_taskJson);
      expect(await vm.applyFeedback(_feedbackJson()), isNull);
      expect(vm.feedback?.total, 80);
      expect(vm.feedback?.issues, hasLength(1));
      expect(vm.history, hasLength(1));
      final rec = vm.history.single;
      expect(rec.source, WritingSource.writing);
      expect(rec.articleId, 'manual');
      expect(rec.text, 'I will follow up with him.');
      // 真的进库了：从库里读回来还在。
      final reloaded = writingRecordsFromJson(
        (await learningRepo.load()).writingHistory,
      );
      expect(reloaded, hasLength(1));
      expect(reloaded.single.text, 'I will follow up with him.');
    });

    test('粘回坏批改报错且不落库', () async {
      vm.setModel('m');
      vm.setText('t');
      vm.applyTask(_taskJson);
      expect(await vm.applyFeedback('{oops'), '没认出批改 JSON；请确认粘的是 v2 批改结果');
      expect(vm.history, isEmpty);
    });

    test('首稿不带上一稿的问题', () async {
      vm.setModel('m');
      vm.setText('I will follow up with him.');
      vm.applyTask(_taskJson);
      await vm.applyFeedback(_feedbackJson());
      final prompt = vm.buildFeedbackPrompt();
      expect(prompt, isNotNull);
      expect(prompt!, isNot(contains('上一稿批改指出过')));
    });

    test('第 2 稿：上一稿的问题会进批改提示词', () async {
      // 先落一条带 round=2 任务的记录，再载入表单（parseImitationTask 不认 round，
      // 只有记录里的 task 才有）。
      final rec = WritingRecord(
        at: '2026-11-09T00:00:00.000Z',
        articleId: 'manual',
        text: 'I will follow up with him.',
        feedback: writingFeedbackFromJson(jsonDecode(_feedbackJson())),
        task: const ImitationTask(
          task: '写一句关于跟进的话',
          model: 'm',
          mustUse: <String>['follow up'],
          round: 2,
        ),
      );
      vm.loadRecord(rec);
      final prompt = vm.buildFeedbackPrompt();
      expect(prompt, isNotNull);
      expect(prompt!, contains('上一稿批改指出过'));
      expect(prompt, contains('follow up on'));
    });
  });

  group('历史筛选与清除', () {
    Future<void> seed() async {
      vm.setArticleContext('A', articleTitle: '第一篇');
      vm.setModel('m');
      vm.setText('t');
      vm.applyTask(_taskJson);
      await vm.applyFeedback(_feedbackJson(total: 70));
    }

    test('本篇 / 全库计数', () async {
      await seed();
      // 默认 scope=all：全库都能看到。
      expect(vm.historyCounts[WritingHistorySource.all], 1);
      // 切到本篇，按当前挂的文章算。
      vm.setFilter(
        const WritingHistoryFilter(scope: WritingHistoryScope.article),
      );
      vm.setArticleContext('A');
      expect(vm.historyCounts[WritingHistorySource.all], 1);
      vm.setArticleContext('B');
      expect(vm.historyCounts[WritingHistorySource.all], 0);
    });

    test('筛选条件变了，filteredHistory 跟着变', () async {
      await seed();
      vm.setArticleContext('A');
      expect(vm.filteredHistory, hasLength(1));
      vm.setFilter(
        const WritingHistoryFilter(source: WritingHistorySource.production),
      );
      expect(vm.filteredHistory, isEmpty);
    });

    test('清历史：清掉当前范围并落库', () async {
      await seed();
      vm.setArticleContext('A');
      await vm.clearHistory();
      expect(vm.history, isEmpty);
      expect(vm.notice, '已清掉当前范围内的 1 条');
      final reloaded = writingRecordsFromJson(
        (await learningRepo.load()).writingHistory,
      );
      expect(reloaded, isEmpty);
    });

    test('载入一条历史记录：范句 / 作答 / 任务 / 批改一起回来', () async {
      await seed();
      vm.loadRecord(vm.history.single);
      expect(vm.model, 'm');
      expect(vm.text, 't');
      expect(vm.task?.task, '写一句关于跟进的话');
      expect(vm.feedback?.total, 70);
    });

    test('清错误与提示', () async {
      vm.buildTaskPrompt();
      expect(vm.error, isNotNull);
      vm.clearNotice();
      expect(vm.error, isNull);
    });
  });

  group('落库口径：去重、活动、校验原文', () {
    Future<void> write() async {
      vm.setModel('I will follow up with the client.');
      vm.setText('I will follow up with him.');
      vm.applyTask(_taskJson);
      await vm.applyFeedback(_feedbackJson());
    }

    test('重复粘回同一份批改：只留一条，不重复记账', () async {
      await write();
      await vm.applyFeedback(_feedbackJson());
      await vm.applyFeedback(_feedbackJson());
      expect(vm.history, hasLength(1));
      final data = await learningRepo.load();
      expect(
        writingRecordsFromJson(data.writingHistory),
        hasLength(1),
      );
      expect(
        data.activity.fold<int>(
          0,
          (int sum, DayActivity d) => sum + d.countOf(ActivityCat.write),
        ),
        1,
      );
    });

    test('落一条真的「写」活动（照 Web recordActivity write）', () async {
      expect(vm.history, isEmpty);
      await write();
      final data = await learningRepo.load();
      expect(data.activity, isNotEmpty);
      expect(data.activity.last.countOf(ActivityCat.write), 1);
    });

    test('AI 编出来的 original（作答里没有那段字）会被丢掉', () async {
      vm.setModel('I will follow up with the client.');
      // 作答里没有 "follow up with"，只有 follow up on。
      vm.setText('I will follow up on him.');
      vm.applyTask(_taskJson);
      expect(await vm.applyFeedback(_feedbackJson()), isNull);
      expect(vm.history, hasLength(1));
      expect(vm.history.single.feedback.issues, isEmpty);
    });
  });
}
