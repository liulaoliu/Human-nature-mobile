/// 产出训练的「评分任务」：把一道题变成仿写批改那套任务，并复用同一份 rubric 口径。
///
/// 对应 Web 版 `src/core/productionPrompts.ts` 的后半段（`ProductionTask` /
/// `makeProductionTask` / `buildProductionFeedbackPrompt` / `parseProductionFeedback` /
/// `productionHits`）。拆到单独文件是因为它依赖 `writing.dart`，
/// 和前半段「拼提示词 / 解析题目包」不是一回事。
library;

import 'production.dart';
import 'writing.dart';

/// 跳过题也留档：不伪造 AI 分数，只记「跳过（未提交）」和已写的草稿。
const String skippedProductionSummary = '跳过（未提交）';

/// 跳过题的空批改：分数全 0、没有问题、summary 写明跳过。
WritingFeedback skippedProductionFeedback() => const WritingFeedback(
      version: 2,
      scores: <WritingScore>[],
      total: 0,
      max: 0,
      issues: <WritingIssue>[],
      recommendations: <WritingRecommendation>[],
      polished: '',
      summary: skippedProductionSummary,
    );

/// 一道产出训练的评分任务：仿写任务 + 产出训练自己的那几列。
class ProductionTask extends ImitationTask {
  const ProductionTask({
    required super.task,
    super.model = '',
    super.structure,
    super.mustUse = const <String>[],
    super.rubric = const <RubricItem>[],
    super.focus,
    super.round,
    this.kind = 'production',
    required this.mode,
    required this.topic,
    required this.goal,
    required this.promptId,
    this.skipped,
    this.sessionId,
    this.answerLang,
    this.targets = const <ProductionTarget>[],
    this.reference,
    this.hits = const <ProductionTargetHit>[],
  });

  /// 历史记录靠这一列把产出训练和普通仿写分开。
  final String kind;

  final ProductionMode mode;

  /// 这一组训练的主题（全脂是随机自选，脱脂奶是用户填的）。
  final String topic;

  /// 中文沟通目标（「委婉拒绝」「说明进度」）。
  final String goal;

  final String promptId;

  /// 用户主动跳过、没有 AI 批改；统计与进度应忽略这一稿。
  final bool? skipped;

  /// 同一组训练；历史里用它把第 1 / 2 稿并排。
  final String? sessionId;

  /// 风味酸奶的方向：默认中译英；英译中时参考答案是中文。
  final ProductionAnswerLang? answerLang;

  final List<ProductionTarget> targets;

  /// 风味酸奶的参考译文；批改提示词里会作为「范句」交给 AI。
  final String? reference;

  /// 判过分的稿子里存的目标块命中情况。
  final List<ProductionTargetHit> hits;

  @override
  ProductionTask copyWith({
    String? task,
    String? model,
    String? Function()? structure,
    List<String>? mustUse,
    List<RubricItem>? rubric,
    String? Function()? focus,
    int? Function()? round,
    ProductionMode? mode,
    String? topic,
    String? goal,
    String? promptId,
    bool? Function()? skipped,
    String? Function()? sessionId,
    ProductionAnswerLang? Function()? answerLang,
    List<ProductionTarget>? targets,
    String? Function()? reference,
    List<ProductionTargetHit>? hits,
  }) =>
      ProductionTask(
        task: task ?? this.task,
        model: model ?? this.model,
        structure: structure != null ? structure() : this.structure,
        mustUse: mustUse ?? this.mustUse,
        rubric: rubric ?? this.rubric,
        focus: focus != null ? focus() : this.focus,
        round: round != null ? round() : this.round,
        mode: mode ?? this.mode,
        topic: topic ?? this.topic,
        goal: goal ?? this.goal,
        promptId: promptId ?? this.promptId,
        skipped: skipped != null ? skipped() : this.skipped,
        sessionId: sessionId != null ? sessionId() : this.sessionId,
        answerLang: answerLang != null ? answerLang() : this.answerLang,
        targets: targets ?? this.targets,
        reference: reference != null ? reference() : this.reference,
        hits: hits ?? this.hits,
      );

  /// 比 `ImitationTask.toJson` 多出产出训练那几列；历史记录原样存这份。
  @override
  Map<String, Object?> toJson() => <String, Object?>{
        ...super.toJson(),
        'kind': kind,
        'mode': mode.name,
        'topic': topic,
        'goal': goal,
        'promptId': promptId,
        if (skipped == true) 'skipped': true,
        if (sessionId != null) 'sessionId': sessionId,
        if (answerLang != null) 'answerLang': answerLang!.name,
        'targets': <Object?>[
          for (final t in targets)
            <String, Object?>{
              'id': t.id,
              'itemId': t.itemId,
              'kind': t.kind.name,
              'text': t.text,
              'meaning': t.meaning,
            },
        ],
        if (reference != null) 'reference': reference,
        if (hits.isNotEmpty)
          'hits': <Object?>[
            for (final h in hits)
              <String, Object?>{
                'id': h.id,
                'kind': h.kind.name,
                'text': h.text,
                'meaning': h.meaning,
                'used': h.used,
              },
          ],
      };
}

/// 出评分任务：复用仿写批改的 rubric / mustUse / focus 口径。
ProductionTask makeProductionTask(
  ProductionPrompt prompt,
  String topic, {
  ProductionMode mode = ProductionMode.skim,
  String? sessionId,
}) {
  final yogurt = mode == ProductionMode.yogurt;
  final hasTargets = prompt.targets.isNotEmpty;
  final answerLang = prompt.answerLang ?? ProductionAnswerLang.en;
  final zhAnswer = yogurt && answerLang == ProductionAnswerLang.zh;
  final reference = (prompt.reference ?? '').trim();

  return ProductionTask(
    task: prompt.zh,
    model: yogurt
        ? (reference.isEmpty ? '（没有粘贴参考译文）' : reference)
        : '（自由表达，没有唯一范句）',
    mode: mode,
    topic: topic,
    goal: prompt.goal,
    promptId: prompt.id,
    sessionId: sessionId,
    answerLang: yogurt ? answerLang : null,
    targets: prompt.targets,
    reference: yogurt && prompt.reference != null && prompt.reference!.isNotEmpty
        ? prompt.reference
        : null,
    mustUse: <String>[for (final t in prompt.targets) t.text],
    rubric: _rubricFor(
      yogurt: yogurt,
      zhAnswer: zhAnswer,
      hasTargets: hasTargets,
    ),
    focus: _focusFor(
      yogurt: yogurt,
      zhAnswer: zhAnswer,
      hasTargets: hasTargets,
      mode: mode,
      targets: prompt.targets,
    ),
  );
}

List<RubricItem> _rubricFor({
  required bool yogurt,
  required bool zhAnswer,
  required bool hasTargets,
}) {
  if (yogurt) {
    if (zhAnswer) {
      return const <RubricItem>[
        RubricItem(
          dimension: '英文原意',
          weight: 40,
          description: '英文原句的意思是否完整、准确，没有漏译 / 加戏',
        ),
        RubricItem(
          dimension: '中文自然度',
          weight: 30,
          description: '中文是否通顺、像正常表达，而不是逐字硬翻',
        ),
        RubricItem(
          dimension: '参考译文差距',
          weight: 30,
          description: '和参考译文相比，哪些表达更准确 / 更地道',
        ),
      ];
    }
    return const <RubricItem>[
      RubricItem(
        dimension: '原文意思',
        weight: 40,
        description: '中文原文的意思是否完整、准确，没有漏译 / 加戏',
      ),
      RubricItem(
        dimension: '英文自然度',
        weight: 30,
        description: '语法、搭配、时态和语序是否自然',
      ),
      RubricItem(
        dimension: '参考译文差距',
        weight: 30,
        description: '和参考译文相比，哪些表达更准确 / 更地道，哪些地方差距大',
      ),
    ];
  }
  if (hasTargets) {
    return const <RubricItem>[
      RubricItem(
        dimension: '意思到位',
        weight: 40,
        description: '中文情境想表达的意思是否完整、准确',
      ),
      RubricItem(
        dimension: '目标词块',
        weight: 30,
        description: '目标词 / 词组 / 习语是否用上且搭配正确',
      ),
      RubricItem(
        dimension: '语法与自然度',
        weight: 30,
        description: '语法、时态、冠词、介词和语序是否自然',
      ),
    ];
  }
  return const <RubricItem>[
    RubricItem(
      dimension: '意思到位',
      weight: 40,
      description: '中文句子想表达的意思是否完整、准确',
    ),
    RubricItem(
      dimension: '语法与自然度',
      weight: 35,
      description: '语法、时态、冠词、介词和语序是否自然',
    ),
    RubricItem(
      dimension: '表达地道',
      weight: 25,
      description: '用词和搭配是否像正常英文，而不是逐字硬翻',
    ),
  ];
}

String _focusFor({
  required bool yogurt,
  required bool zhAnswer,
  required bool hasTargets,
  required ProductionMode mode,
  required List<ProductionTarget> targets,
}) {
  if (yogurt) return zhAnswer ? '英译中' : '逐句翻译';
  if (hasTargets) return <String>[for (final t in targets) t.text].join(' / ');
  return mode == ProductionMode.full ? '随机主题' : '主题翻译';
}

/// 批改提示词：产出训练沿用仿写那套，英译中时补一段「按中文批改」的说明。
String buildProductionFeedbackPrompt(
  ProductionTask task,
  String answer, {
  List<PreviousIssue>? previousIssues,
}) {
  final base = buildWritingFeedbackPrompt(
    task,
    answer,
    WritingFeedbackPromptOptions(previousIssues: previousIssues),
  );
  if (task.answerLang != ProductionAnswerLang.zh) return base;
  return <String>[
    '注意：本题是「英译中」，学生作答是中文。请按中文表达批改，不要按英文语法规则扣分；',
    'issues.original / suggestion / reason 也用中文；problem 应是中文不自然、漏译、加戏或和参考译文差距大的地方。',
    '仍然只输出同样的 v2 JSON。',
    '',
    base,
  ].join('\n');
}

/// 解析批改结果；`answer` 用来校验 original 必须逐字出现在作答里。
WritingFeedbackParse? parseProductionFeedback(String raw, String answer) =>
    parseWritingFeedbackDetailed(raw, WritingFeedbackParseOptions(answer: answer));

/// 历史记录里把 production 任务认出来；坏形状返回 false，不让历史页炸。
bool isProductionTask(Object? task) {
  if (task is! Map) return false;
  return task['kind'] == 'production' &&
      task['topic'] is String &&
      task['promptId'] is String &&
      task['targets'] is List;
}

/// 一条判过分的 production 反馈里，目标块命中情况。
List<ProductionTargetHit> productionHits(Object? task) {
  if (task is! Map) return const <ProductionTargetHit>[];
  if (!isProductionTask(task)) return const <ProductionTargetHit>[];
  final raw = task['hits'];
  if (raw is! List) return const <ProductionTargetHit>[];
  final out = <ProductionTargetHit>[];
  for (final h in raw) {
    if (h is! Map) continue;
    final id = h['id'];
    final text = h['text'];
    final used = h['used'];
    if (id is! String || text is! String || used is! bool) continue;
    final kind = _kindByName(h['kind']) ?? ProductionTargetKind.word;
    final meaning = h['meaning'];
    out.add(ProductionTargetHit(
      id: id,
      kind: kind,
      text: text,
      meaning: meaning is String ? meaning : '',
      used: used,
    ));
  }
  return out;
}

/// 只用于 UI 摘要：目标块命中数。
int countProductionHits(List<ProductionTargetHit> hits) =>
    hits.where((h) => h.used).length;

ProductionTargetKind? _kindByName(Object? raw) {
  if (raw is! String) return null;
  for (final k in ProductionTargetKind.values) {
    if (k.name == raw) return k;
  }
  return null;
}
