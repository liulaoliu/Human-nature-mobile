import 'package:dlaoshi_app/core/ecdict.dart' show LemmaPair;
import 'package:dlaoshi_app/core/vocab/analysis.dart';
import 'package:dlaoshi_app/core/vocab/library.dart';
import 'package:dlaoshi_app/core/vocab/merge.dart' show dedupeLibrary;
import 'package:dlaoshi_app/models/vocab.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/vocab_fixture.dart';

final _now = DateTime.parse('2026-10-02T00:00:00.000Z');

void main() {
  group('markWord', () {
    test('新建词条，回填来源与例句', () {
      final r = markWord(
        createLibrary(),
        const MarkInput(
          word: 'Running',
          articleId: 'a1',
          fileName: 'f.mp3',
          sentenceId: 's001',
          sentenceText: 'He is running fast.',
        ),
        now: _now,
      );
      expect(r.created, isTrue);
      expect(r.item.lemma, 'run');
      expect(r.item.status, VocabStatus.unqueried);
      expect(r.item.examples, hasLength(1));
      expect(r.item.source?.articleId, 'a1');
      expect(r.item.source?.fileName, 'f.mp3');
      expect(r.item.source?.sentenceId, 's001');
      expect(r.library.items, hasLength(1));
    });

    test('按 lemma 去重：大小写 / 变形不新建', () {
      var lib = createLibrary();
      final first = markWord(
        lib,
        const MarkInput(
          word: 'running',
          articleId: 'a1',
          sentenceId: 's1',
          sentenceText: 'He is running.',
        ),
        now: _now,
      );
      lib = first.library;
      final second = markWord(
        lib,
        const MarkInput(
          word: 'Runs',
          articleId: 'a2',
          sentenceId: 's2',
          sentenceText: 'She runs daily.',
        ),
        now: _now,
      );
      expect(second.created, isFalse);
      expect(second.library.items, hasLength(1));
      expect(second.item.examples, hasLength(2));
      // 来源保留第一次的
      expect(second.item.source?.articleId, 'a1');
    });

    test('同一句重复标记不追加重复例句', () {
      var lib = createLibrary();
      lib = markWord(
        lib,
        const MarkInput(
          word: 'run',
          articleId: 'a1',
          sentenceId: 's1',
          sentenceText: 'Run!',
        ),
        now: _now,
      ).library;
      lib = markWord(
        lib,
        const MarkInput(
          word: 'run',
          articleId: 'a1',
          sentenceId: 's1',
          sentenceText: 'Run!',
        ),
        now: _now,
      ).library;
      expect(lib.items.first.examples, hasLength(1));
    });

    test('空词抛错', () {
      expect(
        () => markWord(
          createLibrary(),
          const MarkInput(word: '  ', articleId: 'a1'),
          now: _now,
        ),
        throwsArgumentError,
      );
    });

    test('命中被误标成 usage 的同名单词：改回单词、清掉旧语言点标记，并收进本篇', () {
      final lib = createLibrary().copyWith(
        items: [
          vocabItem(
            id: 'vocab:conglomerate',
            word: 'conglomerate',
            lemma: 'conglomerate',
            kind: VocabItemKind.usage,
            status: VocabStatus.queried,
            meaning: '企业集团',
          ),
        ],
      );
      final r = markWord(
        lib,
        const MarkInput(
          word: 'conglomerate',
          articleId: 'A',
          fileName: 'A',
          sentenceId: 's015',
          sentenceText: 'A family-controlled Danish conglomerate.',
        ),
        now: _now,
      );
      expect(r.created, isFalse);
      expect(r.item.kind, isNull);
      expect(r.item.langPointId, isNull);
      expect(
        r.library.articleEntries
            .any((e) => e.articleId == 'A' && e.lemma == 'conglomerate'),
        isTrue,
      );
    });
  });

  group('markWord 词组 / 带释义 / -ed 还原', () {
    test('markWord 可带释义（词组 — 中文 拆出来的），并直接标 queried', () {
      final r = markWord(
        createLibrary(),
        const MarkInput(word: 'fall back on', articleId: 'a1', meaning: '转而依靠'),
        now: _now,
      );
      expect(r.created, isTrue);
      expect(r.item.meaning, '转而依靠');
      expect(r.item.fieldSources, {VocabField.meaning: VocabFieldSource.manual});
      expect(r.item.status, VocabStatus.queried);
      // 短语不做词形还原
      expect(r.item.lemma, 'fall back on');
    });

    test('ensconced：启发式 lemma 不完美（ensconc），但原词形保留 + 词典可纠正', () {
      final r = markWord(
        createLibrary(),
        const MarkInput(
          word: 'ensconced',
          articleId: 'a1',
          sentenceText: 'He is ensconced in the job.',
        ),
        now: _now,
      );
      expect(r.created, isTrue);
      expect(r.item.word, 'ensconced');
      expect(r.item.lemma, 'ensconc');
    });
  });

  group('applyWordAnalysis', () {
    test('查词结果命中被误标成 usage 的单词：改回单词（本篇才看得到）', () {
      final lib = createLibrary().copyWith(
        items: [
          vocabItem(
            id: 'vocab:reckon',
            word: 'reckon',
            lemma: 'reckon',
            kind: VocabItemKind.usage,
            status: VocabStatus.queried,
            meaning: '认为；估算',
          ),
        ],
      );
      final out = applyWordAnalysis(
        lib,
        const [WordAnalysis(word: 'reckon', meaning: '认为')],
        now: _now,
      );
      final p = out.items.firstWhere((it) => it.lemma == 'reckon');
      expect(p.kind, isNull);
      expect(p.langPointId, isNull);

      // 中文用法笔记 / 真词组不受影响
      final note = applyWordAnalysis(
        createLibrary().copyWith(
          items: [
            vocabItem(
              id: 'vocab:n',
              word: '注意 purges 是名词',
              lemma: '注意 purges 是名词',
              kind: VocabItemKind.usage,
            ),
          ],
        ),
        const [WordAnalysis(word: 'purge', meaning: '清洗')],
        now: _now,
      );
      expect(
        note.items.firstWhere((it) => it.lemma == '注意 purges 是名词').kind,
        VocabItemKind.usage,
      );
    });

    test('把查词结果填进已有词条', () {
      var lib = markWord(
        createLibrary(),
        const MarkInput(
          word: 'run',
          articleId: 'a1',
          sentenceId: 's1',
          sentenceText: 'Run!',
        ),
        now: _now,
      ).library;
      lib = applyWordAnalysis(
        lib,
        const [
          WordAnalysis(
            word: 'running',
            phonetic: '/rʌŋɪŋ/',
            partOfSpeech: 'v.',
            meaning: '跑',
            usage: ['run a business'],
            examples: [(text: 'I run.', translation: '我跑。')],
          ),
        ],
        now: _now,
      );
      final it0 = lib.items.first;
      expect(it0.phonetic, '/rʌŋɪŋ/');
      expect(it0.meaning, '跑');
      expect(it0.usage, ['run a business']);
      expect(it0.status, VocabStatus.queried);
      expect(it0.examples, hasLength(2));
    });

    test('查词结果把 word/lemma/id 一起改成原形', () {
      var lib = markWord(
        createLibrary(),
        const MarkInput(word: 'companies', articleId: 'a1'),
        now: _now,
      ).library;
      expect(lib.items.first.lemma, 'company');
      lib = applyWordAnalysis(
        lib,
        const [WordAnalysis(word: 'company', meaning: '公司')],
        now: _now,
      );
      expect(lib.items.first.word, 'company');
      expect(lib.items.first.lemma, 'company');
      expect(lib.items.first.id, 'vocab:company');
    });

    test('手动改过的含义不被覆盖', () {
      var lib = markWord(
        createLibrary(),
        const MarkInput(word: 'run', articleId: 'a1'),
        now: _now,
      ).library;
      lib = editItem(
        lib,
        lib.items.first.id,
        const VocabItemPatch(meaning: '我自己的释义'),
        now: _now,
      );
      lib = applyWordAnalysis(
        lib,
        const [WordAnalysis(word: 'run', meaning: '跑')],
        now: _now,
      );
      expect(lib.items.first.meaning, '我自己的释义');
      expect(lib.items.first.status, VocabStatus.edited);
    });

    test('只锁手动改过的字段，其他字段仍可由 AI 补', () {
      var lib = markWord(
        createLibrary(),
        const MarkInput(word: 'run', articleId: 'a1'),
        now: _now,
      ).library;
      lib = editItem(
        lib,
        lib.items.first.id,
        const VocabItemPatch(meaning: '我的释义'),
        now: _now,
      );
      lib = applyWordAnalysis(
        lib,
        const [
          WordAnalysis(
            word: 'run',
            phonetic: '/rʌn/',
            meaning: '跑',
            definition: 'to move fast',
          ),
        ],
        now: _now,
      );
      final it = lib.items.first;
      expect(it.meaning, '我的释义');
      expect(it.phonetic, '/rʌn/');
      expect(it.definition, 'to move fast');
      expect(it.fieldSources, {
        VocabField.meaning: VocabFieldSource.manual,
        VocabField.phonetic: VocabFieldSource.ai,
        VocabField.definition: VocabFieldSource.ai,
      });
    });

    test('新词条逐字段记来源（AI 没给的由词典补）', () {
      final lib = applyWordAnalysis(
        createLibrary(),
        const [
          WordAnalysis(
            word: 'run',
            phonetic: '/rʌn/',
            partOfSpeech: 'v.',
            meaning: '跑',
            definition: 'to move fast',
            fieldSources: {VocabField.meaning: VocabFieldSource.dict},
          ),
        ],
        now: _now,
      );
      expect(lib.items.first.fieldSources, {
        VocabField.phonetic: VocabFieldSource.ai,
        VocabField.partOfSpeech: VocabFieldSource.ai,
        VocabField.meaning: VocabFieldSource.dict,
        VocabField.definition: VocabFieldSource.ai,
      });
    });

    test('没标记过的词也会建条目', () {
      final lib = applyWordAnalysis(
        createLibrary(),
        const [WordAnalysis(word: 'phonics', meaning: '自然拼读法')],
        now: _now,
      );
      expect(lib.items, hasLength(1));
      expect(lib.items.first.status, VocabStatus.queried);
      expect(lib.items.first.source, isNull);
    });

    test('用法去重合并', () {
      var lib = markWord(
        createLibrary(),
        const MarkInput(word: 'run', articleId: 'a1'),
        now: _now,
      ).library;
      lib = applyWordAnalysis(
        lib,
        const [
          WordAnalysis(word: 'run', usage: ['run a business', 'run out']),
        ],
        now: _now,
      );
      lib = applyWordAnalysis(
        lib,
        const [
          WordAnalysis(word: 'running', usage: ['run out', 'run late']),
        ],
        now: _now,
      );
      expect(lib.items.first.usage, ['run a business', 'run out', 'run late']);
    });

    test('释义被换掉时词性跟着换（不能一个来自词典首义、一个来自 AI 语境义）', () {
      // consort 真实病例
      var lib = markWord(
        createLibrary(),
        const MarkInput(word: 'consort', articleId: 'a1'),
        now: _now,
      ).library;
      lib = applyWordAnalysis(
        lib,
        const [
          WordAnalysis(
            word: 'consort',
            partOfSpeech: 'n.',
            meaning: '配偶',
            fieldSources: {
              VocabField.partOfSpeech: VocabFieldSource.dict,
              VocabField.meaning: VocabFieldSource.dict,
            },
          ),
        ],
        now: _now,
      );
      expect(lib.items.first.partOfSpeech, 'n.');
      lib = applyWordAnalysis(
        lib,
        const [
          WordAnalysis(word: 'consort', partOfSpeech: 'v.', meaning: '交往；厮混'),
        ],
        now: _now,
      );
      expect(lib.items.first.meaning, '交往；厮混');
      expect(lib.items.first.partOfSpeech, 'v.');
    });

    test('释义一字未变、只有词性不同，也要改成 AI 的（词典给的词性只是占位）', () {
      // rival 真实病例
      var lib = markWord(
        createLibrary(),
        const MarkInput(word: 'rival', articleId: 'a1'),
        now: _now,
      ).library;
      lib = lib.copyWith(
        items: [
          lib.items.first.copyWith(
            partOfSpeech: () => 'n.',
            meaning: () => '与……匹敌',
            fieldSources: () => const {
              VocabField.partOfSpeech: VocabFieldSource.dict,
              VocabField.meaning: VocabFieldSource.ai,
            },
          ),
        ],
      );
      lib = applyWordAnalysis(
        lib,
        const [
          WordAnalysis(word: 'rival', partOfSpeech: 'v.', meaning: '与……匹敌'),
        ],
        now: _now,
      );
      expect(lib.items.first.partOfSpeech, 'v.');
      expect(
        lib.items.first.fieldSources?[VocabField.partOfSpeech],
        VocabFieldSource.ai,
      );
    });

    test('手动改过的词性不被 AI 覆盖', () {
      var lib = markWord(
        createLibrary(),
        const MarkInput(word: 'rival', articleId: 'a1'),
        now: _now,
      ).library;
      lib = editItem(
        lib,
        lib.items.first.id,
        const VocabItemPatch(partOfSpeech: 'n.'),
        now: _now,
      );
      lib = applyWordAnalysis(
        lib,
        const [
          WordAnalysis(word: 'rival', partOfSpeech: 'v.', meaning: '与……匹敌'),
        ],
        now: _now,
      );
      expect(lib.items.first.partOfSpeech, 'n.');
      expect(
        lib.items.first.fieldSources?[VocabField.partOfSpeech],
        VocabFieldSource.manual,
      );
    });

    test('释义变了但 AI 没给词性 → 旧的词典词性清掉，别硬凑', () {
      var lib = markWord(
        createLibrary(),
        const MarkInput(word: 'dwarf', articleId: 'a1'),
        now: _now,
      ).library;
      lib = applyWordAnalysis(
        lib,
        const [
          WordAnalysis(
            word: 'dwarf',
            partOfSpeech: 'n.',
            meaning: '矮子',
            fieldSources: {
              VocabField.partOfSpeech: VocabFieldSource.dict,
              VocabField.meaning: VocabFieldSource.dict,
            },
          ),
        ],
        now: _now,
      );
      lib = applyWordAnalysis(
        lib,
        const [WordAnalysis(word: 'dwarf', meaning: '使相形见绌')],
        now: _now,
      );
      expect(lib.items.first.meaning, '使相形见绌');
      expect(lib.items.first.partOfSpeech, isNull);
    });

    test('释义没变就只补空（不无谓改词性）', () {
      var lib = markWord(
        createLibrary(),
        const MarkInput(word: 'run', articleId: 'a1'),
        now: _now,
      ).library;
      lib = applyWordAnalysis(
        lib,
        const [
          WordAnalysis(
            word: 'run',
            partOfSpeech: 'v.',
            meaning: '跑',
            fieldSources: {
              VocabField.partOfSpeech: VocabFieldSource.dict,
              VocabField.meaning: VocabFieldSource.dict,
            },
          ),
        ],
        now: _now,
      );
      lib = applyWordAnalysis(
        lib,
        const [WordAnalysis(word: 'run', meaning: '跑')],
        now: _now,
      );
      expect(lib.items.first.partOfSpeech, 'v.');
    });

    test('新词条带上默认来源（用于归属到当前文章）', () {
      const src = VocabSource(
        articleId: 'a1',
        fileName: 'art-A',
        sentenceId: 's1',
        sentenceText: 'Foo bar.',
      );
      final lib = applyWordAnalysis(
        createLibrary(),
        const [WordAnalysis(word: 'foo', meaning: 'x')],
        now: _now,
        defaultSource: src,
      );
      expect(lib.items.first.source?.articleId, 'a1');
      expect(lib.items.first.source?.fileName, 'art-A');
      expect(lib.items.first.source?.sentenceId, 's1');
      expect(lib.items.first.source?.sentenceText, 'Foo bar.');
    });
  });

  group('applyConfusables', () {
    test('按 lemma 写回混淆项', () {
      var lib = markWord(
        createLibrary(),
        const MarkInput(word: 'adapt', articleId: 'a1'),
        now: _now,
      ).library;
      lib = applyConfusables(
        lib,
        const [
          ConfusableResult(
            word: 'adapts',
            confusables: [VocabConfusable(word: 'adopt', meaning: '采用')],
          ),
        ],
        VocabConfusableSource.ai,
        now: _now,
      );
      expect(lib.items.first.confusables, hasLength(1));
      expect(lib.items.first.confusables!.first.word, 'adopt');
      expect(lib.items.first.confusables!.first.meaning, '采用');
      expect(lib.items.first.confusablesSource, VocabConfusableSource.ai);
    });

    test('写入时按调用方标来源（离线词典）', () {
      var lib = markWord(
        createLibrary(),
        const MarkInput(word: 'adapt', articleId: 'a1'),
        now: _now,
      ).library;
      lib = applyConfusables(
        lib,
        const [
          ConfusableResult(
            word: 'adapt',
            confusables: [VocabConfusable(word: 'adopt')],
          ),
        ],
        VocabConfusableSource.dict,
        now: _now,
      );
      expect(lib.items.first.confusablesSource, VocabConfusableSource.dict);
    });

    test('匹配不到的词条不动', () {
      final lib = applyConfusables(
        createLibrary(),
        const [
          ConfusableResult(
            word: 'zzz',
            confusables: [VocabConfusable(word: 'x')],
          ),
        ],
        VocabConfusableSource.ai,
        now: _now,
      );
      expect(lib.items, isEmpty);
    });

    test('去重合并（dedupeLibrary）', () {
      final a = vocabItem(
        id: 'vocab:a',
        word: 'adapt',
        lemma: 'adapt',
        confusables: const [VocabConfusable(word: 'adopt')],
      );
      final b = vocabItem(
        id: 'vocab:b',
        word: 'adapt',
        lemma: 'adapt',
        confusables: const [
          VocabConfusable(word: 'adopt'),
          VocabConfusable(word: 'adept'),
        ],
      );
      final lib = dedupeLibrary(
        const VocabLibrary(schemaVersion: 1).copyWith(items: [a, b]),
      );
      expect(lib.items, hasLength(1));
      expect(
        lib.items.first.confusables?.map((c) => c.word).toList(),
        ['adopt', 'adept'],
      );
    });
  });

  group('原形校正 / 去重', () {
    test('applyLemmaMap 把非原型改为原形（word/lemma/id）', () {
      var lib = markWord(
        createLibrary(),
        const MarkInput(word: 'saw', articleId: 'a1'),
        now: _now,
      ).library;
      lib = applyLemmaMap(
        lib,
        const [LemmaPair(from: 'saw', to: 'see')],
        now: _now,
      );
      expect(lib.items.first.word, 'see');
      expect(lib.items.first.lemma, 'see');
      expect(lib.items.first.id, 'vocab:see');
    });

    test('applyLemmaMap 后 dedupe 合并同一原形的词', () {
      var lib = markWord(
        createLibrary(),
        const MarkInput(word: 'seen', articleId: 'a1'),
        now: _now,
      ).library;
      lib = markWord(
        lib,
        const MarkInput(word: 'saw', articleId: 'a1'),
        now: _now,
      ).library;
      expect(lib.items, hasLength(2)); // seen / saw 是两个 lemma
      lib = applyLemmaMap(
        lib,
        const [LemmaPair(from: 'seen', to: 'see'), LemmaPair(from: 'saw', to: 'see')],
        now: _now,
      );
      lib = dedupeLibrary(lib);
      expect(lib.items, hasLength(1));
      expect(lib.items.first.lemma, 'see');
    });

    test('relemmaLibrary 按 word 重算 lemma', () {
      final lib = createLibrary().copyWith(
        items: [vocabItem(id: 'vocab:x', word: 'running', lemma: 'running')],
      );
      expect(relemmaLibrary(lib).items.first.lemma, 'run');
    });
  });

  group('applyPosAnalysis', () {
    const row = PosRow(
      lemma: 'slide',
      surface: 'sliding',
      pos: 'adj.',
      syntax: '现在分词转化来的形容词，作定语',
      role: '修饰 prices',
      meaning: '持续下跌的',
      reason: '相当于 prices that are sliding',
      label: 'adj.（分词形容词）',
    );

    test('单词条目按原形改写并写入词性 / 笔记', () {
      var lib = markWord(
        createLibrary(),
        const MarkInput(word: 'sliding', articleId: 'a1'),
        now: _now,
      ).library;
      lib = applyPosAnalysis(lib, const [row], now: _now);
      expect(lib.items.first.word, 'slide');
      expect(lib.items.first.lemma, 'slide');
      expect(lib.items.first.partOfSpeech, 'adj.');
      expect(lib.items.first.note, contains('辨析'));
    });

    test('手动改过的词性不被 AI 辨析覆盖', () {
      var lib = markWord(
        createLibrary(),
        const MarkInput(word: 'sliding', articleId: 'a1'),
        now: _now,
      ).library;
      lib = editItem(
        lib,
        lib.items.first.id,
        const VocabItemPatch(partOfSpeech: 'n.'),
        now: _now,
      );
      lib = applyPosAnalysis(lib, const [row], now: _now);
      final it = lib.items.first;
      expect(it.partOfSpeech, 'n.');
      expect(it.fieldSources?[VocabField.partOfSpeech], VocabFieldSource.manual);
      expect(it.note, contains('辨析'));
    });

    test('短语条目不改词形，只记笔记', () {
      var lib = markWord(
        createLibrary(),
        const MarkInput(word: 'sliding oil price', articleId: 'a1'),
        now: _now,
      ).library;
      lib = applyPosAnalysis(lib, const [row], now: _now);
      expect(lib.items.first.word, 'sliding oil price');
      expect(lib.items.first.note, contains('辨析'));
    });

    test('派生词当原形时**不改词形**（unchallenged 不能被改成 challenge）', () {
      // 真实病例：辨析说 unchallenged 的原形是 challenge，改完 challenge 卡上挂着
      // unchallenged 的词典释义 → 词性释义全错位
      var lib = markWord(
        createLibrary(),
        const MarkInput(word: 'unchallenged', articleId: 'a1'),
        now: _now,
      ).library;
      lib = applyPosAnalysis(
        lib,
        const [
          PosRow(
            lemma: 'challenge',
            surface: 'unchallenged',
            pos: 'adj.',
            meaning: '未受质疑的',
          ),
        ],
        now: _now,
      );
      final it = lib.items.first;
      expect(it.word, 'unchallenged');
      expect(it.lemma, 'unchalleng'); // 启发性 lemma，但**没有**被改成 challenge
      expect(it.partOfSpeech, 'adj.');
      expect(it.note, contains('未改词形'));
    });

    test('真屈折照旧改词形（running → run）', () {
      var lib = markWord(
        createLibrary(),
        const MarkInput(word: 'running', articleId: 'a1'),
        now: _now,
      ).library;
      lib = applyPosAnalysis(
        lib,
        const [
          PosRow(
            lemma: 'run',
            surface: 'running',
            pos: 'v.',
            meaning: '跑',
          ),
        ],
        now: _now,
      );
      expect(lib.items.first.word, 'run');
    });
  });
}
