import 'package:dlaoshi_app/core/writing.dart';
import 'package:dlaoshi_app/core/writing_draft.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WritingDraft：空态与相等性', () {
    test('默认是空草稿', () {
      const d = WritingDraft();
      expect(d.model, '');
      expect(d.text, '');
      expect(d.task, isNull);
      expect(d.mustUse, isEmpty);
      expect(d.isEmpty, isTrue);
      expect(emptyWritingDraft.isEmpty, isTrue);
    });

    test('有任意字段就不算空', () {
      expect(const WritingDraft(model: 'x').isEmpty, isFalse);
      expect(const WritingDraft(text: 'x').isEmpty, isFalse);
      expect(const WritingDraft(mustUse: <String>['a']).isEmpty, isFalse);
      expect(
        const WritingDraft(task: ImitationTask(task: 't', model: 'm')).isEmpty,
        isFalse,
      );
    });

    test('copyWith 能改字段、也能清掉 task', () {
      const d = WritingDraft(model: 'm', text: 't');
      expect(d.copyWith(text: 'x').text, 'x');
      expect(d.copyWith(text: 'x').model, 'm');
      const withTask = WritingDraft(task: ImitationTask(task: 't', model: 'm'));
      expect(withTask.copyWith(task: () => null).task, isNull);
    });
  });

  group('WritingDraft：序列化往返', () {
    test('范句 / 作答 / 必须用上的词都能存回来', () {
      const d = WritingDraft(
        model: 'I will follow up with the client.',
        text: 'I will follow up with him.',
        mustUse: <String>['follow up'],
      );
      final back = normalizeWritingDraft(d.toJson());
      expect(back.model, d.model);
      expect(back.text, d.text);
      expect(back.mustUse, <String>['follow up']);
      expect(back.task, isNull);
    });

    test('任务过一遍重验后能读回来', () {
      const task = ImitationTask(
        task: '写一句关于出差的话',
        model: 'I will follow up with the client.',
        structure: 'will + 动词原形',
        mustUse: <String>['follow up'],
        rubric: <RubricItem>[
          RubricItem(dimension: '语法准确', weight: 40, description: '硬错'),
        ],
      );
      const d = WritingDraft(model: 'm', text: 't', task: task);
      final back = normalizeWritingDraft(d.toJson());
      expect(back.task, isNotNull);
      expect(back.task!.task, task.task);
      expect(back.task!.structure, task.structure);
      expect(back.task!.mustUse, <String>['follow up']);
      expect(back.task!.rubric.single.dimension, '语法准确');
    });

    test('坏 JSON / 非 Map 回空草稿', () {
      expect(normalizeWritingDraft(null).isEmpty, isTrue);
      expect(normalizeWritingDraft('oops').isEmpty, isTrue);
      expect(normalizeWritingDraft(<Object?>[1, 2]).isEmpty, isTrue);
      expect(normalizeWritingDraft(<String, Object?>{}).isEmpty, isTrue);
    });

    test('task 形状不对就当没有任务，其余字段照留', () {
      final back = normalizeWritingDraft(<String, Object?>{
        'model': 'm',
        'text': 't',
        'task': <String, Object?>{'task': ''},
      });
      expect(back.task, isNull);
      expect(back.model, 'm');
      expect(back.text, 't');
    });

    test('mustUse 去空、去重、非字符串忽略', () {
      final back = normalizeWritingDraft(<String, Object?>{
        'mustUse': <Object?>['a', ' a ', '', '  ', 3, null, 'b'],
      });
      expect(back.mustUse, <String>['a', 'b']);
    });

    test('非字符串的 model / text 当空串', () {
      final back = normalizeWritingDraft(<String, Object?>{
        'model': 1,
        'text': <String>[],
      });
      expect(back.model, '');
      expect(back.text, '');
    });
  });
}
