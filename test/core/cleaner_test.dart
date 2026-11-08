import 'package:dlaoshi_app/core/cleaner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalizeTypography', () {
    test('把 PDF 连字展成普通字母', () {
      expect(normalizeTypography('Brie\ufb01ng O\ufb00shore'), 'Briefing Offshore');
    });

    test('删掉软连字符并直接接合', () {
      expect(normalizeTypography('recent\u00adly'), 'recently');
    });

    test('不换行空格 / 窄空格变成普通空格', () {
      expect(normalizeTypography('a\u00a0b\u202fc'), 'a b c');
    });

    test('统一换行符', () {
      expect(normalizeTypography('a\r\nb\rc'), 'a\nb\nc');
    });
  });

  group('cleanText', () {
    test('行末连字符断词：去掉连字符后是词典里的词', () {
      expect(cleanText('The com-\npared figures rose.'), 'The compared figures rose.');
    });

    test('行末连字符断词：真复合词保留连字符', () {
      expect(cleanText('A co-\nfounder resigned.'), 'A co-founder resigned.');
    });

    test('段内硬换行用空格合并', () {
      expect(
        cleanText('The quick brown\nfox jumps over\nthe lazy dog.'),
        'The quick brown fox jumps over the lazy dog.',
      );
    });

    test('句末标点后接大写不会把字符粘起来', () {
      expect(cleanText('He left.\nNext day it rained.'), 'He left. Next day it rained.');
    });

    test('保留手动加的「【…】」标题 / 导语，单独成段不并入正文', () {
      expect(
        cleanText('【标题】\n【导语】\nBody text here.'),
        '【标题】\n\n【导语】\n\nBody text here.',
      );
      // 缩进的标记行也认
      expect(cleanText('  【标题】\nBody.'), '【标题】\n\nBody.');
    });

    test('空行切段落', () {
      expect(
        cleanText('First paragraph.\n\nSecond paragraph.'),
        'First paragraph.\n\nSecond paragraph.',
      );
    });

    test('连字符后是空行时不跨段合并', () {
      expect(cleanText('end-\n\nstart'), 'end-\n\nstart');
    });

    test('空输入返回空串', () {
      expect(cleanText(''), '');
    });

    test('只有空白返回空串', () {
      expect(cleanText('  \n\n \t \n'), '');
    });

    test('单行且末尾无换行原样返回', () {
      expect(cleanText('Just one line.'), 'Just one line.');
    });

    test('真实样本：2021 的软连字符', () {
      expect(
        cleanText('Mississip\u00adpi’s literacy programme'),
        'Mississippi’s literacy programme',
      );
      expect(cleanText('af\u00adfordable housing'), 'affordable housing');
    });

    test('真实样本：ligature 混在正文里', () {
      expect(cleanText('The ﬁrm said proﬁts ﬁrmed.'), 'The firm said profits firmed.');
    });

    test('幂等：洗两遍结果一样', () {
      final once = cleanText('The com-\npared\n\nBrie\ufb01ng');
      expect(cleanText(once), once);
    });
  });
}
