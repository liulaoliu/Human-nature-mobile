import 'dart:convert';

import 'package:dlaoshi_app/core/activity/activity.dart' show ActivityCat;
import 'package:dlaoshi_app/core/drill_sentence.dart';
import 'package:dlaoshi_app/core/drill_sentence_draft.dart';
import 'package:dlaoshi_app/core/writing.dart';
import 'package:dlaoshi_app/core/writing_record_json.dart';
import 'package:dlaoshi_app/data/db/migrations.dart';
import 'package:dlaoshi_app/data/prefs_store.dart';
import 'package:dlaoshi_app/data/repositories/learning_repository.dart';
import 'package:dlaoshi_app/models/vocab.dart';
import 'package:dlaoshi_app/viewmodels/drill_sentence_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Database> _openMem() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  await ensureSchema(db);
  return db;
}

VocabItem _item(
  String id,
  String word, {
  String? meaning,
  List<String>? phrases,
  List<String>? idioms,
  List<String> usage = const <String>[],
}) =>
    VocabItem(
      id: id,
      word: word,
      lemma: word.toLowerCase(),
      meaning: meaning,
      phrases: phrases,
      idioms: idioms,
      usage: usage,
      createdAt: '2026-01-01T00:00:00Z',
      updatedAt: '2026-01-01T00:00:00Z',
    );

/// 一份合法的 v2 批改回包；`original` 必须逐字出现在作答里才能留下来。
String _feedbackJson({
  int total = 80,
  String original = 'follow up with',
  String suggestion = 'follow up on',
}) =>
    jsonEncode(<String, Object?>{
      'version': 2,
      'scores': <Object?>[
        <String, Object?>{'dimension': '意思到位', 'score': total, 'max': 100},
      ],
      'total': total,
      'max': 100,
      'issues': <Object?>[
        <String, Object?>{
          'original': original,
          'suggestion': suggestion,
          'rule': 'chunk-sense',
          'key': 'follow-up',
          'reason': '介词',
          'severity': 'must-fix',
        },
      ],
      'recommendations': <Object?>[],
      'polished': '',
      'summary': '不错',
    });

List<VocabItem> _items() => <VocabItem>[
      _item('a', 'follow up', meaning: '跟进'),
      _item('b', 'run into', meaning: '偶遇'),
      _item('c', 'set aside', meaning: '留出'),
    ];

List<({String? id, String itemId})> _results() =>
    <({String? id, String itemId})>[
      (id: null, itemId: 'a'),
      (id: null, itemId: 'b'),
      (id: null, itemId: 'c'),
    ];

void main() {
  late Database db;
  late LearningRepository learningRepo;
  late PrefsStore store;
  late DrillSentenceViewModel vm;

  setUp(() async {
    db = await _openMem();
    learningRepo = LearningRepository(db);
    store = PrefsStore.memory();
    vm = DrillSentenceViewModel(learning: learningRepo, prefsStore: store);
    await vm.bootstrap();
    vm.startBatch(_items(), _results(), DrillSentenceKind.memory,
        articleId: 'A1', articleTitle: '第一篇');
  });

  tearDown(() async {
    vm.dispose();
    await db.close();
  });

  group('开一轮与题目', () {
    test('startBatch 后题目数 = 素材数，批次身份稳定', () {
      expect(vm.hasTasks, isTrue);
      expect(vm.tasks, hasLength(3));
      expect(vm.points, hasLength(3));
      expect(vm.batchId, drillSentenceId(DrillSentenceKind.memory, vm.points));
      expect(vm.index, 0);
      expect(vm.round, 1);
      expect(vm.answer, '');
      expect(vm.feedback, isNull);
    });

    test('题目只要求用上本轮那一个词，focus 是稳定身份', () {
      final t = vm.task!;
      expect(t.mustUse, <String>['follow up']);
      expect(t.model, '');
      expect(t.focus, drillTaskIdOf(t));
      expect(t.task, contains('follow up'));
    });

    test('同一组内容换顺序，批次身份不变', () {
      final id = vm.batchId;
      vm.startBatch(_items(), _results().reversed.toList(),
          DrillSentenceKind.memory);
      expect(vm.batchId, id);
    });

    test('素材为空时没有题可做，也不报错', () {
      vm.startBatch(<VocabItem>[], <({String? id, String itemId})>[],
          DrillSentenceKind.memory);
      expect(vm.hasTasks, isFalse);
      expect(vm.task, isNull);
      expect(vm.index, 0);
    });
  });

  group('按题存草稿', () {
    test('切题不丢别的题的作答', () {
      vm.setAnswer('I will follow up with the client.');
      vm.openTask(1);
      expect(vm.answer, '');
      vm.setAnswer('I ran into an old friend.');
      vm.openTask(0);
      expect(vm.answer, 'I will follow up with the client.');
      vm.openTask(1);
      expect(vm.answer, 'I ran into an old friend.');
    });

    test('换一个 ViewModel 能读回停在哪题与各题作答', () async {
      vm.setAnswer('first answer');
      vm.openTask(2);
      vm.setAnswer('third answer');
      final again =
          DrillSentenceViewModel(learning: learningRepo, prefsStore: store);
      await again.bootstrap();
      again.startBatch(_items(), _results(), DrillSentenceKind.memory);
      expect(again.index, 2);
      expect(again.answer, 'third answer');
      again.openTask(0);
      expect(again.answer, 'first answer');
      again.dispose();
    });

    test('换批次时只保留同题 id 的作答', () async {
      vm.setAnswer('keep me');
      // 少一个词条 → 不同批次身份
      final fewer = _results().sublist(0, 2);
      vm.startBatch(_items(), fewer, DrillSentenceKind.memory);
      expect(vm.batchId, isNot(drillSentenceId(DrillSentenceKind.memory,
          drillSentencePoints(_items(), _results(), DrillSentenceKind.memory))));
      expect(vm.answer, 'keep me'); // 第 1 题还在这一轮里
      expect(vm.tasks, hasLength(2));
    });

    test('清空这一轮草稿后作答与批改都没了', () async {
      vm.setAnswer('something');
      await vm.clearDraft();
      expect(vm.answer, '');
      expect(vm.feedback, isNull);
      expect(vm.draft.answers, isEmpty);
      expect(vm.notice, contains('已清空'));
    });
  });

  group('出题与批改', () {
    test('没作答时拼批改提示词报错并返回 null', () {
      expect(vm.buildFeedbackPrompt(), isNull);
      expect(vm.error, '先写点东西再批改');
    });

    test('拼出的批改提示词带题目与作答', () {
      vm.setAnswer('I will follow up with the client.');
      final prompt = vm.buildFeedbackPrompt();
      expect(prompt, isNotNull);
      expect(prompt, contains('follow up'));
      expect(prompt, contains('I will follow up with the client.'));
      expect(vm.error, isNull);
    });

    test('粘回批改 → 记一条 drillSentence 记录并落库，反馈跟着题走', () async {
      vm.setAnswer('I will follow up with the client.');
      expect(await vm.applyFeedback(_feedbackJson()), isNull);
      expect(vm.feedback, isNotNull);
      expect(vm.feedback!.total, 80);
      expect(vm.feedback!.issues, hasLength(1));

      final data = await learningRepo.load();
      final records = writingRecordsFromJson(data.writingHistory);
      expect(records, hasLength(1));
      expect(records.single.source, WritingSource.drillSentence);
      expect(records.single.task?.focus, drillTaskIdOf(vm.task!));
      expect(vm.history, hasLength(1));
    });

    test('重复粘回同题同稿同文字不刷历史', () async {
      vm.setAnswer('I will follow up with the client.');
      expect(await vm.applyFeedback(_feedbackJson()), isNull);
      expect(await vm.applyFeedback(_feedbackJson()), isNull);
      expect(vm.history, hasLength(1));
    });

    test('非法批改 JSON 返回中文原因，不落库', () async {
      vm.setAnswer('I will follow up with the client.');
      final reason = await vm.applyFeedback('not json');
      expect(reason, isNotNull);
      expect(reason, contains('没解析出批改结果'));
      expect(vm.history, isEmpty);
      expect(vm.feedback, isNull);
    });

    test('批改落库同时给今天的「写」活动 +1', () async {
      vm.setAnswer('I will follow up with the client.');
      await vm.applyFeedback(_feedbackJson());
      final data = await learningRepo.load();
      expect(data.activity, hasLength(1));
      expect(data.activity.single.countOf(ActivityCat.write), 1);
    });

    test('批改结果按题隔离：切到别的题不显示上一题的分数', () async {
      vm.setAnswer('I will follow up with the client.');
      await vm.applyFeedback(_feedbackJson());
      vm.openTask(1);
      expect(vm.feedback, isNull);
      vm.openTask(0);
      expect(vm.feedback!.total, 80);
    });
  });

  group('重写与第 2 稿', () {
    test('批过之后才能重写，且只到 2 稿', () async {
      expect(vm.canRewrite, isFalse);
      vm.setAnswer('I will follow up with the client.');
      await vm.applyFeedback(_feedbackJson());
      expect(vm.canRewrite, isTrue);
      vm.rewrite();
      expect(vm.round, 2);
      expect(vm.answer, 'I will follow up with the client.'); // 作答保留
      expect(vm.canRewrite, isFalse);
    });

    test('第 2 稿的批改提示词带上「上一稿指出过」', () async {
      vm.setAnswer('I will follow up with the client.');
      await vm.applyFeedback(_feedbackJson());
      vm.rewrite();
      vm.setAnswer('I will follow up on the client.');
      final prompt = vm.buildFeedbackPrompt();
      expect(prompt, contains('上一稿批改指出过'));
      expect(prompt, contains('follow up on'));
    });

    test('第 2 稿再粘回会记第 2 条记录（稿数不同）', () async {
      vm.setAnswer('I will follow up with the client.');
      await vm.applyFeedback(_feedbackJson());
      vm.rewrite();
      vm.setAnswer('I will follow up on the client.');
      expect(await vm.applyFeedback(_feedbackJson(
        total: 90,
        original: 'follow up with the client',
        suggestion: 'follow up on the client',
      )), isNull);
      expect(vm.history, hasLength(2));
    });
  });
}
