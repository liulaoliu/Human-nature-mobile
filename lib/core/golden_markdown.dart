/// 本课素材导出 Markdown（对应 Web `src/core/goldenMarkdown.ts`）。
///
/// 干净 Markdown，方便贴到 Notion / 写作素材库。纯函数：不碰存储、不带 UI。
library;

import 'golden.dart';
import 'golden_progress.dart' show GoldenDrillRecord;

String _mdText(String s) => s.replaceAll('\r', '').replaceAll('`', r'\`');

String _sectionLabel(GoldenSectionRole role) => switch (role) {
      GoldenSectionRole.intro => '开头段',
      GoldenSectionRole.conclusion => '结尾段',
      GoldenSectionRole.body => '主体段',
    };

/// 把一课金句导成 Markdown。
///
/// [title] 缺省「D老师小课堂」；[sentences] 是当前文章正文（用来算 drillKey）；
/// [records] + [articleId] + [includeProgress] 同时给才会在标题后打勾 ——
/// 默认不带，避免把学习状态混进素材。
String goldenToMarkdown(
  GoldenLesson lesson, {
  String? title,
  List<GoldenTextMeta>? sentences,
  List<GoldenDrillRecord>? records,
  String? articleId,
  bool includeProgress = false,
}) {
  final textOf = <String, String>{
    for (final s in sentences ?? const <GoldenTextMeta>[]) s.id: s.text,
  };
  final progress = <String, GoldenDrillRecord>{
    for (final r in records ?? const <GoldenDrillRecord>[])
      if (articleId == null || r.articleId == articleId)
        '${r.sentenceId}|${r.drillKey}': r,
  };
  final lines = <String>[];
  lines.add('# ${_mdText(title ?? 'D老师小课堂')}');
  final summary = lesson.summary;
  if (summary != null && summary.isNotEmpty) {
    lines
      ..add('')
      ..add(_mdText(summary));
  }
  if (lesson.outline.isNotEmpty) {
    lines
      ..add('')
      ..add('## 本篇脉络');
    for (final sec in lesson.outline) {
      lines
        ..add('')
        ..add('### ${_sectionLabel(sec.role)}');
      for (final p in sec.points) {
        lines.add('- ${_mdText(p)}');
      }
    }
  }
  lines
    ..add('')
    ..add('## 金句');
  for (final s in lesson.sentences) {
    final text = textOf[s.id] ?? '';
    final rec = progress['${s.id}|${goldenDrillKey(text, s.targets)}'];
    final mark = includeProgress && rec != null && rec.mastered ? ' ✅' : '';
    lines
      ..add('')
      ..add('### ${s.id}$mark');
    if (text.isNotEmpty) {
      lines
        ..add('')
        ..add('**${_mdText(text)}**');
    }
    final zh = s.zh;
    if (zh != null && zh.isNotEmpty) {
      lines
        ..add('')
        ..add(_mdText(zh));
    }
    final pattern = s.pattern;
    if (pattern != null && pattern.isNotEmpty) {
      lines
        ..add('')
        ..add('- 句型：${_mdText(pattern)}');
    }
    final tense = s.tense;
    if (tense != null && tense.isNotEmpty) {
      lines.add('- 时态：${_mdText(tense)}');
    }
    final note = s.note;
    if (note != null && note.isNotEmpty) {
      lines.add('- 用法：${_mdText(note)}');
    }
    if (s.targets.isNotEmpty) {
      lines
        ..add('')
        ..add('**学习点**');
      for (final t in s.targets) {
        final zhOfTarget = t.zh;
        final suffix = zhOfTarget == null || zhOfTarget.isEmpty
            ? ''
            : ' — ${_mdText(zhOfTarget)}';
        lines.add('- ${goldenTargetKindLabel[t.kind]}：${_mdText(t.en)}$suffix');
      }
    }
    final extras = (lesson.extraPoints ?? const <GoldenExtraPoint>[])
        .where((p) => p.sentenceId == s.id)
        .toList(growable: false);
    if (extras.isNotEmpty) {
      lines
        ..add('')
        ..add('**加练语言点**');
      for (final p in extras) {
        final zhOfExtra = p.zh;
        final suffix =
            zhOfExtra == null || zhOfExtra.isEmpty ? '' : ' — ${_mdText(zhOfExtra)}';
        lines.add('- ${_mdText(p.en)}$suffix');
      }
    }
  }
  return '${lines.join('\n').trim()}\n';
}
