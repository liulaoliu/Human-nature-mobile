/// 仿写训练：从范句生成「仿写任务 + 评分 rubric」，写完再让 AI **严格**批改。
///
/// 两轮都是纯文本 → JSON：
///   1) 出任务：给范句 → `{ task, model, mustUse, rubric }`
///   2) 批改：给任务 + 学生作答 → `{ version, scores, issues, recommendations, polished, summary }`
///
/// 提示词刻意强调「严格、就事论事、指出具体错误、给可直接用的改法」，杜绝「很棒/下次注意」式空话。
/// 解析层对不合格的 JSON 直接返回空，不放水。
///
/// v2 批改契约：每条 issue 必须带闭集 `rule` + 稳定的 `key`，
/// AI 额外给 0–3 条 `recommendations`（可加入本课的语言点）。
///
/// 对应 Web 版 `src/core/writing.ts`（689 行）；记录相关的部分拆在 `writing_record.dart`。
library;

import 'dart:convert';

import 'writing_error_rules.dart';

export 'writing_error_rules.dart'
    show WritingIssueType, WritingRule, writingRuleCatalog, writingTypeLabel;
export 'writing_json.dart';
export 'writing_record.dart';

/// rubric 的一维（维度名 + 权重 + 扣分说明）。
class RubricItem {
  const RubricItem({required this.dimension, this.weight = 0, this.description});

  final String dimension;
  final int weight;
  final String? description;

  @override
  String toString() => 'RubricItem($dimension, $weight)';
}

/// 一道仿写任务（题目 + 范句 + 必须用上的词 + rubric）。
class ImitationTask {
  const ImitationTask({
    required this.task,
    this.model = '',
    this.structure,
    this.mustUse = const <String>[],
    this.rubric = const <RubricItem>[],
    this.focus,
    this.round,
  });

  final String task;

  /// 范句原文；拷打造句没有范句时是空串。
  final String model;
  final String? structure;
  final List<String> mustUse;
  final List<RubricItem> rubric;

  /// 「语言点造句」：必须用上的那个词块；普通仿写没有这个字段。
  final String? focus;

  /// 第几稿：按批改意见改写后是 2；首稿不写。
  final int? round;

  ImitationTask copyWith({
    String? task,
    String? model,
    String? Function()? structure,
    List<String>? mustUse,
    List<RubricItem>? rubric,
    String? Function()? focus,
    int? Function()? round,
  }) =>
      ImitationTask(
        task: task ?? this.task,
        model: model ?? this.model,
        structure: structure != null ? structure() : this.structure,
        mustUse: mustUse ?? this.mustUse,
        rubric: rubric ?? this.rubric,
        focus: focus != null ? focus() : this.focus,
        round: round != null ? round() : this.round,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'task': task,
        'model': model,
        if (structure != null) 'structure': structure,
        'mustUse': mustUse,
        'rubric': <Object?>[
          for (final r in rubric)
            <String, Object?>{
              'dimension': r.dimension,
              'weight': r.weight,
              if (r.description != null) 'description': r.description,
            },
        ],
        if (focus != null) 'focus': focus,
        if (round != null) 'round': round,
      };
}

/// 一个评分维度的得分。
class WritingScore {
  const WritingScore({
    required this.dimension,
    this.score = 0,
    this.max = 0,
    this.comment,
  });

  final String dimension;
  final int score;
  final int max;
  final String? comment;

  Map<String, Object?> toJson() => <String, Object?>{
        'dimension': dimension,
        'score': score,
        'max': max,
        if (comment != null) 'comment': comment,
      };
}

/// 一条错因。
class WritingIssue {
  const WritingIssue({
    required this.original,
    required this.suggestion,
    required this.rule,
    required this.key,
    this.reason,
    this.severity = 'must-fix',
  });

  /// 原文片段（必须逐字出现在学生作答里）。
  final String original;

  /// 建议改法。
  final String suggestion;
  final String? reason;

  /// 闭集错因；跨句 / 跨篇趋势的归一键。
  final WritingRule rule;

  /// 这一条错因的具体身份（复习卡 / 去重）。
  final String key;

  /// `must-fix`（硬错）或 `improvement`（提升项）。
  final String severity;

  /// 大类只从 rule 推导，不允许视图另算一份。
  WritingIssueType get type => rule.type;

  bool get isImprovement => severity == 'improvement';

  Map<String, Object?> toJson() => <String, Object?>{
        'original': original,
        'suggestion': suggestion,
        if (reason != null) 'reason': reason,
        'type': rule.type.name,
        'rule': rule.id,
        'key': key,
        'severity': severity,
      };

  @override
  String toString() => 'WritingIssue(${rule.id}, $key)';
}

/// 可加入本课的语言点（批改里 AI 给的 0–3 条建议）。
enum WritingRecommendationKind { chunk, pattern, collocation, usage, grammar }

const Map<WritingRecommendationKind, String> _recKindLabel =
    <WritingRecommendationKind, String>{
  WritingRecommendationKind.chunk: '词块',
  WritingRecommendationKind.pattern: '句型',
  WritingRecommendationKind.collocation: '搭配',
  WritingRecommendationKind.usage: '用法',
  WritingRecommendationKind.grammar: '语法',
};

/// 语言点建议的来源：错因 / 文章 / AI 自想。
enum WritingRecommendationFrom { error, article, ai }

/// 一条可加入本课的语言点建议。
class WritingRecommendation {
  const WritingRecommendation({
    required this.kind,
    required this.point,
    required this.why,
    this.zh,
    this.example,
    this.priority = 2,
    this.from = WritingRecommendationFrom.ai,
    this.issueKey,
    this.pointId,
  });

  final WritingRecommendationKind kind;

  /// 英文语言点本身（词块 / 句型 / 搭配）。
  final String point;
  final String? zh;
  final String why;
  final String? example;

  /// 1 最该练、3 最不着急。
  final int priority;
  final WritingRecommendationFrom from;

  /// 来自哪条错因（`from == error` 时）。
  final String? issueKey;

  /// 文章自带语言点 id（`from == article` 时）。
  final String? pointId;

  String get kindLabel => _recKindLabel[kind] ?? '词块';

  Map<String, Object?> toJson() => <String, Object?>{
        'kind': kind.name,
        'point': point,
        if (zh != null) 'zh': zh,
        'why': why,
        if (example != null) 'example': example,
        'priority': priority,
        'from': from.name,
        if (issueKey != null) 'issueKey': issueKey,
        if (pointId != null) 'pointId': pointId,
      };

  @override
  String toString() => 'WritingRecommendation(${kind.name}, $point)';
}

/// 一次批改的结果。
class WritingFeedback {
  const WritingFeedback({
    this.version = 2,
    this.scores = const <WritingScore>[],
    this.total = 0,
    this.max = 0,
    this.issues = const <WritingIssue>[],
    this.recommendations = const <WritingRecommendation>[],
    this.polished,
    this.summary,
  });

  /// 2 = issues 带 rule/key；旧记录回填后也是 2。
  final int version;
  final List<WritingScore> scores;
  final int total;
  final int max;
  final List<WritingIssue> issues;
  final List<WritingRecommendation> recommendations;
  final String? polished;
  final String? summary;

  Map<String, Object?> toJson() => <String, Object?>{
        'version': version,
        'scores': <Object?>[for (final s in scores) s.toJson()],
        'total': total,
        'max': max,
        'issues': <Object?>[for (final i in issues) i.toJson()],
        'recommendations': <Object?>[for (final r in recommendations) r.toJson()],
        if (polished != null) 'polished': polished,
        if (summary != null) 'summary': summary,
      };
}

/// 只认 v2：分析 / 趋势 / 复习入口用这个判断，旧记录必须先回填。
bool isWritingFeedbackV2(WritingFeedback? feedback) => feedback?.version == 2;

final RegExp _fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```', caseSensitive: false);

String _stripFence(String raw) {
  final m = _fence.firstMatch(raw);
  return (m != null ? m.group(1)! : raw).trim();
}

String _asString(Object? v) => v is String ? v.trim() : '';

List<String> _asStringArray(Object? v) {
  if (v is! List) return const <String>[];
  return <String>[
    for (final e in v) _asString(e),
  ].where((s) => s.isNotEmpty).toList();
}

int _asInt(Object? v) {
  if (v is num) return v.isFinite ? v.toInt() : 0;
  if (v is String) return num.tryParse(v)?.toInt() ?? 0;
  return 0;
}

/// 出题提示词：给定范句（可带结构与要用的搭配），生成仿写任务 + rubric。
String buildImitationTaskPrompt({
  required String model,
  String? structure,
  List<String>? mustUse,
}) {
  final must = (mustUse ?? const <String>[]).where((s) => s.isNotEmpty).toList();
  return <String>[
    '你是英语写作教练。请基于下面这个**范句**，设计一个「仿写」任务，用于训练中国学生的英语写作。',
    '',
    '要求：',
    '- task：用中文清楚说明让学生写什么（话题/情境/需要写几句），要能从范句的结构迁移；',
    '- structure：一句话点出范句值得模仿的句型结构；',
    '- mustUse：必须用上的词 / 搭配（${must.isNotEmpty ? '就用这些' : '从范句里挑 2–3 个'}）：'
        '${must.isNotEmpty ? must.join('、') : '（自定）'}；',
    '- rubric：3–4 个评分维度（如 语法准确 / 结构运用 / 用词地道 / 连贯），每个给权重（加起来 100），并写清扣分标准；',
    '- 不要让学生逐字翻译范句，要换内容、套结构。',
    '',
    '只输出一个 JSON 对象，不要任何其他文字。格式：',
    '{"task":"...","model":"范句原文","structure":"...","mustUse":["..."],'
        '"rubric":[{"dimension":"语法准确","weight":30,"description":"..."}]}',
    '',
    '范句：',
    '"""',
    model.trim(),
    '"""',
    if (structure != null && structure.isNotEmpty) '结构提示：$structure',
  ].where((s) => s.isNotEmpty).join('\n');
}

/// 解析仿写任务；缺 task/model 视为不合格。
ImitationTask? parseImitationTask(String raw) {
  final text = _stripFence(raw);
  if (text.isEmpty) return null;
  Object? obj;
  try {
    obj = jsonDecode(text);
  } on FormatException {
    return null;
  }
  if (obj is! Map) return null;
  final task = _asString(obj['task']);
  final model = _asString(obj['model']);
  if (task.isEmpty || model.isEmpty) return null;
  final rubric = <RubricItem>[];
  final rubricRaw = obj['rubric'];
  if (rubricRaw is List) {
    for (final r in rubricRaw) {
      if (r is! Map) continue;
      final dimension = _asString(r['dimension']);
      if (dimension.isEmpty) continue;
      final description = _asString(r['description']);
      rubric.add(RubricItem(
        dimension: dimension,
        weight: _asInt(r['weight']),
        description: description.isEmpty ? null : description,
      ));
    }
  }
  final structure = _asString(obj['structure']);
  return ImitationTask(
    task: task,
    model: model,
    structure: structure.isEmpty ? null : structure,
    mustUse: _asStringArray(obj['mustUse']),
    rubric: rubric,
  );
}

/// 文章自带的语言点（只能从里面挑 pointId，防止 AI 编出不存在的点）。
class AvailablePoint {
  const AvailablePoint({required this.id, required this.en, this.zh, this.kind});

  final String id;
  final String en;
  final String? zh;
  final String? kind;
}

/// 第二稿要复查的上一条错因（只取定位与改法）。
class PreviousIssue {
  const PreviousIssue({
    this.original = '',
    required this.suggestion,
    this.reason,
    required this.rule,
    required this.key,
  });

  final String original;
  final String suggestion;
  final String? reason;
  final WritingRule rule;
  final String key;
}

/// 批改提示词的可选项。
class WritingFeedbackPromptOptions {
  const WritingFeedbackPromptOptions({this.availablePoints, this.previousIssues});

  /// 文章自带的语言点（只能从里面挑 pointId）。
  final List<AvailablePoint>? availablePoints;

  /// 第二稿：上一轮批改的 issues，让 AI 专查「改了没」。
  final List<PreviousIssue>? previousIssues;
}

/// 批改提示词：给定任务与评分标准 + 学生作答，要求严格批改。
String buildWritingFeedbackPrompt(
  ImitationTask task,
  String userText, [
  WritingFeedbackPromptOptions options = const WritingFeedbackPromptOptions(),
]) {
  final rubric = task.rubric.isNotEmpty
      ? task.rubric
          .map((r) => '- ${r.dimension}（满分 ${r.weight}）：${r.description ?? ''}')
          .join('\n')
      : '- 语法准确（满分 40）\n- 用词与搭配（满分 30）\n- 结构与连贯（满分 30）';

  final points = (options.availablePoints ?? const <AvailablePoint>[])
      .where((p) => p.en.trim().isNotEmpty)
      .toList();
  final pointLines = points.isNotEmpty
      ? points
          .map((p) => '- ${p.id} | ${p.en}'
              '${p.zh != null ? ' | ${p.zh}' : ''}'
              '${p.kind != null ? ' | ${p.kind}' : ''}')
          .join('\n')
      : '（本题没有可选语言点；recommendations 里不要写 pointId / from=article）';

  final model = task.model.trim();
  final mustUse =
      task.mustUse.map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  final taskRef = <String>[
    if (model.isNotEmpty) '范句：$model',
    if (mustUse.isNotEmpty) '要求用上：${mustUse.join('、')}',
  ].join('；');

  final previous = (options.previousIssues ?? const <PreviousIssue>[])
      .where((i) => i.suggestion.trim().isNotEmpty)
      .toList();
  final previousBlock = previous.isEmpty
      ? const <String>[]
      : <String>[
          '这是改写后的新稿。上一稿批改指出过这些问题：',
          for (final i in previous)
            '- [${i.rule.id}/${i.key}] “${i.original.isEmpty ? '（缺词）' : i.original}” → '
                '“${i.suggestion}”${i.reason != null ? '（${i.reason}）' : ''}',
          '请逐条检查：已经改掉的不要再报；仍然存在或改错的继续报，并尽量沿用同一个 rule/key；',
          '另外照常检查新出现的问题。',
          '',
        ];

  return <String>[
    '你是严格的英语写作批改老师。请批改下面这篇仿写。**就事论事，不要客套、不要泛泛鼓励。**',
    '',
    '批改要求（必须严格遵守）：',
    '- 只依据下面的评分标准打分；每项都要给出**具体** comment，指出扣分对应的原句；',
    '- issues 要逐条列出**真实存在的**问题：original 必须是学生原文里**逐字**出现的片段（不要改写），'
        'suggestion 给可直接替换的正确写法，reason 说明为什么错（语法/搭配/中式英语等）；',
    '- 同一条错误只报一次；不要为了凑数把「可以更好」写成「错」；',
    '- rule 必须从下面的闭集里选；key 用稳定的小写连字符 slug'
        '（同一种错误跨句、跨篇保持同一个 key，具体词块用具体片段，如 chunk-come-to-an-end）；',
    '- severity：硬错（拼写 / 语法 / 搭配 / 词块 / 语义错）写 must-fix；只是更地道的表达写 improvement；',
    '- recommendations 给 0–3 条**可复习 / 可加入本课**的语言点。'
        'kind 只能是 chunk / pattern / collocation / usage（纯语法规则不要放这里，放进 issues）；',
    '- recommendations 的 why 要说明「和你这次的错/这篇的主题有什么关系」；'
        'from=error 时带对应 issueKey，from=article 时只能从下面语言点里选并带 pointId，自己想到的写 from=ai；',
    '- polished 给一份**完整改写**（保留学生原意，修正所有问题）；',
    '- summary 用中文 2–3 句总结，直说最需要改的地方。',
    '',
    '错因规则闭集（rule: 说明）：',
    writingRuleCatalog(),
    '',
    ...previousBlock,
    '评分标准：',
    rubric,
    '',
    '任务：',
    task.task,
    // 拷打造句没有范句，只写「要求用上」；旧题面输出保持原样。
    if (taskRef.isNotEmpty) '（$taskRef）',
    '',
    '可选语言点（id | 英文 | 中文 | 类型）：',
    pointLines,
    '',
    '学生作答：',
    '"""',
    userText.trim(),
    '"""',
    '',
    '只输出一个 JSON 对象，不要任何其他文字。格式：',
    '{"version":2,"scores":[{"dimension":"语法准确","score":32,"max":40,"comment":"..."}],'
        '"total":82,"max":100,',
    '"issues":[{"original":"学生原文片段","suggestion":"正确写法","reason":"为什么错",'
        '"rule":"chunk-sense","key":"chunk-come-to-an-end","severity":"must-fix"}],',
    '"recommendations":[{"kind":"chunk","point":"come to an end","zh":"结束",'
        '"why":"你这次把 an end to 当成了独立词块","example":"The meeting came to an end.",'
        '"priority":1,"from":"error","issueKey":"chunk-come-to-an-end"}],',
    '"polished":"...","summary":"..."}',
  ].join('\n');
}

/// 解析批改时丢掉 / 补全了什么（界面要能提示）。
class WritingFeedbackDropped {
  WritingFeedbackDropped();

  /// 无法定位 / 缺建议 / 重复的 issues 条数。
  int issues = 0;

  /// 缺字段 / 重复 / 不在白名单的 recommendations 条数。
  int recommendations = 0;

  /// 缺 rule/key、由启发式补全的条数（不是丢弃，但要在界面提示）。
  int inferred = 0;
  List<String> reasons = <String>[];

  bool get isEmpty => issues == 0 && recommendations == 0 && inferred == 0;

  @override
  String toString() =>
      'WritingFeedbackDropped(issues: $issues, recs: $recommendations, inferred: $inferred)';
}

/// 解析结果（批改 + 丢弃计数）。
class WritingFeedbackParse {
  const WritingFeedbackParse({required this.feedback, required this.dropped});

  final WritingFeedback feedback;
  final WritingFeedbackDropped dropped;
}

/// 解析批改时的可选项。
class WritingFeedbackParseOptions {
  const WritingFeedbackParseOptions({this.answer, this.availablePointIds});

  /// 学生原文；给了就校验 original 必须逐字出现，防止 AI 编原文。
  final String? answer;

  /// 文章可选语言点 id；给了就校验 from=article 的 pointId。
  final Set<String>? availablePointIds;
}

List<String> _normalizeReasonList(List<String> list) {
  final seen = <String>{};
  final out = <String>[];
  for (final s in list) {
    final t = s.trim();
    if (t.isEmpty || !seen.add(t)) continue;
    out.add(t);
    if (out.length >= 5) break;
  }
  return out;
}

WritingRecommendationKind? _recKindByName(Object? raw) {
  if (raw is! String) return null;
  for (final k in WritingRecommendationKind.values) {
    if (k.name == raw) return k;
  }
  return null;
}

WritingRecommendationFrom _recFromByName(Object? raw) {
  if (raw is String) {
    for (final f in WritingRecommendationFrom.values) {
      if (f.name == raw) return f;
    }
  }
  return WritingRecommendationFrom.ai;
}

WritingRecommendation? _parseRecommendation(
  Object? raw,
  Set<String> issueKeys,
  Set<String>? availablePointIds,
  WritingFeedbackDropped dropped,
) {
  if (raw is! Map) {
    dropped.recommendations++;
    return null;
  }
  final kind = _recKindByName(raw['kind']);
  if (kind == null) {
    dropped.recommendations++;
    dropped.reasons.add('recommendation kind 不在白名单：${_asString(raw['kind'])}'.trim());
    return null;
  }
  final point = _asString(raw['point']);
  final why = _asString(raw['why']);
  if (point.isEmpty || why.isEmpty) {
    dropped.recommendations++;
    dropped.reasons.add('recommendation 缺 point / why');
    return null;
  }
  final from = _recFromByName(raw['from']);
  final priorityRaw = _asInt(raw['priority']);
  final priority = priorityRaw == 1 ? 1 : (priorityRaw == 3 ? 3 : 2);
  final pointId = _asString(raw['pointId']);
  if (from == WritingRecommendationFrom.article) {
    if (pointId.isEmpty) {
      dropped.recommendations++;
      dropped.reasons.add('recommendation from=article 但缺 pointId');
      return null;
    }
    if (availablePointIds != null && !availablePointIds.contains(pointId)) {
      dropped.recommendations++;
      dropped.reasons.add('recommendation pointId 不在本题语言点里：$pointId');
      return null;
    }
  }
  final issueKey = _asString(raw['issueKey']);
  if (issueKey.isNotEmpty && !issueKeys.contains(issueKey)) {
    // 不丢推荐本身，但把悬空引用摘掉；趋势仍可用 point 本身。
    dropped.reasons.add('recommendation issueKey 没对应 issue：$issueKey');
  }
  final zh = _asString(raw['zh']);
  final example = _asString(raw['example']);
  return WritingRecommendation(
    kind: kind,
    point: point,
    zh: zh.isEmpty ? null : zh,
    why: why,
    example: example.isEmpty ? null : example,
    priority: priority,
    from: from,
    issueKey: issueKeys.contains(issueKey) && issueKey.isNotEmpty ? issueKey : null,
    pointId: pointId.isEmpty ? null : pointId,
  );
}

/// 解析批改结果；至少要有 scores 或 issues 才算有效。
///
/// 严格点：issues 的 suggestion 必须有；给了 answer 时 original 必须逐字出现；
/// rule/key 缺失时用闭集启发式补全并计入 `inferred`（回填旧记录的同一套逻辑）。
WritingFeedbackParse? parseWritingFeedbackDetailed(
  String raw, [
  WritingFeedbackParseOptions options = const WritingFeedbackParseOptions(),
]) {
  final text = _stripFence(raw);
  if (text.isEmpty) return null;
  Object? obj;
  try {
    obj = jsonDecode(text);
  } on FormatException {
    return null;
  }
  if (obj is! Map) return null;

  final dropped = WritingFeedbackDropped();
  final scores = <WritingScore>[];
  final scoresRaw = obj['scores'];
  if (scoresRaw is List) {
    for (final s in scoresRaw) {
      if (s is! Map) continue;
      final dimension = _asString(s['dimension']);
      if (dimension.isEmpty) continue;
      final comment = _asString(s['comment']);
      scores.add(WritingScore(
        dimension: dimension,
        score: _asInt(s['score']),
        max: _asInt(s['max']),
        comment: comment.isEmpty ? null : comment,
      ));
    }
  }

  final issues = <WritingIssue>[];
  final seenIssues = <String>{};
  final issuesRaw = obj['issues'];
  if (issuesRaw is List) {
    for (final s in issuesRaw) {
      if (s is! Map) {
        dropped.issues++;
        continue;
      }
      final original = _asString(s['original']);
      final suggestion = _asString(s['suggestion']);
      final reason = _asString(s['reason']);
      if (suggestion.isEmpty) {
        dropped.issues++;
        dropped.reasons.add('issue 缺 suggestion');
        continue;
      }
      final answer = options.answer;
      if (answer != null && original.isNotEmpty && !answer.contains(original)) {
        dropped.issues++;
        dropped.reasons.add(
            'original 不在学生原文里：${original.length > 40 ? original.substring(0, 40) : original}');
        continue;
      }
      final fallback = classifyLegacyIssue(LegacyIssueLike(
        original: original,
        suggestion: suggestion,
        reason: reason,
      ));
      WritingRule rule;
      final ruleRaw = s['rule'];
      if (isWritingRule(ruleRaw)) {
        rule = WritingRule.byId(ruleRaw)!;
      } else {
        rule = fallback.rule;
        dropped.inferred++;
      }
      String key;
      if (isWritingIssueKey(s['key'])) {
        key = s['key'] as String;
      } else {
        key = writingKeyFor(rule, original, suggestion);
        dropped.inferred++;
      }
      final severityRaw = _asString(s['severity']);
      final severity = severityRaw == 'improvement' || severityRaw == 'must-fix'
          ? severityRaw
          : fallback.severity;
      final dedupe = '$key|$original|$suggestion';
      if (!seenIssues.add(dedupe)) {
        dropped.issues++;
        continue;
      }
      issues.add(WritingIssue(
        original: original,
        suggestion: suggestion,
        reason: reason.isEmpty ? null : reason,
        rule: rule,
        key: key,
        severity: severity,
      ));
      if (issues.length >= 20) break;
    }
  }

  final issueKeys = <String>{for (final i in issues) i.key};
  final recommendations = <WritingRecommendation>[];
  final seenRecommendations = <String>{};
  final recsRaw = obj['recommendations'];
  if (recsRaw is List) {
    for (final r in recsRaw) {
      final rec = _parseRecommendation(
          r, issueKeys, options.availablePointIds, dropped);
      if (rec == null) continue;
      final dedupe = '${rec.kind.name}|${rec.point.toLowerCase()}';
      if (!seenRecommendations.add(dedupe)) {
        dropped.recommendations++;
        continue;
      }
      recommendations.add(rec);
      if (recommendations.length >= 5) break;
    }
  }

  if (scores.isEmpty && issues.isEmpty) return null;
  final totalRaw = _asInt(obj['total']);
  final maxRaw = _asInt(obj['max']);
  final total = totalRaw != 0
      ? totalRaw
      : scores.fold<int>(0, (a, s) => a + s.score);
  final max = maxRaw != 0 ? maxRaw : scores.fold<int>(0, (a, s) => a + s.max);
  dropped.reasons = _normalizeReasonList(dropped.reasons);
  final polished = _asString(obj['polished']);
  final summary = _asString(obj['summary']);
  return WritingFeedbackParse(
    feedback: WritingFeedback(
      version: 2,
      scores: scores,
      total: total,
      max: max,
      issues: issues,
      recommendations: recommendations,
      polished: polished.isEmpty ? null : polished,
      summary: summary.isEmpty ? null : summary,
    ),
    dropped: dropped,
  );
}

/// 兼容旧调用：只要结果，不要丢弃计数。
WritingFeedback? parseWritingFeedback(
  String raw, [
  WritingFeedbackParseOptions options = const WritingFeedbackParseOptions(),
]) =>
    parseWritingFeedbackDetailed(raw, options)?.feedback;
