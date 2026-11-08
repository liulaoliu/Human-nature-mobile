import 'package:flutter_test/flutter_test.dart';

import 'package:dlaoshi_app/core/analyzer_shared.dart';

void main() {
  group('splitList', () {
    test('按换行 / 分号 / 顿号拆，去项目符号与编号', () {
      expect(
        splitList('- run out\n1. run a business；take part、spelling'),
        ['run out', 'run a business', 'take part', 'spelling'],
      );
    });

    test('空串与全是空项时不返回空字符串', () {
      expect(splitList(''), isEmpty);
      expect(splitList(';；\n、'), isEmpty);
    });
  });

  group('cleanExampleText', () {
    test('去掉编号、项目符号与包裹引号，压缩空白', () {
      expect(cleanExampleText('1. “He runs fast.”'), 'He runs fast.');
      expect(cleanExampleText('-   She  ran \t away '), 'She ran away');
    });

    test('只去掉首尾引号，句中的引号保留', () {
      expect(cleanExampleText('He said "hi" loudly'), 'He said "hi" loudly');
      expect(cleanExampleText('“He said hi”'), 'He said hi');
    });
  });

  group('quoted', () {
    test('用三引号围栏包住，前后各留一个换行', () {
      expect(quoted('  hello  '), '"""\nhello\n"""');
    });
  });

  test('行类型保持解析层与写库层同形', () {
    const row = PhraseRow(word: 'run', phrases: ['run out'], idioms: []);
    expect(row.word, 'run');
    const marks = (word: 'run', marks: <String>['及物']);
    expect(marks.marks, ['及物']);
    const tr = TranslationRow(sentenceId: 's1', translation: '他跑了。');
    expect(tr.sentenceId, 's1');
  });
}
