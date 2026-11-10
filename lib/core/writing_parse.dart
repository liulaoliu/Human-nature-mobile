/// 仿写训练的**解析层**：把 AI 输出的 JSON 还原成强类型对象。
///
/// 从 `writing.dart` 拆出来：这里放着「读 AI 输出」的严格守卫 ——
/// 出题任务缺 task/model 直接返回 null；批改结果缺 rule/key 时用闭集启发式补全
/// 并计入 `inferred`，original 不在作答里就丢掉那条 issue。
/// 与 `writing_json.dart`（读回已经审过的历史记录，口径宽松）**故意不是同一套**。
///
/// 五个私有助手 `_fence` / `_stripFence` / `_asString` / `_asStringArray` / `_asInt`
/// 只被本文件的 `parseImitationTask` 与 `parseWritingFeedbackDetailed` 使用，
/// 所以原样搬到这里，不需要跨文件共享。
library;

import 'dart:convert';

import 'writing_error_rules.dart';
import 'writing_types.dart';

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
