/// 奶牛工棚的派生视图：目标块进度、统计、趋势、历史筛选与分组。
///
/// 尝试记录仍写在 `writing_records`（`source = 'production'`），
/// 这里的进度、统计、趋势全部**从记录现算**，不另存一份。
/// 为什么不另存：attempts 是 append-only 的事实，进度只是它的函数；
/// 单写一份会多一个需要迁移、对账、备份的状态源。
///
/// 对应 Web 版 `src/core/productionHistory.ts`（540 行）。
library;

import 'activity/activity.dart' show dayKeyLocal;
import 'production.dart';
import 'production_task.dart';
import 'writing.dart';

/// 一个目标块的练习进度（从记录现算出来的形状）。
class ProductionProgress {
  const ProductionProgress({
    required this.key,
    required this.kind,
    required this.text,
    required this.meaning,
    required this.attempts,
    required this.hits,
    required this.misses,
    required this.streak,
    required this.lastAt,
    required this.dueAt,
    this.itemId,
    this.lastArticleId,
    this.lastMode,
    this.updatedAt,
  });

  final String key;
  final String? itemId;
  final ProductionTargetKind kind;
  final String text;
  final String meaning;
  final int attempts;
  final int hits;
  final int misses;
  final int streak;
  final String lastAt;
  final String dueAt;
  final String? lastArticleId;
  final ProductionMode? lastMode;
  final String? updatedAt;

  ProductionProgress copyWith({
    int? attempts,
    int? hits,
    int? misses,
    int? streak,
    String? lastAt,
    String? dueAt,
    String? lastArticleId,
    ProductionMode? lastMode,
    String? updatedAt,
  }) =>
      ProductionProgress(
        key: key,
        kind: kind,
        text: text,
        meaning: meaning,
        attempts: attempts ?? this.attempts,
        hits: hits ?? this.hits,
        misses: misses ?? this.misses,
        streak: streak ?? this.streak,
        lastAt: lastAt ?? this.lastAt,
        dueAt: dueAt ?? this.dueAt,
        itemId: itemId,
        lastArticleId: lastArticleId ?? this.lastArticleId,
        lastMode: lastMode ?? this.lastMode,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  /// 排序 / 去重时用的「最近一次动过」。
  String get stamp => updatedAt ?? lastAt;

  @override
  String toString() => 'ProductionProgress($key, $hits/$attempts)';
}

/// 进度表最多留多少行。
const int productionProgressCap = 5000;

/// 复习间隔（命中一次升一档；漏一次立刻到期）。
const List<int> _dueDays = <int>[1, 3, 7, 14, 30, 60, 120];

String _isoOr(Object? value, String fallback) {
  if (value is String) {
    final t = DateTime.tryParse(value);
    if (t != null) return value;
  }
  return fallback;
}

int _nonNeg(Object? v) {
  if (v is num) {
    if (!v.isFinite || v <= 0) return 0;
    return v.floor();
  }
  return 0;
}

ProductionMode? _modeByName(Object? raw) {
  if (raw is! String) return null;
  for (final m in ProductionMode.values) {
    if (m.name == raw) return m;
  }
  return null;
}

ProductionTargetKind? _kindByName(Object? raw) {
  if (raw is! String) return null;
  for (final k in ProductionTargetKind.values) {
    if (k.name == raw) return k;
  }
  return null;
}

String _str(Object? v) => v is String ? v.trim() : '';

/// 外部输入（数据库 / 备份）→ 目标块进度；坏行丢弃。
List<ProductionProgress> normalizeProductionProgress(Object? raw) {
  if (raw is! List) return const <ProductionProgress>[];
  final now = DateTime.now().toUtc().toIso8601String();
  final byKey = <String, ProductionProgress>{};
  for (final item in raw) {
    if (item is! Map) continue;
    final kind = _kindByName(item['kind']);
    if (kind == null) continue;
    final text = _str(item['text']);
    if (text.isEmpty) continue;
    final keyRaw = _str(item['key']);
    final key = keyRaw.isNotEmpty ? keyRaw : productionTargetKey(kind, text);
    final row = ProductionProgress(
      key: key,
      kind: kind,
      text: text,
      meaning: _str(item['meaning']),
      attempts: _nonNeg(item['attempts']),
      hits: _nonNeg(item['hits']),
      misses: _nonNeg(item['misses']),
      streak: _nonNeg(item['streak']),
      lastAt: _isoOr(item['lastAt'], now),
      dueAt: _isoOr(item['dueAt'], now),
      itemId: _str(item['itemId']).isEmpty ? null : _str(item['itemId']),
      lastArticleId:
          _str(item['lastArticleId']).isEmpty ? null : _str(item['lastArticleId']),
      lastMode: _modeByName(item['lastMode']),
      updatedAt: _isoOr(item['updatedAt'], '') == ''
          ? null
          : item['updatedAt'] as String,
    );
    final old = byKey[key];
    if (old == null || row.stamp.compareTo(old.stamp) >= 0) byKey[key] = row;
  }
  return _sortedCapped(byKey.values);
}

List<ProductionProgress> _sortedCapped(Iterable<ProductionProgress> rows) {
  final list = rows.toList()
    ..sort((a, b) => b.stamp.compareTo(a.stamp));
  return list.length <= productionProgressCap
      ? list
      : list.sublist(0, productionProgressCap);
}

/// 合并备份：同一目标块取更新的一行；不累加，避免同一批 attempts 被算两次。
List<ProductionProgress> mergeProductionProgress(
  List<ProductionProgress> current,
  List<ProductionProgress> incoming,
) {
  final map = <String, ProductionProgress>{
    for (final p in current) p.key: p,
  };
  for (final row in incoming) {
    final old = map[row.key];
    if (old == null || row.stamp.compareTo(old.stamp) >= 0) map[row.key] = row;
  }
  return _sortedCapped(map.values);
}

/// 工棚的累计统计。
class ProductionStats {
  const ProductionStats({
    required this.attempts,
    required this.sessions,
    required this.rewrites,
    required this.modes,
    required this.targetAttempts,
    required this.targetHits,
    required this.targetMisses,
    required this.hitRate,
    required this.avgScore,
  });

  final int attempts;
  final int sessions;
  final int rewrites;
  final Map<String, int> modes;
  final int targetAttempts;
  final int targetHits;
  final int targetMisses;
  final double hitRate;
  final double avgScore;
}

/// 历史筛选条件。
class ProductionHistoryFilter {
  const ProductionHistoryFilter({this.articleId, this.mode, this.topic});

  final String? articleId;

  /// `null` 或 [ProductionMode.full] 等；界面传 `null` 表示「全部」。
  final ProductionMode? mode;
  final String? topic;
}

/// 只留下产出训练的记录（普通仿写 / 金句课都在同一个历史里）。
List<WritingRecord> productionRecords(List<WritingRecord> history) =>
    history.where((r) => r.source == WritingSource.production).toList();

/// 一条记录里的产出任务；不是产出训练就返回 null。
ProductionTask? productionTaskOf(WritingRecord record) {
  final task = record.task;
  if (task is ProductionTask) return task;
  return null;
}

/// 旧产出稿没有 sessionId 时补的分组信息。
class LegacyProductionGroup {
  const LegacyProductionGroup({
    required this.sessionId,
    required this.articleId,
    required this.day,
    required this.mode,
    required this.topic,
    required this.count,
    required this.firstAt,
    required this.lastAt,
  });

  final String sessionId;
  final String articleId;
  final String day;
  final ProductionMode mode;
  final String topic;
  final int count;
  final String firstAt;
  final String lastAt;
}

/// 补 sessionId 的结果（记录 + 改了条数 + 分组摘要）。
class LegacyProductionMigration {
  const LegacyProductionMigration({
    required this.records,
    required this.changed,
    required this.groups,
  });

  final List<WritingRecord> records;
  final int changed;
  final List<LegacyProductionGroup> groups;
}

/// 旧产出稿没有 sessionId：按「文章 + 学习日 + 模式 + 主题」补一个确定性 id，
/// 让两稿 / 多题至少能归到同一组。迁移前由调用方备份原历史。
LegacyProductionMigration assignLegacyProductionSessionIds(
  List<WritingRecord> history,
) {
  var changed = 0;
  final groups = <String, LegacyProductionGroup>{};
  final records = <WritingRecord>[];
  for (final rec in history) {
    if (rec.source != WritingSource.production) {
      records.add(rec);
      continue;
    }
    final task = productionTaskOf(rec);
    if (task == null || (task.sessionId ?? '').isNotEmpty) {
      records.add(rec);
      continue;
    }
    final day = rec.at.length >= 10 ? rec.at.substring(0, 10) : rec.at;
    final sessionId = 'legacy:${rec.articleId}|$day|${task.mode.name}|${task.topic}';
    changed++;
    final prev = groups[sessionId];
    groups[sessionId] = LegacyProductionGroup(
      sessionId: sessionId,
      articleId: rec.articleId,
      day: day,
      mode: task.mode,
      topic: task.topic,
      count: (prev?.count ?? 0) + 1,
      firstAt: prev != null && prev.firstAt.compareTo(rec.at) < 0 ? prev.firstAt : rec.at,
      lastAt: prev != null && prev.lastAt.compareTo(rec.at) > 0 ? prev.lastAt : rec.at,
    );
    records.add(rec.copyWith(task: () => task.copyWith(sessionId: () => sessionId)));
  }
  return LegacyProductionMigration(
    records: records,
    changed: changed,
    groups: groups.values.toList(),
  );
}

/// 造一条「跳过」的产出记录：保留已写草稿与题面，但不伪造 AI 分数。
WritingRecord makeSkippedProductionRecord({
  required ProductionTask task,
  required String text,
  required String at,
  required String articleId,
  required String articleTitle,
  required int round,
}) =>
    WritingRecord(
      at: at,
      articleId: articleId,
      articleTitle: articleTitle,
      model: task.model,
      text: text,
      feedback: skippedProductionFeedback(),
      task: task.copyWith(round: () => round, skipped: () => true),
      source: WritingSource.production,
    );

/// 记录里这次判分的目标块；老记录没有 hits 时返回空，不猜。
List<ProductionTargetHit> productionRecordHits(WritingRecord record) =>
    productionHits(record.task);

String _addDays(String iso, int days) {
  final t = DateTime.tryParse(iso);
  if (t == null) return iso;
  return t.add(Duration(days: days)).toUtc().toIso8601String();
}

void _applyRecord(Map<String, ProductionProgress> map, WritingRecord rec) {
  final task = productionTaskOf(rec);
  if (task == null) return;
  final hits = productionRecordHits(rec);
  for (final hit in hits) {
    final key = productionTargetKey(hit.kind, hit.text);
    final prev = map[key];
    final target = task.targets
        .where((t) => productionTargetKey(t.kind, t.text) == key)
        .firstOrNull;
    final base = prev ??
        ProductionProgress(
          key: key,
          kind: hit.kind,
          text: hit.text,
          meaning: hit.meaning,
          attempts: 0,
          hits: 0,
          misses: 0,
          streak: 0,
          lastAt: rec.at,
          dueAt: rec.at,
          itemId: (target?.itemId ?? '').isEmpty ? null : target!.itemId,
        );
    final streak = hit.used ? base.streak + 1 : 0;
    final idx = streak - 1 < 0 ? 0 : streak - 1;
    map[key] = base.copyWith(
      attempts: base.attempts + 1,
      hits: base.hits + (hit.used ? 1 : 0),
      misses: base.misses + (hit.used ? 0 : 1),
      streak: streak,
      lastAt: rec.at,
      dueAt: hit.used ? _addDays(rec.at, _dueDays[idx >= _dueDays.length ? _dueDays.length - 1 : idx]) : rec.at,
      lastArticleId: rec.articleId,
      lastMode: task.mode,
      updatedAt: rec.at,
    );
  }
}

/// 从全部记录现算目标块进度。
List<ProductionProgress> deriveProductionProgress(List<WritingRecord> records) {
  final map = <String, ProductionProgress>{};
  for (final rec in records) {
    _applyRecord(map, rec);
  }
  return map.values.toList();
}

/// 增量：把新增 attempts 叠到已有进度上（调用方负责只传没算过的记录）。
List<ProductionProgress> applyProductionProgressRecords(
  List<ProductionProgress> progress,
  List<WritingRecord> records,
) {
  final map = <String, ProductionProgress>{
    for (final p in progress) p.key: p,
  };
  for (final rec in records) {
    _applyRecord(map, rec);
  }
  return map.values.toList();
}

/// 按键索引进度。
Map<String, ProductionProgress> progressByKey(List<ProductionProgress> progress) =>
    <String, ProductionProgress>{for (final p in progress) p.key: p};

/// 到期了没有。
bool isProgressDue(ProductionProgress progress, String nowIso) {
  final due = DateTime.tryParse(progress.dueAt);
  final now = DateTime.tryParse(nowIso);
  if (due == null || now == null) return true;
  return !due.isAfter(now);
}

/// 薄弱：漏过，或命中率低于 70%。
bool isProgressWeak(ProductionProgress progress) =>
    progress.misses > 0 ||
    progress.hits / (progress.attempts < 1 ? 1 : progress.attempts) < 0.7;

/// 最近动过没有（默认 7 天）。
bool isProgressRecent(ProductionProgress progress, String nowIso, {int days = 7}) {
  final last = DateTime.tryParse(progress.lastAt);
  final now = DateTime.tryParse(nowIso);
  if (last == null || now == null) return false;
  return now.difference(last).inMilliseconds <= days * 86400000;
}

/// 顶栏 / 今日计划用的目标块提醒数。
class ProductionReviewCounts {
  const ProductionReviewCounts({
    required this.due,
    required this.weak,
    required this.newTargets,
  });

  final int due;
  final int weak;

  /// 全库候选里还没练过的目标块；不传候选时保持 0。
  final int newTargets;
}

ProductionReviewCounts productionReviewCounts(
  List<ProductionProgress> progress,
  String nowIso, {
  List<ProductionTarget> candidates = const <ProductionTarget>[],
}) {
  var due = 0;
  var weak = 0;
  for (final p in progress) {
    if (isProgressDue(p, nowIso)) due++;
    if (isProgressWeak(p)) weak++;
  }
  final keys = <String>{for (final p in progress) p.key};
  final newTargets = candidates
      .where((t) => !keys.contains(productionTargetKey(t.kind, t.text)))
      .length;
  return ProductionReviewCounts(due: due, weak: weak, newTargets: newTargets);
}

/// 工棚的累计统计（跳过稿不算真实产出，也不拉低平均分）。
ProductionStats productionStats(List<WritingRecord> records) {
  final production = productionRecords(records);
  final modes = <String, int>{};
  final sessions = <String>{};
  var attempts = 0;
  var rewrites = 0;
  var score = 0;
  var scored = 0;
  var targetAttempts = 0;
  var targetHits = 0;
  for (final rec in production) {
    final task = productionTaskOf(rec);
    if (task?.skipped == true) continue;
    attempts++;
    final mode = task?.mode.name ?? 'unknown';
    modes[mode] = (modes[mode] ?? 0) + 1;
    final sid = task?.sessionId ?? '';
    if (sid.isNotEmpty) sessions.add(sid);
    if ((task?.round ?? 1) > 1) rewrites++;
    if (rec.feedback.max > 0) {
      score += rec.feedback.total;
      scored++;
    }
    final hits = productionRecordHits(rec);
    targetAttempts += hits.length;
    targetHits += hits.where((h) => h.used).length;
  }
  return ProductionStats(
    attempts: attempts,
    sessions: sessions.length,
    rewrites: rewrites,
    modes: modes,
    targetAttempts: targetAttempts,
    targetHits: targetHits,
    targetMisses: targetAttempts - targetHits,
    hitRate: targetAttempts == 0 ? 0 : targetHits / targetAttempts,
    avgScore: scored == 0 ? 0 : score / scored,
  );
}

/// 最近 N 天的目标块命中率 + 重写平均提分。
class ProductionTrend {
  const ProductionTrend({
    required this.recentAttempts,
    required this.recentHits,
    required this.recentHitRate,
    required this.rewriteGain,
  });

  final int recentAttempts;
  final int recentHits;
  final double recentHitRate;

  /// 第 2 稿相对第 1 稿的平均分差（只算成组的两稿）。
  final double rewriteGain;
}

ProductionTrend productionTrend(
  List<WritingRecord> records,
  String nowIso, {
  int days = 7,
}) {
  final now = DateTime.tryParse(nowIso);
  var recentAttempts = 0;
  var recentHits = 0;
  for (final rec in productionRecords(records)) {
    final at = DateTime.tryParse(rec.at);
    if (now == null || at == null) continue;
    if (now.difference(at).inMilliseconds > days * 86400000) continue;
    final hits = productionRecordHits(rec);
    recentAttempts += hits.length;
    recentHits += hits.where((h) => h.used).length;
  }
  var gainSum = 0;
  var gainCount = 0;
  for (final group in groupProductionAttempts(records)) {
    WritingRecord? first;
    WritingRecord? second;
    for (final r in group.records) {
      final round = productionTaskOf(r)?.round ?? 1;
      if (round == 1 && first == null) first = r;
      if (round == 2 && second == null) second = r;
    }
    if (first != null && second != null) {
      gainSum += second.feedback.total - first.feedback.total;
      gainCount++;
    }
  }
  return ProductionTrend(
    recentAttempts: recentAttempts,
    recentHits: recentHits,
    recentHitRate: recentAttempts == 0 ? 0 : recentHits / recentAttempts,
    rewriteGain: gainCount == 0 ? 0 : gainSum / gainCount,
  );
}

/// 批改里的高频错因（按 rule + key 聚合）。
class ProductionErrorStat {
  const ProductionErrorStat({
    required this.key,
    required this.rule,
    required this.count,
    required this.sample,
  });

  final String key;
  final String rule;
  final int count;
  final String sample;
}

List<ProductionErrorStat> productionTopErrors(
  List<WritingRecord> records, {
  int limit = 5,
}) {
  final map = <String, ProductionErrorStat>{};
  for (final rec in productionRecords(records)) {
    for (final issue in rec.feedback.issues) {
      final key = '${issue.rule.id}|${issue.key}';
      final prev = map[key];
      if (prev != null) {
        map[key] = ProductionErrorStat(
          key: key,
          rule: prev.rule,
          count: prev.count + 1,
          sample: prev.sample,
        );
      } else {
        map[key] = ProductionErrorStat(
          key: key,
          rule: issue.rule.id,
          count: 1,
          sample: issue.original.isNotEmpty ? issue.original : issue.suggestion,
        );
      }
    }
  }
  final list = map.values.toList()
    ..sort((a, b) => b.count.compareTo(a.count));
  return list.length <= limit ? list : list.sublist(0, limit);
}

/// 按文章 / 吃法 / 关键词筛历史。
List<WritingRecord> filterProductionHistory(
  List<WritingRecord> records, [
  ProductionHistoryFilter filter = const ProductionHistoryFilter(),
]) {
  final topic = (filter.topic ?? '').trim().toLowerCase();
  return productionRecords(records).where((rec) {
    final task = productionTaskOf(rec);
    if ((filter.articleId ?? '').isNotEmpty && rec.articleId != filter.articleId) {
      return false;
    }
    if (filter.mode != null && task?.mode != filter.mode) return false;
    if (topic.isNotEmpty) {
      final hay = '${task?.topic ?? ''} ${task?.task ?? ''}'.toLowerCase();
      if (!hay.contains(topic)) return false;
    }
    return true;
  }).toList();
}

/// 一组并排看的稿子（同一次训练里的第 1 / 2 稿）。
class ProductionAttemptGroup {
  const ProductionAttemptGroup({
    required this.key,
    required this.promptId,
    required this.title,
    required this.records,
    this.sessionId,
    this.legacy,
  });

  final String key;
  final String? sessionId;
  final String promptId;
  final String title;

  /// 旧记录没有 sessionId，只做了日期兜底分组。
  final bool? legacy;
  final List<WritingRecord> records;
}

/// 按 session + prompt 分组，方便把第 1 稿 / 第 2 稿并排看。
List<ProductionAttemptGroup> groupProductionAttempts(List<WritingRecord> records) {
  final groups = <String, List<WritingRecord>>{};
  final metas = <String, ({String? sessionId, String promptId, String title})>{};
  for (final rec in productionRecords(records)) {
    final task = productionTaskOf(rec);
    if (task == null) continue;
    // 旧记录没有 sessionId：按「同一天 + 文章 + 模式 + 主题」兜底，
    // 至少让同一次两稿还能并排；不同天的会自然分开。
    final day = rec.at.length >= 10 ? rec.at.substring(0, 10) : rec.at;
    final sid = task.sessionId ?? '';
    final legacy = 'legacy:$day|${rec.articleId}|${task.mode.name}|${task.topic}';
    final key = '${sid.isNotEmpty ? sid : legacy}|${task.promptId}';
    (groups[key] ??= <WritingRecord>[]).add(rec);
    metas.putIfAbsent(
      key,
      () => (
        sessionId: sid.isNotEmpty ? sid : null,
        promptId: task.promptId,
        title: task.task.isNotEmpty ? task.task : task.topic,
      ),
    );
  }
  final out = <ProductionAttemptGroup>[];
  for (final entry in groups.entries) {
    final meta = metas[entry.key]!;
    final rows = entry.value
      ..sort((a, b) {
        final ar = productionTaskOf(a)?.round ?? 1;
        final br = productionTaskOf(b)?.round ?? 1;
        return ar != br ? ar.compareTo(br) : a.at.compareTo(b.at);
      });
    out.add(ProductionAttemptGroup(
      key: entry.key,
      sessionId: meta.sessionId,
      promptId: meta.promptId,
      title: meta.title,
      legacy: meta.sessionId == null ? true : null,
      records: rows,
    ));
  }
  out.sort((a, b) {
    final at = a.records.isEmpty ? '' : a.records.last.at;
    final bt = b.records.isEmpty ? '' : b.records.last.at;
    return bt.compareTo(at);
  });
  return out;
}

String _mdEscape(String s) =>
    s.replaceAll('|', r'\|').replaceAll(RegExp(r'\n+'), ' ');

/// 工棚历史导出：按次列出作答、分数、问题、目标块命中，便于归档。
String productionHistoryMarkdown(List<WritingRecord> records) {
  final lines = <String>['# 奶牛工棚产出记录', ''];
  for (final rec in productionRecords(records)) {
    final task = productionTaskOf(rec);
    final label = task?.mode.name ?? '产出';
    final hits = productionRecordHits(rec);
    final at = DateTime.tryParse(rec.at);
    final day = at == null ? rec.at : dayKeyLocal(at.toLocal());
    lines.add('## $day · $label · ${rec.articleTitle ?? rec.articleId}');
    lines.add('');
    if ((task?.topic ?? '').isNotEmpty) lines.add('- 主题：${task!.topic}');
    if ((task?.task ?? '').isNotEmpty) lines.add('- 题目：${task!.task}');
    if (task?.skipped == true) {
      lines.add('- 状态：跳过（未提交，无 AI 批改）');
    } else {
      lines.add('- 分数：${rec.feedback.total}/${rec.feedback.max}');
    }
    if ((task?.reference ?? '').isNotEmpty) lines.add('- 参考译文：${task!.reference}');
    lines.add('');
    lines.add('**作答**');
    lines.add('');
    lines.add(rec.text.isEmpty ? '（空）' : rec.text);
    lines.add('');
    if (hits.isNotEmpty) {
      lines.add('**目标块**');
      lines.add('');
      for (final hit in hits) {
        final meaning = hit.meaning.isEmpty ? '' : '（${hit.meaning}）';
        lines.add('- ${hit.used ? '✅' : '❌'} ${hit.text}$meaning');
      }
      lines.add('');
    }
    if (rec.feedback.issues.isNotEmpty) {
      lines.add('**问题**');
      lines.add('');
      for (final issue in rec.feedback.issues) {
        final reason =
            (issue.reason ?? '').isEmpty ? '' : '（${_mdEscape(issue.reason!)}）';
        lines.add(
          '- ${_mdEscape(issue.original)} → ${_mdEscape(issue.suggestion)}$reason',
        );
      }
      lines.add('');
    }
    final summary = rec.feedback.summary ?? '';
    if (summary.isNotEmpty) {
      lines.add('**总评**：$summary');
      lines.add('');
    }
  }
  return lines.join('\n');
}

/// 历史列表里一条记录的身份（不依赖 DB 自增 id）。
String productionRecordKey(WritingRecord record) => writingRecordKey(
      at: record.at,
      articleId: record.articleId,
      text: record.text,
      sentenceId: record.sentenceId,
      examId: record.examId,
      task: record.task,
    );
