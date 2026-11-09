/// 「D老师小课堂」金句课的强类型内容模型（纯 Dart，可单测）。
///
/// 这些类只描述**内容**，不含用户进度（进度在 LearningData）。
/// 外部输入（AI / 备份 / SQLite）一律先过 `golden_parse.dart` 的
/// `normalizeGoldenLesson` 守卫，不许 `Map as GoldenLesson` 直接进业务。
library;

/// 目标类型：`pattern` / `tense` 是写作最值得迁移的句型与时态。
enum GoldenTargetKind { pattern, tense, collocation, idiom, usage, word }

/// 文章脉络里一段的角色。
enum GoldenSectionRole { intro, body, conclusion }

/// 金句来源的选择方式。
enum GoldenPickMode { recommended, all, manual, ai }

/// 填空单位：一个词一个空 / 一个语言点一个空。
enum GoldenBlankUnit { word, target }

/// 「加入本课」的语言点类型。
enum GoldenExtraPointKind { chunk, pattern, collocation, idiom, usage }

/// 「加入本课」的来源。
enum GoldenExtraPointSource { ai, user }

/// 整课内容的来源。
enum GoldenSource { ai, local, merged }

/// 单条考试题 / 题目的来源。
enum GoldenItemSource { local, ai }

/// 守卫函数的输入：当前文章里句子的最小信息（正文 + 译文）。
class GoldenTextMeta {
  const GoldenTextMeta({
    required this.id,
    required this.text,
    this.translation,
  });

  final String id;
  final String text;
  final String? translation;
}

/// 目标在原文里的一段出现位置（[start, end)）。
class GoldenTargetSpan {
  const GoldenTargetSpan({
    required this.start,
    required this.end,
    required this.text,
  });

  final int start;
  final int end;
  final String text;
}

/// 一个要被填 / 拼 / 回忆的学习点；[en] 必须是原句里逐字出现的片段。
class GoldenTarget {
  const GoldenTarget({
    required this.en,
    required this.kind,
    this.zh,
  });

  final String en;
  final GoldenTargetKind kind;
  final String? zh;

  Map<String, Object?> toJson() => <String, Object?>{
        'en': en,
        'kind': kind.name,
        if (zh != null) 'zh': zh,
      };
}

/// 一句金句的 AI / 本地内容（不含用户进度）。
class GoldenSentence {
  const GoldenSentence({
    required this.id,
    this.zh,
    this.pattern,
    this.tense,
    this.note,
    this.targets = const <GoldenTarget>[],
  });

  /// 对应 `Sentence.id`。
  final String id;
  final String? zh;
  final String? pattern;
  final String? tense;
  final String? note;
  final List<GoldenTarget> targets;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        if (zh != null) 'zh': zh,
        if (pattern != null) 'pattern': pattern,
        if (tense != null) 'tense': tense,
        if (note != null) 'note': note,
        'targets': targets.map((t) => t.toJson()).toList(),
      };
}

/// 文章结构的一段（开头 / 主体 / 结尾），对应原文段落。
class GoldenSection {
  const GoldenSection({
    required this.paraId,
    required this.role,
    this.title,
    this.points = const <String>[],
  });

  final String paraId;
  final GoldenSectionRole role;
  final String? title;
  final List<String> points;

  Map<String, Object?> toJson() => <String, Object?>{
        'paraId': paraId,
        'role': role.name,
        if (title != null) 'title': title,
        'points': points,
      };
}

/// 仿写考试题的评分维度。
class GoldenRubric {
  const GoldenRubric({
    required this.dimension,
    required this.weight,
    this.description,
  });

  final String dimension;
  final int weight;
  final String? description;

  Map<String, Object?> toJson() => <String, Object?>{
        'dimension': dimension,
        'weight': weight,
        if (description != null) 'description': description,
      };
}

/// 仿写考试里的一条题：用学过的句型，按中文提示写新句子。
class GoldenExamItem {
  const GoldenExamItem({
    required this.id,
    required this.sentenceId,
    required this.task,
    required this.model,
    this.structure,
    this.mustUse = const <String>[],
    this.rubric = const <GoldenRubric>[],
    this.source = GoldenItemSource.ai,
    this.focus,
  });

  final String id;
  final String sentenceId;
  final String task;
  final String model;
  final String? structure;
  final List<String> mustUse;
  final List<GoldenRubric> rubric;
  final GoldenItemSource source;
  final String? focus;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'sentenceId': sentenceId,
        'task': task,
        'model': model,
        if (structure != null) 'structure': structure,
        'mustUse': mustUse,
        'rubric': rubric.map((r) => r.toJson()).toList(),
        'source': source.name,
        if (focus != null) 'focus': focus,
      };
}

/// 用户从「错因复盘」加进本课的语言点。
///
/// 为什么不塞进 `sentences[].targets`：`goldenDrillKey` 会把 targets 算进
/// 哈希，改 targets 等于让现有进度 / 掌握状态全部失效。extraPoints 只影响
/// 「语言点造句」的可选项，不动填空 / 拼句的身份。
class GoldenExtraPoint {
  const GoldenExtraPoint({
    required this.sentenceId,
    required this.en,
    required this.kind,
    required this.source,
    this.zh,
    this.issueKey,
    this.at,
  });

  final String sentenceId;
  final String en;
  final GoldenExtraPointKind kind;
  final GoldenExtraPointSource source;
  final String? zh;
  final String? issueKey;
  final String? at;

  Map<String, Object?> toJson() => <String, Object?>{
        'sentenceId': sentenceId,
        'en': en,
        'kind': kind.name,
        'source': source.name,
        if (zh != null) 'zh': zh,
        if (issueKey != null) 'issueKey': issueKey,
        if (at != null) 'at': at,
      };
}

/// 本课设置：去重、金句来源、填空单位、整句渐进、考试门槛。
class GoldenLessonOptions {
  const GoldenLessonOptions({
    this.dedupe = false,
    this.pick,
    this.blankUnit,
    this.sentenceFill,
    this.examAfter,
  });

  final bool dedupe;
  final GoldenPickMode? pick;
  final GoldenBlankUnit? blankUnit;
  final bool? sentenceFill;

  /// 完成多少句「遣词造句」后解锁仿写考试；null / 5 都是默认 5，10 才显式存。
  final int? examAfter;

  Map<String, Object?> toJson() => <String, Object?>{
        'dedupe': dedupe,
        if (pick != null) 'pick': pick!.name,
        if (blankUnit != null) 'blankUnit': blankUnit!.name,
        if (sentenceFill != null) 'sentenceFill': sentenceFill,
        if (examAfter != null) 'examAfter': examAfter,
      };
}

/// 一篇文章的金句课内容。AI 生成或本地推导，存 `SavedArticle.golden`。
class GoldenLesson {
  const GoldenLesson({
    this.version = 1,
    required this.source,
    this.summary,
    this.outline = const <GoldenSection>[],
    required this.sentences,
    required this.selected,
    this.aiSelected,
    this.exam,
    this.extraPoints,
    this.options = const GoldenLessonOptions(),
    this.updatedAt,
  });

  final int version;
  final GoldenSource source;
  final String? summary;
  final List<GoldenSection> outline;
  final List<GoldenSentence> sentences;
  final List<String> selected;
  final List<String>? aiSelected;
  final List<GoldenExamItem>? exam;
  final List<GoldenExtraPoint>? extraPoints;
  final GoldenLessonOptions options;
  final String? updatedAt;

  GoldenLesson copyWith({
    int? version,
    GoldenSource? source,
    String? Function()? summary,
    List<GoldenSection>? outline,
    List<GoldenSentence>? sentences,
    List<String>? selected,
    List<String>? Function()? aiSelected,
    List<GoldenExamItem>? Function()? exam,
    List<GoldenExtraPoint>? Function()? extraPoints,
    GoldenLessonOptions? options,
    String? Function()? updatedAt,
  }) =>
      GoldenLesson(
        version: version ?? this.version,
        source: source ?? this.source,
        summary: summary != null ? summary() : this.summary,
        outline: outline ?? this.outline,
        sentences: sentences ?? this.sentences,
        selected: selected ?? this.selected,
        aiSelected: aiSelected != null ? aiSelected() : this.aiSelected,
        exam: exam != null ? exam() : this.exam,
        extraPoints: extraPoints != null ? extraPoints() : this.extraPoints,
        options: options ?? this.options,
        updatedAt: updatedAt != null ? updatedAt() : this.updatedAt,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'version': version,
        'source': source.name,
        if (summary != null) 'summary': summary,
        'outline': outline.map((s) => s.toJson()).toList(),
        'sentences': sentences.map((s) => s.toJson()).toList(),
        'selected': selected,
        if (aiSelected != null) 'aiSelected': aiSelected,
        if (exam != null) 'exam': exam!.map((e) => e.toJson()).toList(),
        if (extraPoints != null)
          'extraPoints': extraPoints!.map((p) => p.toJson()).toList(),
        'options': options.toJson(),
        if (updatedAt != null) 'updatedAt': updatedAt,
      };
}
