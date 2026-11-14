/// 「⚡ 一键处理」五步的编排（读库 → 纯函数变换 → 写库 / 冲突重放）。
///
/// 为什么放 `services/`：五步要读词库、读文章、读离线词典 / 例句，还要处理
/// `VocabConflict`（重读后**重放同一次变换**，不是拿旧结果去写）。ViewModel
/// 只该管「跑到第几步 / 每步结果」，不该认识仓储。
///
/// 五步的顺序与 Web 版 `useDictTools.ts` 一致：
/// 挑词 → 补齐 → 补例句 → 校正原形 → 补混淆项。
/// 例句必须排在校正之前：校正后词形变了，例句表按旧词形对不上。
library;

import '../core/ecdict.dart'
    show
        Ecdict,
        EcdictLevel,
        dictConfusables,
        dictLemmaPairs,
        pickAboveLevelWords;
import '../core/article_vocab.dart' show kindOfItem;
import '../core/entry_kind.dart' show isWordEntry;
import '../core/tatoeba.dart' show Tatoeba, TatoebaExample, examplesFor;
import '../core/vocab/analysis.dart'
    show ConfusableResult, applyConfusables, applyLemmaMap;
import '../core/vocab/dict_enrich.dart' show enrichWithDict;
import '../core/vocab/library.dart' show createLibrary;
import '../core/vocab/word.dart' show normalizeWord;
import '../core/vocab/merge.dart'
    show
        applyExamples,
        dedupeLibrary,
        maxExamples,
        pickOfflineExamples,
        targetOfflineExamples;
import '../core/word_pick.dart' show PickEntry;
import '../data/repositories/article_repository.dart';
import '../data/repositories/vocab_repository.dart' show VocabConflict, VocabRepository;
import '../data/tatoeba_loader.dart' show loadTatoebaExamples;
import '../models/vocab.dart';
import 'vocab_mark.dart' show addWordsToArticle;

/// 抽例句的函数（测试注入假数据用）。
typedef ExampleLookup = Future<Map<String, List<TatoebaExample>>> Function(
  Set<String> words,
);

/// 一步跑完的状态。
enum DictStepStatus { ok, skipped, failed }

/// 一步的结果：给界面直接显示的一句话。
class DictStepOutcome {
  const DictStepOutcome({
    required this.stepId,
    required this.status,
    required this.message,
    this.count = 0,
  });

  final String stepId;
  final DictStepStatus status;
  final String message;

  /// 这步实际处理了多少条（补了几个 / 校正了几个）。
  final int count;

  bool get ok => status == DictStepStatus.ok;
  bool get failed => status == DictStepStatus.failed;
}

/// 五步执行器的接口（ViewModel 只认这个，测试可注入假实现）。
abstract class DictToolsRunner {
  Future<DictStepOutcome> run(
    String stepId, {
    required Ecdict? dict,
    String? articleId,
    EcdictLevel level,
  });

  Future<List<DictStepOutcome>> runAll({
    required Ecdict? dict,
    String? articleId,
    EcdictLevel level,
  });
}

/// 五步的执行器。
class DictToolsService implements DictToolsRunner {
  DictToolsService({
    required this.vocab,
    required this.articles,
    ExampleLookup? exampleLookup,
    DateTime Function()? clock,
  })  : _lookup = exampleLookup ?? loadTatoebaExamples,
        _clock = clock ?? DateTime.now;

  final VocabRepository vocab;
  final ArticleRepository articles;
  final ExampleLookup _lookup;
  final DateTime Function() _clock;

  /// 跑一步。[dict] 由 ViewModel 先加载好；例句那步用不到。
  ///
  /// [articleId] 只给「本篇挑词」用：没选文章时这步跳过（不静默退回全库，
  /// 那样会把别的篇的词收进来）。
  @override
  Future<DictStepOutcome> run(
    String stepId, {
    required Ecdict? dict,
    String? articleId,
    EcdictLevel level = EcdictLevel.cet6,
  }) async {
    switch (stepId) {
      case 'pick':
        if (dict == null) return _needDict('pick');
        return _pick(dict: dict, articleId: articleId, level: level);
      case 'enrich':
        if (dict == null) return _needDict('enrich');
        return _mutate(
          stepId: 'enrich',
          transform: (lib) {
            final r = enrichWithDict(lib, dict, now: _clock());
            return (library: r.library, count: r.filled);
          },
          okMessage: (n) => '已用词典补齐 $n 个词',
          skippedMessage: '没有可补齐的（词典里没有，或已有数据）',
        );
      case 'examples':
        return _examples();
      case 'lemma':
        if (dict == null) return _needDict('lemma');
        return _mutate(
          stepId: 'lemma',
          transform: (lib) {
            final pairs = dictLemmaPairs(dict, lib.items);
            if (pairs.isEmpty) {
              return (library: lib, count: 0);
            }
            return (
              library: dedupeLibrary(applyLemmaMap(lib, pairs, now: _clock())),
              count: pairs.length,
            );
          },
          okMessage: (n) => '已校正 $n 个词形（重复的已合并）',
          skippedMessage: '没有可校正的原形（词典里查不到或已是原形）',
        );
      case 'confuse':
        if (dict == null) return _needDict('confuse');
        return _mutate(
          stepId: 'confuse',
          transform: (lib) {
            final results = <ConfusableResult>[];
            for (final it in lib.items) {
              if (!isWordEntry(kind: kindOfItem(it), word: it.word)) continue;
              if ((it.confusables?.isNotEmpty ?? false)) continue;
              if ((it.meaning ?? '').trim().isEmpty) continue;
              final conf = dictConfusables(dict, it.word);
              if (conf.length < 3) continue;
              results.add(
                ConfusableResult(
                  word: it.word,
                  confusables: [
                    for (final c in conf)
                      VocabConfusable(word: c.word, meaning: c.meaning),
                  ],
                ),
              );
            }
            if (results.isEmpty) return (library: lib, count: 0);
            return (
              library: applyConfusables(
                lib,
                results,
                VocabConfusableSource.dict,
                now: _clock(),
              ),
              count: results.length,
            );
          },
          okMessage: (n) => '已用词典给 $n 个词生成混淆项',
          skippedMessage: '没有可补的混淆项（缺释义或没有合适的拼写近邻）',
        );
      default:
        return DictStepOutcome(
          stepId: stepId,
          status: DictStepStatus.failed,
          message: '未知步骤：$stepId',
        );
    }
  }

  /// 依次跑五步。每步失败不阻断后面的步骤（和 Web 版一致）。
  @override
  Future<List<DictStepOutcome>> runAll({
    required Ecdict? dict,
    String? articleId,
    EcdictLevel level = EcdictLevel.cet6,
  }) async {
    const order = <String>['pick', 'enrich', 'examples', 'lemma', 'confuse'];
    final out = <DictStepOutcome>[];
    for (final id in order) {
      out.add(
        await run(id, dict: dict, articleId: articleId, level: level),
      );
    }
    return out;
  }

  // ---- 各步 ----

  DictStepOutcome _needDict(String stepId) => DictStepOutcome(
        stepId: stepId,
        status: DictStepStatus.skipped,
        message: '离线词典还没加载好，稍后再试',
      );

  Future<DictStepOutcome> _pick({
    required Ecdict dict,
    required String? articleId,
    required EcdictLevel level,
  }) async {
    if (articleId == null || articleId.isEmpty) {
      return const DictStepOutcome(
        stepId: 'pick',
        status: DictStepStatus.skipped,
        message: '先在精读页选一篇，再来挑词',
      );
    }
    final article = await articles.load(articleId);
    if (article == null) {
      return const DictStepOutcome(
        stepId: 'pick',
        status: DictStepStatus.failed,
        message: '读不到这一篇，可能已经被删了',
      );
    }
    final library = await vocab.load() ?? createLibrary();
    final known = <String>{
      for (final it in library.items) ...[it.lemma, normalizeWord(it.word)],
    };
    final picked = <String, PickEntry>{};
    for (final s in article.sentences) {
      for (final w in pickAboveLevelWords(dict, s.text, level, max: 1 << 30)) {
        if (known.contains(w)) continue;
        picked.putIfAbsent(
          w,
          () => PickEntry(
            sentenceId: s.id,
            word: w,
            count: 1,
            sentenceText: s.text,
          ),
        );
      }
    }
    if (picked.isEmpty) {
      return const DictStepOutcome(
        stepId: 'pick',
        status: DictStepStatus.skipped,
        message: '这篇没有新的超纲词',
      );
    }
    try {
      final created = await addWordsToArticle(
        repo: vocab,
        articleId: articleId,
        entries: picked.values.toList(growable: false),
      );
      return DictStepOutcome(
        stepId: 'pick',
        status: DictStepStatus.ok,
        count: created,
        message: '按当前水平挑出 ${picked.length} 个超纲词，新收 $created 个',
      );
    } on VocabConflict {
      return const DictStepOutcome(
        stepId: 'pick',
        status: DictStepStatus.failed,
        message: '词库在别处被改了，这步稍后再点一次',
      );
    }
  }

  Future<DictStepOutcome> _examples() async {
    final before = await vocab.load() ?? createLibrary();
    final wants = <String>{};
    for (final it in before.items) {
      if (it.examples.length >= maxExamples) continue;
      if (_offlineCount(it) >= targetOfflineExamples) continue;
      wants
        ..add(it.word)
        ..add(it.lemma);
    }
    if (wants.isEmpty) {
      return DictStepOutcome(
        stepId: 'examples',
        status: DictStepStatus.skipped,
        message: '生词都有例句了（每个词已有 $targetOfflineExamples 条离线例句）',
      );
    }
    final Map<String, List<TatoebaExample>> found;
    try {
      found = await _lookup(wants);
    } on Object catch (e) {
      return DictStepOutcome(
        stepId: 'examples',
        status: DictStepStatus.failed,
        message: '读离线例句库失败：$e',
      );
    }
    if (found.isEmpty) {
      return const DictStepOutcome(
        stepId: 'examples',
        status: DictStepStatus.skipped,
        message: '离线例句库里没查到这些词的例句',
      );
    }
    final tatoeba = Tatoeba(byWord: found);
    final outcome = await _mutate(
      stepId: 'examples',
      transform: (lib) => _applyTatoeba(lib, tatoeba),
      okMessage: (n) => '已给 $n 个词补上离线例句（Tatoeba）',
      skippedMessage: '离线例句库里没查到可用的例句',
    );
    return outcome;
  }

  ({VocabLibrary library, int count}) _applyTatoeba(
    VocabLibrary library,
    Tatoeba tatoeba,
  ) {
    final rows =
        <({String word, List<({String text, String? translation})> examples})>[];
    for (final it in library.items) {
      if (it.examples.length >= maxExamples) continue;
      final candidates = examplesFor(tatoeba, it.word, lemma: it.lemma);
      if (candidates.isEmpty) continue;
      final picked = pickOfflineExamples(it, [
        for (final c in candidates) (text: c.en, translation: c.zh),
      ]);
      if (picked.isEmpty) continue;
      rows.add((word: it.word, examples: picked));
    }
    if (rows.isEmpty) return (library: library, count: 0);
    return (
      library: applyExamples(
        library,
        rows,
        _clock(),
        VocabExampleOrigin.tatoeba,
      ),
      count: rows.length,
    );
  }

  // ---- 公共写库 ----

  /// 读最新库 → 变换 → 写库；冲突时重读后**重放同一次变换**（最多 3 次）。
  Future<DictStepOutcome> _mutate({
    required String stepId,
    required ({VocabLibrary library, int count}) Function(VocabLibrary) transform,
    required String Function(int count) okMessage,
    required String skippedMessage,
  }) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      final lib = await vocab.load() ?? createLibrary();
      final at = (await vocab.meta())?.at;
      final r = transform(lib);
      if (r.count <= 0 || identical(r.library, lib)) {
        return DictStepOutcome(
          stepId: stepId,
          status: DictStepStatus.skipped,
          message: skippedMessage,
        );
      }
      try {
        await vocab.save(r.library, baseUpdatedAt: at);
        return DictStepOutcome(
          stepId: stepId,
          status: DictStepStatus.ok,
          count: r.count,
          message: okMessage(r.count),
        );
      } on VocabConflict {
        if (attempt == 2) {
          return DictStepOutcome(
            stepId: stepId,
            status: DictStepStatus.failed,
            message: '词库在别处被改了，这步稍后再点一次',
          );
        }
      } on Object catch (e) {
        return DictStepOutcome(
          stepId: stepId,
          status: DictStepStatus.failed,
          message: '保存失败：$e',
        );
      }
    }
    return DictStepOutcome(
      stepId: stepId,
      status: DictStepStatus.failed,
      message: '保存失败：请稍后再试',
    );
  }

  static int _offlineCount(VocabItem item) =>
      item.examples.where((e) => e.origin == VocabExampleOrigin.tatoeba).length;
}
