/// 「D老师小课堂」的 AI 任务：一次生成「主旨 + 脉络 + 金句 + 句型/时态 + 词块」。
///
/// 对应 Web `src/core/goldenAi.ts`（210 行）。
///
/// 边界（别越界改）：
///   - 提示词只要求 AI **挑句子、加注释**，不要求它改写原句；
///   - 解析层一律过 `normalizeGoldenLesson`，校验句子 id 与目标是否逐字出现；
///   - AI 缺的句子 / 目标由本地推导补齐（`mergeGoldenLessons`），所以 AI 失败也能练。
library;

import 'dart:convert';

import '../models/document.dart';
import 'golden.dart';
import 'golden_parse.dart';

/// 一次最多让 AI 挑几句。
const int goldenAiMaxSentences = 12;

/// 提示词里的一句。
class GoldenPromptSentence {
  const GoldenPromptSentence({
    required this.id,
    required this.text,
    this.translation,
    this.paraId,
  });

  final String id;
  final String text;
  final String? translation;
  final String? paraId;
}

/// 提示词入参。
class GoldenPromptInput {
  const GoldenPromptInput({
    required this.sentences,
    this.title,
    this.maxSentences = 10,
  });

  final String? title;
  final List<GoldenPromptSentence> sentences;

  /// 让 AI 挑几句；默认 10，最多 12。
  final int maxSentences;
}

/// 网页版 / 本机 agent 共用的一份提示词。
String buildGoldenPrompt(GoldenPromptInput input) {
  final max = input.maxSentences.clamp(1, goldenAiMaxSentences);
  final lines = <String>[
    for (final s in input.sentences)
      '${s.id}\t${s.text}'
          '${(s.translation ?? '').trim().isEmpty ? '' : '\t译：${s.translation!.trim()}'}',
  ];
  return <String>[
    '你是英语写作教练。请从下面这篇文章里挑出最值得「仿写迁移」的句子，做成一套金句精练。',
    '',
    '挑选标准（按优先级）：',
    '1. 有值得学的句型 / 结构（如 in response to + n., … has become …）；',
    '2. 有时态 / 语态重点（现在完成、被动、虚拟、倒装等）；',
    '3. 有可迁移的搭配 / 习语；',
    '4. 句子长度适中（8–40 词），不要挑太短的口水句。',
    '最多挑 $max 句；宁可少挑，也不要凑数。',
    '',
    '对每一句输出：',
    '- id：原样照抄句子编号；',
    '- zh：整句中文（有现成译文就用它，不要改写意思）；',
    '- pattern：一句话点出值得迁移的句型；',
    '- tense：时态 / 语态重点（只写句子真实用到的）；',
    '- note：用法提醒；本句所有无法逐字挖空的语法/用法都可以放这里，不要省略；',
    '- targets：尽量覆盖本句所有可迁移语言点（phrases / idioms / collocations / words），'
        '按在句中出现的先后排列；通常 3–12 个，最多 $goldenTargetLimit 个'
        '（短句少、长句最多 20，程序会按句长再截断），不要只挑 3–6 个。每项：',
    '  - en：**必须是原句里逐字出现的连续片段**，不要改写、不要补标点；',
    '  - zh：简短中文提示（填空时给用户看）；',
    '  - kind：只能是 pattern / tense / collocation / idiom / usage / word 之一。',
    '',
    '另外输出：',
    '- summary：2–3 句中文概括文章核心；',
    '- outline：按段落给 { paraId, role, points }，role 只能是 intro / body / conclusion，'
        'points 是 1–2 条中文要点；',
    '- selected：你挑中的句子 id 数组，和 sentences 里的 id 一致。',
    '',
    '硬规则：',
    '- 只从给定句子里挑，不要编造句子；',
    '- targets.en 必须是原句的逐字片段；语法/结构/用法不是逐字片段的，'
        '放 pattern / tense / note，不要硬造成 target；',
    '- 不要输出 Markdown、不要解释，只输出一个 JSON 对象。',
    '',
    '输出格式：',
    '{"summary":"...","outline":[{"paraId":"p01","role":"intro","points":["..."]}],'
        '"selected":["s001"],"sentences":[{"id":"s001","zh":"...","pattern":"...",'
        '"tense":"...","note":"...","targets":[{"en":"in response to",'
        '"zh":"为了应对","kind":"collocation"}]}]}',
    '',
    if (input.title != null && input.title!.trim().isNotEmpty)
      '文章标题：${input.title!.trim()}',
    '句子（id\t原文\t译文）：',
    ...lines,
  ].where((line) => line.isNotEmpty).join('\n');
}

final RegExp _fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```', caseSensitive: false);

String _stripFence(String raw) {
  final m = _fence.firstMatch(raw);
  return (m != null ? m.group(1)! : raw).trim();
}

/// 从一段文本里抠出第一个配平的 JSON 对象（忽略前后解释）。
String? _extractJsonObject(String text) {
  final start = text.indexOf('{');
  if (start < 0) return null;
  var depth = 0;
  var inStr = false;
  var esc = false;
  for (var i = start; i < text.length; i++) {
    final c = text[i];
    if (inStr) {
      if (esc) {
        esc = false;
      } else if (c == r'\') {
        esc = true;
      } else if (c == '"') {
        inStr = false;
      }
    } else if (c == '"') {
      inStr = true;
    } else if (c == '{') {
      depth++;
    } else if (c == '}') {
      depth--;
      if (depth == 0) return text.substring(start, i + 1);
    }
  }
  return null;
}

final RegExp _badEscape = RegExp(r'\\(?![\\"/bfnrtu])');

String _sanitizeJson(String s) => s
    .replaceAll(r'\(', '[')
    .replaceAll(r'\)', ']')
    .replaceAll(r'\[', '[')
    .replaceAll(r'\]', ']')
    .replaceAll(_badEscape, '');

/// 解析 AI 金句课；宽容围栏 / 前后废话 / 非法转义，但内容仍要过 `normalizeGoldenLesson`。
///
/// `at` 用于测试固定时间；不传就用当前 UTC 时间。
GoldenLesson? parseGoldenLesson(
  String raw,
  List<GoldenTextMeta> sentences, {
  String? at,
}) {
  final text = _stripFence(raw);
  if (text.isEmpty) return null;
  final balanced = _extractJsonObject(text);
  final candidates = <String>[
    text,
    ?balanced,
    _sanitizeJson(text),
    if (balanced != null) _sanitizeJson(balanced),
  ];
  for (final c in candidates) {
    Object? parsed;
    try {
      parsed = jsonDecode(c);
    } catch (_) {
      continue;
    }
    final lesson = normalizeGoldenLesson(parsed, sentences);
    if (lesson != null) {
      return lesson.copyWith(
        source: GoldenSource.ai,
        updatedAt: () => at ?? DateTime.now().toUtc().toIso8601String(),
      );
    }
  }
  return null;
}

/// 合并选项。
class MergeGoldenOptions {
  const MergeGoldenOptions({
    this.dedupe,
    this.preferAI = false,
    this.blankUnit,
    this.sentenceFill,
  });

  /// 用户的本课设置（去重）优先于 AI 返回。
  final bool? dedupe;

  /// 首次 AI 生成时用 AI 挑的金句；用户手动改过选择后默认保留本地。
  final bool preferAI;

  /// 填空单位；用户本课设置优先。
  final GoldenBlankUnit? blankUnit;

  /// 整句渐进开关；用户本课设置优先。
  final bool? sentenceFill;
}

/// AI 与本地合并：AI 有的用 AI，AI 缺的用本地；保证每句至少有内容可练。
///
/// 用户手动选的金句（`local.selected` 和 AI 不同）默认保留本地选择，
/// 除非调用方显式 `preferAI: true`。
GoldenLesson mergeGoldenLessons(
  GoldenLesson local,
  GoldenLesson ai,
  List<Sentence> sentences, [
  MergeGoldenOptions opts = const MergeGoldenOptions(),
  String? at,
]) {
  final byId = <String, Sentence>{for (final s in sentences) s.id: s};
  final localContent = <String, GoldenSentence>{
    for (final s in local.sentences) s.id: s,
  };
  final aiContent = <String, GoldenSentence>{
    for (final s in ai.sentences) s.id: s,
  };
  final ids = <String>{
    for (final s in ai.sentences) s.id,
    for (final s in local.sentences) s.id,
  };
  final merged = <GoldenSentence>[];
  for (final id in ids) {
    final sentence = byId[id];
    if (sentence == null) continue;
    final a = aiContent[id];
    final l = localContent[id] ?? buildLocalGoldenSentence(sentence);
    // AI 注释优先，但本地语言点不能被覆盖：两边取并集后再按原句重排 / 去重。
    // `normalizeGoldenTargets` 吃的是原始 JSON 形状（`en`/`kind`/`zh`），
    // 所以强类型 target 要转回 Map 再喂进去，不能直接传对象。
    final targets = normalizeGoldenTargets(sentence.text, <Object?>[
      for (final t in <GoldenTarget>[...?a?.targets, ...l.targets]) t.toJson(),
    ]);
    final zh = (a?.zh != null && a!.zh!.isNotEmpty) ? a.zh : l.zh;
    final pattern =
        (a?.pattern != null && a!.pattern!.isNotEmpty) ? a.pattern : l.pattern;
    final tense = (a?.tense != null && a!.tense!.isNotEmpty) ? a.tense : l.tense;
    final note = (a?.note != null && a!.note!.isNotEmpty) ? a.note : l.note;
    merged.add(GoldenSentence(
      id: id,
      zh: (zh == null || zh.isEmpty) ? null : zh,
      pattern: (pattern == null || pattern.isEmpty) ? null : pattern,
      tense: (tense == null || tense.isEmpty) ? null : tense,
      note: (note == null || note.isEmpty) ? null : note,
      targets: targets,
    ));
  }
  final valid = <String>{for (final s in merged) s.id};
  final preferred = opts.preferAI
      ? ai.selected
      : (local.selected.isNotEmpty ? local.selected : ai.selected);
  final selected = <String>[
    for (final id in preferred)
      if (valid.contains(id)) id,
  ];
  final exam = (ai.exam != null && ai.exam!.isNotEmpty) ? ai.exam : local.exam;
  final summary = (ai.summary != null && ai.summary!.isNotEmpty)
      ? ai.summary
      : (local.summary != null && local.summary!.isNotEmpty
          ? local.summary
          : null);
  final outline = ai.outline.isNotEmpty ? ai.outline : local.outline;
  final localOptions = local.options;
  final lesson = GoldenLesson(
    source: GoldenSource.merged,
    summary: summary,
    outline: outline,
    sentences: merged,
    selected: selected.isNotEmpty ? selected : <String>[for (final s in merged) s.id],
    aiSelected: <String>[
      for (final id in ai.selected)
        if (valid.contains(id)) id,
    ],
    exam: (exam == null || exam.isEmpty) ? null : exam,
    options: GoldenLessonOptions(
      dedupe: opts.dedupe ?? localOptions.dedupe,
      pick: opts.preferAI ? GoldenPickMode.ai : (localOptions.pick ?? GoldenPickMode.manual),
      blankUnit: opts.blankUnit ?? localOptions.blankUnit ?? GoldenBlankUnit.word,
      sentenceFill: opts.sentenceFill ?? localOptions.sentenceFill ?? true,
      examAfter: localOptions.examAfter,
    ),
    updatedAt: at ?? DateTime.now().toUtc().toIso8601String(),
  );
  return lesson.options.dedupe ? dedupeGoldenLesson(lesson) : lesson;
}
