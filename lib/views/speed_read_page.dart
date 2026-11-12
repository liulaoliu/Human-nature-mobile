/// 速读页：一句一句读，超时就地拷打。
///
/// 三层分工和别处一致：
///   - 目标时长、挖空、判分、结算都在 `core/speed_read.dart`（纯函数，已测）；
///   - 状态编排在 `viewmodels/speed_read_view_model.dart`；
///   - 本文件只管「摆」和「点」。
///
/// 布局按项目约定吸顶 + 吸底：顶部是进度与读秒，底部是当前阶段的主按钮，
/// 中间正文自己滚 —— 长句子在小屏上也不会把按钮顶出屏幕。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/learning.dart';
import '../core/speed_read.dart';
import '../core/vocab_stats.dart' show PickSession;
import '../core/word_pick.dart' show PickEntry;
import '../data/repositories/learning_repository.dart';
import '../data/repositories/vocab_repository.dart';
import '../models/document.dart';
import '../services/vocab_mark.dart';
import '../viewmodels/pick_mode_view_model.dart';
import '../viewmodels/speed_read_view_model.dart';
import '../widgets/status_bar.dart';
import 'pickable_sentence.dart';
import 'reader_body.dart' show PickBar;
import 'sentence_extras.dart';

/// 速读页。
class SpeedReadPage extends StatefulWidget {
  const SpeedReadPage({super.key});

  @override
  State<SpeedReadPage> createState() => _SpeedReadPageState();
}

class _SpeedReadPageState extends State<SpeedReadPage> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<SpeedReadViewModel>().bootstrap();
    });
    // 250ms 只为刷新读秒；读秒本身由 ViewModel 现算，掉帧不会算错时间。
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted) return;
      context.read<SpeedReadViewModel>().tick();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SpeedReadViewModel>();
    final pick = context.watch<PickModeViewModel?>();
    final picking = pick != null && pick.enabled;
    return Scaffold(
      appBar: AppBar(
        title: Text(vm.hasArticle ? '速读 · 第 ${vm.index + 1} 句' : '速读'),
        actions: [
          if (vm.hasArticle) ...[
            // 选词模式与精读页共用同一个 `PickModeViewModel`：
            // 在哪一页开都算开，切页面不会自己关掉。
            IconButton(
              key: const ValueKey('speed-pick-toggle'),
              tooltip: picking ? '关闭选词模式' : '选词模式',
              isSelected: picking,
              icon: Icon(picking ? Icons.pan_tool : Icons.pan_tool_outlined),
              onPressed: pick == null
                  ? null
                  : () {
                      pick.toggleEnabled();
                      if (!pick.enabled) _flushPickSession(context, pick);
                    },
            ),
            IconButton(
              tooltip: '重来',
              icon: const Icon(Icons.restart_alt),
              onPressed: vm.restart,
            ),
            IconButton(
              tooltip: '换一篇',
              icon: const Icon(Icons.library_books_outlined),
              onPressed: () => vm.openArticle(null),
            ),
          ],
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (vm.error != null) StatusBar.error(message: vm.error!),
            if (vm.busy) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: vm.hasArticle
                  ? _Reader(vm: vm, pick: pick)
                  : _Picker(vm: vm),
            ),
          ],
        ),
      ),
      // 选词时底栏换成选词条（与精读页同款部件）；否则是原来的阶段按钮。
      bottomNavigationBar: picking
          ? PickBar(
              pick: pick,
              busy: vm.busy,
              onCommit: (entries) => _commitPicks(context, vm, entries),
            )
          : null,
    );
  }

  /// 把速读页攒下的词加进「正在读的这一篇」。
  ///
  /// 与精读页不同：速读的 ViewModel 不认识词的关联，所以这里直接走
  /// `addWordsToArticle` 按文章 id 加，不经过 `ReaderViewModel`。
  Future<void> _commitPicks(
    BuildContext context,
    SpeedReadViewModel vm,
    List<PickEntry> entries,
  ) async {
    final pick = context.read<PickModeViewModel?>();
    final repo = context.read<VocabRepository>();
    final article = vm.article;
    if (pick == null || article == null || entries.isEmpty) return;
    try {
      final added = await addWordsToArticle(
        repo: repo,
        articleId: article.id,
        fileName: article.book,
        entries: entries,
      );
      if (!context.mounted) return;
      pick.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(added > 0 ? '已收录 $added 个新词' : '没加进去（可能已收过）'),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('加词失败：$e')),
      );
    }
  }

  /// 关掉选词模式时记一次选词时长（和精读页同一口径）。
  void _flushPickSession(BuildContext context, PickModeViewModel pick) {
    final session = pick.takeSession();
    if (session == null) return;
    final learning = context.read<LearningRepository>();
    unawaited(_writePickSession(learning, session));
  }

  Future<void> _writePickSession(
    LearningRepository learning,
    PickSession session,
  ) async {
    try {
      final loaded = await learning.load();
      await learning.writeSection(
        loaded..sessions = [...loaded.sessions, session].take(500).toList(),
        LearningSection.sessions,
      );
    } catch (_) {
      // 统计写不进去不影响选词本身。
    }
  }
}

/// 选文章。
class _Picker extends StatelessWidget {
  const _Picker({required this.vm});

  final SpeedReadViewModel vm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dim = theme.colorScheme.onSurfaceVariant;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('挑一篇来读', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (vm.library.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Column(
              children: [
                Icon(Icons.article_outlined, size: 48, color: dim),
                const SizedBox(height: 12),
                Text('还没有文章', style: theme.textTheme.titleMedium),
                const SizedBox(height: 6),
                Text(
                  '先去「精读」粘贴一篇英文，再回来速读。',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(color: dim),
                ),
              ],
            ),
          )
        else
          for (final row in vm.library)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(row.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                '${row.sentenceCount} 句',
                style: theme.textTheme.bodySmall?.copyWith(color: dim),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => vm.openArticle(row.id),
            ),
      ],
    );
  }
}

/// 逐句读界面：顶栏吸顶、底栏吸底、正文自己滚。
class _Reader extends StatelessWidget {
  const _Reader({required this.vm, this.pick});

  final SpeedReadViewModel vm;
  final PickModeViewModel? pick;

  @override
  Widget build(BuildContext context) {
    final s = vm.sentence;
    if (s == null) return _DoneView(vm: vm);
    return Column(
      children: [
        _TopBar(vm: vm),
        Expanded(child: _Body(vm: vm, sentence: s, pick: pick)),
        _BottomBar(vm: vm),
      ],
    );
  }
}

/// 吸顶：第几句、读秒、进度条。
class _TopBar extends StatelessWidget {
  const _TopBar({required this.vm});

  final SpeedReadViewModel vm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dim = theme.colorScheme.onSurfaceVariant;
    final target = vm.target;
    final elapsed = vm.elapsedMs;
    final progress = target <= 0 ? 0.0 : (elapsed / target).clamp(0.0, 1.0);
    final over = elapsed > target;
    return Container(
      color: theme.colorScheme.surface,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                '第 ${vm.index + 1} / ${vm.total} 句',
                style: theme.textTheme.labelLarge,
              ),
              const Spacer(),
              Text(
                _seconds(elapsed),
                style: theme.textTheme.titleSmall?.copyWith(
                  color: over ? theme.colorScheme.error : null,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Text(
                ' / ${_seconds(target)}',
                style: theme.textTheme.bodySmall?.copyWith(color: dim),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 4,
              color: over ? theme.colorScheme.error : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// 正文：原文 / 拷打题 / 揭晓后的译文与语言点。
class _Body extends StatelessWidget {
  const _Body({required this.vm, required this.sentence, this.pick});

  final SpeedReadViewModel vm;
  final Sentence sentence;
  final PickModeViewModel? pick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dim = theme.colorScheme.onSurfaceVariant;
    final phase = vm.phase;
    final drill = vm.drill;
    final showBlank = (phase == SpeedReadPhase.drill || phase == SpeedReadPhase.drillAnswer) && drill != null;
    final text = showBlank ? drill.prompt : sentence.text;
    final picking = pick != null && pick!.enabled && !showBlank;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (picking)
            // 选词模式下正文逐词可点，和精读页是同一个部件。
            // 速读的 ViewModel 不持有词库，「已收」下划线在这里不标
            // （加词本身已有去重，重复点不会建出第二条词条）。
            PickableSentence(
              sentenceId: sentence.id,
              text: text,
              pick: pick,
              style: theme.textTheme.headlineSmall?.copyWith(height: 1.55),
              onTapWord: (index, word) => pick!.toggle(sentence.id, index, word),
            )
          else
            SelectableText(
              text,
              style: theme.textTheme.headlineSmall?.copyWith(height: 1.55),
            ),
          const SizedBox(height: 16),
          if (phase == SpeedReadPhase.reveal || phase == SpeedReadPhase.drillAnswer) _TimingChip(vm: vm),
          if (phase == SpeedReadPhase.reveal) ...[
            const SizedBox(height: 12),
            // 揭晓阶段整屏停住：译文 + 语言点 + 搭配 + 本句语速，
            // 用户看完自己点「下一句」（`elapsedMs` 此时已定格，不再计时）。
            SentenceExtras(sentence: sentence),
            if (sentence.collocations.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '搭配：${sentence.collocations.join('；')}',
                  style: theme.textTheme.bodySmall?.copyWith(color: dim),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _sentenceSpeed(vm),
                style: theme.textTheme.bodySmall?.copyWith(color: dim),
              ),
            ),
          ],
          if (phase == SpeedReadPhase.drill && drill != null) ...[
            const SizedBox(height: 8),
            Text(
              '超时了。把空里的词选回来：',
              style: theme.textTheme.bodyMedium?.copyWith(color: dim),
            ),
            const SizedBox(height: 8),
            for (final option in drill.options)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: OutlinedButton(
                  onPressed: () => vm.chooseDrill(option),
                  style: OutlinedButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    minimumSize: const Size.fromHeight(44),
                  ),
                  child: Text(option),
                ),
              ),
          ],
          if (phase == SpeedReadPhase.drillAnswer && drill != null) _DrillResult(vm: vm, drill: drill),
        ],
      ),
    );
  }
}

/// 用时与目标。
class _TimingChip extends StatelessWidget {
  const _TimingChip({required this.vm});

  final SpeedReadViewModel vm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dim = theme.colorScheme.onSurfaceVariant;
    final slow = vm.slow;
    return Row(
      children: [
        Icon(
          slow ? Icons.hourglass_bottom : Icons.check_circle_outline,
          size: 16,
          color: slow ? theme.colorScheme.error : theme.colorScheme.primary,
        ),
        const SizedBox(width: 6),
        Text(
          slow ? '慢于目标：${_seconds(vm.readMs)}' : '达标：${_seconds(vm.readMs)}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: slow ? theme.colorScheme.error : dim,
          ),
        ),
      ],
    );
  }
}

/// 拷打对错。
class _DrillResult extends StatelessWidget {
  const _DrillResult({required this.vm, required this.drill});

  final SpeedReadViewModel vm;
  final SpeedReadDrill drill;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ok = vm.drillOk == true;
    final color = ok ? theme.colorScheme.primary : theme.colorScheme.error;
    return Row(
      children: [
        Icon(ok ? Icons.check_circle : Icons.cancel, size: 18, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            ok ? '对：${drill.answer}' : '应该是：${drill.answer}',
            style: theme.textTheme.bodyMedium?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

/// 吸底：上一句 / 下一句常驻。
///
/// 「下一句」按当前阶段干活，但**按钮文字不变**：读的阶段按它 = 读完了
/// （超时且开了自动拷打会直接进拷打），揭晓阶段按它 = 继续下一句，
/// 拷打阶段按它 = 不做拷打、直接翻句（所以不再需要单独的「跳过」）。
class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.vm});

  final SpeedReadViewModel vm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dim = theme.colorScheme.onSurfaceVariant;
    final hint = _hintOf(vm);
    return Container(
      color: theme.colorScheme.surface,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (vm.rows.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _summaryOf(vm),
                style: theme.textTheme.bodySmall?.copyWith(color: dim),
              ),
            ),
          if (hint.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                hint,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(color: dim),
              ),
            ),
          Row(
            children: [
              // 回上一句：常驻，第一句时禁用。
              // 走 `go(-1)` —— 只移动游标、不记成绩（`advance` 才记）。
              TextButton.icon(
                onPressed: vm.index > 0 ? () => vm.go(-1) : null,
                icon: const Icon(Icons.chevron_left, size: 20),
                label: const Text('上一句'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: vm.advance,
                  child: const Text('下一句'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 阶段提示：告诉用户现在按「下一句」会发生什么。
String _hintOf(SpeedReadViewModel vm) {
  switch (vm.phase) {
    case SpeedReadPhase.read:
      return '读完按「下一句」';
    case SpeedReadPhase.reveal:
      return '看完按「下一句」继续';
    case SpeedReadPhase.drill:
      return '选一个词填回去；不想做就按「下一句」';
    case SpeedReadPhase.drillAnswer:
      return '';
  }
}

/// 读完一篇的结算。
class _DoneView extends StatelessWidget {
  const _DoneView({required this.vm});

  final SpeedReadViewModel vm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dim = theme.colorScheme.onSurfaceVariant;
    final sum = summarize(vm.rows);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Icon(Icons.celebration_outlined, size: 48, color: theme.colorScheme.primary),
        const SizedBox(height: 12),
        Center(child: Text('这一篇读完了', style: theme.textTheme.titleLarge)),
        const SizedBox(height: 16),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _Metric(label: '句数', value: '${sum.count}'),
                _Metric(label: '平均语速', value: sum.avgWpm > 0 ? '${sum.avgWpm} 词/分钟' : '—'),
                _Metric(label: '慢于目标', value: '${sum.slow} 句'),
                _Metric(
                  label: '拷打',
                  value: sum.drillTotal > 0 ? '${sum.drillCorrect} / ${sum.drillTotal} 对' : '没触发',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(onPressed: vm.restart, child: const Text('再读一遍')),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => vm.openArticle(null),
          child: Text('换一篇', style: TextStyle(color: dim)),
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(label, style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          )),
          const Spacer(),
          Text(value, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

/// `1234ms` → `1.2s`。
String _seconds(int ms) => '${(ms / 1000).toStringAsFixed(1)}s';

/// 本句读完的速度：`words / readMs * 60000`，超时在后面加注。
String _sentenceSpeed(SpeedReadViewModel vm) {
  final s = vm.sentence;
  if (s == null || vm.readMs <= 0) return '';
  final words = wordCount(s.text);
  final wpm = (words / vm.readMs * 60000).round();
  return '本句速度 $wpm 词/分${vm.slow ? '（超时）' : ''}';
}

String _summaryOf(SpeedReadViewModel vm) {
  final sum = summarize(vm.rows);
  final parts = <String>['已读 ${sum.count} 句'];
  if (sum.avgWpm > 0) parts.add('${sum.avgWpm} 词/分');
  if (sum.slow > 0) parts.add('慢 ${sum.slow}');
  if (sum.drillTotal > 0) parts.add('拷打 ${sum.drillCorrect}/${sum.drillTotal}');
  return parts.join(' · ');
}
