/// 「这一轮考哪些词、怎么出卷」的规则（纯函数）。
///
/// 范围（全库 / 本篇 / 未掌握 / 到期 / 常错）× 题型 → 候选池；再交给
/// [buildQuizSet] 出卷。规则放这里（带测试），`DrillViewModel` 只负责拿结果去跑会话。
///
/// 对应 Web 版 `src/core/quizPool.ts`（100 行）。那边的 `buildQuizSet` 里
/// `shuffleQuiz` 用 `Math.random`，这边注入 `rnd` 好让测试确定。
library;

import '../models/vocab.dart';
import 'article_vocab.dart' show kindOfItem;
import 'entry_kind.dart' show isStudyable;
import 'quiz.dart';
import 'vocab/review.dart' show isDue;

/// 整卷考试的模式。
///
/// 前两种分开开考（不是默认混在一起）：文章题不写 SRS / 错题本，统计也算「读」，
/// 混在一起会让判分落盘和正确率口径分叉 —— 所以要混得显式选 [mixed]。
///
/// [dictation] 是「听写」：按文章原句顺序，每句挖一个词做听音填空
/// （`quiz.dart` 的 `makeDictationQuestion`），考的是「听得出、写得出」。
enum QuizMode { vocab, article, dictation, mixed }

const Map<QuizMode, String> quizModeLabel = <QuizMode, String>{
  QuizMode.vocab: '词级卷',
  QuizMode.article: '文章卷',
  QuizMode.dictation: '听写',
  QuizMode.mixed: '混合卷',
};

/// 这个模式要不要选一篇（听写按文章句子走，必须选）。
bool quizModeNeedsArticle(QuizMode mode) =>
    mode != QuizMode.vocab;

/// 考试范围。
enum QuizScope {
  all,
  article,
  unmastered,
  due,
  lapses;

  /// 存档用（不存序号，插值不会错位）。
  String get storage => name;
}

const Map<QuizScope, String> quizScopeLabel = <QuizScope, String>{
  QuizScope.all: '全库',
  QuizScope.article: '本篇',
  QuizScope.unmastered: '未掌握',
  QuizScope.due: '到期',
  QuizScope.lapses: '常错',
};

/// 宽容解析：认不出回 [QuizScope.article]（拷打默认只看本篇）。
QuizScope parseQuizScope(Object? raw) {
  if (raw is QuizScope) return raw;
  if (raw is String) {
    for (final s in QuizScope.values) {
      if (s.name == raw) return s;
    }
  }
  return QuizScope.article;
}

/// 能拿来出题的词条。
///
/// 用法笔记（中文说明）不出题；没有释义的是废卡（选义题出不了、拼写题提示为空）。
List<VocabItem> quizStudyableItems(List<VocabItem> items) => items
    .where((it) => isStudyable(
          kind: kindOfItem(it),
          word: it.word,
          meaning: it.meaning,
        ))
    .toList(growable: false);

/// 「本篇」认哪些词：收进本篇的（`source.fileName` 对得上）**或**正文里出现过的。
///
/// 两条并起来是有意的：只走查词没点「收进本篇」的词，正文里明明有，
/// 不该因为没点按钮就考不到。
class QuizPoolContext {
  const QuizPoolContext({
    this.articleIdentity = '',
    this.docLemmas = const <String>{},
  });

  /// 当前文章身份（词条的 `source.fileName` 用它认「本篇的词」）。
  final String articleIdentity;

  /// 本篇正文出现的 lemma。
  final Set<String> docLemmas;
}

/// 按范围取候选词。[studyable] 先过一次 [quizStudyableItems] 更省。
List<VocabItem> quizPool(
  List<VocabItem> studyable,
  QuizScope scope,
  QuizPoolContext ctx, {
  DateTime? now,
}) {
  final at = now ?? DateTime.now();
  switch (scope) {
    case QuizScope.all:
      return studyable;
    case QuizScope.due:
      return studyable.where((it) => isDue(it, at)).toList(growable: false);
    case QuizScope.lapses:
      return studyable
          .where((it) => it.reviewState.lapses > 0)
          .toList(growable: false);
    case QuizScope.unmastered:
      return studyable
          .where((it) => it.status != VocabStatus.mastered)
          .toList(growable: false);
    case QuizScope.article:
      return studyable
          .where((it) =>
              it.source?.fileName == ctx.articleIdentity ||
              it.source?.articleId == ctx.articleIdentity ||
              ctx.docLemmas.contains(it.lemma))
          .toList(growable: false);
  }
}

/// 出一份题集。
///
/// [unique] 开着（默认）= 每个词最多出一题（题型随机轮一遍，先出得来的先出）；
/// 关掉 = 交给 [buildQuizQuestions]（同词多题型都可能出现）。
List<QuizQuestion> buildQuizSet(
  List<VocabItem> items,
  List<QuizKind> kinds, {
  bool unique = true,
  double Function() rnd = _defaultRnd,
}) {
  if (!unique) return buildQuizQuestions(items, kinds);
  final out = <QuizQuestion>[];
  for (final it in shuffleQuiz(items, rnd)) {
    for (final k in shuffleQuiz(kinds, rnd)) {
      final q = makeQuestion(it, k, items);
      if (q != null) {
        out.add(q);
        break;
      }
    }
  }
  return out;
}

/// 默认随机源（固定种子，测试不注入时也能复现）。
double _defaultRnd() {
  _seed = (_seed * 1103515245 + 12345) & 0x7FFFFFFF;
  return _seed / 0x7FFFFFFF;
}

int _seed = 20261113;

/// 把题集截到 [limit] 题；[limit] <= 0 表示不限。
List<QuizQuestion> limitQuizSet(List<QuizQuestion> set, int limit) =>
    limit <= 0 || set.length <= limit ? set : set.sublist(0, limit);

/// 整卷考试的题量档位；`0` = 不限。
///
/// 与 Web 版 `useQuizSettings.ts` 的默认题量 20 对齐；拷打那边的 5/10/15/20/30
/// 是另一套（每档各记各的），别混用。
const List<int> quizLimitOptions = <int>[5, 10, 20, 30, 0];
const int defaultQuizLimit = 20;

/// 这个数是不是合法题量（0 = 不限）。
bool isQuizLimit(int n) => n == 0 || n == 5 || n == 10 || n == 20 || n == 30;

/// 宽容解析：不在档位里就回默认 20。
int normalizeQuizLimit(Object? raw) {
  final n = switch (raw) {
    int i => i,
    num d when d.isFinite => d.toInt(),
    String s => int.tryParse(s.trim()),
    _ => null,
  };
  return (n != null && isQuizLimit(n)) ? n : defaultQuizLimit;
}

/// 题量显示文案（0 显示「不限」）。
String quizLimitLabel(int n) => n <= 0 ? '不限' : '$n 题';

/// 整卷考试的默认题型（照 Web `useQuizSettings.ts` 默认值）。
///
/// 词级默认只考拼写 / 例句填空 / 搭配填空；
/// 文章级默认**不含 grammar、含 phraseBlank** —— 与 `buildArticleQuestions`
/// 自己的默认值正好相反，所以组卷时必须显式传 kinds。
const List<QuizKind> defaultQuizVocabKinds = <QuizKind>[
  QuizKind.spell,
  QuizKind.cloze,
  QuizKind.usage,
];
const List<QuizKind> defaultQuizArticleKinds = <QuizKind>[
  QuizKind.translate,
  QuizKind.translate2,
  QuizKind.functionWord,
  QuizKind.ordering,
  QuizKind.phraseBlank,
];
