import 'package:dlaoshi_app/core/article_vocab.dart';
import 'package:dlaoshi_app/core/entry_kind.dart';
import 'package:dlaoshi_app/core/lang_points.dart';
import 'package:dlaoshi_app/core/vocab/library.dart';
import 'package:dlaoshi_app/core/vocab/merge.dart';
import 'package:dlaoshi_app/core/vocab/word.dart';
import 'package:dlaoshi_app/models/document.dart';
import 'package:dlaoshi_app/models/vocab.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/vocab_fixture.dart';

/// 语言点收藏（词组 / 习语 / 用法）的领域逻辑。
/// 用例逐条对照 Web 版 `src/core/langPoints.test.ts`。
const String now = '2026-10-02T00:00:00.000Z';

VocabSource _src(String articleId, String sentenceId,
        [String sentenceText = 'Sentence.']) =>
    VocabSource(
      articleId: articleId,
      fileName: articleId,
      sentenceId: sentenceId,
      sentenceText: sentenceText,
    );

LanguagePoint _p(
  VocabKind kind,
  String word,
  VocabSource source, {
  String? gloss,
}) =>
    LanguagePoint(kind: kind, word: word, gloss: gloss, source: source);

Sentence _sentence(String id, String text, List<SentenceLanguage> langs) =>
    Sentence(id: id, paraId: 'p01', text: text, languages: langs);

void main() {
  group('splitGlossText（拆「英文 — 中文」）', () {
    test('拆「英文 — 中文」（也认 – / -）', () {
      expect(splitGlossText('run out — 用完'), (word: 'run out', gloss: '用完'));
      expect(
        splitGlossText('take its toll – 造成损害'),
        (word: 'take its toll', gloss: '造成损害'),
      );
      expect(splitGlossText('ensconced'), (word: 'ensconced', gloss: null));
    });
  });

  group('语言点收进词库（upsertLanguagePoints）', () {
    test('词组 / 习语 / 用法各建一条，带类型与释义；重复调用返回同一个库（幂等）', () {
      final pts = [
        _p(VocabKind.phrase, 'fall back on', _src('A', 's1'), gloss: '转而依靠'),
        _p(VocabKind.idiom, 'take its toll', _src('A', 's2'), gloss: '造成损害'),
        _p(VocabKind.usage, '注意 subject to 是形容词', _src('A', 's3')),
      ];
      final lib = upsertLanguagePoints(createLibrary(), pts, now: DateTime.parse(now));
      expect(lib.items, hasLength(3));
      final phrase = lib.items.firstWhere((it) => it.lemma == 'fall back on');
      expect(kindOfItem(phrase), VocabKind.phrase);
      expect(phrase.meaning, '转而依靠');
      expect(phrase.status, VocabStatus.queried); // 语言点直接带释义收进来，没有「待查」
      expect(phrase.contexts, hasLength(1));
      // 语言点也要有本篇归属：侧栏语言点页签 / 按篇打印靠它
      expect(
        lib.articleEntries.map((e) => '${e.articleId}:${e.lemma}:${e.origin.name}'),
        [
          'A:fall back on:auto',
          'A:take its toll:auto',
          'A:${textKey('注意 subject to 是形容词')}:auto',
        ],
      );
      final usage = lib.items.firstWhere((it) => it.kind == VocabItemKind.usage);
      expect(usage.word, '注意 subject to 是形容词');
      expect(usage.meaning, isNull);
      // 幂等：再跑一次不该改动
      expect(identical(upsertLanguagePoints(lib, pts, now: DateTime.parse(now)), lib),
          isTrue);
    });

    test('同一词组在不同文章出现 → 累积语境，不重复建条', () {
      final first = upsertLanguagePoints(
        createLibrary(),
        [_p(VocabKind.phrase, 'run out', _src('A', 's1'), gloss: '用完')],
        now: DateTime.parse(now),
      );
      final second = upsertLanguagePoints(
        first,
        [
          _p(VocabKind.phrase, 'Run out', _src('B', 's9', 'We ran out of time.'),
              gloss: '用完'),
        ],
        now: DateTime.parse(now),
      );
      expect(second.items, hasLength(1));
      expect(second.items[0].contexts, hasLength(2));
    });

    test('已经手动加进生词本的词组：补上类型与释义，不新建重复条', () {
      final base = createLibrary().copyWith(items: [
        VocabItem(
          id: 'vocab:fall back on',
          word: 'fall back on',
          lemma: 'fall back on',
          createdAt: now,
          updatedAt: now,
        ),
      ]);
      final next = upsertLanguagePoints(
        base,
        [_p(VocabKind.phrase, 'fall back on', _src('A', 's1'), gloss: '转而依靠')],
        now: DateTime.parse(now),
      );
      expect(next.items, hasLength(1));
      expect(next.items[0].kind, VocabItemKind.phrase);
      expect(next.items[0].meaning, '转而依靠');
    });

    test('中文用法笔记不跟单词撞车：另建一条，也不会把已有单词改成「用法」', () {
      final lib0 = createLibrary().copyWith(items: [
        VocabItem(
          id: 'vocab:purge',
          word: 'purge',
          lemma: 'purge',
          createdAt: now,
          updatedAt: now,
        ),
      ]);
      final lib = upsertLanguagePoints(
        lib0,
        [_p(VocabKind.usage, '注意 purges 在这里是名词复数', _src('A', 's1'))],
        now: DateTime.parse(now),
      );
      expect(lib.items, hasLength(2));
      final word = lib.items.firstWhere((it) => it.lemma == 'purge');
      expect(kindOf(kind: kindOfItem(word), word: word.word), VocabKind.word);
      final note =
          lib.items.firstWhere((it) => kindOfItem(it) == VocabKind.usage);
      expect(note.word, '注意 purges 在这里是名词复数');
      expect(note.lemma, textKey('注意 purges 在这里是名词复数')); // 按整条文本做键
    });

    test('单个英文单词写进「词组」栏：当普通单词收（不标类型），多词的才标 词组', () {
      final lib = upsertLanguagePoints(
        createLibrary(),
        [
          _p(VocabKind.phrase, 'purges', _src('A', 's1'), gloss: '清洗'),
          _p(VocabKind.phrase, 'fall back on', _src('A', 's2'), gloss: '转而依靠'),
        ],
        now: DateTime.parse(now),
      );
      expect(lib.items.firstWhere((it) => it.lemma == 'purge').kind, isNull);
      expect(
        lib.items.firstWhere((it) => it.lemma == 'fall back on').kind,
        VocabItemKind.phrase,
      );
    });

    test('单个英文单词写进「用法」栏也当单词：不标 usage、键用原形', () {
      final kk = langPointKeyAndKind(_p(VocabKind.usage, 'conglomerate', _src('A', 's1')));
      expect(kk.key, 'conglomerate');
      expect(kk.kind, isNull);

      const note = 'conglomerate 企业集团';
      final kk2 = langPointKeyAndKind(_p(VocabKind.usage, note, _src('A', 's1')));
      expect(kk2.key, textKey(note));
      expect(kk2.kind, VocabKind.usage);

      final lib = upsertLanguagePoints(
        createLibrary(),
        [_p(VocabKind.usage, 'reckon', _src('A', 's2'))],
        now: DateTime.parse(now),
      );
      final it = lib.items.firstWhere((x) => x.lemma == 'reckon');
      expect(kindOf(kind: kindOfItem(it), word: it.word), VocabKind.word);
      expect(it.kind, isNull);
    });

    test('语言点标记（langPointId）：词形被改写后也不会重复收同一条', () {
      final source =
          _src('A', 's1', 'We fall back on it.');
      final points = [_p(VocabKind.phrase, 'fall back on', source, gloss: '转而依靠')];
      final lib = upsertLanguagePoints(createLibrary(), points,
          now: DateTime.parse(now));
      expect(lib.items[0].langPointId, contains('fall back on'));
      // 模拟词典把它改名成别的词形：再收一次不该新建
      final renamed = lib.copyWith(items: [
        lib.items[0].copyWith(word: 'fallback', lemma: 'fallback'),
      ]);
      final again = upsertLanguagePoints(renamed, points,
          now: DateTime.parse(now));
      expect(again.items, hasLength(1));
    });

    test('repairLanguageKinds：修早先版本误标（单词被标成用法/词组），真笔记不动', () {
      final lib = dedupeLibrary(createLibrary().copyWith(items: [
        vocabItem(id: 'a', word: 'purge', lemma: 'purge', kind: VocabItemKind.usage),
        vocabItem(id: 'b', word: 'alga', lemma: 'alga', kind: VocabItemKind.phrase),
        vocabItem(
            id: 'c',
            word: '注意 purges 是名词',
            lemma: '注意 purges 是名词',
            kind: VocabItemKind.usage),
        vocabItem(
            id: 'd',
            word: 'fall back on',
            lemma: 'fall back on',
            kind: VocabItemKind.phrase),
        vocabItem(
                id: 'e',
                word: '注意 purges 在这里是名词复数',
                lemma: '注意 purges 在这里是名词复数',
                kind: VocabItemKind.usage,
                status: VocabStatus.queried)
            .copyWith(langPointId: () => 'usage|A|s1|注意 purges 在这里是名词复数'),
      ]));
      final out = repairLanguageKinds(lib);
      final byId = {for (final it in out.items) it.id: it};
      expect(byId['a']!.kind, isNull);
      expect(byId['b']!.kind, isNull);
      expect(byId['c']!.kind, VocabItemKind.usage);
      expect(byId['d']!.kind, VocabItemKind.phrase);
      expect(byId['e']!.kind, VocabItemKind.usage);
      expect(identical(repairLanguageKinds(out), out), isTrue); // 幂等
    });

    test('repairLanguageKinds：带旧 langPointId 的单单词 usage 也改回单词（本篇不再丢词）', () {
      final lib = createLibrary().copyWith(
        items: [
          vocabItem(
            id: 'vocab:conglomerate',
            word: 'conglomerate',
            lemma: 'conglomerate',
            kind: VocabItemKind.usage,
            status: VocabStatus.queried,
            meaning: '企业集团',
          ).copyWith(langPointId: () => 'usage|A|s1|conglomerate 企业集团'),
        ],
        articleEntries: [
          articleEntry(
            articleId: 'A',
            lemma: 'conglomerate',
            origin: VocabOrigin.auto,
            addedAt: now,
            sentenceId: 's1',
            sentenceText: 'A family-controlled Danish conglomerate.',
          ),
        ],
      );
      final out = repairLanguageKinds(lib);
      expect(out.items[0].kind, isNull);
      expect(out.items[0].langPointId, isNull);
      expect(kindOfItem(out.items[0]), VocabKind.word);
      expect(out.articleEntries[0].lemma, 'conglomerate');
      expect(identical(repairLanguageKinds(out), out), isTrue); // 幂等
    });

    test('repairLanguageKinds：旧 usage 笔记占着英文词键 → 改用整条文本键', () {
      const note = 'mantra 本义为\u201c曼怛罗、祷文\u201d，引申为反复强调的口头禅。';
      final legacy = createLibrary().copyWith(
        items: [
          vocabItem(
            id: 'vocab:mantra',
            word: note,
            lemma: 'mantra',
            kind: VocabItemKind.usage,
            status: VocabStatus.queried,
          ),
        ],
        articleEntries: [
          articleEntry(
            articleId: 'A',
            lemma: 'mantra',
            origin: VocabOrigin.manual,
            addedAt: now,
            sentenceId: 's010',
            sentenceText: 'Mrs May\u2019s mantra.',
          ),
        ],
      );
      final out = repairLanguageKinds(legacy);
      final fixed = out.items[0];
      expect(fixed.lemma, textKey(note));
      expect(fixed.id, 'vocab:${textKey(note)}');
      expect(fixed.kind, VocabItemKind.usage);
      expect(out.articleEntries[0].lemma, textKey(note)); // 按篇条目跟着改名
      expect(identical(repairLanguageKinds(out), out), isTrue); // 幂等
    });

    test('类型过滤：词组可背、用法笔记不背', () {
      final lib = upsertLanguagePoints(
        createLibrary(),
        [
          _p(VocabKind.phrase, 'run out', _src('A', 's1'), gloss: '用完'),
          _p(VocabKind.idiom, 'take its toll', _src('A', 's2'), gloss: '造成损害'),
          _p(VocabKind.usage, '注意 subject to 是形容词', _src('A', 's3')),
        ],
        now: DateTime.parse(now),
      );
      final studyable = lib.items
          .where((it) =>
              isStudyable(kind: kindOfItem(it), word: it.word, meaning: it.meaning))
          .map((it) => it.word)
          .toList();
      expect(studyable, ['run out', 'take its toll']);
      expect(
        lib.items
            .where((it) =>
                isWordEntry(kind: kindOfItem(it), word: it.word))
            .length,
        0,
      );
      expect(kindOfItem(lib.items[0]), VocabKind.phrase);
    });
  });

  group('languagePointsOf（从句子语言点抽条目）', () {
    test('抽三类条目：词组/习语拆「英文 — 中文」，用法整条保留，都带来源句', () {
      final pts = languagePointsOf(
        [
          _sentence('s1', 'It takes its toll and we fall back on it.', const [
            SentenceLanguage(
              phrases: ['fall back on — 转而依靠'],
              idioms: ['take its toll — 造成损害'],
              usage: ['注意 subject to 这里是形容词'],
              source: LanguageSource.ai,
            ),
          ]),
        ],
        articleId: 'A',
        fileName: 'A',
      );
      expect(pts.map((p) => [p.kind, p.word, p.gloss]), [
        [VocabKind.phrase, 'fall back on', '转而依靠'],
        [VocabKind.idiom, 'take its toll', '造成损害'],
        [VocabKind.usage, '注意 subject to 这里是形容词', null],
      ]);
      final s0 = pts[0].source;
      expect(s0.articleId, 'A');
      expect(s0.fileName, 'A');
      expect(s0.sentenceId, 's1');
      expect(s0.sentenceText, 'It takes its toll and we fall back on it.');
    });

    test('空句数组 / 没有语言点 → 空；兼容旧的单条 language 字段', () {
      expect(languagePointsOf(const [], articleId: 'A'), isEmpty);
      expect(
        languagePointsOf([_sentence('s1', 'Plain.', const [])], articleId: 'A'),
        isEmpty,
      );
      final legacy = Sentence(
        id: 's2',
        paraId: 'p01',
        text: 'Old.',
        language: const SentenceLanguage(phrases: ['run out']),
      );
      expect(languagePointsOf([legacy], articleId: 'A').map((p) => p.word),
          ['run out']);
    });
  });

  group('键 / 类型规则（langPointKeyAndKind）与分组', () {
    final source = _src('A', 's1');

    test('用法笔记 / 没有英文的说明：整条文本当键，类型 usage', () {
      expect(
        langPointKeyAndKind(_p(VocabKind.usage, '注意 purges 是名词', source)),
        (key: textKey('注意 purges 是名词'), kind: VocabKind.usage),
      );
      expect(
        langPointKeyAndKind(_p(VocabKind.phrase, '「死马当活马医」', source)),
        (key: textKey('「死马当活马医」'), kind: VocabKind.usage),
      );
    });

    test('单个英文单词（AI 写进词组栏）→ 当普通单词；多词 → 按原形，保留词组类型', () {
      expect(
        langPointKeyAndKind(_p(VocabKind.phrase, 'purges', source)),
        (key: lemmaOf('purges'), kind: null),
      );
      expect(
        langPointKeyAndKind(_p(VocabKind.idiom, 'take its toll', source)),
        (key: 'take its toll', kind: VocabKind.idiom),
      );
    });

    test('langPointId / 签名：同篇同句同文只算一条；内容变了签名才变', () {
      final a = _p(VocabKind.phrase, 'run out', source, gloss: '用完');
      final b = _p(VocabKind.phrase, 'run out', source, gloss: '用光');
      expect(langPointIdOf(a), langPointIdOf(
          _p(VocabKind.phrase, 'run out', source, gloss: '别的释义')));
      expect(langPointSignature([a]), isNot(langPointSignature([b])));
      expect(langPointSignature([a, _p(VocabKind.phrase, 'run in', source)]).keys,
          ['A']);
    });

    test('groupLangPoints：按 词组 / 习语 / 用法 分组，空组不出现', () {
      final lib = upsertLanguagePoints(
        createLibrary(),
        [
          _p(VocabKind.phrase, 'run out', source, gloss: '用完'),
          _p(VocabKind.idiom, 'take its toll', _src('A', 's2'), gloss: '造成损害'),
          _p(VocabKind.usage, '注意 run out 是动词短语', _src('A', 's3')),
        ],
        now: DateTime.parse(now),
      );
      expect(groupLangPoints(lib.items).map((g) => (g.kind, g.items.length)), [
        (VocabKind.phrase, 1),
        (VocabKind.idiom, 1),
        (VocabKind.usage, 1),
      ]);
    });
  });
}
