import 'dart:convert';

import 'package:dlaoshi_app/core/activity/activity.dart';
import 'package:dlaoshi_app/core/answer_events.dart';
import 'package:dlaoshi_app/core/goals.dart';
import 'package:dlaoshi_app/core/kind_stats.dart';
import 'package:dlaoshi_app/core/learning.dart';
import 'package:dlaoshi_app/core/mistakes.dart';
import 'package:dlaoshi_app/core/practice.dart';
import 'package:dlaoshi_app/core/vocab_stats.dart';
import 'package:dlaoshi_app/data/db/learning_json.dart';
import 'package:dlaoshi_app/data/db/migrations.dart';
import 'package:dlaoshi_app/data/repositories/learning_repository.dart';
import 'package:dlaoshi_app/models/listening.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Database> _openMem() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  await ensureSchema(db);
  return db;
}

/// 一份「每段都有内容」的学习记录。
///
/// 各段只放一条（或少数几条按读回的顺序排好），这样下面的往返断言可以用
/// `learningSectionJson` 直接做深比较，而不用逐字段手写 —— 顺序错、默认值错、
/// 少一个键都会当场挂。
LearningData _sample() => LearningData(
      practice: <PracticeRecord>[
        const PracticeRecord(
          at: '2026-11-01T01:00:00.000Z',
          kind: PracticeKind.quiz,
          total: 10,
          correct: 7,
          seconds: 120,
          articleId: 'a1',
        ),
        const PracticeRecord(
          at: '2026-11-02T02:00:00.000Z',
          kind: PracticeKind.dictation,
          total: 5,
          correct: 5,
        ),
      ],
      // 读侧是 `ORDER BY at DESC`（照 Web 口径），所以样例本身就按新→旧摆，
      // 这样「写进去什么顺序、读回来什么顺序」才是逐段深比较的前提。
      mistakes: <MistakeEntry>[
        MistakeEntry(
          id: 'listen:q1',
          kind: MistakeKind.listen,
          at: '2026-11-04T04:00:00.000Z',
          count: 1,
          label: '听力第 1 题',
          question: const ListeningQuestion(
            id: 'q1',
            type: ListeningQType.mcq,
            stem: 'What is it?',
            options: <String>['A thing', 'A place'],
            answer: 'A thing',
            accept: <String>['thing'],
          ),
          articleId: 'a1',
          text: 'A thing',
        ),
        MistakeEntry(
          id: 'vocab:v1',
          kind: MistakeKind.vocab,
          at: '2026-11-03T03:00:00.000Z',
          count: 2,
          label: 'alpha',
          itemId: 'v1',
          articleId: 'a1',
        ),
      ],
      readDone: <ReadDone>[
        const ReadDone(
          day: '2026-11-01',
          articleId: 'a1',
          title: 'Global Growth',
          at: '2026-11-01T05:00:00.000Z',
        ),
      ],
      writingHistory: <Map<String, Object?>>[
        <String, Object?>{
          'at': '2026-11-02T06:00:00.000Z',
          'articleId': 'a1',
          'model': '请用 slowing 造句。',
          'text': 'Growth is slowing down.',
          'feedback': <String, Object?>{'score': 8, 'notes': <String>['还行']},
          'source': 'drillSentence',
          'sentenceId': 's1',
        },
      ],
      backTranslations: <Map<String, Object?>>[
        <String, Object?>{
          'id': 'bt:1',
          'at': '2026-11-03T07:00:00.000Z',
          'articleId': 'a1',
          'sentenceId': 's1',
          'sourceZh': '增长正在放缓。',
          'answer': 'Growth is slowing.',
          'reference': 'Growth is slowing down.',
          'feedback': <String, Object?>{'comment': '漏了 down'},
          'closeness': <String, Object?>{'exact': false, 'ratio': 0.75},
          'articleTitle': 'Global Growth',
          'gradedBy': 'ai',
        },
      ],
      retells: <RetellRecord>[
        const RetellRecord(
          at: '2026-11-04T08:00:00.000Z',
          articleId: 'a1',
          text: 'Global growth is slowing.',
          words: 5,
        ),
      ],
      activity: <DayActivity>[
        DayActivity(day: '2026-11-01', counts: <ActivityCat, int>{
          ActivityCat.read: 3,
          ActivityCat.vocab: 5,
        }),
        DayActivity(day: '2026-11-02', counts: <ActivityCat, int>{
          ActivityCat.write: 1,
        }),
      ],
      studyDays: <StudyDay>[
        const StudyDay(day: '2026-11-01', seconds: 600, cards: 20),
        const StudyDay(day: '2026-11-02', seconds: 300, cards: 10),
      ],
      sessions: <PickSession>[
        const PickSession(at: '2026-11-01T09:00:00.000Z', seconds: 90, picked: 8),
        const PickSession(at: '2026-11-02T09:00:00.000Z', seconds: 60, picked: 5),
      ],
      studiedDays: <StudiedDay>[
        const StudiedDay(day: '2026-11-01', ids: <String>['v1', 'v2', 'v3']),
        const StudiedDay(day: '2026-11-02', ids: <String>['v2']),
      ],
      skimmed: <String>['a1', 'a2'],
      kindStats: <String, Map<String, KindStat>>{
        'a1': <String, KindStat>{
          'cloze': const KindStat(total: 10, correct: 7),
          'spell': const KindStat(total: 5, correct: 3),
        },
      },
      answerEvents: <AnswerEvent>[
        const AnswerEvent(
          at: '2026-11-01T10:00:00.000Z',
          day: '2026-11-01',
          articleId: 'a1',
          source: PracticeKind.quiz,
          kind: 'cloze',
          cat: ActivityCat.vocab,
          correct: true,
          questionId: 'q1',
        ),
        const AnswerEvent(
          at: '2026-11-01T10:01:00.000Z',
          day: '2026-11-01',
          articleId: 'a1',
          source: PracticeKind.dictation,
          kind: 'dictation',
          cat: ActivityCat.listen,
          correct: false,
        ),
      ],
      goldenDrills: <Map<String, Object?>>[
        <String, Object?>{
          'id': 'gd:1',
          'at': '2026-11-02T11:00:00.000Z',
          'articleId': 'a1',
          'sentenceId': 's1',
          'drillKey': 's1|0',
          'fillTries': 3,
          'assembleTries': 2,
          'recallTries': 1,
          'mastered': true,
          'completedAt': '2026-11-03T00:00:00.000Z',
        },
      ],
      writingErrorProgress: <Map<String, Object?>>[
        <String, Object?>{
          'id': 'we:1',
          'rule': 'article',
          'key': 'a|the',
          'articleId': 'a1',
          'original': 'the growth',
          'suggestion': 'growth',
          'status': 'paused',
          'streak': 2,
          'reviews': 4,
          'lastCorrect': true,
          'createdAt': '2026-11-01T00:00:00.000Z',
          'updatedAt': '2026-11-04T00:00:00.000Z',
        },
      ],
      productionProgress: <Map<String, Object?>>[
        <String, Object?>{
          'key': 'phrase:slow down',
          'kind': 'phrase',
          'text': 'slow down',
          'meaning': '放慢',
          'attempts': 3,
          'hits': 2,
          'misses': 1,
          'streak': 1,
          'lastAt': '2026-11-05T00:00:00.000Z',
          'dueAt': '2026-11-06T00:00:00.000Z',
          'lastMode': 'recall',
          'updatedAt': '2026-11-05T00:00:00.000Z',
        },
      ],
    );

void main() {
  late Database db;
  late LearningRepository repo;

  setUp(() async {
    db = await _openMem();
    repo = LearningRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('读写往返', () {
    test('空库读回空记录，hasRows 为 false', () async {
      final empty = await repo.load();
      expect(hasLearningData(empty), isFalse);
      expect(await repo.hasRows(), isFalse);
    });

    test('16 段逐段往返，形状与顺序都对', () async {
      final input = _sample();
      await repo.writeAll(input);

      expect(await repo.hasRows(), isTrue);
      final loaded = await repo.load();
      for (final key in LearningSection.values) {
        expect(
          learningSectionJson(loaded, key),
          equals(learningSectionJson(input, key)),
          reason: '${key.name} 往返不一致',
        );
      }
    });

    test('答题事件与写侧的事件 id 无关：同一毫秒去重后不重复', () async {
      await repo.writeAll(_sample());
      final again = await repo.load();
      // 再写一遍（内容相同）不会多出一行：唯一索引 + INSERT OR IGNORE。
      await repo.writeAll(again);
      expect((await repo.load()).answerEvents.length, 2);
    });

    test('write 只动指定段，别的段原样保留', () async {
      await repo.writeAll(_sample());

      final onlyPractice = emptyLearning()
        ..practice = <PracticeRecord>[
          const PracticeRecord(
            at: '2026-12-01T00:00:00.000Z',
            kind: PracticeKind.listening,
            total: 1,
            correct: 1,
          ),
        ];
      await repo.write(onlyPractice, <LearningSection>[LearningSection.practice]);

      final loaded = await repo.load();
      expect(loaded.practice.single.kind, PracticeKind.listening);
      // 其它段没被碰：读完记录、错题、活动统计都还在。
      expect(loaded.readDone, hasLength(1));
      expect(loaded.mistakes, hasLength(2));
      expect(loaded.activity, hasLength(2));
    });

    test('长期资产五段永不清表', () async {
      await repo.writeAll(_sample());
      final before = await repo.load();
      expect(before.answerEvents, hasLength(2));
      expect(before.backTranslations, hasLength(1));
      expect(before.goldenDrills, hasLength(1));
      expect(before.writingErrorProgress, hasLength(1));
      expect(before.productionProgress, hasLength(1));

      // 只传这五段 + 一份空记录：清表要跳过它们，写入也没有条目。
      await repo.write(emptyLearning(), <LearningSection>[
        LearningSection.answerEvents,
        LearningSection.backTranslations,
        LearningSection.goldenDrills,
        LearningSection.writingErrorProgress,
        LearningSection.productionProgress,
      ]);

      final after = await repo.load();
      // 工棚那段例外：它的写入语义是「以这份列表为准，不在里面的就删」，
      // 所以空列表等于全删 —— 这正是 Web 版的口径，别改。
      expect(after.productionProgress, isEmpty);
      expect(after.answerEvents, hasLength(2));
      expect(after.backTranslations, hasLength(1));
      expect(after.goldenDrills, hasLength(1));
      expect(after.writingErrorProgress, hasLength(1));
    });

    test('sections 为空时什么都不写', () async {
      await repo.writeAll(_sample());
      await repo.write(emptyLearning(), const <LearningSection>[]);
      expect((await repo.load()).readDone, hasLength(1));
    });

    test('writeSection 是 write 的单段简写', () async {
      await repo.writeAll(_sample());
      final next = await repo.load();
      next.skimmed = <String>['a3'];
      await repo.writeSection(next, LearningSection.skimmed);
      expect((await repo.load()).skimmed, <String>['a3']);
    });
  });

  group('快照', () {
    test('空库不拍快照', () async {
      expect(await repo.snapshot('manual'), isNull);
      expect(await repo.listSnapshots(), isEmpty);
    });

    test('拍完能在列表里看到，体积大于 0', () async {
      await repo.writeAll(_sample());
      final at = await repo.snapshot('manual');
      expect(at, isNotNull);

      final list = await repo.listSnapshots();
      expect(list, hasLength(1));
      expect(list.single.at, at);
      expect(list.single.reason, 'manual');
      expect(list.single.bytes, greaterThan(0));
    });

    test('内容没变不重复拍', () async {
      await repo.writeAll(_sample());
      expect(await repo.snapshot('a'), isNotNull);
      expect(await repo.snapshot('b'), isNull);
      expect(await repo.listSnapshots(), hasLength(1));
    });

    test('节流：minIntervalMs 内不再拍', () async {
      await repo.writeAll(_sample());
      expect(await repo.snapshot('a'), isNotNull);
      expect(await repo.snapshot('b', minIntervalMs: 60 * 1000), isNull);
      // 传 0 就是不节流，只剩内容去重 —— 内容变了就拍。
      final next = await repo.load();
      next.skimmed = <String>['a9'];
      await repo.writeSection(next, LearningSection.skimmed);
      expect(await repo.snapshot('c', minIntervalMs: 0), isNotNull);
    });

    test('最多留 12 版', () async {
      await repo.writeAll(_sample());
      final data = await repo.load();
      for (var i = 0; i < 15; i++) {
        data.skimmed = <String>['a$i'];
        await repo.writeSection(data, LearningSection.skimmed);
        expect(await repo.snapshot('第 $i 版'), isNotNull);
      }
      final list = await repo.listSnapshots();
      expect(list, hasLength(learningSnapshotKeep));
      // 新的在前，最老的一版（第 0 版）已经被挤掉了。
      expect(list.first.reason, '第 14 版');
    });
  });

  group('恢复', () {
    test('快照不存在返回 false', () async {
      expect(await repo.restore('2026-01-01T00:00:00.000Z'), isFalse);
    });

    test('恢复回去并留下 before-restore 那张', () async {
      await repo.writeAll(_sample());
      final at = await repo.snapshot('before-change');
      expect(at, isNotNull);

      final changed = await repo.load();
      changed.skimmed = <String>['zzz'];
      changed.readDone = const <ReadDone>[];
      await repo.writeAll(changed);
      expect((await repo.load()).skimmed, <String>['zzz']);

      expect(await repo.restore(at!), isTrue);
      final back = await repo.load();
      expect(back.skimmed, <String>['a1', 'a2']);
      expect(back.readDone, hasLength(1));

      final list = await repo.listSnapshots();
      expect(list.map((e) => e.reason), contains('before-restore'));
    });

    test('答题事件按 append-only 合并，不丢新事件', () async {
      await repo.writeAll(_sample());
      final at = await repo.snapshot('before-change');

      final changed = await repo.load();
      changed.answerEvents = <AnswerEvent>[
        ...changed.answerEvents,
        const AnswerEvent(
          at: '2026-11-06T00:00:00.000Z',
          day: '2026-11-06',
          articleId: 'a2',
          source: PracticeKind.golden,
          kind: 'goldenExam',
          cat: ActivityCat.write,
          correct: true,
          questionId: 'q9',
        ),
      ];
      await repo.writeSection(changed, LearningSection.answerEvents);
      expect((await repo.load()).answerEvents, hasLength(3));

      expect(await repo.restore(at!), isTrue);
      final merged = (await repo.load()).answerEvents;
      // 三条都在（旧快照 2 条 ∪ 当前 3 条），并且按 at 升序。
      expect(merged, hasLength(3));
      expect(merged.map((e) => e.at).toList(), <String>[
        '2026-11-01T10:00:00.000Z',
        '2026-11-01T10:01:00.000Z',
        '2026-11-06T00:00:00.000Z',
      ]);
    });

    test('损坏的快照抛 FormatException，不静默变空库', () async {
      await db.rawInsert(
        'INSERT INTO learning_snapshots (at, reason, payload, bytes) VALUES (?, ?, ?, ?)',
        ['2026-01-01T00:00:00.000Z', 'broken', 'not json at all', 5],
      );
      expect(
        () => repo.restore('2026-01-01T00:00:00.000Z'),
        throwsA(isA<FormatException>()),
      );
    });

    test('明文 TEXT 快照也读得回来（兼容不用 gzip 的旧数据）', () async {
      final payload = jsonEncode(learningToJson(_sample()));
      await db.rawInsert(
        'INSERT INTO learning_snapshots (at, reason, payload, bytes) VALUES (?, ?, ?, ?)',
        ['2026-01-01T00:00:00.000Z', 'plain', payload, payload.length],
      );
      expect(await repo.restore('2026-01-01T00:00:00.000Z'), isTrue);
      expect((await repo.load()).mistakes, hasLength(2));
    });
  });

  group('派生统计', () {
    test('baseline 存读往返；迁移时就写了一张空基线', () async {
      // v7 迁移里无条件 `saveDerivedBaseline`（历史聚合要有底），所以空库也有一张。
      final fresh = await repo.loadDerivedBaseline();
      expect(fresh.at, isNotNull);
      expect(fresh.activity, isEmpty);
      expect(fresh.kindStats, isEmpty);

      await repo.writeAll(_sample());
      await repo.saveDerivedBaseline(at: '2026-11-07T00:00:00.000Z');
      final base = await repo.loadDerivedBaseline();
      expect(base.at, '2026-11-07T00:00:00.000Z');
      expect(base.activity, isA<List<Object?>>());
      expect(base.kindStats, isA<Map>());
    });

    test('rebuildDerived：baseline 铺底 + quiz 事件叠加，其它 source 不算', () async {
      // baseline 里先给一条「迁移前」的历史量。
      await db.rawInsert(
        'INSERT OR REPLACE INTO learning_derived_baseline (id, payload, at) VALUES (1, ?, ?)',
        [
          jsonEncode(<String, Object?>{
            'activity': <Object?>[],
            'kindStats': <String, Object?>{
              'a1': <String, Object?>{
                'cloze': <String, Object?>{'total': 4, 'correct': 2},
              },
            },
          }),
          '2026-11-01T00:00:00.000Z',
        ],
      );

      await repo.writeSection(_sample(), LearningSection.answerEvents);
      await repo.rebuildDerived();

      final stats = (await repo.load()).kindStats;
      // baseline 4/2 + 一条 quiz 对题 = 5/3；dictation 那条 source 不是 quiz，不进统计。
      expect(stats['a1']!['cloze'], const KindStat(total: 5, correct: 3));
      expect(stats['a1']!.containsKey('dictation'), isFalse);
    });

    test('rebuildDerived 不碰活动聚合', () async {
      await repo.writeAll(_sample());
      final before = (await repo.load()).activity;
      await repo.rebuildDerived();
      final after = (await repo.load()).activity;
      expect(learningSectionJson(
        LearningData(activity: after),
        LearningSection.activity,
      ), equals(learningSectionJson(LearningData(activity: before), LearningSection.activity)));
    });
  });

  group('清理', () {
    test('clearAll 清掉 16 段（长期资产也清）', () async {
      await repo.writeAll(_sample());
      expect(await repo.hasRows(), isTrue);
      await repo.clearAll();
      expect(await repo.hasRows(), isFalse);
      final empty = await repo.load();
      expect(hasLearningData(empty), isFalse);
      // 快照不属于学习记录本身，清库不动它。
      expect(empty.answerEvents, isEmpty);
    });

    test('checkpoint 不抛（内存库也能跑）', () async {
      await repo.writeAll(_sample());
      await repo.checkpoint();
    });
  });
}
