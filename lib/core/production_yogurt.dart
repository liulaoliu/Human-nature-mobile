/// 风味酸奶的「逐句对子」与会话里 prompt 数组之间的换算。
///
/// 会话一开始把对子编译成 prompts（`buildYogurtPromptsFromPairs`），此后界面只认 prompts。
/// 但断句是**可以随时改的**（做了一半发现这句应该拆开 / 两句该并成一句），
/// 改完就得重新编译 prompts，同时尽量把「当前这题」留在原处，别让进度乱跳。
///
/// 对应 Web 版 `src/core/productionYogurt.ts`（76 行）。
library;

import 'production.dart';
import 'production_prompts.dart';

/// 逐句题目的 id 前缀。
const String yogurtPromptPrefix = 'yogurt-';

/// 整段连写那一题的 id。
const String yogurtParagraphId = 'yogurt-paragraph';

/// 逐句那一题（整段连写不算对子）。
bool isYogurtPairPrompt(ProductionPrompt prompt) =>
    prompt.id.startsWith(yogurtPromptPrefix) && prompt.id != yogurtParagraphId;

/// 从会话 prompts 反推逐句对子；整段连写那一题不在里面。
List<YogurtPair> yogurtPairsOf(List<ProductionPrompt> prompts) => <YogurtPair>[
      for (final prompt in prompts.where(isYogurtPairPrompt))
        YogurtPair(source: prompt.zh, reference: prompt.reference ?? ''),
    ];

/// 比对用的键：只忽略首尾和连续空白；标点改动仍算不同一句。
String yogurtTextKey(String text) => text.trim().replaceAll(RegExp(r'\s+'), ' ');

/// 改断句后重编译的结果。
class YogurtRemapResult {
  const YogurtRemapResult({
    required this.prompts,
    required this.index,
    this.warning = '',
  });

  final List<ProductionPrompt> prompts;

  /// 改完断句后停在第几题：仍然停在同一句上；那句被合并 / 删掉就退到原位置。
  final int index;
  final String warning;
}

/// 中途改断句：按新的对子重编译 prompts，并尽量保住当前题号。
///
/// 定位顺序：先按「当前这题的原文」找同一句 → 找不到（被合并 / 删掉 / 改写了）就退到原下标，
/// 再夹到合法范围。返回 null 表示一对有内容的都没有，界面不该应用这次修改。
YogurtRemapResult? remapYogurtPrompts(
  List<ProductionPrompt> oldPrompts,
  int index,
  List<YogurtPair> pairs, {
  ProductionDirection direction = ProductionDirection.zhEn,
  bool paragraph = false,
  String warning = '',
}) {
  final built = buildYogurtPromptsFromPairs(
    pairs,
    direction: direction,
    warning: warning,
    paragraph: paragraph,
  );
  if (built == null) return null;
  final prompts = built.prompts;
  var next = index;
  if (index >= 0 && index < oldPrompts.length) {
    final current = oldPrompts[index];
    if (current.id == yogurtParagraphId) {
      final at = prompts.indexWhere((p) => p.id == yogurtParagraphId);
      if (at >= 0) next = at;
    } else {
      final key = yogurtTextKey(current.zh);
      final at = prompts.indexWhere(
        (p) => isYogurtPairPrompt(p) && yogurtTextKey(p.zh) == key,
      );
      if (at >= 0) next = at;
    }
  }
  final safe = next < 0 ? 0 : (next > prompts.length - 1 ? prompts.length - 1 : next);
  return YogurtRemapResult(
    prompts: prompts,
    index: safe,
    warning: built.warning,
  );
}
