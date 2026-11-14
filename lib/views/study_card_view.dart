/// 单词卡：热度边框、点击翻面、释义区、SRS 行、卡面工具。
///
/// 对应 Web 版 `StudyCardView.tsx` + `StudyCardTools.tsx`。**翻面规则**：整张卡可点，
/// 点一下才露出释义（学习模式选对释义已经看过，那一步由 [StudyCardFlow] 直接置 revealed）。
library;

import 'package:flutter/material.dart';

import '../core/vocab/merge.dart' show vocabCardBlocks;
import '../core/vocab/word.dart' show cleanGloss, displayMeaning;
import '../theme/app_skin.dart' show SkinColors;
import '../viewmodels/study_card_flow.dart';
import '../viewmodels/study_spelling_front.dart';

/// 热度 → 边框色（越久越红，与 Web 的 heat-0..4 同色系）。
///
/// 三档暖色走 [SkinColors] 而不是 `colorScheme`：色相要跨明暗保持一致
/// （绿→黄→橙的语义），但明度必须跟着浅色/深色换，否则浅色主题下
/// 浅绿边框在白底上几乎看不见。`colorScheme` 里没有「绿黄橙三档」这种语义。
Color heatColor(ColorScheme scheme, SkinColors skin, int heat) => switch (heat) {
      0 => scheme.outlineVariant,
      1 => skin.heat1,
      2 => skin.heat2,
      3 => skin.heat3,
      _ => scheme.error,
    };

/// 单词卡。
class StudyCardPanel extends StatelessWidget {
  const StudyCardPanel({
    super.key,
    required this.flow,
    required this.onSpeak,
    this.spelling,
    this.onSpellInput,
    this.onCheckSpelling,
    this.onMarkUnknown,
    this.onEdit,
    this.onDelete,
  });

  final StudyCardFlow flow;
  final VoidCallback? onSpeak;

  /// 卡面拼写状态机（不传 = 这个入口不考拼写）。
  final StudySpellingFront? spelling;
  final ValueChanged<String>? onSpellInput;
  final VoidCallback? onCheckSpelling;
  final VoidCallback? onMarkUnknown;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final card = flow.card;
    if (card == null) return const SizedBox.shrink();
    final scheme = theme.colorScheme;
    final skin = SkinColors.of(context);
    final heat = flow.heat;
    final meaning = displayMeaning(
      partOfSpeech: card.partOfSpeech,
      meaning: card.meaning,
    );
    final definition = cleanGloss(card.definition);
    final blocks = vocabCardBlocks(card, maxExamples: 3);
    final spellFront = spelling?.front ?? false;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: heatColor(scheme, skin, heat),
          width: heat >= 3 ? 2 : 1,
        ),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            scheme.surfaceContainerHigh,
            scheme.surface,
          ],
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        // 正面拼写时不翻面：点了等于看答案，得先拼完
        onTap: spellFront ? null : flow.reveal,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (spellFront) ...[
                // 只给中文释义 + 词性，绝不显示英文单词 / 音标，也不自动朗读
                Text(
                  '看释义，拼出这个英文单词',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                if (meaning.isNotEmpty)
                  Text(
                    meaning,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge,
                  ),
                const SizedBox(height: 16),
                TextField(
                  key: const ValueKey<String>('study-spell-input'),
                  autofocus: true,
                  onChanged: onSpellInput,
                  onSubmitted: (_) => onCheckSpelling?.call(),
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    hintText: '拼出这个英文单词，回车检查',
                    border: OutlineInputBorder(),
                  ),
                ),
              ] else ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        card.word,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (onSpeak != null)
                      IconButton(
                        onPressed: onSpeak,
                        icon: const Icon(Icons.volume_up_outlined),
                        tooltip: '读一遍',
                      ),
                  ],
                ),
                if ((card.phonetic ?? '').isNotEmpty)
                  Text(
                    card.phonetic!,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                if (spelling != null && spelling!.checked) ...[
                  const SizedBox(height: 8),
                  Text(
                    spelling!.ok
                        ? '✔ 拼对了'
                        : '✘ 你写的是「${spelling!.input.isEmpty ? '（空）' : spelling!.input}」',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: spelling!.ok ? skin.success : scheme.error,
                    ),
                  ),
                ],
                if (!flow.revealed && !(spelling?.checked ?? false)) ...[
                  const SizedBox(height: 18),
                  Text(
                    '点一下看释义',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
              if (flow.revealed || (spelling?.checked ?? false)) ...[
                const SizedBox(height: 20),
                Container(height: 1, color: scheme.outlineVariant),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (meaning.isNotEmpty)
                        Text(meaning, style: theme.textTheme.titleLarge),
                      for (final mark in card.grammarMarks ?? const <String>[])
                        Chip(
                          label: Text(mark),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                        ),
                      if (onMarkUnknown != null)
                        TextButton(
                          onPressed: onMarkUnknown,
                          child: const Text('不认识'),
                        ),
                    ],
                  ),
                ),
                if (definition.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      definition,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
                for (final block in blocks) ...[
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${block.label}：',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      block.lines.join('\n'),
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    flow.srsLine,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (onEdit != null || onDelete != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (onEdit != null)
                        TextButton.icon(
                          onPressed: onEdit,
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          label: const Text('编辑'),
                        ),
                      if (onDelete != null)
                        TextButton.icon(
                          onPressed: onDelete,
                          icon: const Icon(Icons.delete_outline, size: 18),
                          label: const Text('删除'),
                        ),
                    ],
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 卡片顶上的计时（热度决定颜色）。
class StudyTimerChip extends StatelessWidget {
  const StudyTimerChip({super.key, required this.flow});

  final StudyCardFlow flow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final skin = SkinColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: heatColor(scheme, skin, flow.heat).withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '⏱ ${flow.timerLabel}',
        style: TextStyle(
          fontSize: 12,
          color: flow.heat >= 3 ? scheme.error : scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// 拼错卡：把「判为不认识」这件事钉在屏幕上，用户确认后才换下一张。
///
/// 口径：错一次定生死 —— 不给第二次输入框（能再输一次等于把判断变成抄写）。
class SpellMissPanel extends StatelessWidget {
  const SpellMissPanel({super.key, required this.miss, required this.onAck});

  final SpellMissCard miss;
  final VoidCallback onAck;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.error),
        color: scheme.errorContainer.withValues(alpha: 0.25),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '拼错了 · 判为「不认识」',
            style: theme.textTheme.titleMedium?.copyWith(
              color: scheme.error,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '你写的是「${miss.typed.isEmpty ? '（空）' : miss.typed}」',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 6),
          Text(
            '正确写法：${miss.word}',
            style: theme.textTheme.titleLarge,
          ),
          if (miss.meaning.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              miss.meaning,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            '这个词会从零重学，已排到本轮队尾。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          FilledButton(
            key: const ValueKey<String>('study-spell-ack'),
            onPressed: onAck,
            child: const Text('知道了，下一个'),
          ),
        ],
      ),
    );
  }
}

/// 选中文释义（学习模式的门禁 / 锤炼里的选义共用）。
class MeaningQuizPanel extends StatelessWidget {
  const MeaningQuizPanel({
    super.key,
    required this.word,
    required this.options,
    required this.correctIndex,
    required this.onPick,
    this.picked,
    this.wrongPick = false,
    this.onReveal,
  });

  final String word;
  final List<String> options;

  /// 正确项下标（由调用方从 `MeaningOption` 取；`-1` = 不知道）。
  final int correctIndex;
  final void Function(int index) onPick;
  final int? picked;
  final bool wrongPick;
  final VoidCallback? onReveal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final skin = SkinColors.of(context);
    final revealed = picked != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          word,
          textAlign: TextAlign.center,
          style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 20),
        for (final (i, text) in options.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                alignment: Alignment.centerLeft,
                backgroundColor: revealed && i == correctIndex
                    ? skin.successSurface
                    : (revealed && i == picked && wrongPick
                        ? scheme.error.withValues(alpha: 0.15)
                        : null),
                side: BorderSide(
                  color: revealed && i == correctIndex
                      ? skin.success
                      : (revealed && i == picked && wrongPick
                          ? scheme.error
                          : scheme.outlineVariant),
                ),
              ),
              onPressed: revealed ? null : () => onPick(i),
              child: Text('${'ABCD'[i]}. $text'),
            ),
          ),
        if (revealed) ...[
          const SizedBox(height: 4),
          Text(
            wrongPick ? '✘ 选错了 · 正确的是绿色那条' : '看了答案 · 正确的是绿色那条',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
        if (onReveal != null && !revealed) ...[
          const SizedBox(height: 8),
          TextButton(onPressed: onReveal, child: const Text('不认识，看答案')),
        ],
      ],
    );
  }
}
