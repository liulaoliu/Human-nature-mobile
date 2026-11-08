import 'package:dlaoshi_app/core/quiz_parts.dart';
import 'package:dlaoshi_app/models/vocab.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/vocab_fixture.dart';

VocabItem item({
  String id = 'v1',
  String word = 'run',
  String? meaning,
  List<String> usage = const [],
  List<String>? phrases,
  List<String>? grammarMarks,
  List<VocabConfusable>? confusables,
}) =>
    vocabItem(
      id: id,
      word: word,
      lemma: word,
      meaning: meaning,
      usage: usage,
      phrases: phrases,
      grammarMarks: grammarMarks,
      confusables: confusables,
    );

double half() => 0.5;

void main() {
  group('normalizeAnswer / canonical', () {
    test('小写、去首尾标点、压空白', () {
      expect(normalizeAnswer('  Running, '), 'running');
      expect(normalizeAnswer('“word”'), 'word');
      expect(normalizeAnswer('a  business.'), 'a business');
    });

    test('canonical 只留字母数字', () {
      expect(canonical("Bad-Temperedly's"), 'badtemperedlys');
      expect(canonical('   '), '');
    });
  });

  group('formatAnswerInput', () {
    test('按答案标点自动补连字符与撇号', () {
      expect(formatAnswerInput('badt', 'bad-temperedly'), 'bad-t');
      expect(formatAnswerInput('dont', "don't"), "don't");
    });

    test('不是前缀 / 空输入 → 原样返回', () {
      expect(formatAnswerInput('xyz', 'bad-temperedly'), 'xyz');
      expect(formatAnswerInput('', 'bad-temperedly'), '');
      expect(formatAnswerInput('badtemperedly', 'bad-temperedly'), 'bad-temperedly');
    });
  });

  group('maskAnswer', () {
    test('字母数字变下划线，标点保留', () {
      expect(maskAnswer('run'), '___');
      expect(maskAnswer('run a business'), '___ _ ${'_' * 8}');
      expect(maskAnswer("don't"), "___'_");
    });
  });

  group('blankWord', () {
    test('单词按 lemma 命中并挖空', () {
      final r = blankWord('He is running fast.', 'run')!;
      expect(r.blanked, 'He is ____ fast.');
      expect(r.surface, 'running');
    });

    test('短语按整段子串匹配', () {
      final r = blankWord('The human rights record is poor.', 'human rights')!;
      expect(r.surface, 'human rights');
    });

    test('找不到 / 空参数 → null', () {
      expect(blankWord('nothing', 'run'), isNull);
      expect(blankWord('', 'run'), isNull);
      expect(blankWord('text', ''), isNull);
    });
  });

  group('baseAccept', () {
    test('含原词形、词条 word、lemma，去重去空', () {
      final it = vocabItem(word: 'running', lemma: 'run');
      final out = baseAccept(it, 'ran');
      expect(out, containsAll(<String>['ran', 'running', 'run']));
    });
  });

  group('meaningOverlaps', () {
    test('相等或互为子串算重叠', () {
      expect(meaningOverlaps('适应', '适应'), isTrue);
      expect(meaningOverlaps('微调，调整', '调整'), isTrue);
      expect(meaningOverlaps('适应', '采用'), isFalse);
      expect(meaningOverlaps('', '采用'), isFalse);
    });
  });

  group('pickDistractors', () {
    test('排除自身、优先形近', () {
      final pool = [
        item(id: 'a', word: 'adapt'),
        item(id: 'b', word: 'adopt'),
        item(id: 'c', word: 'adept'),
        item(id: 'd', word: 'zebra'),
      ];
      final out = pickDistractors(pool[0], pool, 2, half);
      expect(out, isNot(contains('adapt')));
      expect(out, contains('adopt'));
    });

    test('优先用 AI 混淆项，剔除与目标近义的', () {
      final me = item(
        id: 'a',
        word: 'adapt',
        meaning: '适应',
        confusables: const [
          VocabConfusable(word: 'adjust', meaning: '适应'),
          VocabConfusable(word: 'adopt', meaning: '收养'),
        ],
      );
      expect(pickDistractors(me, const [], 3, half), ['adopt']);
    });
  });

  group('pickMeaningDistractors', () {
    test('排除同释义并去重', () {
      final pool = [
        item(id: 'a', meaning: '适应'),
        item(id: 'b', meaning: '采用'),
        item(id: 'c', meaning: '采用'),
      ];
      final out = pickMeaningDistractors(pool[0], pool, 3, half);
      expect(out, isNot(contains('适应')));
      expect(out.toSet().length, out.length);
    });
  });

  group('chunkList', () {
    test('合并用法与词组，去空、去重、去掉光杆词', () {
      final it = item(word: 'run', usage: ['run out', ' ', 'run'], phrases: ['run out', 'run late']);
      expect(chunkList(it), ['run out', 'run late']);
    });
  });

  group('blankParticle', () {
    test('挖掉最后一个介词', () {
      final r = blankParticle('run out of')!;
      expect(r.blanked, 'run out ____');
      expect(r.particle, 'of');
    });

    test('没有介词 → null', () {
      expect(blankParticle('run a business'), isNull);
    });
  });

  group('markQuestion', () {
    test('成对标记出题；兼类与无标记返回 null', () {
      final q = markQuestion(item(grammarMarks: ['可数']))!;
      expect(q.answer, '可数');
      expect(q.options.toSet(), {'可数', '不可数'});
      expect(markQuestion(item(grammarMarks: ['可数', '不可数'])), isNull);
      expect(markQuestion(item(grammarMarks: const [])), isNull);
    });
  });

  group('shuffleQuiz', () {
    test('不改原列表、元素不丢', () {
      final src = [1, 2, 3, 4, 5];
      final out = shuffleQuiz(src, half);
      expect(src, [1, 2, 3, 4, 5]);
      expect(out.toList()..sort(), [1, 2, 3, 4, 5]);
    });
  });
}
