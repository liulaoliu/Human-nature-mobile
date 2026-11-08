/// 词库写入侧：标词、AI 查词结果回填、混淆项、原形校正、-ing/-ed 辨析。
///
/// 输入都是外部数据（阅读界面 / AI 粘回 / 离线词典），解析与守卫在调用方完成
/// （`lib/core/backup_parse.dart` / `lib/data/…`），本层只处理「已经合法的结构」。
///
/// 对应 Web 版 `src/core/vocab/analysis.ts`（461 行）。
library;

import '../ecdict.dart' show LemmaPair;
import '../article_vocab.dart' show addArticleEntry;
import '../entry_kind.dart' show isSingleEnglishWord;
import '../vocab_fields.dart' show isFieldLocked;
import '../../models/vocab.dart';
import 'merge.dart';
import 'sense.dart';
import 'word.dart';

/// 一份查词结果（AI 或离线词典都走这个形状）。
class WordAnalysis {
  const WordAnalysis({
    required this.word,
    this.phonetic,
    this.partOfSpeech,
    this.meaning,
    this.definition,
    this.usage,
    this.examples,
    this.fieldSources,
  });

  final String word;
  final String? phonetic;
  final String? partOfSpeech;
  final String? meaning;

  /// 英英释义（学习者词典风格的一句话，可选）。
  final String? definition;
  final List<String>? usage;
  final List<({String text, String? translation})>? examples;

  /// 每个字段的来源；没给按 AI 处理。
  final Map<VocabField, VocabFieldSource>? fieldSources;

  VocabFieldSource sourceOf(VocabField field) =>
      fieldSources?[field] ?? VocabFieldSource.ai;
}

bool _hasText(String? v) => v != null && v.trim().isNotEmpty;

VocabLibrary _replaceItem(VocabLibrary library, VocabItem item) =>
    library.copyWith(
      items: library.items
          .map((it) => it.id == item.id ? item : it)
          .toList(growable: false),
    );

/// 标一个词的入参。
class MarkInput {
  const MarkInput({
    required this.word,
    required this.articleId,
    this.fileName,
    this.sentenceId,
    this.sentenceText,
    this.meaning,
    this.kind,
    this.origin,
    this.via,
  });

  final String word;
  final String articleId;
  final String? fileName;
  final String? sentenceId;

  /// 标词时所在的整句原文，用于回填例句与来源。
  final String? sentenceText;

  /// 已知的释义（如「词组 — 中文」里的中文），标词时直接写上。
  final String? meaning;

  /// 词条类型（词组 / 习语 / 用法笔记；null = 普通单词）。
  final VocabItemKind? kind;

  /// 收录方式：自动标词 / 手动加入（默认手动）。
  final VocabOrigin? origin;

  /// 细分来源：AI / 离线词典 / 手动 / 语言点。
  final VocabVia? via;
}

/// 标词结果。
class MarkResult {
  const MarkResult({
    required this.library,
    required this.item,
    required this.created,
  });

  final VocabLibrary library;
  final VocabItem item;

  /// 是新建还是命中了已有词条（去重）。
  final bool created;
}

/// 把已入库的单词收进当前篇；词组/习语/用法和多词条目不进正文编号。
VocabLibrary _collectToArticle(
  VocabLibrary library,
  MarkInput input,
  VocabItem item,
  DateTime at,
) {
  final kind = input.kind;
  if (kind != null && kind != VocabItemKind.word) return library;
  if (input.word.trim().contains(RegExp(r'\s'))) return library;
  final articleId = (input.fileName?.trim().isNotEmpty ?? false)
      ? input.fileName!.trim()
      : input.articleId.trim();
  if (articleId.isEmpty) return library;
  final meaning = input.meaning?.trim();
  return addArticleEntry(
    library,
    articleId: articleId,
    lemma: item.lemma,
    origin: input.origin ?? VocabOrigin.manual,
    via: input.via,
    sentenceId: input.sentenceId,
    sentenceText: input.sentenceText ?? '',
    meaning: (meaning?.isNotEmpty ?? false) ? meaning : null,
    meaningSource: (meaning?.isNotEmpty ?? false) ? VocabMeaningSource.manual : null,
    now: at,
  );
}

/// 标记一个词。按 lemma 去重：
///   - 已有 → 只追加来源/例句、更新时间，不新建；
///   - 没有 → 建新词条，status = unqueried。
///
/// 同时把它收进**当前篇**的按篇条目（只收普通单词）。
MarkResult markWord(
  VocabLibrary library,
  MarkInput input, {
  DateTime? now,
}) {
  final lemma = lemmaOf(input.word);
  if (lemma.isEmpty) {
    throw ArgumentError('markWord: 空的单词');
  }
  final at = now ?? DateTime.now();
  final iso = at.toIso8601String();
  final example = VocabExample(
    text: (input.sentenceText?.isNotEmpty ?? false)
        ? input.sentenceText!
        : input.word,
    articleId: input.articleId,
    fileName: input.fileName,
    sentenceId: input.sentenceId,
    origin: VocabExampleOrigin.article,
  );
  final source = VocabSource(
    articleId: input.articleId,
    fileName: input.fileName,
    sentenceId: input.sentenceId,
    sentenceText: input.sentenceText ?? '',
  );

  final existing =
      library.items.where((it) => it.lemma == lemma).firstOrNull;
  final given = input.meaning?.trim();
  final givenText = (given?.isNotEmpty ?? false) ? given : null;
  // 「单词」不写 kind（老数据也没有），保持数据干净；词组/习语/用法才标
  final kind = (input.kind != null && input.kind != VocabItemKind.word)
      ? input.kind
      : null;

  if (existing != null) {
    // 已有释义不改；只在「这次才补上释义」时记手动来源
    final meaning = existing.meaning ?? givenText;
    final fieldSources = (existing.meaning == null && givenText != null)
        ? {...?existing.fieldSources, VocabField.meaning: VocabFieldSource.manual}
        : existing.fieldSources;
    /// 单词被早期语言点逻辑误标成 usage / phrase：这次是**按单词**加进来的，
    /// 就顺手改回单词并清掉旧的语言点标记（否则收语言点时又会被改回去）。
    final upgradeToWord =
        kind == null && isSingleEnglishWord(existing.word);
    final merged = existing.copyWith(
      kind: upgradeToWord
          ? () => null
          : ((existing.kind ?? kind) != null
              ? () => existing.kind ?? kind
              : null),
      langPointId: upgradeToWord ? () => null : null,
      examples: mergeExamples(existing.examples, [example]),
      source: () => betterSource(existing.source, source),
      contexts: () => upsertContext(
        existing.contexts,
        contextFromSource(source, iso, meaning: givenText),
      ),
      meaning: () => meaning,
      fieldSources: () => fieldSources,
      updatedAt: iso,
    );
    return MarkResult(
      library: _collectToArticle(_replaceItem(library, merged), input, merged, at),
      item: merged,
      created: false,
    );
  }

  final item = VocabItem(
    id: 'vocab:$lemma',
    word: input.word.trim(),
    lemma: lemma,
    kind: kind,
    meaning: givenText,
    fieldSources:
        givenText != null ? {VocabField.meaning: VocabFieldSource.manual} : null,
    usage: const [],
    examples: [example],
    source: source,
    // 词组/习语/用法笔记是语言点里直接带释义收过来的，没有「待查」这一步
    status: (givenText != null || kind != null)
        ? VocabStatus.queried
        : VocabStatus.unqueried,
    note: '',
    tags: const [],
    contexts: [contextFromSource(source, iso, meaning: givenText)],
    reviewState: defaultReviewState,
    createdAt: iso,
    updatedAt: iso,
  );
  return MarkResult(
    library: _collectToArticle(
      library.copyWith(items: [...library.items, item]),
      input,
      item,
      at,
    ),
    item: item,
    created: true,
  );
}

/// 把「一键提示词」粘回解析出的词条结果合并进词库。
///   - 已有词条：填缺的音标/词性/含义，用法与例句并入；手动改过/已掌握的不覆盖含义；
///   - 没标记过的词：也建条目（整篇批量查词会用到），source 为 null。
VocabLibrary applyWordAnalysis(
  VocabLibrary library,
  List<WordAnalysis> words, {
  DateTime? now,
  VocabSource? defaultSource,
}) {
  final iso = (now ?? DateTime.now()).toIso8601String();
  var items = library.items;

  for (final wa in words) {
    final lemma = lemmaOf(wa.word);
    if (lemma.isEmpty) continue;
    final target = normalizeWord(wa.word);
    // 命中已有：按 lemma，或按词形完全一致（容忍历史遗留的怪 lemma）
    final idx = items.indexWhere((it) =>
        it.lemma == lemma ||
        (target.isNotEmpty && normalizeWord(it.word) == target));
    final examples = (wa.examples ?? const <({String text, String? translation})>[])
        .map((e) => VocabExample(text: e.text, translation: e.translation))
        .toList(growable: false);
    final incoming = <VocabField, String?>{
      VocabField.phonetic: _hasText(wa.phonetic) ? wa.phonetic : null,
      VocabField.partOfSpeech:
          normalizePos(wa.partOfSpeech ?? '').isEmpty ? null : normalizePos(wa.partOfSpeech ?? ''),
      VocabField.meaning: _cleanOrNull(wa.meaning),
      VocabField.definition: _cleanOrNull(wa.definition),
    };
    final incomingSources = <VocabField, VocabFieldSource>{};
    for (final field in VocabField.values) {
      if (_hasText(incoming[field])) {
        incomingSources[field] = wa.sourceOf(field);
      }
    }

    if (idx == -1) {
      items = [
        ...items,
        VocabItem(
          id: 'vocab:$lemma',
          word: wa.word.trim(),
          lemma: lemma,
          phonetic: incoming[VocabField.phonetic],
          partOfSpeech: incoming[VocabField.partOfSpeech],
          meaning: incoming[VocabField.meaning],
          definition: incoming[VocabField.definition],
          fieldSources: incomingSources.isEmpty ? null : incomingSources,
          usage: wa.usage ?? const [],
          examples: examples,
          source: defaultSource,
          status: VocabStatus.queried,
          contexts: defaultSource != null
              ? [
                  contextFromSource(
                    defaultSource,
                    iso,
                    meaning: incoming[VocabField.meaning],
                  )
                ]
              : null,
          note: '',
          tags: const [],
          reviewState: defaultReviewState,
          createdAt: iso,
          updatedAt: iso,
        ),
      ];
      continue;
    }

    final cur = items[idx];
    // 词形 / id 仍按旧规则整条锁：手动改过或已掌握的不让查询结果改身份
    final identityLocked = cur.status == VocabStatus.edited ||
        cur.status == VocabStatus.mastered;
    final newWord =
        identityLocked ? cur.word : ((wa.word.trim().isEmpty) ? cur.word : wa.word.trim());
    final newLemmaRaw = identityLocked ? cur.lemma : lemmaOf(newWord);
    final newLemma = newLemmaRaw.isEmpty ? cur.lemma : newLemmaRaw;
    final fieldSources = <VocabField, VocabFieldSource>{...?cur.fieldSources};

    // 音标只补空；词性与释义要**同源**（释义换了说法，词性就必须跟着换）
    var phonetic = cur.phonetic;
    if (!isFieldLocked(cur, VocabField.phonetic) &&
        (cur.phonetic?.isEmpty ?? true) &&
        _hasText(incoming[VocabField.phonetic])) {
      phonetic = incoming[VocabField.phonetic];
      fieldSources[VocabField.phonetic] = wa.sourceOf(VocabField.phonetic);
    }
    var meaning = cur.meaning;
    var meaningReplaced = false;
    final incomingMeaning = incoming[VocabField.meaning];
    if (!isFieldLocked(cur, VocabField.meaning) && _hasText(incomingMeaning)) {
      meaningReplaced = incomingMeaning != cur.meaning;
      meaning = incomingMeaning;
      fieldSources[VocabField.meaning] = wa.sourceOf(VocabField.meaning);
    }
    var partOfSpeech = cur.partOfSpeech;
    if (!isFieldLocked(cur, VocabField.partOfSpeech)) {
      // 词典补的词性是**词头首义**，AI 给的是**语境义项**，两者不是一回事
      // （consort → n. 交往；厮混）。词典那条只能算占位，不能挡住 AI。
      final dictPlaceholder =
          fieldSources[VocabField.partOfSpeech] == VocabFieldSource.dict;
      final incomingPos = incoming[VocabField.partOfSpeech];
      if (_hasText(incomingPos) &&
          (meaningReplaced ||
              dictPlaceholder ||
              (cur.partOfSpeech?.isEmpty ?? true))) {
        // 释义和词性来自同一行答案，必须一起采纳
        partOfSpeech = incomingPos;
        fieldSources[VocabField.partOfSpeech] = wa.sourceOf(VocabField.partOfSpeech);
      } else if (meaningReplaced) {
        // 换了说法却没给词性：宁可空着，也不能留着上一版的词性凑一对
        partOfSpeech = null;
        fieldSources.remove(VocabField.partOfSpeech);
      }
    }
    var definition = cur.definition;
    if (!isFieldLocked(cur, VocabField.definition) &&
        _hasText(incoming[VocabField.definition])) {
      definition = incoming[VocabField.definition];
      fieldSources[VocabField.definition] = wa.sourceOf(VocabField.definition);
    }

    final ctxMeaning = incoming[VocabField.meaning];
    /// 查词结果按「单词」回来时，顺手把误标成 usage / phrase 的同词条目改回单词。
    final upgradeToWord =
        isSingleEnglishWord(wa.word) && isSingleEnglishWord(cur.word);
    final merged = reconcileSense(cur.copyWith(
      id: identityLocked ? cur.id : 'vocab:$newLemma',
      word: newWord,
      lemma: newLemma,
      kind: upgradeToWord ? () => null : null,
      langPointId: upgradeToWord ? () => null : null,
      phonetic: () => phonetic,
      partOfSpeech: () => partOfSpeech,
      meaning: () => meaning,
      definition: () => definition,
      fieldSources: () => fieldSources.isEmpty ? null : fieldSources,
      usage: mergeUnique(cur.usage, wa.usage ?? const []),
      examples: mergeExamples(cur.examples, examples),
      source: () => betterSource(
        cur.source,
        defaultSource ??
            const VocabSource(
              articleId: '',
              fileName: null,
              sentenceId: null,
              sentenceText: '',
            ),
      ),
      contexts: defaultSource != null
          ? () => upsertContext(
                cur.contexts,
                contextFromSource(defaultSource, iso, meaning: ctxMeaning),
              )
          : null,
      status: identityLocked ? cur.status : VocabStatus.queried,
      updatedAt: iso,
    ));
    items = [
      for (var i = 0; i < items.length; i++) i == idx ? merged : items[i],
    ];
  }

  return library.copyWith(items: items);
}

String? _cleanOrNull(String? raw) {
  if (raw == null) return null;
  final cleaned = cleanGloss(raw);
  return cleaned.isEmpty ? null : cleaned;
}

/// 一份混淆项结果。
class ConfusableResult {
  const ConfusableResult({required this.word, required this.confusables});

  final String word;
  final List<VocabConfusable> confusables;
}

/// 把混淆项（形近/义近词）写回对应词条。按 lemma 匹配，已有的会被覆盖（视为刷新）。
///
/// [source] 必须由调用方在写入边界给出（AI / 离线词典），
/// 旧数据没有来源时保持 null，不能靠时间或内容反推。
VocabLibrary applyConfusables(
  VocabLibrary library,
  List<ConfusableResult> results,
  VocabConfusableSource source, {
  DateTime? now,
}) {
  if (results.isEmpty) return library;
  final iso = (now ?? DateTime.now()).toIso8601String();
  final byLemma = <String, List<VocabConfusable>>{};
  for (final r in results) {
    final lemma = lemmaOf(r.word);
    if (lemma.isNotEmpty && r.confusables.isNotEmpty) {
      byLemma[lemma] = r.confusables;
    }
  }
  return library.copyWith(
    items: library.items.map((it) {
      final c = byLemma[it.lemma];
      if (c == null) return it;
      return it.copyWith(
        confusables: () => c,
        confusablesSource: () => source,
        updatedAt: iso,
      );
    }).toList(growable: false),
  );
}

/// 按「原词形 → 原形」映射校正词条：改 word / lemma / id。
/// 校正后应再跑一次 `dedupeLibrary`（可能产生重复）。
VocabLibrary applyLemmaMap(
  VocabLibrary library,
  List<LemmaPair> pairs, {
  DateTime? now,
}) {
  if (pairs.isEmpty) return library;
  final iso = (now ?? DateTime.now()).toIso8601String();
  final map = <String, String>{};
  for (final p in pairs) {
    final from = normalizeWord(p.from);
    final to = p.to.trim();
    if (from.isNotEmpty && to.isNotEmpty) map[from] = to;
  }
  return library.copyWith(
    items: library.items.map((it) {
      final to = map[normalizeWord(it.word)] ?? map[it.lemma];
      if (to == null) return it;
      final lemma = lemmaOf(to);
      return it.copyWith(
        word: to,
        lemma: lemma,
        id: 'vocab:$lemma',
        updatedAt: iso,
      );
    }).toList(growable: false),
  );
}

/// 重新按 word 计算 lemma（修正历史遗留的旧 lemma / 不统一）。
/// 之后配合 `dedupeLibrary` 合并重复。
VocabLibrary relemmaLibrary(VocabLibrary library) => library.copyWith(
      items: library.items.map((it) {
        final lemma = lemmaOf(it.word);
        if (lemma.isEmpty || lemma == it.lemma) return it;
        return it.copyWith(lemma: lemma, id: 'vocab:$lemma');
      }).toList(growable: false),
    );

/// -ing / -ed 语法辨析结果的一行（8 列）。
class PosRow {
  const PosRow({
    required this.lemma,
    required this.surface,
    required this.pos,
    this.syntax = '',
    this.role = '',
    this.meaning = '',
    this.reason = '',
    this.label = '',
  });

  final String lemma;
  final String surface;
  final String pos;
  final String syntax;
  final String role;
  final String meaning;
  final String reason;
  final String label;
}

/// 写回 -ing/-ed 语法辨析结果：
///   - 单词条目（非短语）按其原形改 word/lemma/id；短语条目保持词形不变；
///   - 词性用短标注；完整辨析（语法身份/成分/理由/最准确词性）追加进 note。
/// 之后建议跑一次 `dedupeLibrary`。
VocabLibrary applyPosAnalysis(
  VocabLibrary library,
  List<PosRow> rows, {
  DateTime? now,
}) {
  if (rows.isEmpty) return library;
  final iso = (now ?? DateTime.now()).toIso8601String();
  final items = [...library.items];
  for (final row in rows) {
    final surface = normalizeWord(row.surface);
    final lemma = normalizeWord(row.lemma);
    if (surface.isEmpty) continue;
    // 匹配条目：词形等于当前形式 → 短语里含当前形式 → lemma 相同
    var idx =
        items.indexWhere((it) => normalizeWord(it.word) == surface);
    if (idx < 0) {
      idx = items.indexWhere(
          (it) => normalizeWord(it.word).split(' ').contains(surface));
    }
    if (idx < 0) {
      idx = items.indexWhere(
          (it) => it.lemma == lemma || normalizeWord(it.word) == lemma);
    }
    if (idx < 0) continue;
    final cur = items[idx];
    final single = !cur.word.trim().contains(' ');
    final locked = cur.status == VocabStatus.edited ||
        cur.status == VocabStatus.mastered;
    final asked = single &&
        !locked &&
        row.lemma.trim().isNotEmpty &&
        normalizeWord(row.lemma) != normalizeWord(cur.word);
    // AI 给的原形只在**确认是屈折**时才用来改词形（见 `canRewriteTo`）：
    // 否则 unchallenged 会被改成 challenge，而释义/用法/例句原地不动 → 张冠李戴。
    final rewrite = single &&
        !locked &&
        row.lemma.trim().isNotEmpty &&
        canRewriteTo(cur.word, row.lemma);
    final nextWord = rewrite ? row.lemma.trim() : cur.word;
    final nextLemmaRaw = rewrite ? lemmaOf(nextWord) : '';
    final nextLemma = nextLemmaRaw.isEmpty ? cur.lemma : nextLemmaRaw;
    final fieldSources = <VocabField, VocabFieldSource>{...?cur.fieldSources};
    final pos = row.pos.trim();
    final partOfSpeech =
        (!isFieldLocked(cur, VocabField.partOfSpeech) && pos.isNotEmpty)
            ? pos
            : cur.partOfSpeech;
    if (partOfSpeech != cur.partOfSpeech) {
      fieldSources[VocabField.partOfSpeech] = VocabFieldSource.ai;
    }
    final givenMeaning = row.meaning.trim();
    final meaning = cur.meaning ??
        ((!isFieldLocked(cur, VocabField.meaning) && givenMeaning.isNotEmpty)
            ? givenMeaning
            : null);
    if (meaning != cur.meaning) {
      fieldSources[VocabField.meaning] = VocabFieldSource.ai;
    }
    final noteLine = '[辨析] ${row.surface} — ${row.syntax}'
        '${row.role.isNotEmpty ? '；${row.role}' : ''}'
        '${row.reason.isNotEmpty ? '；${row.reason}' : ''}'
        '${(row.label.isNotEmpty || row.pos.isNotEmpty) ? ' → ${row.label.isNotEmpty ? row.label : row.pos}' : ''}'
        '${(asked && !rewrite) ? '（未改词形：${row.lemma} 是派生词，不是它的词形变化）' : ''}';
    items[idx] = cur.copyWith(
      id: rewrite ? 'vocab:$nextLemma' : cur.id,
      word: nextWord,
      lemma: nextLemma,
      partOfSpeech: () => partOfSpeech,
      meaning: () => meaning,
      fieldSources: () => fieldSources.isEmpty ? null : fieldSources,
      note: cur.note.isEmpty ? noteLine : '${cur.note}\n$noteLine',
      updatedAt: iso,
    );
  }
  return library.copyWith(items: items);
}
