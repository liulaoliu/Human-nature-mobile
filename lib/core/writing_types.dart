/// 仿写训练的**数据结构**：任务、评分、错因、语言点建议、批改结果。
///
/// 从 `writing.dart` 拆出来的原因：这个文件原先 774 行、35 个顶层符号、
/// 被 13 处 import（全库扇入第一）。类型声明和「提示词怎么拼 / AI 输出怎么解」
/// 是三件事，混在一起谁都不好单独读、单独测。
///
/// 这里只放类型和纯 getter，不 import 任何上层（models 之外的依赖都还在 core 内）。
/// `writing.dart` 仍是公共入口：它 re-export 本文件，现有 import 一行都不用改。
library;

import 'writing_error_rules.dart' show WritingIssueType, WritingRule;

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
