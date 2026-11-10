/// 仿写训练的**提示词拼装**：出题提示词 + 批改提示词。
///
/// 从 `writing.dart` 拆出来：这两个函数只做字符串拼装，连 `dart:convert` 都不用，
/// 和「AI 输出怎么解析」（`writing_parse.dart`）、「数据长什么样」（`writing_types.dart`）
/// 是三件独立的事。批改提示词会调 `writingRuleCatalog()` 拿到错因闭集清单。
library;

import 'writing_error_rules.dart' show WritingRule, writingRuleCatalog;
import 'writing_types.dart';

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
