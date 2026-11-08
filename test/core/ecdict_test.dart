// 离线词典：解析 / 查词 / 词形 / 分级判定。
//
// 用例逐条对齐 Web 版 `src/core/ecdict.test.ts`（188 行）。Web 版里那两条
// 「语言点收藏 + 词典归并交替跑」的交叉用例依赖 `upsertLanguagePoints` /
// `applyLemmaMap`，本项目这两个函数还没移植 —— 这里只保留它们真正要守的
// **词典侧**断言（词组不并、两跳词形不多算），等语言点收藏移植后再补交叉用例。

import 'package:dlaoshi_app/core/ecdict.dart';
import 'package:dlaoshi_app/models/vocab.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/vocab_fixture.dart';

// 构造与构建脚本一致的 TSV（\t 分隔；\n 表示换行由脚本转义为 \\n）
const String _wordsTsv = 'word\tphonetic\tpos\ten\tzh\ttag\tcollins\toxford\tbnc\tfrq\n'
    "allow\tә'lau\t\tv. let have\\nv. permit\tt. 允许\\nvi. 容许\tzk gk cet4 ky\t5\t1\t257\t339\n"
    'run\t\t\tv. move fast\tn. 跑\tcet4\t5\t1\t100\t100\n'
    "hobble\t'hɒbl\t\tvt. prevent\tt. 阻碍\tky\t2\t0\t5000\t6000\n"
    'carbonfibre\t\t\t\t\tgre\t0\t0\t0\t0\n'
    'bnconly\t\t\t\t\t\t0\t0\t0\t0\n'
    'fall back on\t\t\tphr. rely on\tt. 转而依靠\t\t0\t0\t0\t0\n'
    'alga\t\t\tn. seaweed\t n. 藻类\t\t0\t0\t0\t0\n'
    'algae\t\t\tn. seaweed\t n. 藻类（复数）\t\t0\t0\t0\t0';

const String _formsTsv = 'running\trun\n'
    'hobbled\thobble\n'
    'ensconced\tensconce\n'
    'falls back on\tfall back on\n'
    // 两跳：algaes → algae → alga（真实词典里就有 1224 个这种两跳词形）
    'algaes\talgae\n'
    'algae\talga';

final Ecdict _dict = parseEcdict(_wordsTsv, _formsTsv);

void main() {
  group('parseEcdict / resolveWord / dictLemmaOf', () {
    test('解析词条并还原转义换行', () {
      final e = _dict.entries['allow']!;
      expect(e.phonetic, "ә'lau");
      expect(e.en, contains('v. let have\nv. permit'));
      expect(e.tag, 'zk gk cet4 ky');
    });

    test('按词形还原原形再取词条', () {
      final hit = resolveWord(_dict, 'running')!;
      expect(hit.lemma, 'run');
      expect(hit.entry.word, 'run');
    });

    test('dictLemmaOf：还原 / 命中 / 查不到', () {
      expect(dictLemmaOf(_dict, 'hobbled'), 'hobble');
      expect(dictLemmaOf(_dict, 'hobble'), 'hobble');
      expect(dictLemmaOf(_dict, 'zzzz'), isNull);
      // 启发式会错成 ensconc 的，词典能给对的（加载时会据此自动纠正）
      expect(dictLemmaOf(_dict, 'ensconced'), 'ensconce');
    });

    test('nearTsv 解析成候选表', () {
      final d = parseEcdict(_wordsTsv, _formsTsv, 'hobble\tallow,run,zzzz\n');
      expect(d.near['hobble'], ['allow', 'run', 'zzzz']);
      // 词典里没有的候选跳过，条数取够就停
      final out = dictConfusables(d, 'hobbled', n: 2);
      expect(out.length, 2);
      expect(out.first.word, 'allow');
      expect(out.first.meaning, 't. 允许');
      expect(out.last.word, 'run');
    });
  });

  group('glossForPos：释义按词性挑行', () {
    const zh = 'n. 誓约, 誓言\\nvi. 起誓, 发誓\\nvt. 立誓, 起誓要';

    test('动词词性挑动词那条（不是永远取第一行）', () {
      expect(glossForPos(zh, 'v.'), 'vi. 起誓, 发誓');
      expect(glossForPos(zh, 'verb'), 'vi. 起誓, 发誓');
      expect(glossForPos(zh, 'vt.'), 'vi. 起誓, 发誓');
    });

    test('名词词性挑名词那条', () {
      expect(glossForPos(zh, 'n.'), 'n. 誓约, 誓言');
    });

    test('挑不到 / 没有词性 → 退回第一行', () {
      expect(glossForPos(zh, 'adj.'), 'n. 誓约, 誓言');
      expect(glossForPos(zh, ''), 'n. 誓约, 誓言');
    });

    test('空释义返回空串', () {
      expect(glossForPos('', 'v.'), '');
    });

    test('真换行也切得开', () {
      expect(glossForPos('n. 誓约\nvt. 立誓', 'v.'), 'vt. 立誓');
    });
  });

  group('isDictWord / dictLemmaPairs（词形归并只碰单个单词）', () {
    test('只认单个英文单词：词组 / 习语 / 用法笔记都不算', () {
      expect(isDictWord(vocabItem(word: 'running')), isTrue);
      expect(isDictWord(vocabItem(word: 'falls back on')), isFalse); // 含空格 = 词组
      expect(isDictWord(vocabItem(word: 'fall back on', kind: VocabItemKind.phrase)),
          isFalse);
      expect(isDictWord(vocabItem(word: 'take its toll', kind: VocabItemKind.idiom)),
          isFalse);
      expect(
        isDictWord(vocabItem(word: '注意 subject to 是形容词',
            kind: VocabItemKind.usage)),
        isFalse,
      ); // 中文笔记
      expect(isDictWord(vocabItem(word: '『』')), isFalse); // 归一化后为空
    });

    test('词组不做词形归并（否则会并进单词、被语言点收藏再加回来 → 数量跳动）', () {
      // 词典里确实有 falls back on → fall back on 的映射
      expect(dictLemmaOf(_dict, 'falls back on'), 'fall back on');
      final pairs = dictLemmaPairs(
        _dict,
        [
          vocabItem(id: 'v1', word: 'falls back on'), // 词组（含空格）
          vocabItem(id: 'v2', word: 'running'), // 单词 → 该归并
          vocabItem(id: 'v3', word: 'hobbled', status: VocabStatus.edited), // 手动改过
        ],
        skipLocked: true,
      );
      expect(pairs, [const LemmaPair(from: 'running', to: 'run')]);
      expect(
        dictLemmaPairs(
          _dict,
          [vocabItem(word: 'hobbled', status: VocabStatus.edited)],
          skipLocked: true,
        ),
        isEmpty,
      );
      expect(
        dictLemmaPairs(_dict, [vocabItem(word: 'hobbled')]),
        [const LemmaPair(from: 'hobbled', to: 'hobble')],
      );
    });

    test('词典里的「两跳」词形：每一跳各自归一，不会多出条目', () {
      // algaes → algae → alga：老写法每轮会把条目的 lemma 改成 alga，
      // 而收藏这边按 lemmaOf('algaes') = 'algae' 找 → 找不到就再建一条，来回跳。
      expect(dictLemmaOf(_dict, 'algaes'), 'algae');
      expect(dictLemmaOf(_dict, 'algae'), 'alga');
      // 单条词条只会被改一次名，反复算同一份 pair 结果稳定
      final items = [vocabItem(word: 'algaes')];
      expect(dictLemmaPairs(_dict, items), [const LemmaPair(from: 'algaes', to: 'algae')]);
      expect(dictLemmaPairs(_dict, items), [const LemmaPair(from: 'algaes', to: 'algae')]);
    });
  });

  group('isAboveLevel / pickAboveLevelWords', () {
    test('四级以内不算超纲，超四级算', () {
      expect(isAboveLevel(_dict, 'allow', EcdictLevel.cet4), isFalse); // 含 cet4
      expect(isAboveLevel(_dict, 'hobble', EcdictLevel.cet4), isTrue); // ky，超四级
      expect(isAboveLevel(_dict, 'run', EcdictLevel.cet4), isFalse);
    });

    test('从正文按水平挑词（原形、去重、按出现顺序）', () {
      const text = 'They allow running and hobble the plan, hobbled again.';
      expect(pickAboveLevelWords(_dict, text, EcdictLevel.cet4), ['hobble']);
    });

    test('词典没有的词不挑', () {
      expect(pickAboveLevelWords(_dict, 'zzzz qqqq', EcdictLevel.cet4), isEmpty);
    });

    test('levelVerdict 区分 超纲/档内/太生僻/未收录', () {
      expect(levelVerdict(_dict, 'hobble', EcdictLevel.cet4), LevelVerdict.above);
      expect(levelVerdict(_dict, 'allow', EcdictLevel.cet4), LevelVerdict.within);
      // 无标签/无频次（只靠 bnc）→ 太生僻
      expect(levelVerdict(_dict, 'bnconly', EcdictLevel.cet4), LevelVerdict.rare);
      expect(levelVerdict(_dict, 'unlisted', EcdictLevel.cet4), LevelVerdict.unknown);
    });

    test('无级别标签的词用词频兜底：超高频基础词不算超纲', () {
      final d = parseEcdict(
        'word\tphonetic\tpos\ten\tzh\ttag\tcollins\toxford\tbnc\tfrq\n'
        // 无标签，但排名很靠前 → 常见词
        'entirely\t\t\t\t\t\t3\t1\t1367\t1858\n'
        // 无标签，中等频次 → 仍算超纲
        'impeachment\t\t\t\t\t\t0\t0\t26724\t7636',
        '',
      );
      expect(levelVerdict(d, 'entirely', EcdictLevel.cet6), LevelVerdict.within);
      expect(levelVerdict(d, 'impeachment', EcdictLevel.cet6), LevelVerdict.above);
    });

    test('pickAboveLevelWords 跳过句中大写专有名词与全大写缩写', () {
      final d = parseEcdict(
        'word\tphonetic\tpos\ten\tzh\ttag\tcollins\toxford\tbnc\tfrq\n'
        'trump\t\t\t\t\tgre\t0\t0\t14687\t12616\n'
        'hobble\t\t\t\t\tky\t2\t0\t5000\t6000\n'
        'cia\t\t\t\t\tgre\t0\t0\t1\t1',
        '',
      );
      // 句首大写的 hobble 收；句中大写的 Trump / 全大写 CIA 跳过
      expect(
        pickAboveLevelWords(d, 'Hobble the plan with Trump and CIA meddling.',
            EcdictLevel.cet4),
        ['hobble'],
      );
    });

    test('少于 3 个字母的原形不挑', () {
      final d = parseEcdict(
        'word\tphonetic\tpos\ten\tzh\ttag\tcollins\toxford\tbnc\tfrq\n'
        'go\t\t\t\t\tky\t2\t0\t100\t100',
        '',
      );
      expect(pickAboveLevelWords(d, 'Go now.', EcdictLevel.cet4), isEmpty);
    });
  });

  group('guessCompoundPos：连字符复合词猜词性', () {
    test('按末段后缀判形容词 / 副词', () {
      expect(guessCompoundPos('self-described'), 'adj.');
      expect(guessCompoundPos('taxpayer-funded'), 'adj.');
      expect(guessCompoundPos('world-leading'), 'adj.');
      expect(guessCompoundPos('50-odd'), 'adj.');
      expect(guessCompoundPos('thought-provoking'), 'adj.');
      expect(guessCompoundPos('seemingly'), isNull); // 没有连字符
      expect(guessCompoundPos('waiting-times'), isNull); // 末段判不出
      expect(guessCompoundPos(null), isNull);
      expect(guessCompoundPos(''), isNull);
    });
  });
}
