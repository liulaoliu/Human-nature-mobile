/// 全库金句本（对应 Web `src/core/goldenBank.ts`）：把每篇的 `SavedArticle.golden`
/// 摊平成可搜索、可筛选、可导出的行。
///
/// 事实来源仍是文章里的 golden + 学习记录里的 goldenDrills；这里只读、不写。
/// 默认按文章标题 / 原文顺序排，方便当成写作素材库。
library;

import 'activity/activity.dart' show dayKeyLocal;
import 'golden.dart';
import 'golden_progress.dart';
import 'print_html.dart';

/// 金句本的一篇文章来源。
class GoldenBankSource {
  const GoldenBankSource({
    required this.id,
    required this.title,
    required this.sentences,
    this.golden,
  });

  /// 稳定文章标识：已保存用 `SavedArticle.id`，当前未保存用 articleKey / title。
  final String id;
  final String title;
  final List<GoldenTextMeta> sentences;
  final GoldenLesson? golden;
}

/// 金句本的一行 = 一句金句 + 它的掌握状态。
class GoldenBankRow {
  const GoldenBankRow({
    required this.articleId,
    required this.articleTitle,
    required this.sentenceId,
    required this.text,
    this.zh,
    this.pattern,
    this.tense,
    this.note,
    required this.targets,
    required this.mastered,
    this.lastAt,
    required this.due,
  });

  final String articleId;
  final String articleTitle;
  final String sentenceId;
  final String text;
  final String? zh;
  final String? pattern;
  final String? tense;
  final String? note;
  final List<GoldenTarget> targets;
  final bool mastered;

  /// 最近一次学习 / 回顾时间（ISO）。
  final String? lastAt;

  /// 已掌握、但今天还没回顾。
  final bool due;
}

/// 状态筛选。
enum GoldenBankStatus { all, todo, mastered, due }

/// 按「学习点类型」筛：一句里只要有一个该类型的学习点就算命中。
///
/// 金句页的主要噪音来源是「这句我要找的是搭配 / 句型」，按状态筛不解决问题。
enum GoldenBankKind { all, pattern, tense, collocation, idiom, usage, word }

const Map<GoldenBankStatus, String> goldenBankStatusLabel =
    <GoldenBankStatus, String>{
  GoldenBankStatus.all: '全部',
  GoldenBankStatus.todo: '还没掌握',
  GoldenBankStatus.mastered: '已掌握',
  GoldenBankStatus.due: '待回顾',
};

const Map<GoldenBankKind, String> goldenBankKindLabel = <GoldenBankKind, String>{
  GoldenBankKind.all: '全部类型',
  GoldenBankKind.pattern: '句型',
  GoldenBankKind.tense: '时态',
  GoldenBankKind.collocation: '搭配',
  GoldenBankKind.idiom: '习语',
  GoldenBankKind.usage: '用法',
  GoldenBankKind.word: '单词',
};

/// `GoldenBankKind` → `GoldenTargetKind`；`all` 返 null。
GoldenTargetKind? goldenBankKindOf(GoldenBankKind kind) => switch (kind) {
      GoldenBankKind.all => null,
      GoldenBankKind.pattern => GoldenTargetKind.pattern,
      GoldenBankKind.tense => GoldenTargetKind.tense,
      GoldenBankKind.collocation => GoldenTargetKind.collocation,
      GoldenBankKind.idiom => GoldenTargetKind.idiom,
      GoldenBankKind.usage => GoldenTargetKind.usage,
      GoldenBankKind.word => GoldenTargetKind.word,
    };

/// 摊平所有文章的金句；没有 golden 的文章不出现。
List<GoldenBankRow> buildGoldenBank(
  List<GoldenBankSource> sources,
  List<GoldenDrillRecord> records, [
  DateTime? now,
]) {
  //  传进来可能是 UTC（测试 / 备份恢复），必须先落本地时区再取日期键，
  //  否则和 `goldenReviewDue` 里的 `at.toLocal()` 两套口径对不上。
  final today = dayKeyLocal(now?.toLocal());
  final rows = <GoldenBankRow>[];
  for (final source in sources) {
    final lesson = source.golden;
    if (lesson == null) continue;
    final byId = <String, GoldenTextMeta>{
      for (final s in source.sentences) s.id: s,
    };
    final selected = lesson.selected.isNotEmpty
        ? lesson.selected
        : lesson.sentences.map((s) => s.id).toList();
    for (final id in selected) {
      GoldenSentence? content;
      for (final s in lesson.sentences) {
        if (s.id == id) {
          content = s;
          break;
        }
      }
      final sentence = byId[id];
      if (content == null || sentence == null) continue;
      final targets = goldenTargetsFor(lesson, id);
      final rec =
          findGoldenRecord(records, source.id, id, goldenDrillKey(sentence.text, targets));
      final zh = content.zh ?? sentence.translation;
      rows.add(GoldenBankRow(
        articleId: source.id,
        articleTitle: source.title.isEmpty ? '未命名' : source.title,
        sentenceId: id,
        text: sentence.text,
        zh: (zh == null || zh.isEmpty) ? null : zh,
        pattern: content.pattern,
        tense: content.tense,
        note: content.note,
        targets: targets,
        mastered: rec?.mastered == true,
        lastAt: rec?.at,
        due: goldenReviewDue(rec, today),
      ));
    }
  }
  final order = <String, int>{
    for (var i = 0; i < sources.length; i++) sources[i].id: i,
  };
  rows.sort((a, b) {
    final byArticle =
        (order[a.articleId] ?? 0).compareTo(order[b.articleId] ?? 0);
    return byArticle != 0 ? byArticle : a.sentenceId.compareTo(b.sentenceId);
  });
  return List<GoldenBankRow>.unmodifiable(rows);
}

/// 金句本搜索 / 状态筛选；不改变原列表。
List<GoldenBankRow> filterGoldenBank(
  List<GoldenBankRow> rows, {
  String? query,
  GoldenBankStatus status = GoldenBankStatus.all,
  GoldenBankKind kind = GoldenBankKind.all,
}) {
  final q = (query ?? '').trim().toLowerCase();
  final wantKind = goldenBankKindOf(kind);
  return List<GoldenBankRow>.unmodifiable(rows.where((r) {
    if (status == GoldenBankStatus.mastered && !r.mastered) return false;
    if (status == GoldenBankStatus.todo && r.mastered) return false;
    if (status == GoldenBankStatus.due && !r.due) return false;
    if (wantKind != null && !r.targets.any((t) => t.kind == wantKind)) {
      return false;
    }
    if (q.isEmpty) return true;
    final hay = <String>[
      r.text,
      ?r.zh,
      ?r.pattern,
      ?r.tense,
      ?r.note,
      for (final t in r.targets) '${t.en} ${t.zh ?? ''}',
    ].where((s) => s.isNotEmpty).join(' ').toLowerCase();
    return hay.contains(q);
  }));
}

String _mdText(String s) => s.replaceAll('\r', '').replaceAll('`', r'\`');

/// 金句本导出 Markdown：按文章分组，方便贴进写作素材库。
String goldenBankToMarkdown(
  List<GoldenBankRow> rows, [
  String title = '全库金句本',
]) {
  final mastered = rows.where((r) => r.mastered).length;
  final lines = <String>[
    '# ${_mdText(title)}',
    '',
    '共 ${rows.length} 句 · $mastered 句已掌握',
  ];
  var current = '';
  for (final r in rows) {
    if (r.articleTitle != current) {
      current = r.articleTitle;
      lines
        ..add('')
        ..add('## ${_mdText(current)}');
    }
    lines
      ..add('')
      ..add('### ${r.mastered ? '✅ ' : ''}${r.sentenceId}')
      ..add('')
      ..add('**${_mdText(r.text)}**');
    final zh = r.zh;
    if (zh != null && zh.isNotEmpty) {
      lines
        ..add('')
        ..add(_mdText(zh));
    }
    final pattern = r.pattern;
    if (pattern != null && pattern.isNotEmpty) {
      lines
        ..add('')
        ..add('- 句型：${_mdText(pattern)}');
    }
    final tense = r.tense;
    if (tense != null && tense.isNotEmpty) {
      lines.add('- 时态：${_mdText(tense)}');
    }
    final note = r.note;
    if (note != null && note.isNotEmpty) {
      lines.add('- 用法：${_mdText(note)}');
    }
    if (r.targets.isNotEmpty) {
      lines
        ..add('')
        ..add('**学习点**');
      for (final t in r.targets) {
        final zhOfTarget = t.zh;
        final suffix = (zhOfTarget == null || zhOfTarget.isEmpty)
            ? ''
            : ' — ${_mdText(zhOfTarget)}';
        lines.add('- ${goldenTargetKindLabel[t.kind]}：${_mdText(t.en)}$suffix');
      }
    }
  }
  return '${lines.join('\n').trim()}\n';
}

String _csvField(String s) =>
    RegExp(r'[",\n\r]').hasMatch(s) ? '"${s.replaceAll('"', '""')}"' : s;

/// 金句本 A4 讲义：两栏密排，打印后就是一张写作素材纸。
String goldenBankToPrintHtml(
  List<GoldenBankRow> rows, [
  String title = '全库金句本',
]) {
  final mastered = rows.where((r) => r.mastered).length;
  final body = StringBuffer();
  for (final r in rows) {
    final targets = r.targets
        .map((t) =>
            '${goldenTargetKindLabel[t.kind]} ${escapeHtml(t.en)}'
            '${t.zh == null || t.zh!.isEmpty ? '' : '（${escapeHtml(t.zh!)}）'}')
        .join('；');
    body.write('<div class="item">\n'
        '        <div class="head">${r.mastered ? '✅ ' : ''}'
        '${escapeHtml(r.articleTitle)} · ${escapeHtml(r.sentenceId)}</div>\n'
        '        <div class="en">${escapeHtml(r.text)}</div>\n');
    if (r.zh != null && r.zh!.isNotEmpty) {
      body.write('        <div class="zh">${escapeHtml(r.zh!)}</div>\n');
    }
    if (r.pattern != null && r.pattern!.isNotEmpty) {
      body.write('        <div class="note">句型：${escapeHtml(r.pattern!)}</div>\n');
    }
    if (r.tense != null && r.tense!.isNotEmpty) {
      body.write('        <div class="note">时态：${escapeHtml(r.tense!)}</div>\n');
    }
    if (targets.isNotEmpty) {
      body.write('        <div class="note">学习点：$targets</div>\n');
    }
    body.write('      </div>');
  }
  return a4Document(
    title: title,
    margin: '10mm',
    fontSize: '9pt',
    lineHeight: '1.4',
    css: '''h1 { font-size: 14pt; margin: 0 0 2mm; }
.meta { color: #666; font-size: 8pt; margin: 0 0 3mm; }
.items { columns: 2; column-gap: 6mm; column-rule: .3pt solid #ddd; }
.item { break-inside: avoid; margin: 0 0 3mm; }
.head { color: #666; font-size: 7.5pt; }
.en { font-weight: 600; margin-top: .5mm; }
.zh { color: #333; }
.note { color: #555; font-size: 8pt; }''',
    body: '<h1>${escapeHtml(title)}</h1>\n'
        '<div class="meta">共 ${rows.length} 句 · $mastered 句已掌握</div>\n'
        '<div class="items">$body</div>',
  );
}

/// 金句本导出 Anki CSV：正面整句，背面中文 + 句型 / 时态 + 学习点。
String goldenBankToAnkiCsv(List<GoldenBankRow> rows, {bool header = true}) {
  final out = <String>[if (header) 'Front,Back,Tags'];
  for (final r in rows) {
    final back = <String>[
      r.zh ?? '',
      if (r.pattern != null && r.pattern!.isNotEmpty) '句型：${r.pattern}',
      if (r.tense != null && r.tense!.isNotEmpty) '时态：${r.tense}',
      if (r.targets.isNotEmpty)
        '学习点：${r.targets.map((t) => '${goldenTargetKindLabel[t.kind]} ${t.en}'
            '${t.zh == null || t.zh!.isEmpty ? '' : '（${t.zh}）'}').join('；')}',
    ].where((s) => s.isNotEmpty).join('<br>');
    final tags = <String>['golden', r.articleTitle]
        .map((t) => t.replaceAll(RegExp(r'\s+'), '_').replaceAll(',', '_'))
        .join(' ');
    out.add(<String>[r.text, back, tags].map(_csvField).join(','));
  }
  return '${out.join('\n')}${out.isEmpty ? '' : '\n'}';
}
