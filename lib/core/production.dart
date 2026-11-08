/// 「D老师奶牛工棚」：用已经学过的词 / 词组 / 习语做**主动产出**。
///
/// 这一层只做纯函数：选目标块、检查目标块有没有用上、挖空与词序提示。
/// 不碰存储，也不碰界面；会话编排在 ViewModel 里。
/// 设置与枚举在 `production_settings.dart`，这里只 re-export。
///
/// 对应 Web 版 `src/core/production.ts`（596 行），语义逐条对齐。
library;

import '../models/document.dart';
import '../models/vocab.dart';
import 'article_vocab.dart' show kindOfItem;
import 'entry_kind.dart';
import 'production_settings.dart';
import 'vocab/review.dart' show isDue;

export 'production_settings.dart';

/// 一个目标块：AI 只许从给定清单里按 [id] 选。
class ProductionTarget {
  const ProductionTarget({
    required this.id,
    required this.itemId,
    required this.kind,
    required this.text,
    required this.meaning,
  });

  /// 稳定 id：`词条 id|来源|下标`，AI 只能原样引用。
  final String id;

  /// 来自哪条词条（取薄弱比例时要回查复习状态）。
  final String itemId;

  final ProductionTargetKind kind;

  /// 英文（词 / 词组 / 习语本身）。
  final String text;

  /// 中文释义，可能为空。
  final String meaning;

  @override
  bool operator ==(Object other) =>
      other is ProductionTarget &&
      other.id == id &&
      other.text == text &&
      other.meaning == meaning;

  @override
  int get hashCode => Object.hash(id, text, meaning);

  @override
  String toString() => 'ProductionTarget($id, $text)';
}

/// 一道题。
class ProductionPrompt {
  const ProductionPrompt({
    required this.id,
    required this.zh,
    this.goal = '',
    this.targets = const <ProductionTarget>[],
    this.reference,
    this.answerLang,
    this.model,
  });

  final String id;

  /// 中文情境提示；出题时绝不把英文目标块写进这里。
  final String zh;

  /// 中文沟通目标（「委婉拒绝」「说明进度」）。
  final String goal;

  final List<ProductionTarget> targets;

  /// 风味酸奶：这一句的参考译文（答完 / 批改后才给用户看）。
  final String? reference;

  /// 风味酸奶方向：默认中译英；英译中时参考答案是中文。
  final ProductionAnswerLang? answerLang;

  /// 目标块题的参考英文句；默认隐藏，只在挖空 / 排序题型里作提示。
  final String? model;

  ProductionPrompt copyWith({
    String? id,
    String? zh,
    String? goal,
    List<ProductionTarget>? targets,
    String? reference,
    ProductionAnswerLang? answerLang,
    String? model,
  }) =>
      ProductionPrompt(
        id: id ?? this.id,
        zh: zh ?? this.zh,
        goal: goal ?? this.goal,
        targets: targets ?? this.targets,
        reference: reference ?? this.reference,
        answerLang: answerLang ?? this.answerLang,
        model: model ?? this.model,
      );

  @override
  String toString() => 'ProductionPrompt($id, $zh)';
}

/// 作答语言：目标块题是英文；风味酸奶英译中时是中文。
enum ProductionAnswerLang { en, zh }

/// 目标块命中情况（判过分的稿子里存这个）。
class ProductionTargetHit {
  const ProductionTargetHit({
    required this.id,
    required this.kind,
    required this.text,
    required this.meaning,
    required this.used,
  });

  final String id;
  final ProductionTargetKind kind;
  final String text;
  final String meaning;
  final bool used;
}
/// 进度视图的最小形状；由历史记录现算。
class ProductionProgressLike {
  const ProductionProgressLike({
    required this.key,
    required this.kind,
    required this.text,
    required this.attempts,
    required this.hits,
    required this.misses,
    required this.dueAt,
    required this.lastAt,
  });

  final String key;
  final ProductionTargetKind kind;
  final String text;
  final int attempts;
  final int hits;
  final int misses;
  final String dueAt;
  final String lastAt;
}

/// 选目标块时用的上下文。
class BuildProductionTargetsOptions {
  const BuildProductionTargetsOptions({
    required this.items,
    required this.scope,
    this.articleIdentity = '',
    this.docLemmas = const <String>{},
    required this.types,
    required this.limit,
    this.weakRatio = 30,
    this.theme = '',
    this.progress = const <ProductionProgressLike>[],
    this.now,
    this.rng,
  });

  final List<VocabItem> items;
  final ProductionScope scope;
  final String articleIdentity;
  final Set<String> docLemmas;
  final List<ProductionTargetKind> types;

  /// 最多取多少个目标块（题数 × 每题目标数）。
  final int limit;
  final int weakRatio;

  /// 当前主题；[ProductionScope.theme] 时按 text / meaning 匹配。
  final String theme;

  /// 从历史记录现算的目标块进度；没有进度 = 新目标。
  final List<ProductionProgressLike> progress;
  final DateTime? now;
  final double Function()? rng;
}

/// 选出来的目标块池。
class ProductionTargetPool {
  const ProductionTargetPool({
    this.targets = const <ProductionTarget>[],
    this.total = 0,
    this.weak = 0,
    this.note = '',
  });

  final List<ProductionTarget> targets;

  /// 过滤后一共有多少候选（用于「不够」提示）。
  final int total;

  /// 其中有多少是薄弱目标。
  final int weak;

  /// 过滤范围没有匹配时回退全库的提示。
  final String note;
}

/// 能拿来背 / 考的词条（用法笔记不进）。
List<VocabItem> productionStudyableItems(List<VocabItem> items) => items
    .where((it) => isStudyable(
          kind: kindOfItem(it),
          word: it.word,
          meaning: it.meaning,
        ))
    .toList(growable: false);

/// 目标块去重用的键：`类型:文本`（文本压小写、压空白）。
String productionTargetKey(ProductionTargetKind kind, String text) =>
    '${kind.name}:${text.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ')}';

/// `run out — 用完` / `run out | 用完` → 英文 / 中文；没有分隔就整段当英文。
({String text, String meaning}) _splitChunk(String text) {
  final raw = text.trim();
  final parts = raw.split(RegExp(r'\s+[—–|]\s+|\s+\|\s+'));
  return (
    text: (parts.isEmpty ? raw : parts.first).trim(),
    meaning: (parts.length > 1 ? parts[1] : '').trim(),
  );
}

bool _isWeakItem(VocabItem item) =>
    item.reviewState.lapses > 0 || item.reviewState.repetitions < 2;

/// 一条词条能出哪些目标块（词条本身 + phrases / idioms）。
List<ProductionTarget> _targetsOfItem(
  VocabItem item,
  Set<ProductionTargetKind> types,
) {
  final out = <ProductionTarget>[];
  final kind = kindOf(kind: kindOfItem(item), word: item.word);
  final asTarget = switch (kind) {
    VocabKind.word => ProductionTargetKind.word,
    VocabKind.phrase => ProductionTargetKind.phrase,
    VocabKind.idiom => ProductionTargetKind.idiom,
    VocabKind.usage => null,
  };
  if (asTarget != null && types.contains(asTarget)) {
    out.add(ProductionTarget(
      id: '${item.id}|self|${asTarget.name}',
      itemId: item.id,
      kind: asTarget,
      text: item.word.trim(),
      meaning: (item.meaning ?? '').trim(),
    ));
  }
  if (types.contains(ProductionTargetKind.phrase) && kind == VocabKind.word) {
    final phrases = item.phrases ?? const <String>[];
    for (var i = 0; i < phrases.length; i++) {
      final c = _splitChunk(phrases[i]);
      if (c.text.isEmpty) continue;
      out.add(ProductionTarget(
        id: '${item.id}|phrase|$i',
        itemId: item.id,
        kind: ProductionTargetKind.phrase,
        text: c.text,
        meaning: c.meaning,
      ));
    }
  }
  if (types.contains(ProductionTargetKind.idiom) && kind == VocabKind.word) {
    final idioms = item.idioms ?? const <String>[];
    for (var i = 0; i < idioms.length; i++) {
      final c = _splitChunk(idioms[i]);
      if (c.text.isEmpty) continue;
      out.add(ProductionTarget(
        id: '${item.id}|idiom|$i',
        itemId: item.id,
        kind: ProductionTargetKind.idiom,
        text: c.text,
        meaning: c.meaning,
      ));
    }
  }
  return out;
}

/// 全库候选目标块（去重、按类型过滤）；用于「到期 / 新目标」提醒口径。
List<ProductionTarget> productionTargetCandidates(
  List<VocabItem> items,
  List<ProductionTargetKind> types,
) {
  final typeSet = types.toSet();
  if (typeSet.isEmpty) return const <ProductionTarget>[];
  final seen = <String>{};
  final out = <ProductionTarget>[];
  for (final item in productionStudyableItems(items)) {
    for (final target in _targetsOfItem(item, typeSet)) {
      final key = productionTargetKey(target.kind, target.text);
      if (target.text.isEmpty || seen.contains(key)) continue;
      seen.add(key);
      out.add(target);
    }
  }
  return out;
}

List<T> _shuffle<T>(List<T> arr, double Function() rng) {
  final out = List<T>.of(arr);
  for (var i = out.length - 1; i > 0; i--) {
    final j = (rng() * (i + 1)).floor();
    final tmp = out[i];
    out[i] = out[j];
    out[j] = tmp;
  }
  return out;
}

/// 选本轮目标块：范围 → 类型 → 去重 → 按「薄弱比例」抽。
///
/// 这里不安排「每道题用哪几个」，那是 AI 出题后由 `targetIds` 决定的；
/// 这里只保证给 AI 一张可用的候选清单。
ProductionTargetPool buildProductionTargets(
  BuildProductionTargetsOptions opts,
) {
  final limit = opts.limit < 1 ? 1 : opts.limit;
  final types = opts.types.toSet();
  if (types.isEmpty) return const ProductionTargetPool();

  // 文章范围只影响候选池；进度范围仍从全库候选里筛。
  final scopePool = opts.scope == ProductionScope.article
      ? opts.items.where((it) {
          final fileName = it.source?.fileName;
          return fileName == opts.articleIdentity ||
              opts.docLemmas.contains(it.lemma);
        }).toList(growable: false)
      : opts.items;
  final studyable = productionStudyableItems(scopePool);
  final byItem = <String, VocabItem>{for (final it in studyable) it.id: it};

  final seen = <String>{};
  final allRaw = <ProductionTarget>[];
  for (final item in studyable) {
    for (final t in _targetsOfItem(item, types)) {
      final key = productionTargetKey(t.kind, t.text);
      if (t.text.isEmpty || seen.contains(key)) continue;
      seen.add(key);
      allRaw.add(t);
    }
  }
  if (allRaw.isEmpty) return const ProductionTargetPool();

  final progress = <String, ProductionProgressLike>{
    for (final p in opts.progress) p.key: p,
  };
  final now = opts.now ?? DateTime.now();
  var all = allRaw;
  var note = '';

  switch (opts.scope) {
    case ProductionScope.recent:
    case ProductionScope.weak:
    case ProductionScope.due:
    case ProductionScope.mistakes:
      all = allRaw.where((t) {
        final p = progress[productionTargetKey(t.kind, t.text)];
        if (p == null) return opts.scope == ProductionScope.due;
        switch (opts.scope) {
          case ProductionScope.recent:
            final last = DateTime.tryParse(p.lastAt);
            return last != null &&
                now.difference(last).inMilliseconds <= 7 * 86400000;
          case ProductionScope.weak:
            return p.misses > 0 ||
                p.hits / (p.attempts < 1 ? 1 : p.attempts) < 0.7;
          case ProductionScope.due:
            final due = DateTime.tryParse(p.dueAt);
            return due == null || !due.isAfter(now);
          default:
            return p.misses > 0;
        }
      }).toList(growable: false);
      if (all.isEmpty) {
        all = allRaw;
        note = '「${productionScopeLabel[opts.scope]}」没有匹配目标块，已回退全库。';
      }
    case ProductionScope.theme:
      final tokens = opts.theme
          .toLowerCase()
          .split(RegExp(r'\s+'))
          .where((s) => s.trim().isNotEmpty)
          .toList(growable: false);
      if (tokens.isNotEmpty) {
        all = allRaw.where((t) {
          final hay = '${t.text} ${t.meaning}'.toLowerCase();
          return tokens.any(hay.contains);
        }).toList(growable: false);
        if (all.isEmpty) {
          all = allRaw;
          note = '主题没有匹配目标块，已回退全库。';
        }
      }
    case ProductionScope.article:
    case ProductionScope.all:
      break;
  }
  if (all.isEmpty) {
    return ProductionTargetPool(note: note);
  }

  final rng = opts.rng ?? _nextRandom;
  final weak = <ProductionTarget>[];
  final strong = <ProductionTarget>[];
  for (final t in all) {
    final item = byItem[t.itemId];
    if (item != null && _isWeakItem(item)) {
      weak.add(t);
    } else {
      strong.add(t);
    }
  }
  final ratio = opts.weakRatio.clamp(0, 100);
  final weakTake = weak.length < (limit * ratio / 100).round()
      ? weak.length
      : (limit * ratio / 100).round();
  final picked = <ProductionTarget>[
    ..._shuffle(weak, rng).take(weakTake),
    ..._shuffle(strong, rng).take(limit - weakTake < 0 ? 0 : limit - weakTake),
  ];
  if (picked.length < limit) {
    final pickedIds = <String>{for (final t in picked) t.id};
    final rest = _shuffle(
      all.where((t) => !pickedIds.contains(t.id)).toList(growable: false),
      rng,
    );
    picked.addAll(rest.take(limit - picked.length));
  }
  return ProductionTargetPool(
    targets: _shuffle(picked, rng),
    total: all.length,
    weak: weak.length,
    note: note,
  );
}

/// 默认随机源：测试里注入固定值，生产里用自增 LCG（可复现、不依赖时钟）。
double _nextRandom() {
  _seed = (_seed * 1103515245 + 12345) & 0x7FFFFFFF;
  return _seed / 0x7FFFFFFF;
}

int _seed = 20261030;

String _escapeRegExp(String s) =>
    s.replaceAllMapped(RegExp(r'[.*+?^${}()|\[\]\\]'), (m) => '\\${m[0]}');

/// 比较目标块时用的归一：小写 + NFKC + 弯引号拉直 + 压空白。
String _normalizeText(String s) => s
    .toLowerCase()
    .replaceAll(RegExp('[’‘]'), "'")
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// 不规则动词表：`run` 也要认 `ran` / `running`。
const Map<String, List<String>> _irregularWords = <String, List<String>>{
  'be': ['am', 'is', 'are', 'was', 'were', 'been', 'being'],
  'become': ['became', 'becoming'],
  'begin': ['began', 'begun', 'beginning'],
  'break': ['broke', 'broken', 'breaking'],
  'bring': ['brought', 'bringing'],
  'buy': ['bought', 'buying'],
  'choose': ['chose', 'chosen', 'choosing'],
  'come': ['came', 'coming'],
  'do': ['did', 'done', 'doing', 'does'],
  'drink': ['drank', 'drunk', 'drinking'],
  'drive': ['drove', 'driven', 'driving'],
  'eat': ['ate', 'eaten', 'eating'],
  'fall': ['fell', 'fallen', 'falling'],
  'feel': ['felt', 'feeling'],
  'find': ['found', 'finding'],
  'fly': ['flew', 'flown', 'flying'],
  'forget': ['forgot', 'forgotten', 'forgetting'],
  'get': ['got', 'gotten', 'getting'],
  'give': ['gave', 'given', 'giving'],
  'go': ['went', 'gone', 'going', 'goes'],
  'grow': ['grew', 'grown', 'growing'],
  'have': ['has', 'had', 'having'],
  'hear': ['heard', 'hearing'],
  'keep': ['kept', 'keeping'],
  'know': ['knew', 'known', 'knowing'],
  'leave': ['left', 'leaving'],
  'lose': ['lost', 'losing'],
  'make': ['made', 'making'],
  'meet': ['met', 'meeting'],
  'pay': ['paid', 'paying'],
  'put': ['putting'],
  'read': ['reading'],
  'run': ['ran', 'running'],
  'say': ['said', 'saying'],
  'see': ['saw', 'seen', 'seeing'],
  'sell': ['sold', 'selling'],
  'send': ['sent', 'sending'],
  'show': ['showed', 'shown', 'showing'],
  'sit': ['sat', 'sitting'],
  'sleep': ['slept', 'sleeping'],
  'speak': ['spoke', 'spoken', 'speaking'],
  'spend': ['spent', 'spending'],
  'stand': ['stood', 'standing'],
  'take': ['took', 'taken', 'taking'],
  'teach': ['taught', 'teaching'],
  'tell': ['told', 'telling'],
  'think': ['thought', 'thinking'],
  'understand': ['understood', 'understanding'],
  'wear': ['wore', 'worn', 'wearing'],
  'win': ['won', 'winning'],
  'write': ['wrote', 'written', 'writing'],
};

/// 目标块是否出现在作答里：单词允许常见词形 / 不规则变化，词组允许插入少量词。
bool targetUsed(String answer, ProductionTarget target) {
  final hay = _normalizeText(answer);
  final needle = _normalizeText(target.text);
  if (needle.isEmpty) return false;
  if (target.kind != ProductionTargetKind.word) {
    if (hay.contains(needle)) return true;
    final words = needle.split(' ').where((w) => w.isNotEmpty).toList();
    if (words.length < 2) return false;
    final pattern = words.map(_escapeRegExp).join(r'(?:\s+\S+){0,2}\s+');
    return RegExp('\\b$pattern\\b', caseSensitive: false).hasMatch(hay);
  }
  final last = needle.substring(needle.length - 1);
  final forms = <String>{
    needle,
    '${needle}s',
    '${needle}es',
    '${needle}d',
    '${needle}ed',
    '${needle}ing',
    '${needle}er',
    '${needle}est',
    '${needle}ly',
    // run → running / rub → rubbing 这类双写辅音
    '$needle$last' 'ing',
    '$needle$last' 'ed',
    ...?_irregularWords[needle],
  };
  final re = RegExp(
    '\\b(?:${forms.map(_escapeRegExp).join('|')})\\b',
    caseSensitive: false,
  );
  return re.hasMatch(hay);
}

/// 参考句切出来的片段：有 [target] 就是这里要填空。
class ClozePart {
  const ClozePart({required this.text, this.target});

  final String text;
  final ProductionTarget? target;
}

/// 把参考句按目标块切成「普通文本 / 空」两段，供真正的填空交互使用。
List<ClozePart> clozeParts(
  String model,
  List<ProductionTarget> targets,
) {
  final sorted = targets.where((t) => t.text.trim().isNotEmpty).toList()
    ..sort((a, b) => b.text.length.compareTo(a.text.length));
  if (sorted.isEmpty) return <ClozePart>[ClozePart(text: model)];
  final byText = <String, ProductionTarget>{
    for (final t in sorted) t.text.trim().toLowerCase(): t,
  };
  final re = RegExp(
    '(${sorted.map((t) => _escapeRegExp(t.text.trim())).join('|')})',
    caseSensitive: false,
  );
  final parts = <ClozePart>[];
  var cursor = 0;
  for (final m in re.allMatches(model)) {
    if (m.start > cursor) {
      parts.add(ClozePart(text: model.substring(cursor, m.start)));
    }
    final piece = m.group(0) ?? '';
    final target = byText[piece.trim().toLowerCase()];
    if (piece.isNotEmpty) {
      parts.add(target == null
          ? ClozePart(text: piece)
          : ClozePart(text: piece, target: target));
    }
    cursor = m.end;
  }
  if (cursor < model.length) {
    parts.add(ClozePart(text: model.substring(cursor)));
  }
  return parts.isEmpty ? <ClozePart>[ClozePart(text: model)] : parts;
}

/// 把目标块从参考句里挖掉，用于「句中挖空」提示。
String clozeSentence(String model, List<ProductionTarget> targets) =>
    clozeParts(model, targets)
        .map((p) => p.target != null ? '_____' : p.text)
        .join();

/// 把参考句拆成词，按 [seed] 稳定洗牌，用于「排序」提示。
List<String> shuffledWords(String model, String seed) {
  final words = model.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  var h = 5381;
  for (var i = 0; i < seed.length; i++) {
    h = (h << 5) + h + seed.codeUnitAt(i);
  }
  for (var i = words.length - 1; i > 0; i--) {
    h = h * 1103515245 + 12345;
    final j = h.abs() % (i + 1);
    final tmp = words[i];
    words[i] = words[j];
    words[j] = tmp;
  }
  return words;
}

/// 逐项检查目标块用没用上。
List<ProductionTargetHit> checkProductionTargets(
  String answer,
  List<ProductionTarget> targets,
) =>
    <ProductionTargetHit>[
      for (final t in targets)
        ProductionTargetHit(
          id: t.id,
          kind: t.kind,
          text: t.text,
          meaning: t.meaning,
          used: targetUsed(answer, t),
        ),
    ];

/// 目标块范围要用的文章词集合（正文词 + 语言点词）。
Set<String> productionDocLemmas(List<Sentence>? sentences) {
  final out = <String>{};
  for (final s in sentences ?? const <Sentence>[]) {
    for (final w in s.vocab) {
      out.add(w.toLowerCase());
    }
    for (final l in s.languages ?? const <SentenceLanguage>[]) {
      for (final k in l.phrases ?? const <String>[]) {
        out.add(k.toLowerCase());
      }
      for (final k in l.idioms ?? const <String>[]) {
        out.add(k.toLowerCase());
      }
    }
  }
  return out;
}

/// 到期范围一天最多取几个目标块（界面提示用）。
int dueDailyCapFor(int limit) =>
    limit < productionDueDailyCap ? limit : productionDueDailyCap;

/// 某个词条在不在「到期」：范围筛选用（转发到 `vocab/review.dart`，不另写一套）。
bool productionItemDue(VocabItem item, [DateTime? now]) => isDue(item, now);
