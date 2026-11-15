import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/golden.dart';
import '../core/golden_drill.dart';
import '../viewmodels/golden_drill_session.dart';
import '../viewmodels/golden_view_model.dart';
import 'golden_fill_view.dart';

/// 练习页：一句一句地练 —— 填空（多轮）→ 拼句 → 小结。
///
/// 三段式（上吸顶 / 中间滚）是刻意的：填空轮次多，每次交卷都要点「交这一轮」，
/// 按钮跟着滚走等于每轮多滚一趟。而且按钮在键盘上方才不会被挡住 ——
/// 用户（2026-11-15）截图要求把这两个键吸顶，位置放在英文正文上方、最顶端
/// tab 下方。
///
/// 输入框由本组件持有（不是 session）：输入框文本属于界面，
/// 判分后的「保留原作答」和「换轮要清空」都在这里处理。
class GoldenDrillView extends StatefulWidget {
  const GoldenDrillView({super.key, required this.onGoPlan});

  /// 回挑句页（换一句 / 改设置）。
  final VoidCallback onGoPlan;

  @override
  State<GoldenDrillView> createState() => _GoldenDrillViewState();
}

class _GoldenDrillViewState extends State<GoldenDrillView>
    with WidgetsBindingObserver {
  List<TextEditingController> _controllers = <TextEditingController>[];

  /// 每个**空位**（句子里出现的位置）一个焦点，不是每个答案一个。
  ///
  /// 同一个学习点在句子里出现两次、又被 cloze 去重成同一条空时，两处共用
  /// 一个 controller（打字同步），但焦点/GlobalKey 必须各有一份 ——
  /// 一个 FocusNode 不能同时挂两个输入框，两个 WidgetSpan 也不能用同一个
  /// GlobalKey。
  ///
  /// 键盘不掉的真正关键不在这里，而在填空输入框的 `onTapOutside`：
  /// `TextField` 默认在「点到外面」时先 unfocus 自己，而点另一个空正是
  /// 「点到当前空的外面」—— 手指按下（down）那一刻旧空失焦、textInput
  /// 通道排队 hide，等抬起（up）才轮到新空 requestFocus，于是键盘落下
  /// 再弹起（用户 2026-11-15 报的现象）。把 `onTapOutside` 置空后，旧空
  /// 不失焦、新空直接接管连接，键盘全程不落。
  final List<FocusNode> _focuses = <FocusNode>[];

  /// 每个空位一个 GlobalKey：键盘一弹，把当前空从键盘底下滚出来。
  final List<GlobalKey> _blankKeys = <GlobalKey>[];

  final ScrollController _scroll = ScrollController();

  String _roundKey = '';

  @override
  void initState() {
    super.initState();
    // 键盘起落会改 viewInsets：布局完成后再检查一次当前空是否被挡。
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeMetrics() {
    _revealFocusedBlank();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scroll.dispose();
    for (final TextEditingController c in _controllers) {
      c.dispose();
    }
    for (final FocusNode f in _focuses) {
      f.dispose();
    }
    super.dispose();
  }

  /// 当前空拿到焦点 / 键盘起落时，把它滚进可视区。
  ///
  /// 为什么不能只靠 `EditableText` 自带的「光标可见」：它是在请求焦点那一帧
  /// 按**旧**的 viewport 算的，键盘动画还没把 body 压小，算完正好被键盘盖住
  /// （用户 2026-11-15 报的「最下方的空被键盘挡住」）。这里在下一帧和键盘
  /// 落位后各补一次；只补两次，不是轮询。
  void _revealBlank(int index) {
    if (index < 0 || index >= _blankKeys.length) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureBlankVisible(index);
    });
    Future<void>.delayed(const Duration(milliseconds: 280), () {
      if (!mounted) return;
      _ensureBlankVisible(index);
    });
  }

  void _revealFocusedBlank() {
    final index = _focuses.indexWhere((FocusNode f) => f.hasFocus);
    if (index >= 0) _revealBlank(index);
  }

  /// 只在空被挡住时滚：已经完整可见就不动，避免点上面一个空也跳一下。
  void _ensureBlankVisible(int index) {
    if (!mounted || index < 0 || index >= _blankKeys.length) return;
    final blank = _blankKeys[index].currentContext;
    if (blank == null) return;
    final box = blank.findRenderObject();
    final scrollable = Scrollable.maybeOf(blank);
    final viewport = scrollable?.context.findRenderObject();
    if (box is! RenderBox || viewport is! RenderBox) {
      Scrollable.ensureVisible(
        blank,
        alignment: 0.5,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    final rect = MatrixUtils.transformRect(
      box.getTransformTo(viewport),
      Offset.zero & box.size,
    );
    const margin = 12.0;
    if (rect.top >= margin && rect.bottom <= viewport.size.height - margin) {
      return;
    }
    Scrollable.ensureVisible(
      blank,
      alignment: rect.bottom > viewport.size.height ? 0.5 : 0.25,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  /// 换句 / 换轮 / 空位数变了才重建输入框。
  ///
  /// **焦点与 GlobalKey 按下标保留**：同一个位置的 `TextField` 能复用
  /// Element / State 和输入连接，换轮时键盘不用先收再弹。只重建 controller
  /// （新一轮从空白开始）。判分（`roundScored`）不作为重建条件 —— 判分后
  /// 输入框仍可编辑，再打字由 `reopenFill` 把判分收掉。
  void _syncControllers(GoldenDrillSession session) {
    final cloze = session.round;
    final blankCount = cloze?.blanks.length ?? 0;
    final slotCount =
        cloze == null ? 0 : cloze.parts.where((GoldenClozePart p) => p.blank).length;
    final key = '${session.sentenceId}|${session.roundIndex}|$blankCount|$slotCount';
    if (key == _roundKey) return;
    _roundKey = key;
    for (final TextEditingController c in _controllers) {
      c.dispose();
    }
    _controllers = <TextEditingController>[
      for (var i = 0; i < blankCount; i++) TextEditingController(),
    ];
    // 焦点 / key 跟着「空位」走：同一学习点重复出现时，两处各有一个输入框。
    _resizeFocuses(slotCount);
    _resizeBlankKeys(slotCount);
    // 新一轮的输入框刚建出来，等这一帧画完再要焦点 —— 在 build 里直接
    // `requestFocus()` 会撞「build 期间改状态」。动作条换轮时会先转移焦点，
    // 这里只是兜底（首次进入 / 外部直接换句）。
    if (slotCount > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_focuses.isEmpty) return;
        _focuses.first.requestFocus();
      });
    }
  }

  /// 焦点按空位下标复用：换轮时保留前 N 个，缺的补、多的释放。
  void _resizeFocuses(int count) {
    while (_focuses.length > count) {
      _focuses.removeLast().dispose();
    }
    while (_focuses.length < count) {
      final index = _focuses.length;
      final node = FocusNode();
      node.addListener(() {
        if (index < _focuses.length && _focuses[index].hasFocus) {
          _revealBlank(index);
        }
      });
      _focuses.add(node);
    }
  }

  void _resizeBlankKeys(int count) {
    while (_blankKeys.length > count) {
      _blankKeys.removeLast();
    }
    while (_blankKeys.length < count) {
      _blankKeys.add(GlobalKey());
    }
  }

  /// 动作条 / 键盘回车共用一个入口：没交就交，交了就下一轮或重试。
  ///
  /// 判分后**不 unfocus**（用户 2026-11-15 要求）：键盘全程留着，判分提示
  /// 放到填空区上方的固定条里，不再靠收键盘来露出来。
  void _fillAction(GoldenDrillSession session) {
    if (!session.roundScored) {
      _submitFill(session);
      return;
    }
    if (session.roundOk) {
      _nextRound(session);
    } else {
      _retryRound(session);
    }
  }

  void _submitFill(GoldenDrillSession session) {
    session.submitFill(<String>[
      for (final TextEditingController c in _controllers) c.text,
    ]);
    // 上方插了判分条，正文会下移：确认当前空还在键盘上方。
    _revealFocusedBlank();
  }

  /// 换轮前先把焦点挪到第 0 个空：FocusNode 和 GlobalKey 跨轮保留，焦点从
  /// 旧轮的空直接落到新轮的空，键盘连接不中断。
  void _nextRound(GoldenDrillSession session) {
    final willFill = session.roundIndex + 1 < session.roundCount;
    if (willFill && _focuses.isNotEmpty) {
      _focuses.first.requestFocus();
    }
    session.nextRound();
  }

  /// 重试同一轮：清空作答，但焦点 / 键盘不动。
  void _retryRound(GoldenDrillSession session) {
    if (_focuses.isNotEmpty) {
      _focuses.first.requestFocus();
    }
    for (final TextEditingController c in _controllers) {
      c.clear();
    }
    session.retryRound();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<GoldenViewModel>();
    final session = vm.drill;
    if (session.sentenceId.isEmpty) {
      return _EmptyDrill(onGoPlan: widget.onGoPlan);
    }
    _syncControllers(session);
    final total = vm.ordered.length;
    final at = vm.ordered.indexWhere((GoldenSentence c) => c.id == session.sentenceId);
    final where = total == 0
        ? '第 1 句'
        : '第 ${at < 0 ? 1 : at + 1}/$total 句';
    final fillProgress = <String>[
      where,
      if (session.roundCount > 0)
        '填空 ${session.roundIndex + 1}/${session.roundCount}',
      if (session.round != null) '这一轮 ${session.round!.blanks.length} 个空',
      if (session.targets.isNotEmpty) '${session.targets.length} 个学习点',
    ].join(' · ');
    return Column(
      children: <Widget>[
        // 动作条吸顶在正文上方：用户（2026-11-15）要求「交这一轮 / 挑句」
        // 别被键盘挡住。填空阶段没有顶栏，动作条就是最上面那一条。
        _BottomBar(
          vm: vm,
          session: session,
          onGoPlan: widget.onGoPlan,
          onFillAction: () => _fillAction(session),
        ),
        // 判分条固定在动作条下面：键盘一直留着，提示必须在键盘上方可见，
        // 不能像以前那样塞在正文末尾（会被键盘挡住，逼用户收键盘）。
        if (session.phase == GoldenDrillPhase.fill && session.roundScored)
          _FillVerdict(
            ok: session.roundOk,
            wrong: session.roundResults.where((bool r) => !r).length,
          ),
        // 填空阶段不画顶部黑框：用户（2026-11-15）要求撤掉那块（原来还会重复显示
        // 一整句英文），把高度让给填空区。进度挪进填空区第一行的小字里，信息不丢。
        if (session.phase != GoldenDrillPhase.fill)
          _TopBar(vm: vm, session: session),
        Expanded(
          child: switch (session.phase) {
            GoldenDrillPhase.fill => GoldenFillView(
                cloze: session.round!,
                controllers: _controllers,
                focuses: _focuses,
                blankKeys: _blankKeys,
                progress: fillProgress,
                scored: session.roundScored,
                results: session.roundResults,
                scrollController: _scroll,
                onSubmitted: () => _fillAction(session),
                onEdited: session.reopenFill,
              ),
            GoldenDrillPhase.assemble => _AssembleBody(session: session),
            GoldenDrillPhase.summary => _SummaryBody(vm: vm, session: session),
          },
        ),
      ],
    );
  }
}

/// 还没挑句子。
class _EmptyDrill extends StatelessWidget {
  const _EmptyDrill({required this.onGoPlan});

  final VoidCallback onGoPlan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('还没开始练。', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              '先去挑句页选一句，再回来练。',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onGoPlan,
              icon: const Icon(Icons.list_alt),
              label: const Text('去挑句'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 填空判分条：固定在动作条下面，键盘挡不到。
///
/// 以前这段汇总在正文末尾的 `ListView` 里，交卷必须收键盘才看得见；现在
/// 键盘全程留着，提示挪到上方。文案顺带把「回车」这个快捷操作说出来。
class _FillVerdict extends StatelessWidget {
  const _FillVerdict({required this.ok, required this.wrong});

  final bool ok;
  final int wrong;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      color: ok ? theme.colorScheme.primaryContainer : theme.colorScheme.errorContainer,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Text(
        ok
            ? '这一轮全对 · 回车或「下一轮」继续'
            : '有 $wrong 个空不对，正确答案已标在空后 · 回车或「重试这一轮」再来',
        style: theme.textTheme.bodySmall?.copyWith(
          color: ok
              ? theme.colorScheme.onPrimaryContainer
              : theme.colorScheme.onErrorContainer,
        ),
      ),
    );
  }
}

/// 吸顶：这一句 + 到哪一步了。
class _TopBar extends StatelessWidget {
  const _TopBar({required this.vm, required this.session});

  final GoldenViewModel vm;
  final GoldenDrillSession session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = vm.ordered.length;
    final at = vm.ordered.indexWhere((GoldenSentence c) => c.id == session.sentenceId);
    final progress = switch (session.phase) {
      GoldenDrillPhase.fill => session.roundCount == 0
          ? '填空'
          : '填空 ${session.roundIndex + 1}/${session.roundCount}',
      GoldenDrillPhase.assemble => '拼句',
      GoldenDrillPhase.summary => '小结',
    };
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  total == 0
                      ? progress
                      : '第 ${at < 0 ? 1 : at + 1}/$total 句 · $progress',
                  style: theme.textTheme.labelLarge,
                ),
              ),
              if (session.targets.isNotEmpty)
                Text(
                  '${session.targets.length} 个学习点',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(session.text, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// 拼句正文。
class _AssembleBody extends StatelessWidget {
  const _AssembleBody({required this.session});

  final GoldenDrillSession session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final assembly = session.assembly;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: <Widget>[
        Text(
          '按正确顺序点出这句话（点错可以撤销）。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: theme.colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(8),
          ),
          child: session.order.isEmpty
              ? Text(
                  '（还没点）',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              : Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: <Widget>[
                    for (final String w in session.order)
                      Chip(label: Text(w), visualDensity: VisualDensity.compact),
                  ],
                ),
        ),
        if (assembly != null) ...<Widget>[
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final String w in assembly.bank)
                ActionChip(
                  label: Text(w),
                  onPressed:
                      session.assembleScored ? null : () => session.pick(w),
                ),
            ],
          ),
        ],
        if (session.assembleScored) ...<Widget>[
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: session.assembleOk
                  ? theme.colorScheme.primaryContainer
                  : theme.colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              session.assembleOk
                  ? '顺序对了。'
                  : '顺序不对（顺序是：${session.targets.map((t) => t.en).join(' → ')}）。',
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ],
    );
  }
}

/// 小结正文。
class _SummaryBody extends StatelessWidget {
  const _SummaryBody({required this.vm, required this.session});

  final GoldenViewModel vm;
  final GoldenDrillSession session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final record = vm.recordFor(session.sentenceId);
    final mastered = record?.mastered ?? false;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: <Widget>[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(
                      mastered ? Icons.emoji_events : Icons.school_outlined,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      mastered ? '这一句已掌握' : '这一句练过一轮',
                      style: theme.textTheme.titleMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  mastered
                      ? '填空、拼句、默写都一次做对，也看过小结了。'
                      : '三步首次都做对，再看一次小结，就算掌握。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Text(session.text, style: theme.textTheme.bodyLarge),
                if (session.targets.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    session.targets
                        .map((GoldenTarget t) =>
                            '${goldenTargetKindLabel[t.kind] ?? t.kind.name}：${t.en}'
                            '${t.zh == null ? '' : ' — ${t.zh}'}')
                        .join('\n'),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '记忆课：先把学习点抄一遍，再不看原文默写整句。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () {
            final text = session.targets.isEmpty
                ? session.text
                : '${session.text}\n'
                    '${session.targets.map((GoldenTarget t) => t.en).join(' / ')}';
            Clipboard.setData(ClipboardData(text: text));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('已复制这一句')),
            );
          },
          icon: const Icon(Icons.copy, size: 18),
          label: const Text('复制这一句'),
        ),
      ],
    );
  }
}

/// 动作条：吸在正文上方（不放底部，否则键盘一弹就把它挡住）。
class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.vm,
    required this.session,
    required this.onGoPlan,
    required this.onFillAction,
  });

  final GoldenViewModel vm;
  final GoldenDrillSession session;
  final VoidCallback onGoPlan;

  /// 填空阶段的唯一动作：没交卷 = 交；已判分 = 下一轮 / 重试。
  /// 由页面统一处理焦点与键盘，别在按钮里直接调 session。
  final VoidCallback onFillAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final action = switch (session.phase) {
      GoldenDrillPhase.fill => FilledButton.icon(
          onPressed: onFillAction,
          icon: Icon(
            !session.roundScored
                ? Icons.check
                : (session.roundOk ? Icons.arrow_forward : Icons.refresh),
          ),
          label: Text(
            !session.roundScored
                ? '交这一轮'
                : (session.roundOk ? '下一轮' : '重试这一轮'),
          ),
        ),
      GoldenDrillPhase.assemble => session.assembleScored
          ? FilledButton.icon(
              onPressed:
                  session.assembleOk ? session.finish : session.retryAssembly,
              icon: Icon(session.assembleOk ? Icons.flag : Icons.refresh),
              label: Text(session.assembleOk ? '看小结' : '重新拼'),
            )
          : FilledButton.icon(
              onPressed:
                  session.order.isEmpty ? null : () => session.submitAssembly(),
              icon: const Icon(Icons.check),
              label: const Text('交拼句'),
            ),
      GoldenDrillPhase.summary => FilledButton.icon(
          onPressed: () => _nextSentence(vm, session, onGoPlan),
          icon: const Icon(Icons.skip_next),
          label: const Text('下一句'),
        ),
    };
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          // 这条在屏幕最上面，分隔线画在下沿（原来吸底时画的是上沿）。
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Row(
        children: <Widget>[
          Expanded(child: action),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: onGoPlan,
            icon: const Icon(Icons.list_alt, size: 18),
            label: const Text('挑句'),
          ),
        ],
      ),
    );
  }
}

/// 下一句：按课程顺序往下走；到末尾就回挑句页。
void _nextSentence(
  GoldenViewModel vm,
  GoldenDrillSession session,
  VoidCallback onGoPlan,
) {
  final rows = vm.ordered;
  final at = rows.indexWhere((GoldenSentence c) => c.id == session.sentenceId);
  if (at >= 0 && at + 1 < rows.length) {
    vm.drill.open(rows[at + 1].id);
    vm.goIndex(at + 1);
    return;
  }
  onGoPlan();
}
