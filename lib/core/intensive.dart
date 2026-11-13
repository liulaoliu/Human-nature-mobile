/// 精读工作流：把「一篇材料」拆成几个阶段，按当前数据算出各阶段状态、深度等级与下一步。
///
/// 纯函数，不碰 Flutter / 存储；界面只负责画出来并按 key 跳转到对应工具。
/// 对应 Web 版 `src/core/intensive.ts`（267 行）。
///
/// 阶段（从浅到深）：
///   skim       通读（速读一遍，判断能不能看懂）
///   vocab      标词 / 查词补齐（音标·释义·例句）
///   chunks     词块（词组 / 习语 / 搭配）
///   comprehend 句子理解（逐句译文 + 语言点）
///   recall     达标拷打（背单词 + 拼写/选义，把词变成长期记忆）
///   produce    产出（仿写 + 批改）
///   grammar    语法专项（结构 / 语态时态 / 功能词）
///
/// 为什么要有这一层：App 以前这些功能各自挂在首页上，用户不知道「先做哪个」。
/// Web 版把顺序固化进一个面板（`IntensivePanel.tsx`），仿写只是其中一步 ——
/// 这也是为什么仿写不该在首页单独占一张卡。
library;

import '../models/vocab.dart' show VocabItem;
import 'vocab/merge.dart' show needsAiExamples;
import 'vocab/review.dart' show hasReviewHistory, isDue;

/// 一篇里某类技能的正确率。
class SkillStat {
  const SkillStat({required this.total, required this.correct});

  final int total;
  final int correct;
}

/// 本篇生词的统计口径。
class IntensiveWords {
  const IntensiveWords({
    required this.total,
    required this.withMeaning,
    required this.withChunks,
    required this.withMarks,
    required this.studied,
    required this.stable,
    required this.due,
    required this.noExample,
    int? chunksAsked,
  }) : chunksAskedRaw = chunksAsked;

  /// 本篇生词总数。
  final int total;

  /// 有中文释义的。
  final int withMeaning;

  /// 有词块（用法 / 词组 / 习语）的。
  final int withChunks;

  /// 传进来的「问过词块」原始值（null = 没传）。
  final int? chunksAskedRaw;

  /// 「问过词块」的词数：`phrases` 字段已存在（空数组也算问过）。
  ///
  /// 为什么要和 [withChunks] 分开：有些词**真的没有**常用搭配（AI 会写「无」），
  /// 按「有内容」算进度，这一阶段永远到不了 100%，「精通」等级直接被锁死。
  /// 省略时退回 [withChunks]（只关心覆盖率的调用方不用改）。
  int get chunksAsked => chunksAskedRaw ?? withChunks;

  /// 有语法标记（可数/及物…）的。
  final int withMarks;

  /// 学过（repetitions > 0）的。
  final int studied;

  /// 已稳定掌握的。
  final int stable;

  /// 当前到期（含逾期）的。
  final int due;

  /// 还没有「自己的例句」的。
  final int noExample;
}

/// 一篇句子的统计口径。
class IntensiveSentences {
  const IntensiveSentences({
    required this.total,
    required this.translated,
    required this.language,
  });

  final int total;

  /// 有译文的句数。
  final int translated;

  /// 有语言点的句数。
  final int language;
}

/// 算精读工作流需要的一切输入。
class IntensiveInput {
  const IntensiveInput({
    required this.hasDoc,
    required this.skimmed,
    required this.words,
    required this.sentences,
    this.quiz,
    this.writes = 0,
  });

  final bool hasDoc;

  /// 通读是否已勾选（主观，本地持久化）。
  final bool skimmed;

  final IntensiveWords words;
  final IntensiveSentences sentences;

  /// 本篇考试正确率（可选）。
  final SkillStat? quiz;

  /// 本篇仿写条数。
  final int writes;
}

/// 精读的七个阶段。
enum IntensiveStageKey { skim, vocab, chunks, comprehend, recall, produce, grammar }

/// 阶段完成状态。
enum IntensiveStageStatus { todo, doing, done }

/// 一个阶段的算好的状态。
class IntensiveStage {
  const IntensiveStage({
    required this.key,
    required this.label,
    required this.emoji,
    required this.status,
    required this.progress,
    required this.detail,
    required this.action,
    required this.enabled,
  });

  final IntensiveStageKey key;
  final String label;
  final String emoji;
  final IntensiveStageStatus status;

  /// 0–100。
  final int progress;
  final String detail;

  /// 主按钮文案。
  final String action;

  /// 是否已具备做这一步的条件（用于禁用按钮）。
  final bool enabled;
}

/// 精读工作流的整体结果。
class IntensivePlan {
  const IntensivePlan({
    required this.stages,
    required this.level,
    required this.levelLabel,
    required this.levelDesc,
    required this.progress,
    required this.nextKey,
    required this.nextLabel,
    required this.nextHint,
  });

  final List<IntensiveStage> stages;

  /// 0 及格 / 1 达标 / 2 产出 / 3 精通。
  final int level;
  final String levelLabel;
  final String levelDesc;

  /// 所有阶段的平均完成度。
  final int progress;

  final IntensiveStageKey? nextKey;
  final String nextLabel;
  final String nextHint;
}

int _clamp(int n, [int lo = 0, int hi = 100]) => n < lo ? lo : (n > hi ? hi : n);

int _pct(int a, int b) => b > 0 ? _clamp(((a / b) * 100).round()) : 0;

IntensiveStageStatus _statusOf(int p) =>
    p >= 100 ? IntensiveStageStatus.done : (p > 0 ? IntensiveStageStatus.doing : IntensiveStageStatus.todo);

/// 阶段按钮的文案 = **点下去真的会发生什么**。
///
/// 标词 / 词块 / 理解这三步都是「补数据」，共用一个一键跑批（跑批一次补齐音标·释义·
/// 例句·词组·习语·翻译·语言点），所以文案里明写「跑批」——否则用户会以为点开的是
/// 某个面板，点完发现数据没变化就变成「点了没反应」。语法那步是真的去练（文章测验）。
const Map<IntensiveStageKey, String> intensiveStageAction = {
  IntensiveStageKey.skim: '去速读',
  IntensiveStageKey.vocab: '跑批补音标 / 释义',
  IntensiveStageKey.chunks: '跑批补词组 / 习语',
  IntensiveStageKey.comprehend: '跑批补译文 / 语言点',
  IntensiveStageKey.recall: '去背单词',
  IntensiveStageKey.produce: '去仿写',
  IntensiveStageKey.grammar: '练结构 / 语法',
};

const List<String> _levelLabels = ['及格', '达标', '产出', '精通'];

const List<String> _levelDescs = [
  '看懂了 → 下一步把生词和句子收干净',
  '词记住了、句子懂了 → 下一步开始产出',
  '能仿写了 → 下一步把词块和语法也吃透',
  '词块 · 语法 · 产出都到位，隔天复习即可',
];

const Map<IntensiveStageKey, String> _nextHints = {
  IntensiveStageKey.skim: '先速读一遍，只求看懂大意、标出卡住的句子',
  IntensiveStageKey.vocab: '把卡住句子里的生词选进「待选」，再点「一键跑批」补齐音标/释义/例句',
  IntensiveStageKey.chunks: '一键跑批会自动生成词组/习语；背单词时的「写搭配」就是在记词块',
  IntensiveStageKey.comprehend: '点「全文翻译」和「语言点」，先自己译、再对答案',
  IntensiveStageKey.recall: '用「记忆拷打 / 词块拷打」快速过，再进背单词按 SRS 复习',
  IntensiveStageKey.produce: '挑一个你划出来的好句式，自己写一句，让 AI 严格批改',
  IntensiveStageKey.grammar: '点「语言点」看结构/语法，再用文章测验的「结构/语法 · 中译英」巩固',
};

/// 由当前数据算出精读工作流。
IntensivePlan buildIntensivePlan(IntensiveInput i) {
  final w = i.words;
  final s = i.sentences;
  final quizAcc = i.quiz != null && i.quiz!.total > 0 ? _pct(i.quiz!.correct, i.quiz!.total) : null;
  final hasWords = w.total > 0;

  // ── 通读 ──
  final skimP = i.skimmed ? 100 : 0;
  // ── 标词 / 查词 ──
  final vocabP = hasWords ? _pct(w.withMeaning, w.total) : 0;
  // ── 词块 ──（进度按「问过」算，覆盖率另说：真没搭配的词不该卡死这一阶段）
  final chunksP = hasWords ? _pct(w.chunksAsked, w.total) : 0;
  // ── 句子理解 ──
  final compP = s.total > 0 ? _clamp((((s.translated + s.language) / (2 * s.total)) * 100).round()) : 0;
  // ── 达标拷打 ──
  final studiedP = hasWords ? _pct(w.studied, w.total) : 0;
  final recallP = hasWords ? (studiedP * 0.5 + (quizAcc ?? studiedP) * 0.5).round() : 0;
  final recallDone = hasWords && w.studied >= w.total && (quizAcc == null || quizAcc >= 80);
  // ── 产出 ──
  final produceP = i.writes > 0 ? 100 : 0;
  // ── 语法专项 ──
  final grammarP = s.total > 0 ? _pct(s.language, s.total) : 0;

  final stages = <IntensiveStage>[
    IntensiveStage(
      key: IntensiveStageKey.skim,
      label: '通读',
      emoji: '👀',
      status: _statusOf(skimP),
      progress: skimP,
      detail: i.skimmed ? '已通读（能看懂大意）' : '先用速读过一遍，标出卡住的句子',
      action: intensiveStageAction[IntensiveStageKey.skim]!,
      enabled: i.hasDoc,
    ),
    IntensiveStage(
      key: IntensiveStageKey.vocab,
      label: '标词 / 查词',
      emoji: '🔍',
      status: _statusOf(vocabP),
      progress: vocabP,
      detail: hasWords
          ? '${w.withMeaning}/${w.total} 有释义${w.noExample > 0 ? ' · ${w.noExample} 个缺例句' : ''}'
          : '还没有生词：选词 / 自动标词，再一键跑批',
      action: intensiveStageAction[IntensiveStageKey.vocab]!,
      enabled: i.hasDoc,
    ),
    IntensiveStage(
      key: IntensiveStageKey.chunks,
      label: '词块',
      emoji: '🧩',
      status: _statusOf(chunksP),
      progress: chunksP,
      detail: hasWords
          ? '${w.withChunks}/${w.total} 有词组/搭配'
              '${w.chunksAsked > w.withChunks ? ' · 已问过 ${w.chunksAsked}' : ''}'
          : '先建生词，再补词组/习语',
      action: intensiveStageAction[IntensiveStageKey.chunks]!,
      enabled: hasWords,
    ),
    IntensiveStage(
      key: IntensiveStageKey.comprehend,
      label: '句子理解',
      emoji: '📖',
      status: _statusOf(compP),
      progress: compP,
      detail: s.total > 0 ? '译文 ${s.translated}/${s.total} · 语言点 ${s.language}/${s.total}' : '没有句子',
      action: intensiveStageAction[IntensiveStageKey.comprehend]!,
      enabled: i.hasDoc,
    ),
    IntensiveStage(
      key: IntensiveStageKey.recall,
      label: '达标拷打',
      emoji: '🥊',
      status: recallDone ? IntensiveStageStatus.done : _statusOf(recallP),
      progress: recallDone ? 100 : recallP,
      detail: hasWords
          ? '学过 ${w.studied}/${w.total} · 稳定 ${w.stable}'
              '${w.due > 0 ? ' · 到期 ${w.due}' : ''}'
              '${quizAcc != null ? ' · 考试 $quizAcc%' : ''}'
          : '先建生词，再来拷打',
      action: intensiveStageAction[IntensiveStageKey.recall]!,
      enabled: hasWords,
    ),
    IntensiveStage(
      key: IntensiveStageKey.produce,
      label: '产出（仿写）',
      emoji: '✍️',
      status: _statusOf(produceP),
      progress: produceP,
      detail: i.writes > 0 ? '已仿写 ${i.writes} 条' : '挑一个好句式，自己写一句再让 AI 批改',
      action: intensiveStageAction[IntensiveStageKey.produce]!,
      enabled: i.hasDoc,
    ),
    IntensiveStage(
      key: IntensiveStageKey.grammar,
      label: '语法专项',
      emoji: '🧠',
      status: _statusOf(grammarP),
      progress: grammarP,
      detail: s.total > 0
          ? '语言点 ${s.language}/${s.total} 句${hasWords && w.withMarks > 0 ? ' · 语法标记 ${w.withMarks} 词' : ''}'
          : '没有句子',
      action: intensiveStageAction[IntensiveStageKey.grammar]!,
      enabled: i.hasDoc,
    ),
  ];

  IntensiveStage stage(IntensiveStageKey k) => stages.firstWhere((x) => x.key == k);
  bool isDone(IntensiveStageKey k) => stage(k).status == IntensiveStageStatus.done;

  final passed = isDone(IntensiveStageKey.skim);
  final solid = passed &&
      isDone(IntensiveStageKey.vocab) &&
      compP >= 90 &&
      stage(IntensiveStageKey.recall).progress >= 60;
  final productive = solid && isDone(IntensiveStageKey.produce);
  final mastered = productive &&
      isDone(IntensiveStageKey.chunks) &&
      isDone(IntensiveStageKey.recall) &&
      isDone(IntensiveStageKey.grammar);
  final level = mastered ? 3 : (productive ? 2 : (solid ? 1 : 0));

  final progress = (stages.fold<int>(0, (a, x) => a + x.progress) / stages.length).round();
  IntensiveStage? next;
  for (final s0 in stages) {
    if (s0.status != IntensiveStageStatus.done) {
      next = s0;
      break;
    }
  }

  final nextKey = next?.key;
  return IntensivePlan(
    stages: stages,
    level: level,
    levelLabel: _levelLabels[level],
    levelDesc: _levelDescs[level],
    progress: progress,
    nextKey: nextKey,
    nextLabel: next != null ? '${next.label} · ${next.action}' : '本篇已精读到位 🎉',
    nextHint: nextKey != null ? _nextHints[nextKey]! : '隔天按到期复习，或换一篇新材料',
  );
}

/// 「有词块」的判定：用法要点 / 词组 / 习语，任一非空就算。
///
/// 精读工作流的「词块」阶段与产出看板的「词块覆盖」共用这一条 ——
/// 原来两处各写一遍，都漏了 `idioms`：只填了习语的词在两边都不算，进度永远差一截。
bool hasVocabChunks({
  required List<String> usage,
  List<String>? phrases,
  List<String>? idioms,
}) =>
    usage.isNotEmpty || (phrases?.isNotEmpty ?? false) || (idioms?.isNotEmpty ?? false);

/// 判定一个词条是否「稳定掌握」：复习次数够、间隔够、且没在最近出错。
///
/// 对应 Web `src/core/mastery.ts` 的 `isStable`。
bool isStableItem({required int repetitions, required int interval, int lapses = 0}) =>
    repetitions >= 2 && interval >= 6 && lapses == 0;

/// 从一批词里数出 [IntensiveWords]。
///
/// [items] 应当是**本篇普通单词**（不含词组 / 习语 / 用法笔记）：这里的口径问的是
/// 「这个词背得怎么样」，语言点条目按设计永远不进背词牌组，拿它们当分母会让
/// 「学过 N/M」到不了 100%。
IntensiveWords intensiveWordsOf(List<VocabItem> items, {DateTime? now}) {
  var withMeaning = 0;
  var withChunks = 0;
  var chunksAsked = 0;
  var withMarks = 0;
  var studied = 0;
  var stable = 0;
  var due = 0;
  var noExample = 0;
  for (final it in items) {
    final hasMeaning = (it.meaning ?? '').trim().isNotEmpty;
    final chunks = hasVocabChunks(usage: it.usage, phrases: it.phrases, idioms: it.idioms);
    if (hasMeaning) withMeaning++;
    if (chunks) withChunks++;
    // 「问过没有」看字段在不在（跑批一定同时写 phrases/idioms，空数组 = AI 说「无」）
    if (it.phrases != null || chunks) chunksAsked++;
    if (it.grammarMarks != null && it.grammarMarks!.isNotEmpty) withMarks++;
    if (hasReviewHistory(it)) studied++;
    final rs = it.reviewState;
    if (isStableItem(
      repetitions: rs.repetitions,
      interval: rs.interval,
      lapses: rs.lapses,
    )) {
      stable++;
    }
    if (isDue(it, now)) due++;
    if (hasMeaning && needsAiExamples(it)) noExample++;
  }
  return IntensiveWords(
    total: items.length,
    withMeaning: withMeaning,
    withChunks: withChunks,
    chunksAsked: chunksAsked,
    withMarks: withMarks,
    studied: studied,
    stable: stable,
    due: due,
    noExample: noExample,
  );
}
