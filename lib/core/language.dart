/// 逐句语言点分析：AI 结构化输出「结构 / 语法 / idiom / 词组 / 用法」，写回句子。
///
/// 写的地基：先把每个句子的语言点讲清楚，之后仿写才有依据。
/// 提示词要求严格 JSON；解析层校验并丢弃不合格项。
///
/// 对应 Web 版 `src/core/language.ts`。
library;

import 'dart:convert';

import '../models/document.dart';

/// 带句子 id 的一行语言点（AI 输出、按句写回时用）。
class LanguageRow {
  const LanguageRow({
    required this.id,
    this.structure,
    this.grammar,
    this.idioms,
    this.phrases,
    this.usage,
  });

  final String id;
  final String? structure;
  final String? grammar;
  final List<String>? idioms;
  final List<String>? phrases;
  final List<String>? usage;
}

/// 编辑器里的五个文本字段（与 [SentenceLanguage] 的文本字段一一对应）。
class LanguageForm {
  const LanguageForm({
    this.structure = '',
    this.grammar = '',
    this.idioms = '',
    this.phrases = '',
    this.usage = '',
  });

  final String structure;
  final String grammar;
  final String idioms;
  final String phrases;
  final String usage;

  @override
  bool operator ==(Object other) =>
      other is LanguageForm &&
      other.structure == structure &&
      other.grammar == grammar &&
      other.idioms == idioms &&
      other.phrases == phrases &&
      other.usage == usage;

  @override
  int get hashCode => Object.hash(structure, grammar, idioms, phrases, usage);

  @override
  String toString() =>
      'LanguageForm($structure | $grammar | $idioms | $phrases | $usage)';
}

/// 空表单。
const LanguageForm emptyLanguageForm = LanguageForm();

final RegExp _listSplit = RegExp(r'[；;、\n]+');

/// 列表字段：支持「；/;/、/换行」分隔，去空、去重（换行也算分隔，多行输入不用手动写分号）。
List<String> splitLanguageList(String s) {
  final seen = <String>{};
  final out = <String>[];
  for (final raw in s.split(_listSplit)) {
    final t = raw.trim();
    if (t.isEmpty || !seen.add(t)) continue;
    out.add(t);
  }
  return out;
}

/// 老数据里列表字段可能是「；/换行」连成的字符串；统一成去重后的数组。
List<String>? _termsOf(Object? v) {
  if (v is List) {
    final out = <String>[];
    for (final x in v) {
      if (x is! String) continue;
      final t = x.trim();
      if (t.isNotEmpty) out.add(t);
    }
    return out.isEmpty ? null : out;
  }
  if (v is String) {
    final out = splitLanguageList(v);
    return out.isEmpty ? null : out;
  }
  return null;
}

/// 一条语言点的兼容层：老数据（单条 `language`、列表字段是字符串、缺字段）与
/// AI / 手动写入的新数据都归一成 [SentenceLanguage]；没内容的返回 null。
///
/// **编辑旧数据就靠这里**：视图只吃归一后的结果，`languageToForm` 不用再判断老形状。
/// 结构 / 语法只裁掉「全是空白」的，内部换行与行首缩进原样保留（粘贴格式要能显示）。
SentenceLanguage? normalizeLanguage(SentenceLanguage? raw) {
  if (raw == null) return null;
  return _buildLanguage(
    structure: raw.structure,
    grammar: raw.grammar,
    idioms: raw.idioms,
    phrases: raw.phrases,
    usage: raw.usage,
    source: raw.source,
    at: raw.at,
  );
}

/// 同上，但输入是**没经过守卫的原始 JSON**（`backup_parse` 之类的地方用）。
/// 列表字段写成字符串（「；/换行」连起来）也认。
SentenceLanguage? normalizeLanguageRaw(Object? raw) {
  if (raw is SentenceLanguage) return normalizeLanguage(raw);
  if (raw is! Map) return null;
  final sourceRaw = raw['source'];
  return _buildLanguage(
    structure: raw['structure'] is String ? raw['structure'] as String : null,
    grammar: raw['grammar'] is String ? raw['grammar'] as String : null,
    idioms: _termsOf(raw['idioms']),
    phrases: _termsOf(raw['phrases']),
    usage: _termsOf(raw['usage']),
    source: sourceRaw is String ? LanguageSource.values.where((s) => s.name == sourceRaw).firstOrNull : null,
    at: raw['at'] is String ? raw['at'] as String : null,
  );
}

SentenceLanguage? _buildLanguage({
  String? structure,
  String? grammar,
  List<String>? idioms,
  List<String>? phrases,
  List<String>? usage,
  LanguageSource? source,
  String? at,
}) {
  final st = structure ?? '';
  final gr = grammar ?? '';
  final hasIdioms = idioms != null && idioms.isNotEmpty;
  final hasPhrases = phrases != null && phrases.isNotEmpty;
  final hasUsage = usage != null && usage.isNotEmpty;
  if (st.trim().isEmpty && gr.trim().isEmpty && !hasIdioms && !hasPhrases && !hasUsage) {
    return null;
  }
  return SentenceLanguage(
    structure: st.trim().isEmpty ? null : st,
    grammar: gr.trim().isEmpty ? null : gr,
    idioms: hasIdioms ? idioms : null,
    phrases: hasPhrases ? phrases : null,
    usage: hasUsage ? usage : null,
    source: source,
    at: (at ?? '').isEmpty ? null : at,
  );
}

/// 取该句所有语言点（兼容旧的单条 `language`；旧的按 AI 来源算；空对象不计）。
List<SentenceLanguage> getSentenceLanguages(Sentence? s) {
  if (s == null) return const [];
  final List<SentenceLanguage> raw;
  final list = s.languages;
  if (list != null && list.isNotEmpty) {
    raw = list;
  } else if (s.language != null) {
    final legacy = s.language!;
    raw = [
      SentenceLanguage(
        structure: legacy.structure,
        grammar: legacy.grammar,
        idioms: legacy.idioms,
        phrases: legacy.phrases,
        usage: legacy.usage,
        source: legacy.source ?? LanguageSource.ai,
        at: legacy.at,
      ),
    ];
  } else {
    raw = const [];
  }
  final out = <SentenceLanguage>[];
  for (final l in raw) {
    final n = normalizeLanguage(l);
    if (n != null) out.add(n);
  }
  return out;
}

/// 该句是否有语言点（AI 或手动）。
bool hasSentenceLanguage(Sentence? s) => getSentenceLanguages(s).isNotEmpty;

/// 粘贴清洗：**只去掉空行，保留每行的行首缩进与单换行**。
///
/// 语言点大多从网页 / AI 回答里复制，常见「一行正文一行空行」，保存后正文里
/// 会把空行原样显示，行距被撑得很散；这里把空行吃掉。
/// 行首缩进是用户有意保留的层级信息（列表 / 代码块），**只清行尾空白，不动行首**。
String cleanPastedText(String raw) {
  final lines = raw.replaceAll(RegExp(r'\r\n?'), '\n').split('\n');
  final out = <String>[];
  for (final line in lines) {
    final trimmedTail = line.replaceAll(RegExp(r'[ \t]+$'), '');
    if (trimmedTail.trim().isEmpty) continue;
    out.add(trimmedTail);
  }
  return out.join('\n');
}

/// 表单 → 一条语言点；空字段不写，全空返回「没内容」的 [SentenceLanguage]。
///
/// 结构 / 语法保留原始换行与缩进，只把「全是空白」当没填。
SentenceLanguage languageFromForm(LanguageForm f) {
  final idioms = splitLanguageList(f.idioms);
  final phrases = splitLanguageList(f.phrases);
  final usage = splitLanguageList(f.usage);
  return SentenceLanguage(
    structure: f.structure.trim().isEmpty ? null : f.structure,
    grammar: f.grammar.trim().isEmpty ? null : f.grammar,
    idioms: idioms.isEmpty ? null : idioms,
    phrases: phrases.isEmpty ? null : phrases,
    usage: usage.isEmpty ? null : usage,
  );
}

/// 表单控件显示用：老数据即使是字符串 / 缺字段，也返回可编辑的文本。
String _formText(Object? v) {
  if (v is String) return v;
  if (v is List) {
    final out = <String>[];
    for (final x in v) {
      if (x is! String) continue;
      final t = x.trim();
      if (t.isNotEmpty) out.add(t);
    }
    return out.join('；');
  }
  return '';
}

/// 一条语言点 → 表单（列表用「；」连起来，编辑时仍可换成多行）。
LanguageForm languageToForm(SentenceLanguage? l) => LanguageForm(
      structure: _formText(l?.structure),
      grammar: _formText(l?.grammar),
      idioms: _formText(l?.idioms),
      phrases: _formText(l?.phrases),
      usage: _formText(l?.usage),
    );

final RegExp _multiNewline = RegExp(r'\s*\n+\s*');

/// 列表里的一行摘要：结构/语法里的换行压成空格，避免把列表撑高。
String languagePreview(SentenceLanguage l) {
  String oneLine(Object? s) =>
      (s is String ? s : '').replaceAll(_multiNewline, ' ').trim();
  return <String>[
    oneLine(l.structure),
    oneLine(l.grammar),
    ...?_termsOf(l.idioms),
    ...?_termsOf(l.phrases),
    ...?_termsOf(l.usage),
  ].where((s) => s.isNotEmpty).join(' ｜ ');
}

/// 出题提示词：按句 id 逐句分析，严格 JSON。
String buildLanguagePrompt(List<({String id, String text})> sentences) {
  final list = sentences.map((s) => '${s.id} | ${s.text}').join('\n');
  return <String>[
    '你是英语精读老师。请对下面每个句子做**语言点分析**，用于写作训练。',
    '',
    '每个句子输出一个对象，字段固定：',
    '- id：原样照抄句子编号；',
    '- structure：一句话点出句子主干与修饰结构（主句 + 从句/非谓语/插入语等）；',
    '- grammar：1–2 条最值得记的语法点（时态、语态、虚拟、倒装、比较……），只说句子真实用到的，不要泛泛而谈；',
    '- idioms：句中的习语（格式：**英文 — 简短中文**，如 take its toll — 造成损害；没有就给空数组）；',
    '- phrases：值得学的词组 / 搭配（格式：**英文 — 简短中文**，如 fall back on — 转而依靠；没有就给空数组）；',
    '- usage：这些词的用法要点（中文，简短，没有就给空数组）。',
    '',
    '要求：只分析真实出现、值得记的点；不要复述句意，不要翻译整句，不要编造。',
    '只输出一个 JSON 对象，格式：',
    '{"sentences":[{"id":"s001","structure":"...","grammar":"...","idioms":["take its toll — 造成损害"],"phrases":["fall back on — 转而依靠"],"usage":["..."]}]}',
    '不要输出其它任何文字。',
    '',
    '句子：',
    list,
  ].join('\n');
}

String _asString(Object? v) => v is String ? v.trim() : '';

List<String>? _asStringArray(Object? v) {
  if (v is! List) return null;
  final out = <String>[];
  for (final x in v) {
    final s = _asString(x);
    if (s.isNotEmpty) out.add(s);
  }
  return out.isEmpty ? null : out;
}

final RegExp _fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```', caseSensitive: false);

String _stripFence(String raw) {
  final m = _fence.firstMatch(raw);
  return (m != null ? m[1]! : raw).trim();
}

/// 从一段文本里抠出第一个「配平的」JSON 对象（忽略前后废话/说明）。
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

/// 修掉 JSON 里非法的反斜杠转义（模型偶发把 [ ] 写成 \( \) 或 \[ \]）。
String _sanitizeJson(String s) => s
    .replaceAll(r'\(', '[')
    .replaceAll(r'\)', ']')
    .replaceAll(r'\[', '[')
    .replaceAll(r'\]', ']')
    .replaceAll(RegExp(r'\\(?![\\"/bfnrtu])'), '');

/// 从解析出的对象里抽出语言点行（每条至少要有 structure/grammar/idioms/phrases/usage 之一）。
List<LanguageRow> _rowsFrom(Object? parsed) {
  final List<Object?> list;
  if (parsed is List) {
    list = parsed;
  } else if (parsed is Map && parsed['sentences'] is List) {
    list = (parsed['sentences'] as List).cast<Object?>();
  } else {
    return const [];
  }
  final out = <LanguageRow>[];
  for (final item in list) {
    if (item is! Map) continue;
    final id = _asString(item['id'] ?? item['sentenceId']);
    if (id.isEmpty) continue;
    final structure = _asString(item['structure']);
    final grammar = _asString(item['grammar']);
    final idioms = _asStringArray(item['idioms']);
    final phrases = _asStringArray(item['phrases']);
    final usage = _asStringArray(item['usage']);
    if (structure.isEmpty &&
        grammar.isEmpty &&
        idioms == null &&
        phrases == null &&
        usage == null) {
      continue;
    }
    out.add(LanguageRow(
      id: id,
      structure: structure.isEmpty ? null : structure,
      grammar: grammar.isEmpty ? null : grammar,
      idioms: idioms,
      phrases: phrases,
      usage: usage,
    ));
  }
  return out;
}

/// 解析并校验语言点。宽容多种写法：代码围栏、前后夹说明、非法反斜杠转义。
/// 每条至少要有 structure/grammar/idioms/phrases/usage 之一，否则丢弃。
List<LanguageRow> parseLanguage(String raw) {
  final text = _stripFence(raw);
  if (text.isEmpty) return const [];
  final balanced = _extractJsonObject(text);
  final candidates = <String>[
    text,
    ?balanced,
    _sanitizeJson(text),
    if (balanced != null) _sanitizeJson(balanced),
  ];
  for (final c in candidates) {
    try {
      final rows = _rowsFrom(jsonDecode(c));
      if (rows.isNotEmpty) return rows;
    } on FormatException {
      // 试下一个
    }
  }
  return const [];
}

/// 把语言点写回句子（按 id 匹配）：**替换/AI 生成的那条，保留手动添加的若干条**。
List<Sentence> applyLanguage(
  List<Sentence> sentences,
  List<LanguageRow> rows, {
  DateTime? now,
}) {
  if (rows.isEmpty) return sentences;
  final at = (now ?? DateTime.now()).toUtc().toIso8601String();
  final byId = {for (final r in rows) r.id: r};
  final out = <Sentence>[];
  for (final s in sentences) {
    final r = byId[s.id];
    if (r == null) {
      out.add(s);
      continue;
    }
    final ai = SentenceLanguage(
      structure: r.structure,
      grammar: r.grammar,
      idioms: r.idioms,
      phrases: r.phrases,
      usage: r.usage,
      source: LanguageSource.ai,
      at: at,
    );
    final manual = getSentenceLanguages(s)
        .where((x) => x.source == LanguageSource.manual)
        .toList();
    out.add(s.copyWith(
      languages: () => [ai, ...manual],
      language: () => null,
    ));
  }
  return out;
}
