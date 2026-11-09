/// 金句课的「仿写考试」纯逻辑（对应 Web `src/core/goldenExam.ts`）。
///
/// 只做三件事：从已完成句子生成本地题、校验 AI/备份返回的题、把题转成
/// 现有仿写批改的 [ImitationTask]（复用提示词与解析，不写第二套口径）。
/// 成绩沿用 `WritingRecord`（source=goldenExam），本文件不碰存储。
library;

import 'dart:convert';

import 'golden.dart';
import 'writing.dart';

export 'golden_types.dart' show GoldenExamItem, GoldenRubric, GoldenItemSource;

const int goldenExamAfterDefault = 5;
const int goldenExamLimit = 10;

int goldenExamAfter(GoldenLesson? lesson) =>
    lesson?.options.examAfter == 10 ? 10 : goldenExamAfterDefault;

String goldenExamItemId(String sentenceId) => 'exam:$sentenceId';

const List<GoldenRubric> defaultGoldenRubric = <GoldenRubric>[
  GoldenRubric(
    dimension: '结构运用',
    weight: 35,
    description: '目标句型 / 时态 / 语态是否准确迁移',
  ),
  GoldenRubric(
    dimension: '用词搭配',
    weight: 25,
    description: '必须使用的词块与固定搭配是否自然',
  ),
  GoldenRubric(
    dimension: '语法准确',
    weight: 25,
    description: '主谓一致、冠词、介词、单复数等硬错误',
  ),
  GoldenRubric(
    dimension: '意思与连贯',
    weight: 15,
    description: '中文提示是否写清楚，句子是否连贯',
  ),
];

const List<GoldenRubric> langPointGoldenRubric = <GoldenRubric>[
  GoldenRubric(
    dimension: '词块使用',
    weight: 50,
    description: '必须用上的词块是否用对、搭配是否成立',
  ),
  GoldenRubric(
    dimension: '语法准确',
    weight: 30,
    description: '主谓一致、冠词、介词、时态等硬错误',
  ),
  GoldenRubric(
    dimension: '自然与语境',
    weight: 20,
    description: '整句是否自然，使用者自己的场景是否讲得通',
  ),
];

double _num(Object? v) {
  if (v is num) return v.isFinite ? v.toDouble() : 0;
  if (v is String) return double.tryParse(v) ?? 0;
  return 0;
}

/// 从已完成句子里生成本地题：中文题干 + 原句范句 + 已学词块 + rubric。
GoldenExamItem makeLocalGoldenExamItem(
  GoldenSentence content,
  GoldenTextMeta sentence,
) {
  final zh = content.zh ?? sentence.translation ?? '';
  final structure = content.pattern ?? content.tense ?? '';
  final task = <String>[
    '用学过的句型仿写一句英文（不要逐字照抄范句，换一个主语或场景）。',
    if (structure.isNotEmpty) '目标结构：$structure。',
    if (zh.isNotEmpty) '中文参考：$zh。',
  ].join(' ');
  final mustUse = content.targets
      .map((t) => t.en)
      .where((s) => s.isNotEmpty)
      .take(6)
      .toList();
  return GoldenExamItem(
    id: goldenExamItemId(sentence.id),
    sentenceId: sentence.id,
    task: task,
    model: sentence.text,
    structure: structure.isEmpty ? null : structure,
    mustUse: mustUse,
    rubric: defaultGoldenRubric,
    source: GoldenItemSource.local,
  );
}

/// 单句仿写：当前句刚走完流程就能练，不要求它已经出现在整课考试里。
GoldenExamItem? buildLocalGoldenExamItem(
  GoldenLesson lesson,
  List<GoldenTextMeta> sentences,
  String sentenceId,
) {
  GoldenSentence? content;
  GoldenTextMeta? sentence;
  for (final c in lesson.sentences) {
    if (c.id == sentenceId) content = c;
  }
  for (final s in sentences) {
    if (s.id == sentenceId) sentence = s;
  }
  return content != null && sentence != null
      ? makeLocalGoldenExamItem(content, sentence)
      : null;
}

/// 单点造句题：只要求用上一个词块，其余自由（与整句仿写互补）。
GoldenExamItem buildLangPointGoldenItem(
  GoldenTextMeta sentence, {
  required String en,
  String? zh,
}) {
  final key = en.toLowerCase().replaceAll(RegExp(r'\s+'), '-');
  return GoldenExamItem(
    id: '${goldenExamItemId(sentence.id)}:lp:$key',
    sentenceId: sentence.id,
    task: <String>[
      '用「$en」写一句英文：必须自然用上它，可以换主语或场景，不要照抄原句。',
      if (zh != null && zh.trim().isNotEmpty) '中文：$zh。',
    ].join(' '),
    model: sentence.text,
    mustUse: <String>[en],
    rubric: langPointGoldenRubric,
    source: GoldenItemSource.local,
    focus: en,
  );
}

/// 仿写考试出题提示词：只让 AI 出中文题干 + 必须用词，不重写范句。
class GoldenExamPromptSentence {
  const GoldenExamPromptSentence({
    required this.id,
    required this.text,
    this.translation,
    this.pattern,
    this.tense,
    this.targets = const <String>[],
  });

  final String id;
  final String text;
  final String? translation;
  final String? pattern;
  final String? tense;
  final List<String> targets;
}

String buildGoldenExamPrompt({
  String? title,
  required List<GoldenExamPromptSentence> sentences,
}) {
  final lines = sentences.map((s) {
    final tr = (s.translation ?? '').trim();
    final structure = (s.pattern ?? '').trim().isNotEmpty
        ? s.pattern!.trim()
        : (s.tense ?? '').trim();
    return <String>[
      s.id,
      s.text,
      if (tr.isNotEmpty) '译：$tr',
      if (structure.isNotEmpty) '结构：$structure',
      '词块：${s.targets.join('、')}',
    ].join('\t');
  });
  return <String>[
    '你是英语写作教练。下面这些句子是学生已经学过的；请为每句出一道「仿写考试题」。',
    '',
    '出题要求：',
    '- sentenceId 原样照抄句子编号；',
    '- task：中文题干，给出一个**新的情境/主语/内容**，让学生套用该句结构写英文；不要只让学生逐字翻译原句；',
    '- structure：一句话点出要迁移的句型 / 时态 / 语态；',
    '- mustUse：必须用上的已学词块（从输入词块里挑 2–4 个，必须是范句里逐字出现的片段）；',
    '- rubric：3–4 个评分维度，权重加起来 100（结构 / 用词 / 语法 / 意思）；',
    '- 不要改写范句，不要输出参考英文答案。',
    '',
    '只输出一个 JSON 对象，不要 Markdown、不要解释：',
    '{"items":[{"sentenceId":"s1","task":"...","structure":"...","mustUse":["..."],"rubric":[{"dimension":"结构运用","weight":35,"description":"..."}]}]}',
    '',
    if (title != null && title.trim().isNotEmpty) '文章标题：$title',
    '句子（id\t原文\t译文\t结构\t词块）：',
    ...lines,
  ].where((l) => l.isNotEmpty).join('\n');
}

String _stripFence(String raw) {
  final m = RegExp(r'```(?:json)?\s*([\s\S]*?)```', caseSensitive: false)
      .firstMatch(raw);
  return (m != null ? m.group(1)! : raw).trim();
}

/// 粘回的 AI 结果先去掉 ```json fence，再用括号深度扫描截出第一个完整 JSON。
Object? _extractJson(String raw) {
  final text = _stripFence(raw);
  if (text.isEmpty) return null;
  try {
    return jsonDecode(text);
  } catch (_) {
    final starts = <int>[text.indexOf('{'), text.indexOf('[')]
        .where((i) => i >= 0)
        .toList();
    if (starts.isEmpty) return null;
    final start = starts.reduce((a, b) => a < b ? a : b);
    final open = text[start];
    final close = open == '{' ? '}' : ']';
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
      } else if (c == open) {
        depth++;
      } else if (c == close) {
        depth--;
        if (depth == 0) {
          try {
            return jsonDecode(text.substring(start, i + 1));
          } catch (_) {
            return null;
          }
        }
      }
    }
    return null;
  }
}

/// AI / 备份 / 手改数据 → 可用的考试题；范句对不上、题面为空的条目直接丢弃。
List<GoldenExamItem> normalizeGoldenExam(
  Object? raw,
  List<GoldenTextMeta> sentences, [
  GoldenItemSource source = GoldenItemSource.ai,
]) {
  final List<Object?> list;
  if (raw is List) {
    list = raw;
  } else if (isGoldenObject(raw)) {
    final m = raw as Map;
    if (m['items'] is List) {
      list = m['items'] as List;
    } else if (m['exam'] is List) {
      list = m['exam'] as List;
    } else {
      list = const <Object?>[];
    }
  } else {
    list = const <Object?>[];
  }
  final byId = <String, GoldenTextMeta>{
    for (final s in sentences) s.id: s,
  };
  final out = <GoldenExamItem>[];
  final seen = <String>{};
  for (final item in list) {
    if (!isGoldenObject(item)) continue;
    final m = item as Map;
    final sentenceId = goldenStr(m['sentenceId']).isNotEmpty
        ? goldenStr(m['sentenceId'])
        : goldenStr(m['id']);
    final sentence = byId[sentenceId];
    if (sentence == null || !seen.add(sentenceId)) continue;
    final task = goldenStr(m['task']);
    if (task.isEmpty) continue;
    final model = sentence.text;
    final lower = model.toLowerCase();
    final mustUse = goldenStrList(m['mustUse'])
        .where((x) => lower.contains(x.toLowerCase()))
        .toList();
    final rubricRaw = m['rubric'] is List ? m['rubric'] as List : const <Object?>[];
    final rubric = <GoldenRubric>[];
    for (final r in rubricRaw) {
      if (!isGoldenObject(r)) continue;
      final rm = r as Map;
      final dimension = goldenStr(rm['dimension']);
      if (dimension.isEmpty) continue;
      final weight = _num(rm['weight']).clamp(0, 100).round();
      final desc = goldenStr(rm['description']);
      rubric.add(GoldenRubric(
        dimension: dimension,
        weight: weight,
        description: desc.isEmpty ? null : desc,
      ));
    }
    final id = goldenStr(m['id']);
    final itemSource = goldenStr(m['source']) == 'local'
        ? GoldenItemSource.local
        : source;
    final structure = goldenStr(m['structure']);
    out.add(GoldenExamItem(
      id: id.isEmpty ? goldenExamItemId(sentenceId) : id,
      sentenceId: sentenceId,
      task: task,
      model: model,
      structure: structure.isEmpty ? null : structure,
      mustUse: mustUse,
      rubric: rubric.isEmpty ? defaultGoldenRubric : rubric,
      source: itemSource,
    ));
  }
  return out;
}

List<GoldenExamItem> parseGoldenExam(String raw, List<GoldenTextMeta> sentences) {
  final obj = _extractJson(raw);
  if (obj == null) return const <GoldenExamItem>[];
  return normalizeGoldenExam(obj, sentences);
}

/// 转成现有仿写批改任务；题目、范句、必须用词都复用同一套结构。
ImitationTask examToImitation(GoldenExamItem item) => ImitationTask(
      task: item.task,
      model: item.model,
      structure: item.structure,
      mustUse: item.mustUse,
      rubric: item.rubric
          .map((r) => RubricItem(
                dimension: r.dimension,
                weight: r.weight,
                description: r.description,
              ))
          .toList(),
      focus: item.focus,
    );

/// 批改提示词：语义上就是「仿写批改」，直接复用核心提示词，避免第二套口径。
String buildGoldenExamFeedbackPrompt(
  GoldenExamItem item,
  String answer, [
  WritingFeedbackPromptOptions options = const WritingFeedbackPromptOptions(),
]) =>
    buildWritingFeedbackPrompt(examToImitation(item), answer, options);

/// 防止重复的旧考试记录被当成普通仿写历史：调用方按这个筛选。
bool isGoldenExamRecord(WritingSource? source) =>
    source == WritingSource.goldenExam;

/// 只保留还存在的句子；改正文/重新选句后旧题自动淘汰。
List<GoldenExamItem>? pruneGoldenExam(
  List<GoldenExamItem>? items,
  List<GoldenTextMeta> sentences,
) {
  if (items == null || items.isEmpty) return null;
  final byId = <String, GoldenTextMeta>{
    for (final s in sentences) s.id: s,
  };
  final next = items.where((item) {
    final s = byId[item.sentenceId];
    return s != null && s.text == item.model;
  }).toList();
  return next.isEmpty ? null : next;
}
