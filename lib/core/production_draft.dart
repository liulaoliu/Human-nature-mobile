/// 奶牛工棚的**会话草稿**（当前这一组没提交的作答）。
///
/// 这是本机偏好 / 会话状态，不进学习记录；真正的提交稿在写作历史里。
/// 刷新 / 关页面后能恢复当前题号、题干、草稿、批改和命中，避免长段落白写。
///
/// 对应 Web 版 `src/core/productionDraft.ts`（194 行）。
///
/// 注：`feedback` / `previousFeedback` 先按**原始 JSON** 存（守卫只看版本号与必要字段），
/// 等 `writing.dart` 的强类型批改结果移植过来再换成 `WritingFeedback`。
library;

import 'production.dart';

/// 存草稿用的键（与 Web 版一致）。
const String productionDraftKeyName = 'reader:productionDraft';

const int _draftVersion = 1;
const int _maxPrompts = 60;

/// 3 篇文章 × 3 种模式：三种吃法各留一组，暂停着酸奶也能开全脂。
const int productionDraftCap = 9;

/// 草稿按「文章 + 模式」各存一份。
///
/// 以前只按文章存，风味酸奶暂停着去开全脂，新的一组会把暂停的那组顶掉；
/// 现在两边的题号 / 作答 / 批改互不覆盖。
String productionDraftKey(String articleId, ProductionMode mode) =>
    '${articleId.isEmpty ? 'manual' : articleId}::${mode.name}';

/// 一组会话草稿。
class ProductionDraft {
  const ProductionDraft({
    this.version = _draftVersion,
    this.sessionId = '',
    this.articleId = 'manual',
    this.at = '',
    this.mode = ProductionMode.full,
    this.sessionTopic = '',
    this.prompts = const <ProductionPrompt>[],
    this.index = 0,
    this.answer = '',
    this.feedback,
    this.previousFeedback,
    this.hits = const <ProductionTargetHit>[],
    this.round = 1,
    this.notice = '',
  });

  final int version;
  final String sessionId;
  final String articleId;

  /// 最后一次改动时间（ISO 串）；排序与「取较新」都按它。
  final String at;
  final ProductionMode mode;
  final String sessionTopic;
  final List<ProductionPrompt> prompts;
  final int index;
  final String answer;

  /// 批改结果（原始 JSON；强类型版等 `writing.dart`）。
  final Map<String, Object?>? feedback;
  final Map<String, Object?>? previousFeedback;
  final List<ProductionTargetHit> hits;
  final int round;
  final String notice;

  ProductionDraft copyWith({
    String? sessionId,
    String? articleId,
    String? at,
    ProductionMode? mode,
    String? sessionTopic,
    List<ProductionPrompt>? prompts,
    int? index,
    String? answer,
    Map<String, Object?>? Function()? feedback,
    Map<String, Object?>? Function()? previousFeedback,
    List<ProductionTargetHit>? hits,
    int? round,
    String? notice,
  }) =>
      ProductionDraft(
        version: version,
        sessionId: sessionId ?? this.sessionId,
        articleId: articleId ?? this.articleId,
        at: at ?? this.at,
        mode: mode ?? this.mode,
        sessionTopic: sessionTopic ?? this.sessionTopic,
        prompts: prompts ?? this.prompts,
        index: index ?? this.index,
        answer: answer ?? this.answer,
        feedback: feedback != null ? feedback() : this.feedback,
        previousFeedback:
            previousFeedback != null ? previousFeedback() : this.previousFeedback,
        hits: hits ?? this.hits,
        round: round ?? this.round,
        notice: notice ?? this.notice,
      );

  @override
  String toString() =>
      'ProductionDraft($articleId::${mode.name}, ${prompts.length} 题, #$index)';
}

bool _isObject(Object? v) => v is Map && v is! List;

String _asString(Object? v, [int max = 5000]) {
  if (v is! String) return '';
  return v.length <= max ? v : v.substring(0, max);
}

ProductionTarget? _normalizeTarget(Object? v) {
  if (!_isObject(v)) return null;
  final map = v as Map;
  final kind = _kindByName(map['kind']);
  if (kind == null) return null;
  final text = _asString(map['text'], 300).trim();
  if (text.isEmpty) return null;
  final itemId = _asString(map['itemId'], 200);
  final id = _asString(map['id'], 200);
  return ProductionTarget(
    id: id.isNotEmpty ? id : '$itemId|${kind.name}|draft',
    itemId: itemId,
    kind: kind,
    text: text,
    meaning: _asString(map['meaning'], 300),
  );
}

ProductionTargetKind? _kindByName(Object? raw) {
  for (final k in ProductionTargetKind.values) {
    if (k.name == raw) return k;
  }
  return null;
}

ProductionTargetHit? _normalizeHit(Object? v) {
  if (!_isObject(v)) return null;
  final map = v as Map;
  final kind = _kindByName(map['kind']);
  if (kind == null) return null;
  final text = _asString(map['text'], 300).trim();
  if (text.isEmpty) return null;
  final id = _asString(map['id'], 200);
  return ProductionTargetHit(
    id: id.isNotEmpty ? id : '${kind.name}:$text',
    kind: kind,
    text: text,
    meaning: _asString(map['meaning'], 300),
    used: map['used'] == true,
  );
}

ProductionPrompt? _normalizePrompt(Object? v) {
  if (!_isObject(v)) return null;
  final map = v as Map;
  final zh = _asString(map['zh'], 2000).trim();
  if (zh.isEmpty) return null;
  final targetsRaw = map['targets'];
  final targets = <ProductionTarget>[];
  if (targetsRaw is List) {
    for (final t in targetsRaw) {
      final target = _normalizeTarget(t);
      if (target != null) targets.add(target);
    }
  }
  final id = _asString(map['id'], 200);
  final model = _asString(map['model'], 1500);
  return ProductionPrompt(
    id: id.isNotEmpty ? id : 'draft-${zh.substring(0, zh.length < 8 ? zh.length : 8)}',
    zh: zh,
    goal: _asString(map['goal'], 500),
    targets: targets,
    reference:
        map['reference'] is String ? _asString(map['reference'], 5000) : null,
    answerLang: map['answerLang'] == 'zh' ? ProductionAnswerLang.zh : null,
    model: model.isEmpty ? null : model,
  );
}

/// 批改结果守卫：只认 v2（有 scores / issues 数组、total 与 max 是有限数）。
Map<String, Object?>? _normalizeFeedback(Object? v) {
  if (!_isObject(v)) return null;
  final map = v as Map;
  if (map['version'] != 2) return null;
  if (map['scores'] is! List || map['issues'] is! List) return null;
  final total = map['total'];
  final max = map['max'];
  if (total is! num || max is! num) return null;
  if (!total.isFinite || !max.isFinite) return null;
  return <String, Object?>{
    for (final e in map.entries) e.key.toString(): e.value,
  };
}

/// 草稿守卫：坏版本 / 没题 / 认不出的吃法一律返回 null。
///
/// [articleId] 给了就要求草稿里的文章对得上（换篇恢复时不串）。
ProductionDraft? normalizeProductionDraft(Object? raw, {String? articleId}) {
  if (!_isObject(raw)) return null;
  final map = raw as Map;
  if (map['version'] != _draftVersion) return null;
  final promptsRaw = map['prompts'];
  final prompts = <ProductionPrompt>[];
  if (promptsRaw is List) {
    for (final p in promptsRaw.take(_maxPrompts)) {
      final prompt = _normalizePrompt(p);
      if (prompt != null) prompts.add(prompt);
    }
  }
  if (prompts.isEmpty) return null;
  ProductionMode? mode;
  for (final m in ProductionMode.values) {
    if (m.name == map['mode']) mode = m;
  }
  if (mode == null) return null;
  final rawId = _asString(map['articleId'], 300);
  final id = rawId.isEmpty ? 'manual' : rawId;
  if (articleId != null && id != articleId) return null;

  final hits = <ProductionTargetHit>[];
  final seen = <String>{};
  final hitsRaw = map['hits'];
  if (hitsRaw is List) {
    for (final h in hitsRaw) {
      final hit = _normalizeHit(h);
      if (hit == null || seen.contains(hit.id)) continue;
      seen.add(hit.id);
      hits.add(hit);
    }
  }

  final rawIndex = map['index'];
  var index = rawIndex is num ? rawIndex.floor() : 0;
  if (index < 0) index = 0;
  if (index > prompts.length - 1) index = prompts.length - 1;

  final at = _asString(map['at'], 100);
  final roundRaw = map['round'];
  return ProductionDraft(
    sessionId: _asString(map['sessionId'], 200),
    articleId: id,
    at: at.isEmpty ? DateTime.now().toUtc().toIso8601String() : at,
    mode: mode,
    sessionTopic: _asString(map['sessionTopic'], 300),
    prompts: prompts,
    index: index,
    answer: _asString(map['answer'], 50000),
    feedback: _normalizeFeedback(map['feedback']),
    previousFeedback: _normalizeFeedback(map['previousFeedback']),
    hits: hits,
    round: roundRaw is num && roundRaw >= 2 ? 2 : 1,
    notice: _asString(map['notice'], 2000),
  );
}

/// 按时间倒序取前 [productionDraftCap] 组，键是「文章::吃法」。
Map<String, ProductionDraft> _capByRecency(Map<String, ProductionDraft> out) {
  final entries = out.entries.toList()
    ..sort((a, b) => b.value.at.compareTo(a.value.at));
  return <String, ProductionDraft>{
    for (final e in entries.take(productionDraftCap)) e.key: e.value,
  };
}

/// 草稿集合守卫：按「文章 + 模式」各留一组，最多 9 组；兼容旧版按文章存的对象。
Map<String, ProductionDraft> normalizeProductionDraftMap(Object? raw) {
  if (!_isObject(raw)) return <String, ProductionDraft>{};
  final map = raw as Map;
  final out = <String, ProductionDraft>{};
  void add(ProductionDraft? draft) {
    if (draft == null) return;
    final key = productionDraftKey(draft.articleId, draft.mode);
    final old = out[key];
    if (old == null || draft.at.compareTo(old.at) >= 0) out[key] = draft;
  }

  if (map['version'] == _draftVersion && map['articleId'] is String) {
    add(normalizeProductionDraft(map));
  } else {
    for (final value in map.values) {
      add(normalizeProductionDraft(value));
    }
  }
  return _capByRecency(out);
}

/// 合并导入：同一篇文章同一模式取较新的草稿，最多留 9 组。
Map<String, ProductionDraft> mergeProductionDraftMaps(
  Map<String, ProductionDraft> current,
  Map<String, ProductionDraft> incoming,
) {
  final out = <String, ProductionDraft>{...current};
  for (final entry in incoming.entries) {
    final old = out[entry.key];
    if (old == null || entry.value.at.compareTo(old.at) >= 0) {
      out[entry.key] = entry.value;
    }
  }
  return _capByRecency(out);
}
