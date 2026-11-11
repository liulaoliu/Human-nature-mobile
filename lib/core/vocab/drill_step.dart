/// 「强制锤炼」的三小步：拼写 → 选义 → 写搭配（纯函数）。
///
/// 什么时候该锤炼由 `drill.dart` 的 [drillReason] 判；这里只回答两个问题：
/// **要过哪几步**、**每步怎么判对**。
///
/// 与 Web 版 `src/reader/panels/StudyDrill.tsx` 的 `buildSteps` / `DRILL_HEAD` 一一对应。
library;

import '../../models/vocab.dart';
import 'drill.dart';
import 'review.dart';

/// 锤炼的一步。
enum DrillStep { spell, meaning, usage }

/// 锤炼面板的标题与说明（两种来路的措辞不同，混成一句用户会以为是自己点错了）。
class DrillHead {
  const DrillHead({required this.title, required this.hint});

  final String title;
  final String hint;
}

/// 按来路给标题：超时 / 重学补考。
DrillHead drillHeadOf(DrillReason reason) => switch (reason) {
      DrillReason.timeout => const DrillHead(
          title: '⏱ 超时锤炼',
          hint: '这张卡停太久了 · 过完才能评分',
        ),
      DrillReason.relearn => const DrillHead(
          title: '♻️ 重学补考',
          hint: '忘过 / 标过「不认识」· 过完才按你点的分记',
        ),
    };

/// 这张卡要过哪几步（按固定顺序：拼写 → 选义 → 写搭配）。
///
/// 缺什么就跳什么：没释义出不了选义题，没搭配就写不出搭配。
List<DrillStep> buildDrillSteps(VocabItem card, List<VocabItem> items) {
  final steps = <DrillStep>[];
  if (card.word.trim().isNotEmpty) steps.add(DrillStep.spell);
  if (canQuizMeaning(card, items)) steps.add(DrillStep.meaning);
  if (collocationsOf(card).isNotEmpty) steps.add(DrillStep.usage);
  return steps;
}

/// 可以拿来考「写搭配」的原文：用法在前，词组在后（与 Web 同序）。
List<String> collocationsOf(VocabItem card) => <String>[
      ...card.usage.map((s) => s.trim()).where((s) => s.isNotEmpty),
      ...(card.phrases ?? const <String>[]).map((s) => s.trim()).where((s) => s.isNotEmpty),
    ];

/// 写搭配判对：写的内容**包含**某个搭配（长度 ≥ 3）就算过。
///
/// 为什么用包含而不是相等：这一关考的是「你还记得它怎么用」，写整句也行。
/// 太短的（比如 `to`）不参与匹配，否则随便打两个字就过。
bool matchesCollocation(String typed, List<String> collocations) {
  final input = _norm(typed);
  if (input.isEmpty) return false;
  for (final c in collocations) {
    final target = _norm(c);
    if (target.length < 3) continue;
    if (input.contains(target)) return true;
  }
  return false;
}

String _norm(String s) =>
    s.trim().toLowerCase().replaceAll(RegExp(r'[\s\u3000]+'), ' ');
