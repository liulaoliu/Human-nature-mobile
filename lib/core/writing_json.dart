/// 仿写 / 批改的**反序列化层**：把存库或备份里的 JSON 还原成强类型对象。
///
/// 为什么不和 `writing.dart` 放一起：那是「提示词 + 解析 AI 输出」，这是
/// 「读回已经审过的记录」，两件事的校验口径**故意不同** ——
///   - 解析 AI 输出：严格，`original` 必须逐字出现在作答里，不合格就丢；
///   - 读回记录：宽松，落盘的已经是审过的，重读再丢一遍等于把历史吃掉。
/// 分开写才不会有人顺手把两边合并成一份「看起来更 DRY」的守卫。
///
/// 对应 Web 版 `src/core/writing.ts` 里 `WritingRecord` 的读取侧（Web 版
/// 直接把 JSON 当强类型用，所以那边没有这一层；Dart 侧必须显式还原）。
library;

// 只依赖类型定义，不依赖 `writing.dart` 伞文件：那会形成
// writing.dart -> writing_json.dart -> writing.dart 的文件级环（re-export 伞
// 天然如此，但拆开更干净，也让这张图能看清真实的依赖方向）。
import 'writing_error_rules.dart' show WritingRule, isWritingRule;
import 'writing_types.dart';

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

WritingRule? _ruleById(Object? raw) =>
    isWritingRule(raw) ? WritingRule.byId(raw) : null;

/// 从存库的 JSON 还原一份仿写任务（`ImitationTask.toJson` 的反方向）。
///
/// 缺 `task` 视为没有任务（拷打造句 / 旧记录）；解析失败一律返回 null，
/// 不抛错 —— 一条坏历史不该让整页历史读不出来。
ImitationTask? imitationTaskFromJson(Object? raw) {
  if (raw is! Map) return null;
  final task = _asString(raw['task']);
  if (task.isEmpty) return null;
  final rubric = <RubricItem>[];
  final rubricRaw = raw['rubric'];
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
  final structure = _asString(raw['structure']);
  final focus = _asString(raw['focus']);
  final round = _asInt(raw['round']);
  return ImitationTask(
    task: task,
    model: _asString(raw['model']),
    structure: structure.isEmpty ? null : structure,
    mustUse: _asStringArray(raw['mustUse']),
    rubric: rubric,
    focus: focus.isEmpty ? null : focus,
    round: round > 0 ? round : null,
  );
}

/// 从存库的 JSON 还原一份批改结果（`WritingFeedback.toJson` 的反方向）。
///
/// 只有 rule 认不出（闭集改过）或 key 为空时才丢那一条 issue —— 没有 rule
/// 就归不了因，留着反而让趋势统计出错；分数、建议、polished 一律保留。
WritingFeedback writingFeedbackFromJson(Object? raw) {
  if (raw is! Map) return const WritingFeedback();

  final scores = <WritingScore>[];
  final scoresRaw = raw['scores'];
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
  final issuesRaw = raw['issues'];
  if (issuesRaw is List) {
    for (final s in issuesRaw) {
      if (s is! Map) continue;
      final suggestion = _asString(s['suggestion']);
      final rule = _ruleById(s['rule']);
      final key = _asString(s['key']);
      if (suggestion.isEmpty || rule == null || key.isEmpty) continue;
      final original = _asString(s['original']);
      final reason = _asString(s['reason']);
      final severityRaw = _asString(s['severity']);
      issues.add(WritingIssue(
        original: original,
        suggestion: suggestion,
        reason: reason.isEmpty ? null : reason,
        rule: rule,
        key: key,
        severity: severityRaw == 'improvement' ? 'improvement' : 'must-fix',
      ));
    }
  }

  final recommendations = <WritingRecommendation>[];
  final recsRaw = raw['recommendations'];
  if (recsRaw is List) {
    for (final r in recsRaw) {
      if (r is! Map) continue;
      final kind = _recKindByName(r['kind']);
      final point = _asString(r['point']);
      final why = _asString(r['why']);
      if (kind == null || point.isEmpty || why.isEmpty) continue;
      final zh = _asString(r['zh']);
      final example = _asString(r['example']);
      final issueKey = _asString(r['issueKey']);
      final pointId = _asString(r['pointId']);
      final priorityRaw = _asInt(r['priority']);
      recommendations.add(WritingRecommendation(
        kind: kind,
        point: point,
        zh: zh.isEmpty ? null : zh,
        why: why,
        example: example.isEmpty ? null : example,
        priority: priorityRaw == 1 ? 1 : (priorityRaw == 3 ? 3 : 2),
        from: _recFromByName(r['from']),
        issueKey: issueKey.isEmpty ? null : issueKey,
        pointId: pointId.isEmpty ? null : pointId,
      ));
    }
  }

  final polished = _asString(raw['polished']);
  final summary = _asString(raw['summary']);
  final version = _asInt(raw['version']);
  return WritingFeedback(
    version: version > 0 ? version : 1,
    scores: scores,
    total: _asInt(raw['total']),
    max: _asInt(raw['max']),
    issues: issues,
    recommendations: recommendations,
    polished: polished.isEmpty ? null : polished,
    summary: summary.isEmpty ? null : summary,
  );
}
