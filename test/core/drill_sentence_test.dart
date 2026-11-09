import 'package:dlaoshi_app/core/drill_sentence.dart';
import 'package:dlaoshi_app/core/quiz.dart';
import 'package:dlaoshi_app/models/vocab.dart';
import 'package:flutter_test/flutter_test.dart';

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

QuizQuestion _question({
  required String id,
  required String itemId,
  required QuizKind kind,
  String? context,
}) =>
    QuizQuestion(
      id: id,
      itemId: itemId,
      lemma: 'x',
      kind: kind,
      word: 'x',
      prompt: '',
      answer: '',
      accept: const <String>[],
      context: context,
    );

void main() {
  group('记忆拷打取词', () {
    test('每个词条一个点，带上词义', () {
      final points = drillSentencePoints(
        <VocabItem>[
          _item('a', 'follow up', meaning: '跟进'),
          _item('b', 'run into', meaning: '偶遇'),
        ],
        <({String? id, String itemId})>[
          (id: null, itemId: 'a'),
          (id: null, itemId: 'b'),
        ],
        DrillSentenceKind.memory,
      );
      expect(points, hasLength(2));
      expect(points.first.en, 'follow up');
      expect(points.first.zh, '跟进');
      expect(points[1].en, 'run into');
    });

    test('同一词条考了多题只取第一次', () {
      final points = drillSentencePoints(
        <VocabItem>[_item('a', 'follow up')],
        <({String? id, String itemId})>[
          (id: 'q1', itemId: 'a'),
          (id: 'q2', itemId: 'a'),
        ],
        DrillSentenceKind.memory,
      );
      expect(points, hasLength(1));
    });

    test('词条不存在就跳过，不抛', () {
      final points = drillSentencePoints(
        <VocabItem>[],
        <({String? id, String itemId})>[(id: null, itemId: 'missing')],
        DrillSentenceKind.memory,
      );
      expect(points, isEmpty);
    });

    test('limit 生效', () {
      final points = drillSentencePoints(
        <VocabItem>[_item('a', 'one'), _item('b', 'two')],
        <({String? id, String itemId})>[
          (id: null, itemId: 'a'),
          (id: null, itemId: 'b'),
        ],
        DrillSentenceKind.memory,
        options: const DrillSentenceOptions(limit: 1),
      );
      expect(points, hasLength(1));
    });

    test('limit = 0 时一个都不出', () {
      final points = drillSentencePoints(
        <VocabItem>[_item('a', 'one')],
        <({String? id, String itemId})>[(id: null, itemId: 'a')],
        DrillSentenceKind.memory,
        options: const DrillSentenceOptions(limit: 0),
      );
      expect(points, isEmpty);
    });
  });

  group('词块拷打取词', () {
    test('优先用这场考试实际考的那条词块', () {
      final points = drillSentencePoints(
        <VocabItem>[
          _item('a', 'follow', phrases: <String>['follow up — 跟进']),
        ],
        <({String? id, String itemId})>[(id: 'q1', itemId: 'a')],
        DrillSentenceKind.chunk,
        options: DrillSentenceOptions(
          questions: <QuizQuestion>[
            _question(
              id: 'q1',
              itemId: 'a',
              kind: QuizKind.usage,
              context: 'follow through — 坚持到底',
            ),
          ],
        ),
      );
      expect(points, hasLength(1));
      expect(points.first.en, 'follow through');
      expect(points.first.zh, '坚持到底');
    });

    test('没有本轮题时就按 phrases → idioms → usage 顺序取第一条', () {
      final points = drillSentencePoints(
        <VocabItem>[
          _item('a', 'follow', idioms: <String>['follow suit — 跟着做']),
        ],
        <({String? id, String itemId})>[(id: null, itemId: 'a')],
        DrillSentenceKind.chunk,
      );
      expect(points.single.en, 'follow suit');
      expect(points.single.zh, '跟着做');
    });

    test('一个词块都取不到时退回单词本身', () {
      final points = drillSentencePoints(
        <VocabItem>[_item('a', 'follow')],
        <({String? id, String itemId})>[(id: null, itemId: 'a')],
        DrillSentenceKind.chunk,
      );
      expect(points.single.en, 'follow');
    });

    test('中文用法笔记不当 mustUse', () {
      final points = drillSentencePoints(
        <VocabItem>[
          _item('a', 'so-called', usage: <String>['常带保留态度']),
        ],
        <({String? id, String itemId})>[(id: null, itemId: 'a')],
        DrillSentenceKind.chunk,
      );
      // usage 是中文 → 跳过，退回单词
      expect(points.single.en, 'so-called');
    });

    test('搭配题的 context 只取分号前第一条', () {
      final points = drillSentencePoints(
        <VocabItem>[_item('a', 'put')],
        <({String? id, String itemId})>[(id: 'q1', itemId: 'a')],
        DrillSentenceKind.chunk,
        options: DrillSentenceOptions(
          questions: <QuizQuestion>[
            _question(
              id: 'q1',
              itemId: 'a',
              kind: QuizKind.collocation,
              context: 'put off — 推迟；put up — 搭建',
            ),
          ],
        ),
      );
      expect(points.single.en, 'put off');
      expect(points.single.zh, '推迟');
    });

    test('重复文本跳过，退回那个词条自己的单词', () {
      final points = drillSentencePoints(
        <VocabItem>[
          _item('a', 'w', phrases: <String>['look after — 照顾']),
          _item('b', 'v', phrases: <String>['Look after — 照看']),
        ],
        <({String? id, String itemId})>[
          (id: null, itemId: 'a'),
          (id: null, itemId: 'b'),
        ],
        DrillSentenceKind.chunk,
      );
      expect(points, hasLength(2));
      expect(points.first.en, 'look after');
      // 第二个词条的唯一词块和上面撞了 → 退回它自己的单词，不重复出同一句。
      expect(points[1].en, 'v');
    });
  });

  group('一轮的身份', () {
    test('同一组内容（顺序无关）得到同一个 id', () {
      const p1 = DrillSentencePoint(id: 'x', itemId: 'a', en: 'follow up');
      const p2 = DrillSentencePoint(id: 'y', itemId: 'b', en: 'run into');
      final one = drillSentenceId(DrillSentenceKind.memory, <DrillSentencePoint>[p1, p2]);
      final two = drillSentenceId(DrillSentenceKind.memory, <DrillSentencePoint>[p2, p1]);
      expect(one, two);
    });

    test('不同种类不同 id', () {
      const p = DrillSentencePoint(id: 'x', itemId: 'a', en: 'follow up');
      expect(
        drillSentenceId(DrillSentenceKind.memory, <DrillSentencePoint>[p]),
        isNot(drillSentenceId(DrillSentenceKind.chunk, <DrillSentencePoint>[p])),
      );
    });

    test('空的点列表也能算出一个稳定 id', () {
      final a = drillSentenceId(DrillSentenceKind.memory, <DrillSentencePoint>[]);
      final b = drillSentenceId(DrillSentenceKind.memory, <DrillSentencePoint>[]);
      expect(a, b);
      expect(a, startsWith('drill:memory:'));
    });
  });

  group('出题', () {
    test('记忆拷打：题面带单词与词义，mustUse 只有那一个词', () {
      const point = DrillSentencePoint(
        id: 'x',
        itemId: 'a',
        en: 'follow up',
        zh: '跟进',
      );
      final task = buildDrillSentenceTask(DrillSentenceKind.memory, point);
      expect(task.task, contains('follow up（跟进）'));
      expect(task.task, contains('记忆拷打'));
      expect(task.mustUse, <String>['follow up']);
      expect(task.model, '');
      expect(task.rubric, hasLength(3));
      expect(task.rubric.first.dimension, '词义与搭配');
    });

    test('词块拷打：题面说词块，rubric 第一维是词块使用', () {
      const point = DrillSentencePoint(id: 'x', itemId: 'a', en: 'follow up');
      final task = buildDrillSentenceTask(DrillSentenceKind.chunk, point);
      expect(task.task, contains('词块拷打'));
      expect(task.task, contains('这个词块'));
      expect(task.rubric.first.dimension, '词块使用');
    });

    test('一批点各出一道题', () {
      const p1 = DrillSentencePoint(id: 'x', itemId: 'a', en: 'one');
      const p2 = DrillSentencePoint(id: 'y', itemId: 'b', en: 'two');
      final tasks =
          buildDrillSentenceTasks(DrillSentenceKind.memory, <DrillSentencePoint>[p1, p2]);
      expect(tasks, hasLength(2));
      expect(tasks[1].mustUse, <String>['two']);
    });

    test('种类中文名', () {
      expect(drillSentenceKindLabel(DrillSentenceKind.memory), '记忆拷打');
      expect(drillSentenceKindLabel(DrillSentenceKind.chunk), '词块拷打');
    });
  });
}
