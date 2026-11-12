// 自动标词的结果解析：AI 不听话的几种写法都得吃掉。
import 'package:flutter_test/flutter_test.dart';

import 'package:dlaoshi_app/core/auto_vocab.dart';
import 'package:dlaoshi_app/core/ecdict.dart' show EcdictLevel;

void main() {
  group('干净的一行一个词', () {
    test('顺序保留、统一小写', () {
      expect(
        parseAutoVocabWords('Outnumber\nhobble\nImpeachment'),
        ['outnumber', 'hobble', 'impeachment'],
      );
    });

    test('重复的只留第一次', () {
      expect(parseAutoVocabWords('hobble\nHobble\nHOBBLE'), ['hobble']);
    });

    test('空行与纯空白行跳过', () {
      expect(parseAutoVocabWords('\n\n  \nhobble\n\n'), ['hobble']);
    });
  });

  group('AI 加了东西', () {
    test('行首编号 / 项目符号 / 中文序号都去掉', () {
      expect(
        parseAutoVocabWords('1. hobble\n2) outnumber\n- impeachment\n* stagnate\n① taper'),
        ['hobble', 'outnumber', 'impeachment', 'stagnate', 'taper'],
      );
    });

    test('带释义的只取词本身', () {
      expect(
        parseAutoVocabWords('hobble —— 蹒跚\noutnumber（数量超过）\ntaper: 逐渐减少'),
        ['hobble', 'outnumber', 'taper'],
      );
    });

    test('一行多个词拆开', () {
      expect(parseAutoVocabWords('hobble, outnumber；taper'), [
        'hobble',
        'outnumber',
        'taper',
      ]);
    });

    test('短语丢掉（短语该走语言点，不进生词本）', () {
      expect(
        parseAutoVocabWords('keep up with\nhobble\nin the long run'),
        ['hobble'],
      );
    });

    test('太短的词丢掉（of / a / is 不是生词）', () {
      expect(parseAutoVocabWords('of\nis\nhobble'), ['hobble']);
    });

    test('引号包着的词去掉引号', () {
      expect(parseAutoVocabWords('"hobble"\n“taper”'), ['hobble', 'taper']);
    });
  });

  group('词形', () {
    test('连字符词整个保留，不从中间切断', () {
      expect(parseAutoVocabWords('well-being'), ['well-being']);
    });

    test('带撇号的词保留', () {
      expect(parseAutoVocabWords("don't"), ["don't"]);
    });

    test('混了中文的行仍能取到英文词', () {
      expect(parseAutoVocabWords('hobble 蹒跚地走'), ['hobble']);
    });
  });

  group('剔掉本篇已有的', () {
    test('已有的不再建议，其余照旧', () {
      expect(
        autoVocabCandidates('hobble\noutnumber\ntaper', known: {'hobble'}),
        ['outnumber', 'taper'],
      );
    });

    test('known 大小写不敏感', () {
      expect(
        autoVocabCandidates('hobble', known: {'Hobble'}),
        isEmpty,
      );
    });

    test('不给 known 时全留', () {
      expect(autoVocabCandidates('hobble'), ['hobble']);
    });
  });

  group('词汇水平标签', () {
    test('每个水平都有短标签', () {
      expect(autoVocabLevelLabel.keys.length, EcdictLevel.values.length);
      for (final level in EcdictLevel.values) {
        expect(autoVocabLevelLabel[level], isNotEmpty);
      }
    });
  });
}
