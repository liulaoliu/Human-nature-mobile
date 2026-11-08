import 'package:flutter_test/flutter_test.dart';

import 'package:dlaoshi_app/core/vocab/word.dart';

/// 逐条移植自 Web 版 `src/core/vocab/word.test.ts`（102 行）。
/// 用例名照抄中文，红了先怀疑移植错，不是测试错。
void main() {
  group('释义/词性清洗', () {
    test('cleanGloss 去掉行尾反斜杠与多余空白', () {
      expect(cleanGloss('n. 林学, 森林地\\'), 'n. 林学, 森林地');
      expect(cleanGloss('  a word formed by something \\ '),
          'a word formed by something');
    });

    test('normalizePos 全称 → 缩写', () {
      expect(normalizePos('noun'), 'n.');
      expect(normalizePos('verb'), 'v.');
      expect(normalizePos('n.'), 'n.');
      expect(normalizePos(''), '');
    });

    test('displayMeaning 去掉与词性重复的开头', () {
      expect(displayMeaning(partOfSpeech: 'noun', meaning: 'n. 林学, 森林地\\'),
          '林学, 森林地');
      expect(displayMeaning(partOfSpeech: 'n.', meaning: '小群, 子群\\'),
          '小群, 子群');
      // 没有词性时，保留释义自带的词性前缀
      expect(displayMeaning(partOfSpeech: '', meaning: 'n. 小群\\'), 'n. 小群');
    });
  });

  group('normalizeWord', () {
    test('统一撇号、去标点、转小写', () {
      expect(normalizeWord('Mississippi\u2019s,'), "mississippi's");
      expect(normalizeWord('Phonics'), 'phonics');
    });

    test('连字符保留', () {
      expect(normalizeWord('state-of-the-art'), 'state-of-the-art');
    });
  });

  group('lemmaOf', () {
    test('复数 → 原形', () {
      expect(lemmaOf('cats'), 'cat');
      expect(lemmaOf('studies'), 'study');
      expect(lemmaOf('boxes'), 'box');
    });

    test('-ing / -ed → 原形', () {
      expect(lemmaOf('running'), 'run');
      expect(lemmaOf('watched'), 'watch');
    });

    test('不规则形查表', () {
      expect(lemmaOf('ran'), 'run');
      expect(lemmaOf('children'), 'child');
      expect(lemmaOf('went'), 'go');
    });

    test('所有格', () {
      expect(lemmaOf("Mississippi's"), 'mississippi');
    });

    test('以 us/ss/is/os 结尾的词不误删 s（census/status/analysis）', () {
      expect(lemmaOf('census'), 'census');
      expect(lemmaOf('status'), 'status');
      expect(lemmaOf('analysis'), 'analysis');
      expect(lemmaOf('boss'), 'boss');
    });

    test('空词返回空串', () {
      expect(lemmaOf('   '), '');
    });
  });

  group('lemmaOf 短语', () {
    test('含空格的短语不做词形还原，保持原样（小写）', () {
      expect(lemmaOf('human rights'), 'human rights');
      expect(lemmaOf('Climate Change'), 'climate change');
    });
  });

  group('canRewriteTo：只有屈折能改名，派生词不行', () {
    test('屈折变化放行', () {
      expect(canRewriteTo('runs', 'run'), isTrue);
      expect(canRewriteTo('running', 'run'), isTrue); // 双写尾辅音
      expect(canRewriteTo('watched', 'watch'), isTrue);
      expect(canRewriteTo('swelling', 'swell'), isTrue);
      expect(canRewriteTo('expunging', 'expunge'), isTrue); // 去 e 加 -ing
      expect(canRewriteTo('companies', 'company'), isTrue); // y → ies
      expect(canRewriteTo('analyses', 'analysis'), isTrue); // -ses → -sis
      expect(canRewriteTo('went', 'go'), isTrue); // 不规则表
      expect(canRewriteTo('children', 'child'), isTrue);
      expect(canRewriteTo('same', 'same'), isTrue);
    });

    test('否定/反义前缀派生出来的词不是词形变化（2026-10-22 的 bug）', () {
      expect(canRewriteTo('unchallenged', 'challenge'), isFalse);
      expect(canRewriteTo('unarticulated', 'articulate'), isFalse);
      expect(canRewriteTo('inarticulate', 'articulate'), isFalse);
      expect(canRewriteTo('discouraged', 'courage'), isFalse);
      expect(canRewriteTo('nonviolent', 'violent'), isFalse);
    });

    test('其它派生后缀也不改名（teacher ≠ teach 的变形）', () {
      expect(canRewriteTo('teacher', 'teach'), isFalse);
      expect(canRewriteTo('quickly', 'quick'), isFalse);
      expect(canRewriteTo('kindness', 'kind'), isFalse);
      expect(canRewriteTo('creation', 'create'), isFalse);
      expect(canRewriteTo('beautiful', 'beauty'), isFalse);
    });

    test('短语与空串不放行', () {
      expect(canRewriteTo('fall back on', 'fall back'), isFalse);
      expect(canRewriteTo('', 'run'), isFalse);
      expect(canRewriteTo('run', ''), isFalse);
    });
  });
}
