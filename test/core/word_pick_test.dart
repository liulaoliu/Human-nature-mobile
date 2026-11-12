import 'package:dlaoshi_app/core/word_pick.dart';
import 'package:flutter_test/flutter_test.dart';

PickTarget t(String sentenceId, int index, String word) =>
    PickTarget(sentenceId: sentenceId, index: index, word: word);

void main() {
  group('PickTarget 身份', () {
    test('同一句同一下标算同一个位置，与词面无关', () {
      expect(t('s1', 3, 'run'), t('s1', 3, 'Run'));
      expect(t('s1', 3, 'run').key, t('s1', 3, 'run').key);
    });

    test('同一句不同下标、不同句同一下标都不相等', () {
      expect(t('s1', 3, 'run'), isNot(t('s1', 4, 'run')));
      expect(t('s1', 3, 'run'), isNot(t('s2', 3, 'run')));
    });
  });

  group('toggle', () {
    test('点一下选中，再点一下取消', () {
      var s = const PickState();
      s = s.toggle(t('s1', 1, 'the'));
      expect(s.length, 1);
      expect(s.contains('s1', 1), isTrue);
      s = s.toggle(t('s1', 1, 'the'));
      expect(s.isEmpty, isTrue);
    });

    test('同一句里重复出现的词各算各的', () {
      var s = const PickState();
      s = s.toggle(t('s1', 0, 'the')).toggle(t('s1', 4, 'the'));
      expect(s.length, 2);
    });

    test('多个句子可以一起选', () {
      var s = const PickState();
      s = s.toggle(t('s1', 0, 'a')).toggle(t('s2', 0, 'b'));
      expect(s.length, 2);
      expect(s.contains('s2', 0), isTrue);
    });

    test('clear 清空', () {
      final s = const PickState().toggle(t('s1', 0, 'a')).clear();
      expect(s.isEmpty, isTrue);
    });
  });

  group('phrases：同句连续选中的词合成词组', () {
    test('连续两个词合成一个词组', () {
      var s = const PickState();
      s = s.toggle(t('s1', 2, 'in')).toggle(t('s1', 3, 'terms'));
      final p = s.phrases;
      expect(p, hasLength(1));
      expect(p.single.phrase, 'in terms');
    });

    test('不连续的词分开成两条', () {
      var s = const PickState();
      s = s
          .toggle(t('s1', 2, 'in'))
          .toggle(t('s1', 4, 'terms'))
          .toggle(t('s1', 5, 'of'));
      final p = s.phrases;
      expect(p.map((e) => e.phrase).toList(), ['in', 'terms of']);
    });

    test('乱序点选也按原文词序拼', () {
      var s = const PickState();
      s = s.toggle(t('s1', 3, 'terms')).toggle(t('s1', 2, 'in'));
      expect(s.phrases.single.phrase, 'in terms');
    });

    test('跨句各自成条，按句分组', () {
      var s = const PickState();
      s = s
          .toggle(t('s1', 0, 'a'))
          .toggle(t('s1', 1, 'b'))
          .toggle(t('s2', 0, 'c'));
      expect(s.phrases.map((e) => e.phrase).toList(), ['a b', 'c']);
    });

    test('空集合没有词组', () {
      expect(const PickState().phrases, isEmpty);
    });
  });

  group('其他', () {
    test('wordsOf 只给该句的词', () {
      var s = const PickState();
      s = s.toggle(t('s1', 0, 'a')).toggle(t('s2', 0, 'b'));
      expect(s.wordsOf('s1'), ['a']);
      expect(s.wordsOf('nope'), isEmpty);
    });

    test('bySentence 句内按词序排', () {
      var s = const PickState();
      s = s.toggle(t('s1', 5, 'e')).toggle(t('s1', 1, 'b'));
      expect(s.bySentence['s1']!.map((x) => x.word).toList(), ['b', 'e']);
    });
  });
}
