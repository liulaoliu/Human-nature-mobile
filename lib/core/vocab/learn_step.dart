import '../../models/vocab.dart';
import 'review.dart';

/// 「学习新单词」里 4 条中文释义这一步的判定（纯函数）。
///
/// 为什么单独一个文件：这一步的规则和复习侧的「认识 / 模糊 / 忘记了」不是一回事——
/// 它多了一个「你有没有看答案」的信号，判定结果也不一样：
///
///   - 点了「看答案」    → 不认识（again）；先高亮正确释义停留一下，再进单词卡
///   - 没看答案、选错    → 不认识（again）；正确标浅绿、你选的那个标浅红，点「继续」才进单词卡
///   - 没看答案、选对    → 首次「模糊」（hard），第二次起「认识」（good）；直接进单词卡
///
/// 「首次只给模糊」是刻意的：四个选项里蒙对的概率不低，
/// 只有**下次又选对一次**才说明真记住了（次数记在 `ReviewState.meaningPasses`，跨轮持久）。
///
/// 判定之后不管走哪条路，**都要进单词卡**：看一遍释义/例句/用法，
/// 既是防蒙对，也是把这一次出场变成一次真正的记忆动作。
/// 与 Web 版 `src/core/vocab/learnStep.ts` 一一对应。

/// 点了「看答案」后，先高亮正确释义停留多久再切到单词卡。期间点击 / 按键可打断。
const Duration learnRevealHold = Duration(milliseconds: 600);

/// 学习模式这一步用户做了什么。
enum LearnAction { reveal, correct, wrong }

/// 判定结果：三种走向。
enum LearnStepKind {
  /// 词库不够 4 个选项：退回「看词 → 显示释义 → 三档评分」。
  fallback,

  /// 停在释义页高亮：正确项浅绿；选错时你点的那项浅红。**不评分、不换页**。
  hold,

  /// 直接进单词卡（选对了）。
  card,
}

class LearnStep {
  const LearnStep({
    required this.kind,
    this.grade,
    this.auto = false,
    this.wrong = false,
    this.pass = false,
    this.label = '',
  });

  const LearnStep.fallback()
      : kind = LearnStepKind.fallback,
        grade = null,
        auto = false,
        wrong = false,
        pass = false,
        label = '';

  final LearnStepKind kind;

  /// 要走哪一档评分（fallback 时为 null）。
  final ReviewGrade? grade;

  /// true = 停留 [learnRevealHold] 后自动进单词卡（看答案）；false = 等用户点「继续」（选错）。
  final bool auto;

  /// 是否连你选错的那项一起标红。
  final bool wrong;

  /// 这次算不算「选对」（写 meaningPasses 用）。
  final bool pass;

  final String label;
}

/// 脏值（负数 / 小数 / 越界）一律按「没选对过」算。
int normPasses(int? n) => (n != null && n > 0) ? n : 0;

/// 这个词「没看答案就选对」过几次。
int meaningPassesOf(VocabItem item) => normPasses(item.reviewState.meaningPasses);

/// 下一次该记几次：选对 +1；判为不认识（看答案 / 选错 / 拼错）**归零**——
/// 都从头学，不再享受「上次选对过」的信用。
int nextMeaningPasses(int passes, bool pass) => pass ? normPasses(passes) + 1 : 0;

/// 判定这一步。规则见文件头；[canQuiz] 为假时不做判定（UI 退回普通卡）。
LearnStep gradeLearnStep({
  required LearnAction action,
  required int passes,
  required bool canQuiz,
}) {
  if (!canQuiz) return const LearnStep.fallback();
  final n = normPasses(passes);
  switch (action) {
    case LearnAction.reveal:
      return const LearnStep(
        kind: LearnStepKind.hold,
        grade: ReviewGrade.again,
        auto: true,
        label: '不认识 · 看了答案',
      );
    case LearnAction.wrong:
      return const LearnStep(
        kind: LearnStepKind.hold,
        grade: ReviewGrade.again,
        wrong: true,
        label: '不认识 · 选错了',
      );
    case LearnAction.correct:
      final grade = n > 0 ? ReviewGrade.good : ReviewGrade.hard;
      return LearnStep(
        kind: LearnStepKind.card,
        grade: grade,
        pass: true,
        label: grade == ReviewGrade.good ? '认识 · 又选对一次' : '模糊 · 第一次选对',
      );
  }
}

/// 把「选对次数」写回词库（只改这一条，其它条目保持原引用）。
///
/// Dart 侧 `meaningPasses` 是 `int`（默认 0），不需要像 Web 版那样在归零时摘字段；
/// 次数没变就原样返回，别白写一次词库。
VocabLibrary recordLearnPass(VocabLibrary library, String id, bool pass, [DateTime? now]) {
  final at = now ?? DateTime.now();
  VocabItem? cur;
  for (final it in library.items) {
    if (it.id == id) {
      cur = it;
      break;
    }
  }
  if (cur == null) return library;
  final next = nextMeaningPasses(meaningPassesOf(cur), pass);
  if (next == cur.reviewState.meaningPasses) return library;
  return library.copyWith(
    items: [
      for (final it in library.items)
        if (it.id != id)
          it
        else
          it.copyWith(
            reviewState: it.reviewState.copyWith(meaningPasses: next),
            updatedAt: at.toUtc().toIso8601String(),
          ),
    ],
  );
}
