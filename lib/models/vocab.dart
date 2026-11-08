/// 词库相关的数据模型（纯数据，不含解析逻辑）。
///
/// 对应 Web 版 `src/types/document.ts` 里 `VocabItem` 往下的那一半。
///
/// 约定（与 Web 版一致）：
/// - 所有字段可序列化，没有函数 / Map / Set；
/// - 时间一律 ISO 8601 字符串（`at` / `updatedAt` / `due` …）；
/// - **这里不做 JSON 解析**。外部输入（备份文件、旧数据）一律先过
///   `lib/core/vocab/parse.dart` 的守卫，坏条目丢弃并计数 —— 对应 Web 版
///   `core/migrations.ts` / `core/backupParse.ts` 的分工。
library;

/// 生词状态流转。
enum VocabStatus { unqueried, queried, edited, mastered }

const _statusNames = <VocabStatus, String>{
  VocabStatus.unqueried: 'unqueried',
  VocabStatus.queried: 'queried',
  VocabStatus.edited: 'edited',
  VocabStatus.mastered: 'mastered',
};

String vocabStatusName(VocabStatus s) => _statusNames[s]!;

/// 外部输入里的状态字符串 → 枚举；不认识就返回 null（由调用方决定丢弃还是兜底）。
VocabStatus? parseVocabStatus(Object? raw) {
  if (raw is! String) return null;
  for (final entry in _statusNames.entries) {
    if (entry.value == raw) return entry.key;
  }
  return null;
}

/// 词条类型：普通单词，或从句子语言点里自动收藏的 词组 / 习语 / 用法笔记。
///
/// 与 `lib/core/entry_kind.dart` 的 `VocabKind` 是同一套值，那边管「怎么判定」，
/// 这里管「存什么」。老数据没有该字段，一律当 `word`。
enum VocabItemKind { word, phrase, idiom, usage }

/// 词条核心字段来源（音标 / 词性 / 中文释义 / 英英释义）。
enum VocabFieldSource { ai, dict, manual }

/// 可能被 AI / 离线词典 / 手动同时写入的核心字段。
enum VocabField { phonetic, partOfSpeech, meaning, definition }

/// 易混项来源：AI 生成 / 离线词典拼写近邻。
enum VocabConfusableSource { ai, dict }

/// 本篇收录的触发方：自动标词 / 手动加入。
enum VocabOrigin { auto, manual }

/// 更细的来源：谁触发之外，还记「从哪来」。
enum VocabVia { ai, dict, manual, language, auto, batch, legacy }

/// 本篇语境释义的来源（AI 结果不覆盖手改）。
enum VocabMeaningSource { manual, context, library, dict, ai }

/// 例句来源：来源句 / AI 生成 / 离线例句库（Tatoeba）。
enum VocabExampleOrigin { article, ai, tatoeba }

/// 自研复习状态（与 Anki 并存）。
class ReviewState {
  const ReviewState({
    this.ease = 2.5,
    this.due,
    this.interval = 0,
    this.repetitions = 0,
    this.lapses = 0,
    this.relearn = 0,
    this.meaningPasses = 0,
  });

  /// 难度系数，初始 2.5。
  final double ease;

  /// 下次复习时间（ISO 8601）；未排期时为 null。
  final String? due;

  /// 间隔天数。
  final int interval;

  /// 已复习次数。
  final int repetitions;

  /// 出错（评「忘记」）次数。老数据没有，按 0 算。
  final int lapses;

  /// 重学阶段：>0 表示正在「从零重学」。1–3，连续答对两次后清零。
  final int relearn;

  /// 「没看答案就选对中文释义」累计过几次。
  ///
  /// 判定规则是「首次选对 = 模糊，第二次起 = 认识」（第一次可能是蒙对的）。
  /// 这个次数必须跟词走、跟备份走，放本机偏好里换台机器就丢了。
  final int meaningPasses;

  ReviewState copyWith({
    double? ease,
    String? Function()? due,
    int? interval,
    int? repetitions,
    int? lapses,
    int? relearn,
    int? meaningPasses,
  }) {
    return ReviewState(
      ease: ease ?? this.ease,
      due: due != null ? due() : this.due,
      interval: interval ?? this.interval,
      repetitions: repetitions ?? this.repetitions,
      lapses: lapses ?? this.lapses,
      relearn: relearn ?? this.relearn,
      meaningPasses: meaningPasses ?? this.meaningPasses,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ReviewState &&
      other.ease == ease &&
      other.due == due &&
      other.interval == interval &&
      other.repetitions == repetitions &&
      other.lapses == lapses &&
      other.relearn == relearn &&
      other.meaningPasses == meaningPasses;

  @override
  int get hashCode =>
      Object.hash(ease, due, interval, repetitions, lapses, relearn, meaningPasses);
}

/// 新词条的默认复习状态（对应 Web 版 `defaultReviewState()`）。
const defaultReviewState = ReviewState();

/// 例句。
class VocabExample {
  const VocabExample({
    required this.text,
    this.translation,
    this.articleId,
    this.fileName,
    this.sentenceId,
    this.origin,
  });

  final String text;
  final String? translation;
  final String? articleId;
  final String? fileName;
  final String? sentenceId;
  final VocabExampleOrigin? origin;

  VocabExample copyWith({String? text, String? translation}) => VocabExample(
        text: text ?? this.text,
        translation: translation ?? this.translation,
        articleId: articleId,
        fileName: fileName,
        sentenceId: sentenceId,
        origin: origin,
      );
}

/// 生词来源：标词时自动回填。
class VocabSource {
  const VocabSource({
    required this.articleId,
    this.fileName,
    this.sentenceId,
    this.sentenceText = '',
  });

  final String articleId;
  final String? fileName;
  final String? sentenceId;

  /// 标词时所在的整句原文。
  final String sentenceText;

  VocabSource copyWith({String? sentenceText}) => VocabSource(
        articleId: articleId,
        fileName: fileName,
        sentenceId: sentenceId,
        sentenceText: sentenceText ?? this.sentenceText,
      );
}

/// 该词在某篇文章里的出现语境（一句话 + 可选「此处含义」）。
class VocabContext {
  const VocabContext({
    required this.articleId,
    this.fileName,
    this.sentenceId,
    this.sentenceText = '',
    this.meaning,
    required this.at,
  });

  final String articleId;
  final String? fileName;
  final String? sentenceId;
  final String sentenceText;

  /// 在这个语境下的释义（AI 按本篇上下文给的；可能没有）。
  final String? meaning;

  /// 记录时刻 ISO。
  final String at;

  VocabContext copyWith({String? sentenceText}) => VocabContext(
        articleId: articleId,
        fileName: fileName,
        sentenceId: sentenceId,
        sentenceText: sentenceText ?? this.sentenceText,
        meaning: meaning,
        at: at,
      );
}

/// AI 生成的易混项（选择题干扰项优先用它）。
class VocabConfusable {
  const VocabConfusable({required this.word, this.meaning});

  final String word;
  final String? meaning;
}

/// 「这篇文章收了这个词」的独立记录。
///
/// 全库 `VocabItem` 按 lemma 只有一条（复习一次），但同一词可以在多篇里各收一次：
/// 每篇的序号、加入方式、语境释义、打印状态都互不影响。
class ArticleVocabEntry {
  const ArticleVocabEntry({
    required this.articleId,
    required this.lemma,
    required this.origin,
    this.via,
    required this.addedAt,
    this.sentenceId,
    this.sentenceText,
    this.meaning,
    this.meaningSource,
    this.printedAt,
  });

  /// 文章稳定标识（与 `source.fileName` / articleIdentity 同一套）。
  final String articleId;

  /// 词条原形（对应 `VocabItem.lemma`）。
  final String lemma;
  final VocabOrigin origin;
  final VocabVia? via;

  /// 加入时间 ISO（合并备份时排序用；篇内编号按数组顺序）。
  final String addedAt;
  final String? sentenceId;
  final String? sentenceText;

  /// 这一篇里该词的语境释义（没有就回退到全库主释义）。
  final String? meaning;
  final VocabMeaningSource? meaningSource;

  /// 这一篇打印过该词的时间（按篇独立）。
  final String? printedAt;

  /// 合并键：同一篇 + 同一 lemma 视为同一条。
  String get key => '$articleId\u0000$lemma';

  ArticleVocabEntry copyWith({
    String? articleId,
    String? lemma,
    VocabOrigin? origin,
    VocabVia? via,
    String? sentenceId,
    String? sentenceText,
    String? Function()? meaning,
    VocabMeaningSource? meaningSource,
    String? Function()? printedAt,
  }) {
    return ArticleVocabEntry(
      articleId: articleId ?? this.articleId,
      lemma: lemma ?? this.lemma,
      origin: origin ?? this.origin,
      via: via ?? this.via,
      addedAt: addedAt,
      sentenceId: sentenceId ?? this.sentenceId,
      sentenceText: sentenceText ?? this.sentenceText,
      meaning: meaning != null ? meaning() : this.meaning,
      meaningSource: meaningSource ?? this.meaningSource,
      printedAt: printedAt != null ? printedAt() : this.printedAt,
    );
  }
}

/// 删除墓碑。
///
/// 没有它，合并两份词库时无法区分「本机删了」和「本机没有」——
/// 直接并集会把用户删掉的词复活。
class VocabTombstone {
  const VocabTombstone({
    required this.kind,
    required this.key,
    required this.at,
    this.lemma,
  });

  final VocabTombstoneKind kind;

  /// item: `item:<id>`；article: `article:<articleId>\u0000<lemma>`
  final String key;

  /// 删除时刻 ISO。
  final String at;

  /// 全库词条删除时记 lemma，合并时可按 lemma 兜底。
  final String? lemma;
}

enum VocabTombstoneKind { item, article }

/// 生词词条，学习层的一等公民。
class VocabItem {
  const VocabItem({
    required this.id,
    required this.word,
    required this.lemma,
    this.kind,
    this.langPointId,
    this.phonetic,
    this.partOfSpeech,
    this.meaning,
    this.grammarMarks,
    this.definition,
    this.fieldSources,
    this.usage = const [],
    this.phrases,
    this.idioms,
    this.examples = const [],
    this.source,
    this.contexts,
    this.status = VocabStatus.unqueried,
    this.note = '',
    this.tags = const [],
    this.lastPrintedAt,
    this.confusables,
    this.confusablesSource,
    this.priorityUntil,
    this.reviewState = defaultReviewState,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;

  /// 原词形。
  final String word;

  /// 归一化形式，去重用（running / ran → run）。
  final String lemma;

  /// 词条类型（null = 普通单词）。
  final VocabItemKind? kind;

  /// 「从哪条语言点收来的」去重标记。
  final String? langPointId;

  final String? phonetic;
  final String? partOfSpeech;
  final String? meaning;

  /// 主要释义的语法标记（可数/不可数、及物/不及物…）。
  final List<String>? grammarMarks;

  /// 英英释义（学习者词典风格的一句话）。
  final String? definition;

  /// 核心字段来源；旧数据没有，不猜。
  final Map<VocabField, VocabFieldSource>? fieldSources;

  /// 用法 / 搭配说明（v1 的 collocations 并入这里）。
  final List<String> usage;

  /// 词组 / 搭配，如 run out；run a business。
  final List<String>? phrases;

  /// 习语 / 固定说法，如 run in the family。
  final List<String>? idioms;

  final List<VocabExample> examples;
  final VocabSource? source;

  /// 在哪些文章里、各自什么语境出现过（多义词据此区分）。
  final List<VocabContext>? contexts;

  final VocabStatus status;
  final String note;
  final List<String> tags;

  /// 最近一次 A4 打印的时间（ISO 8601）；老数据没有，按「未打印」算。
  final String? lastPrintedAt;

  /// 易混项（形近/义近）。
  final List<VocabConfusable>? confusables;
  final VocabConfusableSource? confusablesSource;

  /// 优先重排到期时间（ISO 8601）。答错后写「次日」。
  final String? priorityUntil;

  final ReviewState reviewState;

  /// ISO 8601。
  final String createdAt;

  /// ISO 8601。
  final String updatedAt;

  VocabItem copyWith({
    String? id,
    String? word,
    String? lemma,
    VocabItemKind? Function()? kind,
    String? Function()? langPointId,
    String? Function()? phonetic,
    String? Function()? partOfSpeech,
    String? Function()? meaning,
    List<String>? Function()? grammarMarks,
    String? Function()? definition,
    Map<VocabField, VocabFieldSource>? Function()? fieldSources,
    List<String>? usage,
    List<String>? Function()? phrases,
    List<String>? Function()? idioms,
    List<VocabExample>? examples,
    VocabSource? Function()? source,
    List<VocabContext>? Function()? contexts,
    VocabStatus? status,
    String? note,
    List<String>? tags,
    String? Function()? lastPrintedAt,
    List<VocabConfusable>? Function()? confusables,
    VocabConfusableSource? Function()? confusablesSource,
    String? Function()? priorityUntil,
    ReviewState? reviewState,
    String? createdAt,
    String? updatedAt,
  }) {
    return VocabItem(
      id: id ?? this.id,
      word: word ?? this.word,
      lemma: lemma ?? this.lemma,
      kind: kind != null ? kind() : this.kind,
      langPointId: langPointId != null ? langPointId() : this.langPointId,
      phonetic: phonetic != null ? phonetic() : this.phonetic,
      partOfSpeech: partOfSpeech != null ? partOfSpeech() : this.partOfSpeech,
      meaning: meaning != null ? meaning() : this.meaning,
      grammarMarks: grammarMarks != null ? grammarMarks() : this.grammarMarks,
      definition: definition != null ? definition() : this.definition,
      fieldSources: fieldSources != null ? fieldSources() : this.fieldSources,
      usage: usage ?? this.usage,
      phrases: phrases != null ? phrases() : this.phrases,
      idioms: idioms != null ? idioms() : this.idioms,
      examples: examples ?? this.examples,
      source: source != null ? source() : this.source,
      contexts: contexts != null ? contexts() : this.contexts,
      status: status ?? this.status,
      note: note ?? this.note,
      tags: tags ?? this.tags,
      lastPrintedAt: lastPrintedAt != null ? lastPrintedAt() : this.lastPrintedAt,
      confusables: confusables != null ? confusables() : this.confusables,
      confusablesSource:
          confusablesSource != null ? confusablesSource() : this.confusablesSource,
      priorityUntil: priorityUntil != null ? priorityUntil() : this.priorityUntil,
      reviewState: reviewState ?? this.reviewState,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// 词库。跨文章累积，独立于任何单篇文档。
class VocabLibrary {
  const VocabLibrary({
    this.schemaVersion = 1,
    this.items = const [],
    this.articleEntries = const [],
    this.tombstones = const [],
    this.sentenceTexts = const {},
  });

  final int schemaVersion;
  final List<VocabItem> items;

  /// 按篇收录表；老数据没有该字段，迁移时从来源/语境补出来。
  final List<ArticleVocabEntry> articleEntries;

  /// 删除墓碑：合并本机/服务端时防止已删词复活。
  final List<VocabTombstone> tombstones;

  /// 句子原文的共享表（键见 `core/vocab/sentenceTexts`）。
  ///
  /// 同一句会被多个词条的 source / contexts / articleEntries 引用；只在落盘时
  /// 把原文收进这里，读出来再补回各自字段。
  final Map<String, String> sentenceTexts;

  VocabLibrary copyWith({
    int? schemaVersion,
    List<VocabItem>? items,
    List<ArticleVocabEntry>? articleEntries,
    List<VocabTombstone>? tombstones,
    Map<String, String>? sentenceTexts,
  }) {
    return VocabLibrary(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      items: items ?? this.items,
      articleEntries: articleEntries ?? this.articleEntries,
      tombstones: tombstones ?? this.tombstones,
      sentenceTexts: sentenceTexts ?? this.sentenceTexts,
    );
  }
}

/// 当前 schema 版本。破坏性改动 +1（对应 Web 版 `SCHEMA_VERSION`）。
const vocabSchemaVersion = 1;
