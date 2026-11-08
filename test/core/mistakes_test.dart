import 'package:dlaoshi_app/core/mistakes.dart';
import 'package:dlaoshi_app/models/listening.dart';
import 'package:flutter_test/flutter_test.dart';

final ListeningQuestion _q = const ListeningQuestion(
  id: 'q1',
  type: ListeningQType.gap,
  stem: 's',
  answer: 'a',
);

void main() {
  group('upsertMistake', () {
    test('新增在前、同 id 累加', () {
      var list = upsertMistake(<MistakeEntry>[], vocabMistake('vocab:run', 'run', 't1'));
      list = upsertMistake(list, vocabMistake('vocab:go', 'go', 't2'));
      list = upsertMistake(list, vocabMistake('vocab:run', 'run', 't3'));
      expect(list.map((m) => m.label).toList(), ['go', 'run']);
      expect(list.firstWhere((m) => m.label == 'run').count, 2);
      expect(list.firstWhere((m) => m.label == 'run').at, 't3');
    });

    test('按上限截断', () {
      var list = <MistakeEntry>[];
      for (var i = 0; i < 5; i++) {
        list = upsertMistake(list, vocabMistake('vocab:$i', 'w$i', 't$i'), cap: 3);
      }
      expect(list, hasLength(3));
      // 与 Web 版一致：截断保留**最新的**几条（插在最前），老的丢尾。
      expect(list.map((m) => m.label).toList(), ['w4', 'w3', 'w2']);
    });
  });

  group('错题本：构造 / 计数 / 移除', () {
    test('dict 同文本归一化后同一 id', () {
      expect(dictMistake('The  Plan was', 't').id, dictMistake('the plan was', 't').id);
    });

    test('vocab / listen / dict 计数', () {
      final list = [
        vocabMistake('a', 'a', 't'),
        dictMistake('x', 't'),
        listenMistake('art', _q, 't'),
      ];
      expect(mistakeCounts(list), {
        MistakeKind.vocab: 1,
        MistakeKind.listen: 1,
        MistakeKind.dict: 1,
      });
      expect(mistakeCounts(const []), {MistakeKind.vocab: 0, MistakeKind.listen: 0, MistakeKind.dict: 0});
    });

    test('remove 按 id 移除', () {
      expect(removeMistake([vocabMistake('a', 'a', 't')], 'vocab:a'), isEmpty);
      expect(removeMistake([vocabMistake('a', 'a', 't')], 'vocab:b'), hasLength(1));
    });

    test('listen 的 id 带题号与题干，不带文章', () {
      final m = listenMistake('art-A', _q, 't');
      expect(m.id, startsWith('listen:q1:s'));
      expect(m.articleId, 'art-A');
      expect(m.question?.id, 'q1');
    });

    test('label 与解析', () {
      expect(mistakeLabel[MistakeKind.dict], '听写漏词');
      expect(parseMistakeKind('listen'), MistakeKind.listen);
      expect(parseMistakeKind('x'), isNull);
      expect(mistakeKinds, hasLength(3));
    });
  });
}
