/// 产出训练的提示词与结果解析（全脂 / 脱脂奶 / 风味酸奶）。
///
/// 这一层只拼字符串、解析 AI 回来的 JSON，不碰存储与界面。
/// 对应 Web 版 `src/core/productionPrompts.ts`（514 行）；
/// 其中「出评分任务 / 批改提示词 / 判分结果」那一段依赖 `writing.dart`，
/// 等仿写那套移植过来再补，先不在这里造一份平行实现。
library;

import 'dart:convert';

import 'production.dart';

/// 出「目标块题」的输入（全脂 / 脱脂奶，带本机词块）。
class BuildProductionPackInput {
  const BuildProductionPackInput({
    required this.mode,
    required this.topic,
    required this.angle,
    required this.tone,
    required this.level,
    this.articleTitle = '',
    this.targets = const <ProductionTarget>[],
    this.promptCount = 5,
    this.targetsPerPrompt = 2,
  });

  /// 只能是 [ProductionMode.full] 或 [ProductionMode.skim]。
  final ProductionMode mode;
  final String topic;
  final ProductionAngle angle;
  final ProductionTone tone;
  final ProductionLevel level;
  final String articleTitle;
  final List<ProductionTarget> targets;
  final int promptCount;
  final int targetsPerPrompt;
}

/// 让 AI 从**给定候选清单**里选目标块并出中文情境题。
String buildProductionPackPrompt(BuildProductionPackInput input) {
  final targetLines = input.targets
      .map((t) => '- ${t.id} | ${t.kind.name} | ${t.text}'
          '${t.meaning.isEmpty ? '' : ' | ${t.meaning}'}')
      .join('\n');
  final full = input.mode == ProductionMode.full;
  final topicLine = full
      ? '主题：随机自选（随机挑选日常生活 / 工作 / 学习 / 社交主题，不要围绕单一主题）'
      : '主题：${input.topic}';
  return <String>[
    '你是英语产出训练的出题老师。请写中文情境提示，让学生用英文表达。',
    '',
    topicLine,
    '模式：${productionModeLabel[input.mode]}',
    '角度：${productionAngleLabel[input.angle]}',
    '语气：${productionToneLabel[input.tone]}',
    '难度：${productionLevelLabel[input.level]}',
    !full && input.articleTitle.isNotEmpty ? '参考文章：${input.articleTitle}' : '',
    '',
    '必须遵守：',
    '- 出 ${input.promptCount} 道题；每道题必须分配 ${input.targetsPerPrompt} 个目标块；',
    '- 只能从下面候选清单里选 targetIds，不能编造；目标块不重复使用；',
    full
        ? '- 这是「全脂」随机模式：不要围绕一个主题；每道题换一个不同场景；目标块随机挑，不要总挑清单最前面的。'
        : '- 这是「脱脂奶」主题模式：所有题都围绕上述主题，但每道题的情境仍要具体、不同。',
    '- 难度按 ${productionLevelLabel[input.level]} 控制：B1 用短句和常见词，B2 允许复合句，C1 可以更抽象但必须自然；',
    '- zh 必须是自然的中文情境 / 沟通目标，不能出现英文目标词，不能逐字提示英文句式；',
    '- model 必须是一句自然英文参考句，正确使用本题分配的目标块；它默认不展示，只在挖空 / 排序题型里作提示；',
    '- goal 用中文说明这句话要达成什么（如「委婉拒绝」「说明进度」「表达不同意见」）；',
    '- 题目之间尽量覆盖不同情境，不要 5 道题都在说同一件事；',
    '- 只输出 JSON，不要 Markdown、不要解释。',
    '',
    '候选目标块（id | 类型 | 英文 | 中文）：',
    targetLines,
    '',
    '输出格式：',
    '{"prompts":[{"zh":"中文情境","goal":"中文沟通目标","targetIds":["id1","id2"],"model":"完整英文参考句"}]}',
  ].where((s) => s.isNotEmpty).join('\n');
}

/// 出「纯主题题」的输入（脱脂奶，不强制目标块）。
class BuildTopicPackInput {
  const BuildTopicPackInput({
    required this.topic,
    required this.angle,
    required this.tone,
    required this.level,
    this.articleTitle = '',
    this.promptCount = 5,
    this.randomTopic = false,
  });

  final String topic;
  final ProductionAngle angle;
  final ProductionTone tone;
  final ProductionLevel level;
  final String articleTitle;
  final int promptCount;

  /// 全脂关掉本机词块时：让 AI 自己随机定主题。
  final bool randomTopic;
}

/// 只给主题（或让 AI 随机定主题），让 AI 出中文句子；不强制目标块。
String buildTopicPackPrompt(BuildTopicPackInput input) => <String>[
      '你是英语产出训练的出题老师。请围绕主题写中文句子，让学生翻译成英文。',
      '',
      input.randomTopic
          ? '主题：随机自选（请自己挑一个具体的生活 / 工作 / 学习主题，不要问用户；不同题可以来自不同场景）'
          : '主题：${input.topic}',
      '角度：${productionAngleLabel[input.angle]}',
      '语气：${productionToneLabel[input.tone]}',
      '难度：${productionLevelLabel[input.level]}',
      input.articleTitle.isNotEmpty && !input.randomTopic
          ? '参考文章：${input.articleTitle}'
          : '',
      '',
      '必须遵守：',
      '- 出 ${input.promptCount} 道题；每题只给一个中文句子 / 一个具体沟通情境；',
      '- 难度按 ${productionLevelLabel[input.level]} 控制；长短交错，不要五道题都在说同一件事；',
      '- 中文里不要出现英文答案，不要逐字提示英文句式；',
      '- goal 用中文说明这句话要达成什么（如「解释原因」「提出请求」「表达不同意见」）；',
      '- 只输出 JSON，不要 Markdown、不要解释。',
      '',
      '输出格式：',
      '{"prompts":[{"zh":"中文句子 / 情境","goal":"中文沟通目标"}]}',
    ].where((s) => s.isNotEmpty).join('\n');

/// 去掉 Markdown 围栏，留下 JSON 正文。
String _stripFence(String raw) {
  final m = RegExp(r'```(?:json)?\s*([\s\S]*?)```', caseSensitive: false)
      .firstMatch(raw);
  return (m != null ? m.group(1)! : raw).trim();
}

String _asString(Object? v, int max) =>
    v is String ? _clipText(v.trim(), max) : '';

String _clipText(String s, int max) => s.length <= max ? s : s.substring(0, max);

/// 解析 AI 回来的 JSON 对象；不是对象返回 null。
Map<String, Object?>? _parseObject(String raw) {
  Object? parsed;
  try {
    parsed = jsonDecode(_stripFence(raw));
  } on FormatException {
    return null;
  }
  if (parsed is! Map) return null;
  return <String, Object?>{
    for (final e in parsed.entries) e.key.toString(): e.value,
  };
}

/// 解析脱脂奶题目包；不要求 targetIds。
List<ProductionPrompt>? parseTopicPack(String raw, {int maxPrompts = 12}) {
  final obj = _parseObject(raw);
  if (obj == null) return null;
  final promptsRaw = obj['prompts'];
  if (promptsRaw is! List) return null;
  final prompts = <ProductionPrompt>[];
  for (var i = 0; i < promptsRaw.length; i++) {
    if (i >= maxPrompts) break;
    final item = promptsRaw[i];
    if (item is! Map) continue;
    final zh = _asString(item['zh'], 600);
    if (zh.isEmpty) continue;
    prompts.add(ProductionPrompt(
      id: 'topic-${i + 1}',
      zh: zh,
      goal: _asString(item['goal'], 300),
      targets: const <ProductionTarget>[],
    ));
  }
  return prompts.isEmpty ? null : prompts;
}

/// 解析 AI 题目包。只认候选清单里的目标 id；坏题 / 无目标 / 中文为空直接丢。
List<ProductionPrompt>? parseProductionPack(
  String raw,
  List<ProductionTarget> allowed, {
  int maxPrompts = 12,
}) {
  final obj = _parseObject(raw);
  if (obj == null) return null;
  final promptsRaw = obj['prompts'];
  if (promptsRaw is! List) return null;
  final byId = <String, ProductionTarget>{
    for (final t in allowed) t.id: t,
  };
  final prompts = <ProductionPrompt>[];
  for (var i = 0; i < promptsRaw.length; i++) {
    if (i >= maxPrompts) break;
    final item = promptsRaw[i];
    if (item is! Map) continue;
    final zh = _asString(item['zh'], 600);
    if (zh.isEmpty) continue;
    final idsRaw = item['targetIds'];
    final ids = idsRaw is List
        ? idsRaw.whereType<String>().toList(growable: false)
        : const <String>[];
    final targets = <ProductionTarget>[];
    final seen = <String>{};
    for (final id in ids) {
      final target = byId[id];
      if (target == null || seen.contains(target.id)) continue;
      seen.add(target.id);
      targets.add(target);
    }
    if (targets.isEmpty) continue;
    final model = _asString(item['model'], 1500);
    prompts.add(ProductionPrompt(
      id: 'prod-${i + 1}',
      zh: zh,
      goal: _asString(item['goal'], 300),
      targets: targets,
      model: model.isEmpty ? null : model,
    ));
  }
  return prompts.isEmpty ? null : prompts;
}

/// 按句 / 按行拆一段文本；两种语言共用，供风味酸奶预览编辑。
List<String> splitProductionSentences(
  String text, {
  YogurtSplitMode mode = YogurtSplitMode.sentence,
}) {
  final normalized = text.replaceAll(RegExp(r'\r\n?'), '\n').trim();
  if (normalized.isEmpty) return const <String>[];
  if (mode == YogurtSplitMode.line) {
    return normalized
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
  }
  final out = <String>[];
  final re = RegExp(r'[^。！？!?；;.]+[。！？!?；;.]?');
  for (final line in normalized.split('\n')) {
    for (final m in re.allMatches(line)) {
      final s = m.group(0)!.trim();
      if (s.isNotEmpty) out.add(s);
    }
  }
  return out;
}

/// 一对「原文 / 参考译文」。
class YogurtPair {
  const YogurtPair({this.source = '', this.reference = ''});

  final String source;
  final String reference;

  YogurtPair copyWith({String? source, String? reference}) => YogurtPair(
        source: source ?? this.source,
        reference: reference ?? this.reference,
      );

  @override
  bool operator ==(Object other) =>
      other is YogurtPair &&
      other.source == source &&
      other.reference == reference;

  @override
  int get hashCode => Object.hash(source, reference);

  @override
  String toString() => 'YogurtPair($source / $reference)';
}

/// 配对结果（带句数不一致的提示）。
class YogurtPairResult {
  const YogurtPairResult({
    required this.pairs,
    required this.warning,
    required this.sourceCount,
    required this.referenceCount,
  });

  final List<YogurtPair> pairs;

  /// 句数对不上时的提示；对得上就是空字符串。
  final String warning;
  final int sourceCount;
  final int referenceCount;
}

/// 先拆再配对。句数不一致时以短边为准，长边末尾并进最后一对；
/// 界面上的对齐编辑器可以在此基础上合并 / 拆分 / 移动。
YogurtPairResult? pairYogurtTexts(
  String source,
  String reference, {
  YogurtSplitMode mode = YogurtSplitMode.sentence,
}) {
  final src = splitProductionSentences(source, mode: mode);
  final ref = splitProductionSentences(reference, mode: mode);
  if (src.isEmpty || ref.isEmpty) return null;
  final n = src.length < ref.length ? src.length : ref.length;
  final pairs = <YogurtPair>[];
  for (var i = 0; i < n; i++) {
    final last = i == n - 1;
    final s = last ? src.sublist(i).join(' ') : src[i];
    final r = last ? ref.sublist(i).join(' ') : ref[i];
    if (s.isEmpty && r.isEmpty) continue;
    pairs.add(YogurtPair(source: s, reference: r));
  }
  final warning = src.length == ref.length
      ? ''
      : '${src.length} 句 / ${ref.length} 句，句数不一致；已按顺序配对，末尾多出的内容并入最后一对。';
  return YogurtPairResult(
    pairs: pairs,
    warning: warning,
    sourceCount: src.length,
    referenceCount: ref.length,
  );
}

/// 编译出来的题目组（带句数提示）。
class YogurtPromptResult {
  const YogurtPromptResult({
    required this.prompts,
    this.warning = '',
    this.sourceCount = 0,
    this.referenceCount = 0,
  });

  final List<ProductionPrompt> prompts;

  /// 句数对不上时的提示；对得上就是空字符串。
  final String warning;
  final int sourceCount;
  final int referenceCount;
}

/// 把对子编译成逐句题目；[paragraph] 时再追加一道整段连写。
YogurtPromptResult? buildYogurtPromptsFromPairs(
  List<YogurtPair> pairs, {
  ProductionDirection direction = ProductionDirection.zhEn,
  String warning = '',
  bool paragraph = false,
}) {
  final answerLang = direction == ProductionDirection.enZh
      ? ProductionAnswerLang.zh
      : ProductionAnswerLang.en;
  final usable = pairs
      .where((p) => p.source.trim().isNotEmpty || p.reference.trim().isNotEmpty)
      .toList(growable: false);
  final prompts = <ProductionPrompt>[
    for (var i = 0; i < usable.length; i++)
      ProductionPrompt(
        id: 'yogurt-${i + 1}',
        zh: usable[i].source.trim(),
        goal: direction == ProductionDirection.enZh ? '逐句英译中' : '逐句中译英',
        targets: const <ProductionTarget>[],
        reference: usable[i].reference.trim().isEmpty
            ? null
            : usable[i].reference.trim(),
        answerLang: answerLang,
      ),
  ];
  if (prompts.isEmpty) return null;
  if (paragraph && usable.length > 1) {
    final source = usable
        .map((p) => p.source.trim())
        .where((s) => s.isNotEmpty)
        .join(' ');
    final reference = usable
        .map((p) => p.reference.trim())
        .where((s) => s.isNotEmpty)
        .join(' ');
    if (source.isNotEmpty) {
      prompts.add(ProductionPrompt(
        id: 'yogurt-paragraph',
        zh: source,
        goal: direction == ProductionDirection.enZh ? '整段英译中' : '整段中译英',
        targets: const <ProductionTarget>[],
        reference: reference.isEmpty ? null : reference,
        answerLang: answerLang,
      ));
    }
  }
  return YogurtPromptResult(
    prompts: prompts,
    warning: warning,
    sourceCount: usable.length,
    referenceCount: usable.length,
  );
}

/// 风味酸奶：把用户粘贴的中文原文 + 英文参考译文拆成逐句练习。
///
/// 不依赖 AI；句数对不上时按顺序配对，末尾多出的内容并入最后一题，并返回 warning。
/// 英文参考只挂在 prompt 上，界面在作答 / 批改前不显示。
YogurtPromptResult? buildYogurtPrompts(
  String source,
  String reference, {
  ProductionDirection direction = ProductionDirection.zhEn,
  YogurtSplitMode mode = YogurtSplitMode.sentence,
  bool paragraph = false,
}) {
  final paired = pairYogurtTexts(source, reference, mode: mode);
  if (paired == null) return null;
  return buildYogurtPromptsFromPairs(
    paired.pairs,
    direction: direction,
    warning: paired.warning,
    paragraph: paragraph,
  );
}

/// 校验结论（reason 是给用户看的中文）。
class ProductionQuality {
  const ProductionQuality({required this.ok, this.reason = ''});

  final bool ok;
  final String reason;

  @override
  String toString() => ok ? 'ProductionQuality(ok)' : 'ProductionQuality($reason)';
}

/// AI 题目包硬校验：数量、每题目标数、目标块不重复。
ProductionQuality validateProductionPack(
  List<ProductionPrompt> prompts,
  int expectedCount,
  int targetsPerPrompt, {
  bool requireModel = false,
}) {
  if (prompts.length != expectedCount) {
    return ProductionQuality(
      ok: false,
      reason: '应出 $expectedCount 道题，实际 ${prompts.length} 道',
    );
  }
  final used = <String>{};
  for (var i = 0; i < prompts.length; i++) {
    final prompt = prompts[i];
    if (prompt.targets.length != targetsPerPrompt) {
      return ProductionQuality(
        ok: false,
        reason: '第 ${i + 1} 题应带 $targetsPerPrompt 个目标块，实际 ${prompt.targets.length} 个',
      );
    }
    if (requireModel && (prompt.model ?? '').trim().isEmpty) {
      return ProductionQuality(ok: false, reason: '第 ${i + 1} 题缺少英文参考句 model');
    }
    for (final target in prompt.targets) {
      if (used.contains(target.id)) {
        return ProductionQuality(
          ok: false,
          reason: '目标块「${target.text}」被重复使用',
        );
      }
      used.add(target.id);
    }
  }
  return const ProductionQuality(ok: true);
}

/// 纯主题包硬校验：只查题目数量。
ProductionQuality validateTopicPack(
  List<ProductionPrompt> prompts,
  int expectedCount,
) =>
    prompts.length == expectedCount
        ? const ProductionQuality(ok: true)
        : ProductionQuality(
            ok: false,
            reason: '应出 $expectedCount 道题，实际 ${prompts.length} 道',
          );
