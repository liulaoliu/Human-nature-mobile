/// `core/production.dart` 的测试：选目标块、目标块校验、挖空 / 排序提示、设置守卫。
///
/// 用例逐条照搬 Web 版 `src/core/production.test.ts`（427 行）。
library;

import 'package:dlaoshi_app/core/production.dart';
import 'package:dlaoshi_app/models/document.dart';
import 'package:dlaoshi_app/models/vocab.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/vocab_fixture.dart';

ProductionTarget _target({
  String id = 'v1|self|word',
  String itemId = 'v1',
  ProductionTargetKind kind = ProductionTargetKind.word,
  String text = 'run',
  String meaning = '跑',
}) =>
    ProductionTarget(
      id: id,
      itemId: itemId,
      kind: kind,
      text: text,
      meaning: meaning,
    );

VocabItem _item({
  required String id,
  required String word,
  String? meaning,
  String? lemma,
  VocabItemKind? kind,
  List<String>? phrases,
  List<String>? idioms,
  ReviewState reviewState = defaultReviewState,
  VocabSource? source,
}) =>
    vocabItem(
      id: id,
      word: word,
      lemma: lemma ?? word,
      meaning: meaning,
      kind: kind,
      phrases: phrases,
      idioms: idioms,
      reviewState: reviewState,
      source: source,
    );

void main() {
  group('buildProductionTargets：选词块', () {
    final weak = _item(
      id: 'v1',
      word: 'run',
      meaning: '跑',
      reviewState: const ReviewState(lapses: 2, repetitions: 5),
      source: const VocabSource(
        articleId: 'A',
        fileName: 'A',
        sentenceText: '',
      ),
      phrases: <String>['run out — 用完'],
      idioms: <String>['run in the family — 家族遗传'],
    );
    final strong = _item(
      id: 'v2',
      word: 'curb',
      meaning: '抑制',
      reviewState: const ReviewState(repetitions: 6),
      source: const VocabSource(
        articleId: 'A',
        fileName: 'A',
        sentenceText: '',
      ),
    );
    final other = _item(
      id: 'v3',
      word: 'anchor',
      meaning: '锚',
      source: const VocabSource(
        articleId: 'B',
        fileName: 'B',
        sentenceText: '',
      ),
    );

    test('按范围 + 类型取；词条本身 + phrases/idioms 都算目标块', () {
      final pool = buildProductionTargets(BuildProductionTargetsOptions(
        items: <VocabItem>[weak, strong, other],
        scope: ProductionScope.all,
        articleIdentity: 'A',
        types: const <ProductionTargetKind>[
          ProductionTargetKind.word,
          ProductionTargetKind.phrase,
          ProductionTargetKind.idiom,
        ],
        limit: 10,
        weakRatio: 0,
        rng: () => 0,
      ));
      final texts = pool.targets.map((t) => t.text).toList();
      expect(
        texts,
        containsAll(<String>[
          'run',
          'run out',
          'run in the family',
          'curb',
          'anchor',
        ]),
      );
      expect(
        pool.targets.firstWhere((t) => t.text == 'run out').meaning,
        '用完',
      );
    });

    test('单词被旧数据误标 usage：仍按单词出目标', () {
      final stale = _item(
        id: 'v4',
        word: 'run',
        kind: VocabItemKind.usage,
        meaning: '跑',
      );
      final pool = buildProductionTargets(BuildProductionTargetsOptions(
        items: <VocabItem>[stale],
        scope: ProductionScope.all,
        articleIdentity: 'A',
        types: const <ProductionTargetKind>[ProductionTargetKind.word],
        limit: 10,
        weakRatio: 0,
        rng: () => 0,
      ));
      expect(pool.targets.map((t) => t.text), <String>['run']);
    });

    test('本篇范围只取 source/正文 lemmas 命中的', () {
      final withLemma = buildProductionTargets(BuildProductionTargetsOptions(
        items: <VocabItem>[weak, strong, other],
        scope: ProductionScope.article,
        articleIdentity: 'A',
        docLemmas: <String>{'anchor'},
        types: const <ProductionTargetKind>[ProductionTargetKind.word],
        limit: 10,
        weakRatio: 0,
        rng: () => 0,
      ));
      expect(
        withLemma.targets.map((t) => t.itemId).toList()..sort(),
        <String>['v1', 'v2', 'v3'],
      );

      final onlyA = buildProductionTargets(BuildProductionTargetsOptions(
        items: <VocabItem>[weak, strong, other],
        scope: ProductionScope.article,
        articleIdentity: 'A',
        types: const <ProductionTargetKind>[ProductionTargetKind.word],
        limit: 10,
        weakRatio: 0,
        rng: () => 0,
      ));
      expect(
        onlyA.targets.map((t) => t.text).toList()..sort(),
        <String>['curb', 'run'],
      );
    });

    test('薄弱比例：优先取有 lapses / 复习次数少的词，不够再用正常词补', () {
      final pool = buildProductionTargets(BuildProductionTargetsOptions(
        items: <VocabItem>[weak, strong],
        scope: ProductionScope.all,
        articleIdentity: 'A',
        types: const <ProductionTargetKind>[ProductionTargetKind.word],
        limit: 2,
        weakRatio: 100,
        rng: () => 0,
      ));
      expect(pool.targets.any((t) => t.text == 'run'), isTrue);
      expect(pool.targets, hasLength(2));
      expect(pool.weak, 1);
    });

    test('类型为空 / 词池为空：返回空，不炸', () {
      final pool = buildProductionTargets(BuildProductionTargetsOptions(
        items: <VocabItem>[weak],
        scope: ProductionScope.all,
        articleIdentity: 'A',
        types: const <ProductionTargetKind>[],
        limit: 5,
        weakRatio: 30,
      ));
      expect(pool.targets, isEmpty);
    });
  });

  group('targetUsed / checkProductionTargets：目标块硬校验', () {
    test('单词允许常见词形后缀，词组按连续文本匹配', () {
      expect(targetUsed('I am running daily.', _target()), isTrue);
      expect(targetUsed('I ran daily.', _target()), isTrue);
      expect(
        targetUsed(
          'We need to run out of time.',
          _target(kind: ProductionTargetKind.phrase, text: 'run out'),
        ),
        isTrue,
      );
      expect(
        targetUsed(
          'We run quickly out of time.',
          _target(kind: ProductionTargetKind.phrase, text: 'run out'),
        ),
        isTrue,
      );
      expect(
        targetUsed(
          'run-out',
          _target(kind: ProductionTargetKind.phrase, text: 'run out'),
        ),
        isFalse,
      );
    });

    test('挖空 / 词序提示只改展示，不破坏原句', () {
      const model = 'I will follow up with the client.';
      final out = clozeSentence(
        model,
        <ProductionTarget>[
          _target(kind: ProductionTargetKind.phrase, text: 'follow up'),
        ],
      );
      expect(out, contains('_____'));
      expect(out, isNot(contains('follow up')));
      expect(model, 'I will follow up with the client.');

      final parts = clozeParts(
        model,
        <ProductionTarget>[
          _target(kind: ProductionTargetKind.phrase, text: 'follow up'),
        ],
      );
      expect(parts.where((p) => p.target != null), hasLength(1));
      expect(
        parts.map((p) => p.target != null ? 'BLANK' : p.text).join(),
        contains('BLANK'),
      );

      final shuffled = shuffledWords(model, 'p1')..sort();
      final original = model.split(' ').toList()..sort();
      expect(shuffled, original);
    });

    test('逐项命中；全中 exact', () {
      final hits = checkProductionTargets('I run out every morning.', <ProductionTarget>[
        _target(),
        _target(
          id: 'p1',
          kind: ProductionTargetKind.phrase,
          text: 'run out',
        ),
      ]);
      expect(hits.map((h) => h.used), <bool>[true, true]);
      expect(checkProductionTargets('nothing', <ProductionTarget>[_target()])[0].used,
          isFalse);
    });
  });

  group('ProductionSettings / doc lemmas', () {
    test('坏设置逐项回默认', () {
      expect(normalizeProductionSettings(null), defaultProductionSettings);
      expect(
        normalizeProductionSettings(<String, Object?>{
          'topic': '  x  ',
          'angle': 'bad',
          'tone': 'bad',
          'scope': 'bad',
          'types': <Object?>['word', 'bad', 'word'],
          'promptCount': 4,
          'targetsPerPrompt': 9,
          'weakRatio': 31,
        }),
        defaultProductionSettings.copyWith(
          topic: 'x',
          types: const <ProductionTargetKind>[ProductionTargetKind.word],
        ),
      );
      final yogurt = normalizeProductionSettings(<String, Object?>{
        'mode': 'yogurt',
        'sourceText': '中文',
        'referenceText': 'English',
      });
      expect(yogurt.mode, ProductionMode.yogurt);
      expect(yogurt.sourceText, '中文');
      expect(yogurt.referenceText, 'English');

      final chunks = normalizeProductionSettings(<String, Object?>{
        'fullUseChunks': false,
        'skimUseChunks': true,
      });
      expect(chunks.fullUseChunks, isFalse);
      expect(chunks.skimUseChunks, isTrue);
    });

    test('设置能序列化再读回来', () {
      final s = defaultProductionSettings.copyWith(
        mode: ProductionMode.yogurt,
        topic: '远程办公',
        promptCount: 8,
        types: const <ProductionTargetKind>[
          ProductionTargetKind.phrase,
          ProductionTargetKind.idiom,
        ],
      );
      final back = normalizeProductionSettings(productionSettingsToJson(s));
      expect(back, s);
    });

    test('正文词 + 语言点词都算本篇 lemma', () {
      const s = Sentence(
        id: 's1',
        paraId: 'p1',
        text: 'A run.',
        vocab: <String>['run'],
        languages: <SentenceLanguage>[
          SentenceLanguage(
            phrases: <String>['run out'],
            idioms: <String>['run in the family'],
          ),
        ],
      );
      expect(
        productionDocLemmas(<Sentence>[s]).toList()..sort(),
        <String>['run', 'run in the family', 'run out'],
      );
    });
  });

  group('进度范围：weak / due / mistakes 用 attempts 现算的进度筛选', () {
    final weak = _item(id: 'v1', word: 'run', meaning: '跑');
    final strong = _item(id: 'v2', word: 'curb', meaning: '抑制');
    final progress = <ProductionProgressLike>[
      const ProductionProgressLike(
        key: 'word:run',
        kind: ProductionTargetKind.word,
        text: 'run',
        attempts: 2,
        hits: 0,
        misses: 2,
        lastAt: '2026-11-01T00:00:00.000Z',
        dueAt: '2026-11-01T00:00:00.000Z',
      ),
      const ProductionProgressLike(
        key: 'word:curb',
        kind: ProductionTargetKind.word,
        text: 'curb',
        attempts: 2,
        hits: 2,
        misses: 0,
        lastAt: '2026-11-01T00:00:00.000Z',
        dueAt: '2027-01-01T00:00:00.000Z',
      ),
    ];
    final now = DateTime.parse('2026-11-05T00:00:00.000Z');

    BuildProductionTargetsOptions opts(ProductionScope scope) =>
        BuildProductionTargetsOptions(
          items: <VocabItem>[weak, strong],
          scope: scope,
          articleIdentity: 'A',
          types: const <ProductionTargetKind>[ProductionTargetKind.word],
          limit: 2,
          weakRatio: 0,
          progress: progress,
          now: now,
          rng: () => 0,
        );

    test('weak / mistakes / due 只出 run', () {
      expect(
        buildProductionTargets(opts(ProductionScope.weak))
            .targets
            .map((t) => t.text),
        <String>['run'],
      );
      expect(
        buildProductionTargets(opts(ProductionScope.mistakes))
            .targets
            .map((t) => t.text),
        <String>['run'],
      );
      expect(
        buildProductionTargets(opts(ProductionScope.due))
            .targets
            .map((t) => t.text),
        <String>['run'],
      );
    });

    test('recent 两个都出（都在 7 天内）', () {
      expect(
        buildProductionTargets(opts(ProductionScope.recent))
            .targets
            .map((t) => t.text),
        containsAll(<String>['run', 'curb']),
      );
    });

    test('范围没匹配时回退全库并给提示', () {
      final pool = buildProductionTargets(BuildProductionTargetsOptions(
        items: <VocabItem>[weak],
        scope: ProductionScope.theme,
        theme: '完全不存在的主题',
        articleIdentity: 'A',
        types: const <ProductionTargetKind>[ProductionTargetKind.word],
        limit: 5,
        rng: () => 0,
      ));
      expect(pool.targets.map((t) => t.text), <String>['run']);
      expect(pool.note, contains('已回退全库'));
    });
  });

  group('类型与范围口径', () {
    test('用法笔记不进候选池', () {
      final note = _item(
        id: 'u1',
        word: 'take 的用法',
        kind: VocabItemKind.usage,
        meaning: '表示花费时间',
      );
      expect(productionTargetCandidates(<VocabItem>[note], const <ProductionTargetKind>[
        ProductionTargetKind.word,
        ProductionTargetKind.phrase,
      ]), isEmpty);
    });

    test('没有释义的废卡不进候选池', () {
      final bare = _item(id: 'v9', word: 'zilch');
      expect(
        productionTargetCandidates(
          <VocabItem>[bare],
          const <ProductionTargetKind>[ProductionTargetKind.word],
        ),
        isEmpty,
      );
    });

    test('去重按「类型 + 文本」，跨词条重复只留一个', () {
      final a = _item(id: 'a', word: 'run', meaning: '跑');
      final b = _item(id: 'b', word: 'Run', meaning: '跑');
      final out = productionTargetCandidates(
        <VocabItem>[a, b],
        const <ProductionTargetKind>[ProductionTargetKind.word],
      );
      expect(out, hasLength(1));
      expect(out.first.itemId, 'a');
    });

    test('到期范围一天最多 6 个', () {
      expect(dueDailyCapFor(10), 6);
      expect(dueDailyCapFor(3), 3);
    });

    test('词组里的「英文 — 中文」拆成两半', () {
      final item = _item(
        id: 'v1',
        word: 'run',
        meaning: '跑',
        phrases: <String>['run out — 用完', 'run over | 碾过'],
      );
      final out = productionTargetCandidates(
        <VocabItem>[item],
        const <ProductionTargetKind>[ProductionTargetKind.phrase],
      );
      expect(out.map((t) => t.text), <String>['run out', 'run over']);
      expect(out.map((t) => t.meaning), <String>['用完', '碾过']);
    });

    test('枚举 label 表齐全', () {
      for (final m in ProductionMode.values) {
        expect(productionModeLabel[m], isNotNull);
        expect(productionModeDesc[m], isNotNull);
      }
      for (final s in ProductionScope.values) {
        expect(productionScopeLabel[s], isNotNull);
      }
      for (final l in ProductionLevel.values) {
        expect(productionLevelLabel[l], isNotNull);
      }
      for (final v in ProductionVariant.values) {
        expect(productionVariantLabel[v], isNotNull);
      }
      for (final a in ProductionAngle.values) {
        expect(productionAngleLabel[a], isNotNull);
      }
      for (final t in ProductionTone.values) {
        expect(productionToneLabel[t], isNotNull);
      }
    });
  });
}
