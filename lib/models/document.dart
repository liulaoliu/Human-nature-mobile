/// 文章的中间层数据模型（纯数据，不含解析逻辑）。
///
/// 对应 Web 版 `src/types/document.ts` 里 `Sentence` 往上的那一半。
/// 词库那一半在 `vocab.dart`。
///
/// 约定（与 Web 版一致）：
/// - 所有字段可序列化，没有函数 / Map / Set；
/// - 时间一律 ISO 8601 字符串；
/// - **这里不做 JSON 解析**，外部输入先过 `core/backup_parse.dart` 的守卫。
library;

import 'vocab.dart';

/// 句子与音频的对应区间。
///
/// 这是「块级比例摊词 + 手动锚点」**近似投影**得到的结果，不是强制对齐。
/// `null` 表示未对齐，播放器必须降级为纯文本模式。
class AudioSegment {
  const AudioSegment({required this.start, required this.end});

  /// 起始秒，保留两位小数。
  final double start;

  /// 结束秒，保留两位小数。
  final double end;

  @override
  bool operator ==(Object other) =>
      other is AudioSegment && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'AudioSegment($start, $end)';
}

/// 句子级语言点（AI 结构化分析：结构 / 语法 / idiom / 词组 / 用法）。
class SentenceLanguage {
  const SentenceLanguage({
    this.structure,
    this.grammar,
    this.idioms,
    this.phrases,
    this.usage,
    this.source,
    this.at,
  });

  /// 结构分析。
  final String? structure;

  /// 语法要点。
  final String? grammar;

  /// 习语。
  final List<String>? idioms;

  /// 词组 / 搭配。
  final List<String>? phrases;

  /// 用法说明。
  final List<String>? usage;

  /// AI 生成 / 手动添加。一句可有多条，AI 的只保留一条。
  final LanguageSource? source;

  /// 添加 / 生成时刻（ISO 8601）。
  final String? at;

  @override
  bool operator ==(Object other) =>
      other is SentenceLanguage &&
      other.structure == structure &&
      other.grammar == grammar &&
      _listEq(other.idioms, idioms) &&
      _listEq(other.phrases, phrases) &&
      _listEq(other.usage, usage) &&
      other.source == source &&
      other.at == at;

  @override
  int get hashCode => Object.hash(structure, grammar, source, at);
}

/// 语言点的来源。
enum LanguageSource { ai, manual }

/// 已保存文章从哪来。
///
/// 旧数据没有这个字段就保持未知，**不拿 `sourceKey` 或时间反推**——
/// 反推出来的来源会骗人，而且再也纠正不回来。解析与中文名见
/// `lib/core/article_origin.dart`。
enum ArticleOrigin { library, paste, epub, file }

bool _listEq(List<String>? a, List<String>? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return false;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// 单个句子，精读与复读的共同最小单元。
class Sentence {
  const Sentence({
    required this.id,
    required this.paraId,
    required this.text,
    this.audio,
    this.translation,
    this.grammarNote,
    this.collocations = const [],
    this.vocab = const [],
    this.language,
    this.languages,
    this.tags = const [],
    this.reviewState = defaultReviewState,
  });

  /// 如 "s001"。
  final String id;

  /// 所属段落 id，如 "p01"。
  final String paraId;

  /// 原文，已清理。
  final String text;

  /// 音频区间；未对齐为 null。
  final AudioSegment? audio;

  /// 中文翻译；未查为 null。
  final String? translation;

  /// 长难句结构说明；非长难句为 null。
  final String? grammarNote;

  /// 写作搭配（v1 字段，保留）。
  final List<String> collocations;

  /// 本句出现的生词词形。
  final List<String> vocab;

  /// 旧字段，单条语言点；新数据用 [languages]。
  final SentenceLanguage? language;

  /// 该句的语言点列表（AI 一条 + 手动若干条）。
  final List<SentenceLanguage>? languages;

  /// 标签，如 `["long_sentence"]`。
  final List<String> tags;

  final ReviewState reviewState;

  Sentence copyWith({
    String? id,
    String? paraId,
    String? text,
    AudioSegment? Function()? audio,
    String? Function()? translation,
    String? Function()? grammarNote,
    List<String>? collocations,
    List<String>? vocab,
    SentenceLanguage? Function()? language,
    List<SentenceLanguage>? Function()? languages,
    List<String>? tags,
    ReviewState? reviewState,
  }) {
    return Sentence(
      id: id ?? this.id,
      paraId: paraId ?? this.paraId,
      text: text ?? this.text,
      audio: audio != null ? audio() : this.audio,
      translation: translation != null ? translation() : this.translation,
      grammarNote: grammarNote != null ? grammarNote() : this.grammarNote,
      collocations: collocations ?? this.collocations,
      vocab: vocab ?? this.vocab,
      language: language != null ? language() : this.language,
      languages: languages != null ? languages() : this.languages,
      tags: tags ?? this.tags,
      reviewState: reviewState ?? this.reviewState,
    );
  }
}

/// 段落。
class Paragraph {
  const Paragraph({required this.id, required this.sentenceIds});

  /// 如 "p01"。
  final String id;

  /// 该段包含的句子 id，按顺序。
  final List<String> sentenceIds;

  @override
  bool operator ==(Object other) =>
      other is Paragraph && other.id == id && _listEq(other.sentenceIds, sentenceIds);

  @override
  int get hashCode => Object.hash(id, sentenceIds.length);

  @override
  String toString() => 'Paragraph($id, $sentenceIds)';
}

/// 已保存的文章。
///
/// 为什么存整篇（而不是只存原文、每次重新切句）：粘回来的翻译 / 语法 / 搭配
/// 是挂在句子上的，重新切句会丢。所以连 paragraphs / sentences 一起存，
/// 下次打开就是上次离开时的样子。
///
/// `golden` / `productionDraft` 这类**外部 AI 内容**在模型里按原始 JSON 放着
/// （`models` 不能反向 import `core`）；读的时候过 `core/golden_article.dart`
/// 的 `goldenLessonOf` 拿强类型 `GoldenLesson`，写的时候用 `withGoldenLesson`。
class SavedArticle {
  const SavedArticle({
    required this.id,
    required this.title,
    required this.sentences,
    required this.paragraphs,
    required this.updatedAt,
    this.text = '',
    this.sourceKey,
    this.book,
    this.origin,
    this.golden,
    this.createdAt,
  });

  final String id;
  final String title;

  /// 所属的书（EPUB 导入自动填书名；手动可选）。
  final String? book;

  /// 对应原文库的键；手动粘贴的为 null。
  final String? sourceKey;

  /// 导入来源；旧数据没有就不显示，不猜。
  final ArticleOrigin? origin;

  /// 清洗后的正文；编辑模式与重新切句用。
  final String text;

  final List<Paragraph> paragraphs;
  final List<Sentence> sentences;

  /// D老师小课堂：金句课内容（原始 JSON，读时过守卫）。
  final Map<String, Object?>? golden;

  /// 首次创建时间（老数据没有 → 用 [updatedAt] 兜底）。
  final String? createdAt;

  final String updatedAt;

  SavedArticle copyWith({
    String? id,
    String? title,
    String? Function()? book,
    String? Function()? sourceKey,
    ArticleOrigin? Function()? origin,
    String? text,
    List<Paragraph>? paragraphs,
    List<Sentence>? sentences,
    Map<String, Object?>? Function()? golden,
    String? Function()? createdAt,
    String? updatedAt,
  }) =>
      SavedArticle(
        id: id ?? this.id,
        title: title ?? this.title,
        book: book != null ? book() : this.book,
        sourceKey: sourceKey != null ? sourceKey() : this.sourceKey,
        origin: origin != null ? origin() : this.origin,
        text: text ?? this.text,
        paragraphs: paragraphs ?? this.paragraphs,
        sentences: sentences ?? this.sentences,
        golden: golden != null ? golden() : this.golden,
        createdAt: createdAt != null ? createdAt() : this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  @override
  String toString() => 'SavedArticle($id, "$title", ${sentences.length} 句)';
}
