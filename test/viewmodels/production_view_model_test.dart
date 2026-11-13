import 'package:dlaoshi_app/core/activity/activity.dart';
import 'package:dlaoshi_app/core/ai_config.dart';
import 'package:dlaoshi_app/core/production.dart';
import 'package:dlaoshi_app/core/production_history.dart';
import 'package:dlaoshi_app/core/production_prompts.dart';
import 'package:dlaoshi_app/core/production_task.dart';
import 'package:dlaoshi_app/core/writing_record.dart';
import 'package:dlaoshi_app/core/writing_record_json.dart';
import 'package:dlaoshi_app/data/db/migrations.dart';
import 'package:dlaoshi_app/data/prefs_store.dart';
import 'package:dlaoshi_app/data/repositories/learning_repository.dart';
import 'package:dlaoshi_app/data/repositories/vocab_repository.dart';
import 'package:dlaoshi_app/models/vocab.dart';
import 'package:dlaoshi_app/services/ai_client.dart';
import 'package:dlaoshi_app/viewmodels/production_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/vocab_fixture.dart';

Future<Database> _openMem() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  await ensureSchema(db);
  return db;
}

/// 四个有释义的词条，够选目标块。
List<VocabItem> _words() => [
      vocabItem(id: 'v1', word: 'follow up', meaning: '跟进'),
      vocabItem(id: 'v2', word: 'set aside', meaning: '留出'),
      vocabItem(id: 'v3', word: 'run into', meaning: '偶遇'),
      vocabItem(id: 'v4', word: 'come up with', meaning: '想出'),
    ];

/// 一份合法的「纯主题题」AI 回包。
String _topicPack({int count = 2}) {
  final prompts = <String>[
    for (var i = 1; i <= count; i++)
      '{"zh":"第 $i 个情境","goal":"说明进度"}',
  ];
  return '{"prompts":[${prompts.join(',')}]}';
}

/// 一份合法的「目标块题」AI 回包（每题 2 个目标块，用完 4 个）。
String _packWithTargets(List<ProductionTarget> targets) {
  final ids = <String>[for (final t in targets) '"${t.id}"'];
  return '{"prompts":['
      '{"zh":"跟进一下进度","goal":"说明进度","targetIds":[${ids[0]},${ids[1]}],"model":"I will follow up and set aside time."},'
      '{"zh":"说说你碰上的事","goal":"讲一件事","targetIds":[${ids[2]},${ids[3]}],"model":"I ran into him and came up with a plan."}'
      ']}';
}

/// 一份合法的 v2 批改回包。
String _feedbackJson({int total = 80}) => '{"version":2,'
    '"scores":[{"dimension":"意思到位","score":$total,"max":100}],'
    '"total":$total,"max":100,'
    '"issues":[],"recommendations":[],"polished":"","summary":"不错"}';

void main() {
  late Database db;
  late VocabRepository vocabRepo;
  late LearningRepository learningRepo;
  late PrefsStore store;
  late ProductionViewModel vm;

  setUp(() async {
    db = await _openMem();
    vocabRepo = VocabRepository(db);
    learningRepo = LearningRepository(db);
    store = PrefsStore.memory();
    vm = ProductionViewModel(
      vocab: vocabRepo,
      learning: learningRepo,
      prefsStore: store,
    );
    await vocabRepo.save(VocabLibrary(items: _words()));
    await vm.bootstrap();
  });

  tearDown(() async {
    vm.dispose();
    await db.close();
  });

  group('设置与选块', () {
    test('bootstrap 读出词库；默认是全脂 / 本篇 / 5 题 / 每题 2 块', () {
      expect(vm.library.items, hasLength(4));
      expect(vm.settings.mode, ProductionMode.full);
      expect(vm.settings.promptCount, 5);
      expect(vm.settings.targetsPerPrompt, 2);
      expect(vm.error, isNull);
    });

    test('改设置会落盘，换一个 ViewModel 能读回', () async {
      await vm.updateSettings(
        vm.settings.copyWith(mode: ProductionMode.skim, topic: '工作汇报'),
      );
      final again = ProductionViewModel(
        vocab: vocabRepo,
        learning: learningRepo,
        prefsStore: store,
      );
      await again.bootstrap();
      expect(again.settings.mode, ProductionMode.skim);
      expect(again.settings.topic, '工作汇报');
      again.dispose();
    });

    test('选目标块：范围 all 能选出 4 个（每题 2 块 × 2 题）', () {
      vm.updateSettings(
        vm.settings.copyWith(scope: ProductionScope.all, promptCount: 3),
      );
      // 3 题 × 2 块 = 6，但库里只有 4 个，所以给 4 个。
      expect(vm.buildTargets(), 4);
      expect(vm.pool.total, 4);
    });

    test('本篇范围没挂文章时选不出东西', () {
      vm.updateSettings(vm.settings.copyWith(scope: ProductionScope.article));
      expect(vm.buildTargets(), 0);
    });

    test('没选块就拼目标块提示词 → 报错并返回 null', () {
      expect(vm.buildPackPrompt(), isNull);
      expect(vm.error, contains('先点'));
    });
  });

  group('出题（目标块）', () {
    setUp(() async {
      await vm.updateSettings(
        vm.settings.copyWith(
          scope: ProductionScope.all,
          promptCount: 2,
          targetsPerPrompt: 2,
        ),
      );
      vm.buildTargets();
    });

    test('拼提示词带上候选清单与题数', () {
      final prompt = vm.buildPackPrompt()!;
      expect(prompt, contains('出 2 道题'));
      expect(prompt, contains('follow up'));
    });

    test('粘回合法的包 → 出 2 题、停在第 1 题、任务带上目标块', () {
      expect(vm.applyPack(_packWithTargets(vm.pool.targets)), isNull);
      expect(vm.session.prompts, hasLength(2));
      expect(vm.session.index, 0);
      expect(vm.session.task, isNotNull);
      expect(vm.session.task!.targets, hasLength(2));
      expect(vm.session.task!.mode, ProductionMode.full);
    });

    test('粘回坏 JSON → 报错且不改题目', () {
      final reason = vm.applyPack('这不是 JSON');
      expect(reason, contains('没认出'));
      expect(vm.session.prompts, isEmpty);
    });

    test('题数对不上 → 校验拦下', () {
      final bad = '{"prompts":[{"zh":"只有一题","goal":"x","targetIds":[]}]}';
      final reason = vm.applyPack(bad);
      expect(reason, isNotNull);
      expect(vm.session.prompts, isEmpty);
    });

    test('换题会清掉作答与批改；越界忽略', () {
      vm.applyPack(_packWithTargets(vm.pool.targets));
      vm.session.setAnswer('some answer');
      expect(vm.session.nextPrompt(), isTrue);
      expect(vm.session.index, 1);
      expect(vm.session.answer, '');
      expect(vm.session.prevPrompt(), isTrue);
      expect(vm.session.prevPrompt(), isFalse);
      vm.session.openPrompt(99);
      expect(vm.session.index, 0);
    });
  });

  group('出题（纯主题）', () {
    setUp(() async {
      await vm.updateSettings(vm.settings.copyWith(
        mode: ProductionMode.skim,
        topic: '面试',
        scope: ProductionScope.all,
        promptCount: 2,
        skimUseChunks: false,
      ));
    });

    test('不带词块时拼的是主题提示词（含主题与题数）', () {
      final prompt = vm.buildTopicPrompt();
      expect(prompt, contains('主题：面试'));
      expect(prompt, contains('出 2 道题'));
    });

    test('粘回主题包 → 出 2 题，题目没有目标块', () {
      expect(vm.applyPack(_topicPack()), isNull);
      expect(vm.session.prompts, hasLength(2));
      expect(vm.session.task!.targets, isEmpty);
      expect(vm.session.task!.mode, ProductionMode.skim);
    });
  });

  group('风味酸奶', () {
    setUp(() async {
      await vm.updateSettings(vm.settings.copyWith(
        mode: ProductionMode.yogurt,
        sourceText: '我去了学校。你来了吗？',
        referenceText: 'I went to school. Did you come?',
      ));
    });

    test('拆句配对：两句对两句，句数一致时没有 warning', () {
      final paired = vm.yogurtPairs()!;
      expect(paired.pairs, hasLength(2));
      expect(paired.warning, isEmpty);
    });

    test('编译成逐句题 + 整段题（默认带整段）', () {
      expect(vm.buildYogurt(), isNull);
      expect(vm.session.prompts, hasLength(3));
      expect(vm.session.prompts.first.goal, '逐句中译英');
      expect(vm.session.prompts.last.id, 'yogurt-paragraph');
      expect(vm.session.task!.answerLang, ProductionAnswerLang.en);
    });

    test('句数不一致时给 warning 并进 notice', () async {
      await vm.updateSettings(vm.settings.copyWith(
        sourceText: '我去了。你来了。他走了。',
        referenceText: 'I went.',
      ));
      vm.buildYogurt();
      expect(vm.notice, contains('句数不一致'));
    });

    test('重新拆句后按当前题原文找回同一句', () async {
      vm.buildYogurt();
      vm.session.openPrompt(1);
      final currentZh = vm.session.prompts[1].zh;
      vm.remapYogurt(<YogurtPair>[
        const YogurtPair(source: '新增的一句。', reference: 'A new one.'),
        YogurtPair(source: currentZh, reference: 'kept'),
      ]);
      expect(vm.session.index, 1);
      expect(vm.session.prompts[1].zh, currentZh);
    });
  });

  group('作答与批改', () {
    setUp(() async {
      await vm.updateSettings(vm.settings.copyWith(
        mode: ProductionMode.skim,
        topic: '面试',
        scope: ProductionScope.all,
        promptCount: 2,
        skimUseChunks: false,
      ));
      vm.applyPack(_topicPack());
    });

    test('没作答时拼批改提示词 → 报错', () {
      expect(vm.session.buildFeedbackPrompt(), isNull);
      expect(vm.error, contains('先写'));
    });

    test('作答后能拼出批改提示词（含学生原文）', () {
      vm.session.setAnswer('I went to the interview yesterday.');
      final prompt = vm.session.buildFeedbackPrompt()!;
      expect(prompt, contains('I went to the interview yesterday.'));
    });

    test('粘回批改 → 记一条记录并落库，重新读能拿到', () async {
      vm.session.setAnswer('I went to the interview yesterday.');
      expect(await vm.session.applyFeedback(_feedbackJson()), isNull);
      expect(vm.session.feedback!.total, 80);
      expect(vm.history, hasLength(1));
      final rec = vm.history.first;
      expect(rec.source, WritingSource.production);
      expect(rec.text, 'I went to the interview yesterday.');
      final saved = await learningRepo.load();
      final reloaded = writingRecordsFromJson(saved.writingHistory);
      expect(reloaded, hasLength(1));
      expect(reloaded.first.source, WritingSource.production);
      expect(reloaded.first.text, 'I went to the interview yesterday.');
      // 派生视图只认产出训练的稿子（仿写记录不算）。
      expect(productionRecords(reloaded), hasLength(1));
    });

    test('粘回坏批改 → 报错且不记录', () async {
      vm.session.setAnswer('anything');
      final reason = await vm.session.applyFeedback('不是 JSON');
      expect(reason, contains('没认出'));
      expect(vm.history, isEmpty);
    });

    test('同一稿重复粘回批改：只留一条，不重复记账', () async {
      vm.session.setAnswer('I went to the interview yesterday.');
      await vm.session.applyFeedback(_feedbackJson());
      await vm.session.applyFeedback(_feedbackJson());
      expect(vm.history, hasLength(1));
      final data = await learningRepo.load();
      expect(
        data.activity.fold<int>(
          0,
          (int sum, DayActivity d) => sum + d.countOf(ActivityCat.write),
        ),
        1,
      );
    });

    test('真写了才记「写」活动；跳过稿不记账', () async {
      vm.session.setAnswer('I went to the interview yesterday.');
      await vm.session.applyFeedback(_feedbackJson());
      var data = await learningRepo.load();
      expect(data.activity.last.countOf(ActivityCat.write), 1);

      // 跳到下一题、只记一条跳过稿：历史多一条，但活动不变。
      vm.session.nextPrompt();
      await vm.session.skipCurrent();
      expect(vm.history, hasLength(2));
      data = await learningRepo.load();
      expect(data.activity.last.countOf(ActivityCat.write), 1);
    });

    test('跳过这一题：记一条「跳过（未提交）」，稿数 +1', () async {
      vm.session.setAnswer('写了一半');
      expect(await vm.session.skipCurrent(), isTrue);
      expect(vm.session.round, 2);
      final rec = vm.history.first;
      expect(rec.feedback.summary, skippedProductionSummary);
      expect((rec.task as ProductionTask).skipped, isTrue);
      expect(rec.text, '写了一半');
    });

    test('重写：稿数 +1、作答清空、上一稿批改留作对照', () async {
      vm.session.setAnswer('第一稿');
      await vm.session.applyFeedback(_feedbackJson());
      vm.session.startRewrite();
      expect(vm.session.round, 2);
      expect(vm.session.answer, '');
      expect(vm.session.feedback, isNull);
      expect(vm.session.previousFeedback!.total, 80);
    });

    test('最多两稿：没批改不能重写，第 2 稿之后也不能再重写', () async {
      // 没批改就重写 = 白清作答，按钮得挡下来。
      vm.session.setAnswer('第一稿');
      expect(vm.session.canRewrite, isFalse);
      vm.session.startRewrite();
      expect(vm.session.round, 1);
      expect(vm.session.answer, '第一稿');

      await vm.session.applyFeedback(_feedbackJson());
      expect(vm.session.canRewrite, isTrue);
      vm.session.startRewrite();
      expect(vm.session.round, 2);

      // 第 2 稿批改完就是终点（对齐 Web `rewrite()` 的 round >= 2 上限）。
      vm.session.setAnswer('第二稿');
      await vm.session.applyFeedback(_feedbackJson(total: 90));
      expect(vm.session.canRewrite, isFalse);
      vm.session.startRewrite();
      expect(vm.session.round, 2);
      expect(vm.session.answer, '第二稿');
    });
  });

  group('草稿', () {
    setUp(() async {
      await vm.updateSettings(vm.settings.copyWith(
        mode: ProductionMode.skim,
        topic: '面试',
        scope: ProductionScope.all,
        promptCount: 2,
        skimUseChunks: false,
      ));
      vm.applyPack(_topicPack());
    });

    test('没题目时存草稿什么都不做', () async {
      final empty = ProductionViewModel(
        vocab: vocabRepo,
        learning: learningRepo,
        prefsStore: store,
      );
      await empty.bootstrap();
      await empty.saveDraft();
      expect(empty.drafts, isEmpty);
      empty.dispose();
    });

    test('存草稿 → 换 ViewModel 能续上（题目 / 题号 / 作答都在）', () async {
      vm.session.setAnswer('我写了一半');
      await vm.saveDraft();
      final again = ProductionViewModel(
        vocab: vocabRepo,
        learning: learningRepo,
        prefsStore: store,
      );
      await again.bootstrap();
      expect(again.resumableDraft, isNotNull);
      again.resumeDraft();
      expect(again.session.prompts, hasLength(2));
      expect(again.session.answer, '我写了一半');
      expect(again.session.task, isNotNull);
      again.dispose();
    });

    test('丢掉草稿后不再可续', () async {
      await vm.saveDraft();
      expect(vm.resumableDraft, isNotNull);
      await vm.discardDraft();

      expect(vm.resumableDraft, isNull);
    });

    test('不同吃法的草稿互不覆盖', () async {
      await vm.saveDraft();
      await vm.updateSettings(vm.settings.copyWith(mode: ProductionMode.full));
      expect(vm.resumableDraft, isNull);
      await vm.updateSettings(vm.settings.copyWith(mode: ProductionMode.skim));
      expect(vm.resumableDraft, isNotNull);
    });

    test('作答一动就自动存（防抖 250ms），切走回来还在这一题', () async {
      // 不点「暂停」：只改作答，等防抖过去。
      vm.session.setAnswer('自动存下来的半句');
      expect(vm.resumableDraft, isNull, reason: '还没到防抖时间，不写盘');
      await Future<void>.delayed(const Duration(milliseconds: 400));

      expect(vm.resumableDraft, isNotNull);
      final again = ProductionViewModel(
        vocab: vocabRepo,
        learning: learningRepo,
        prefsStore: store,
      );
      await again.bootstrap();
      again.resumeDraft();
      expect(again.session.answer, '自动存下来的半句');
      again.dispose();
    });

    test('自动保存不刷「已暂停」提示（那是手动暂停才说的话）', () async {
      vm.clearNotice();
      vm.session.setAnswer('悄悄存');
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(vm.notice, isNot(contains('已暂停')));
      expect(vm.resumableDraft, isNotNull);
    });
  });

  group('AI 直连（出题 / 批改）', () {
    late List<String> prompts;
    late AiReply Function(String prompt) reply;

    ProductionViewModel build() => ProductionViewModel(
          vocab: vocabRepo,
          learning: learningRepo,
          prefsStore: store,
          complete: (AiConfig _, String prompt) async {
            prompts.add(prompt);
            return reply(prompt);
          },
        );

    setUp(() async {
      prompts = <String>[];
      reply = (String _) => const AiReply.ok('{"prompts":[]}');
    });

    test('没配客户端：出题直接提示去设置，不发请求', () async {
      final bare = ProductionViewModel(
        vocab: vocabRepo,
        learning: learningRepo,
        prefsStore: store,
      );
      await bare.bootstrap();
      final reason = await bare.generateWithAi();
      expect(reason, contains('AI 跑批'));
      expect(bare.session.hasPrompts, isFalse);
      bare.dispose();
    });

    test('AI 出题：一次请求就把题拼出来（纯主题，不选块）', () async {
      final ai = build();
      await ai.bootstrap();
      await ai.updateSettings(ai.settings.copyWith(
        mode: ProductionMode.skim,
        topic: '面试',
        scope: ProductionScope.all,
        promptCount: 2,
        skimUseChunks: false,
      ));
      reply = (String _) => AiReply.ok(_topicPack());

      expect(await ai.generateWithAi(), isNull);
      expect(prompts, hasLength(1));
      expect(prompts.single, contains('面试'));
      expect(ai.session.hasPrompts, isTrue);
      expect(ai.session.prompts, hasLength(2));
      expect(ai.busy, isFalse);
      ai.dispose();
    });

    test('AI 出题：回复认不出来时报错，不塞半截题目进去', () async {
      final ai = build();
      await ai.bootstrap();
      await ai.updateSettings(ai.settings.copyWith(
        mode: ProductionMode.skim,
        topic: '面试',
        scope: ProductionScope.all,
        skimUseChunks: false,
      ));
      reply = (String _) => const AiReply.ok('抱歉，我不太明白');

      final reason = await ai.generateWithAi();
      expect(reason, contains('没认出'));
      expect(ai.session.hasPrompts, isFalse);
      ai.dispose();
    });

    test('AI 出题：网络失败把原因原样交给界面', () async {
      final ai = build();
      await ai.bootstrap();
      await ai.updateSettings(ai.settings.copyWith(
        mode: ProductionMode.skim,
        topic: '面试',
        scope: ProductionScope.all,
        skimUseChunks: false,
      ));
      reply = (String _) =>
          const AiReply.fail('key 不对（HTTP 401）', AiErrorKind.unauthorized);

      final reason = await ai.generateWithAi();
      expect(reason, contains('401'));
      expect(ai.error, contains('401'));
      ai.dispose();
    });

    test('AI 批改：回复直接走粘回同一条解析路径，落库一条记录', () async {
      final ai = build();
      await ai.bootstrap();
      await ai.updateSettings(ai.settings.copyWith(
        mode: ProductionMode.skim,
        topic: '面试',
        scope: ProductionScope.all,
        promptCount: 2,
        skimUseChunks: false,
      ));
      ai.applyPack(_topicPack());
      ai.session.setAnswer('I went to the interview yesterday.');
      reply = (String _) => AiReply.ok(_feedbackJson());

      expect(await ai.session.gradeWithAi(), isNull);
      expect(prompts, hasLength(1));
      expect(prompts.single, contains('I went to the interview yesterday.'));
      expect(ai.session.feedback!.total, 80);
      expect(ai.history, hasLength(1));
      expect(ai.history.first.source, WritingSource.production);
      expect(ai.session.aiBusy, isFalse);
      ai.dispose();
    });

    test('AI 批改：没作答时不发请求（交给手动粘贴那条路先写东西）', () async {
      final ai = build();
      await ai.bootstrap();
      await ai.updateSettings(ai.settings.copyWith(
        mode: ProductionMode.skim,
        topic: '面试',
        scope: ProductionScope.all,
        promptCount: 2,
        skimUseChunks: false,
      ));
      ai.applyPack(_topicPack());

      expect(await ai.session.gradeWithAi(), isNotNull);
      expect(prompts, isEmpty);
      expect(ai.history, isEmpty);
      ai.dispose();
    });

    test('AI 批改：回复不是 JSON 时报错，不落记录', () async {
      final ai = build();
      await ai.bootstrap();
      await ai.updateSettings(ai.settings.copyWith(
        mode: ProductionMode.skim,
        topic: '面试',
        scope: ProductionScope.all,
        promptCount: 2,
        skimUseChunks: false,
      ));
      ai.applyPack(_topicPack());
      ai.session.setAnswer('anything');
      reply = (String _) => const AiReply.ok('这是一段话，不是 JSON');

      final reason = await ai.session.gradeWithAi();
      expect(reason, contains('没认出'));
      expect(ai.history, isEmpty);
      expect(ai.session.aiBusy, isFalse);
      ai.dispose();
    });
  });
}
