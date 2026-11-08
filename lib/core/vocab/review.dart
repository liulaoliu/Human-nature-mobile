import '../../models/vocab.dart';
import 'library.dart';
import 'word.dart';

/// 复习排期（SM-2 变体）与背单词队列。
///
/// 到期 / 间隔 / 优先重排的顺序全在这里算，视图只消费结果。
/// 与 Web 版 `src/core/vocab/review.ts` 一一对应。

/// 复习评分：四个按钮。
enum ReviewGrade { again, hard, good, easy }

/// 背单词的两种模式：新学习 / 复习。
enum StudyMode { learn, review }

int _quality(ReviewGrade g) => switch (g) {
      ReviewGrade.again => 1,
      ReviewGrade.hard => 3,
      ReviewGrade.good => 4,
      ReviewGrade.easy => 5,
    };

/// 重学阶段最多累计到几（只用于展示/审计，不影响队列上限）。
const int relearnMax = 3;

/// 按**本地日历**加天数（对应 Web 版 `setDate(getDate() + n)`）。
///
/// 不能直接 `add(Duration(days: n))`：那是加 24 小时，遇到夏令时会漂一小时；
/// 也不能在 UTC 上算，因为 Web 版是按本地日历切的，两边结果必须一致。
DateTime _addDays(DateTime d, int days) {
  final local = d.toLocal();
  return DateTime(local.year, local.month, local.day + days, local.hour, local.minute,
      local.second, local.millisecond, local.microsecond);
}

/// 拼错 / 记住过又忘的词打的标签。
const String spellingMissTag = '不认识';

/// SM-2 变体的复习推进。纯函数，返回新的 [ReviewState]。
///
///   - again（q=1）：重来，repetitions 归零，间隔 1 天，ease −0.2（下限 1.3），
///     并进入 / 保持「重学」状态（`relearn + 1`，上限 3）。
///   - 重学中的词答对：1 天 → 3 天，**连续第二次答对才退出重学**，之后回到正常间隔。
///   - 正常词 hard/good/easy：repetitions +1，间隔 1 → 6 → round(interval × ease)
///
/// 为什么重学要单独一档：以前 again 只把 repetitions 归零，词就掉回「新词」，
/// 复习队列只看 repetitions > 0，于是「记住过又忘」的词会在复习模式里消失。
/// 现在 `relearn` 是显式状态，队列据此把它排在复习最前，并按 1→3 天巩固。
ReviewState review(ReviewState state, ReviewGrade grade, [DateTime? now]) {
  final at = now ?? DateTime.now();
  final q = _quality(grade);
  var ease = state.ease;
  var interval = state.interval;
  var repetitions = state.repetitions;
  var lapses = state.lapses;
  var relearn = state.relearn;
  if (q < 3) {
    repetitions = 0;
    interval = 1;
    ease = ease - 0.2 < 1.3 ? 1.3 : ease - 0.2;
    lapses += 1;
    relearn = relearn + 1 > relearnMax ? relearnMax : relearn + 1;
  } else {
    repetitions += 1;
    if (relearn > 0) {
      // 重学阶梯：先 1 天，再 3 天；第二次答对才退出重学状态
      if (repetitions == 1) {
        interval = 1;
      } else if (repetitions == 2) {
        interval = 3;
        relearn = 0;
      } else {
        final next = (interval * ease).round();
        interval = next > 6 ? 6 : next;
      }
    } else if (repetitions == 1) {
      interval = 1;
    } else if (repetitions == 2) {
      interval = 6;
    } else {
      interval = (interval * ease).round();
    }
    final adjusted = ease + (0.1 - (5 - q) * (0.08 + (5 - q) * 0.02));
    ease = adjusted < 1.3 ? 1.3 : adjusted;
  }
  return state.copyWith(
    ease: ease,
    interval: interval,
    repetitions: repetitions,
    due: () => _addDays(at, interval).toUtc().toIso8601String(),
    lapses: lapses,
    relearn: relearn,
  );
}

/// 这个词是不是正在重学（拼错 / 记住过又忘记）。
bool isRelearning(VocabItem item) => item.reviewState.relearn > 0;

/// 从没被排期过的新词。
///
/// 不能再用 `repetitions == 0` 判断：答错后 repetitions 也会归零，
/// 那样「学过但忘了」的词会被当成新词，既占每日新词配额、又挤不进复习队列。
bool isFresh(VocabItem item) {
  final rs = item.reviewState;
  return !isRelearning(item) && rs.repetitions == 0 && rs.interval == 0 && rs.due == null;
}

/// 有过学习记录（排过期 / 答错过 / 正在重学）。
bool hasReviewHistory(VocabItem item) {
  final rs = item.reviewState;
  return isRelearning(item) || rs.repetitions > 0 || rs.interval > 0 || rs.due != null;
}

/// 推进某个词条的复习状态。
VocabLibrary reviewItem(VocabLibrary library, String id, ReviewGrade grade, [DateTime? now]) {
  final at = now ?? DateTime.now();
  return library.copyWith(
    items: [
      for (final it in library.items)
        if (it.id == id)
          it.copyWith(reviewState: review(it.reviewState, grade, at), updatedAt: at.toUtc().toIso8601String())
        else
          it,
    ],
  );
}

/// 到期了没有（含逾期）。
bool isDue(VocabItem item, [DateTime? now]) {
  final due = item.reviewState.due;
  if (due == null) return false;
  final at = DateTime.tryParse(due);
  if (at == null) return false;
  return !at.isAfter(now ?? DateTime.now());
}

/// 这个词要不要在复习 / 加练时先做「选中文释义」。
///
/// 起因：第一次学习就点「不认识」的词，第二次及以上如果仍然模糊或继续标不认识，
/// 只翻面看释义记不住。规则只在**已经标过不认识 / 正在重学**的词上生效：
///   - 正在重学的词（拼错、记住过又忘）→ 每次出场都先选释义；
///   - 记忆还没重新建立（repetitions = 0）→ 每次出场先选释义；
///   - 本轮加练 / 收尾重练 → 即使刚评过模糊（repetitions 已 +1）也要先选。
///
/// 不按 lapses 猜：lapses 只记「忘记」，普通第一次忘记不等于「不认识」。
bool needsMeaningCheck(VocabItem item, {bool extra = false, bool retrying = false}) {
  if (isRelearning(item)) return true;
  if (!item.tags.contains(spellingMissTag)) return false;
  return item.reviewState.repetitions == 0 || extra || retrying;
}

/// 词库够不够出「正确释义 + 3 个干扰项」。
///
/// 与 [needsMeaningCheck] 分开：规则说该考，但词库太小出不了题时退回普通卡片。
bool canQuizMeaning(VocabItem item, List<VocabItem> items) {
  final correct = _meaningOf(item);
  if (correct.isEmpty) return false;
  final others = <String>{
    for (final it in items)
      if (it.id != item.id)
        if (_meaningOf(it).isNotEmpty) _meaningOf(it),
  }..remove(correct);
  return others.length >= 3;
}

String _meaningOf(VocabItem item) =>
    displayMeaning(partOfSpeech: item.partOfSpeech, meaning: item.meaning);

/// 到期（含逾期）的词条，按到期时间升序。
List<VocabItem> dueItems(List<VocabItem> items, [DateTime? now]) =>
    sortItems(items.where((it) => isDue(it, now)).toList(), VocabSortBy.due);

/// 次日 ISO（优先重排用）。
String nextDayIso([DateTime? now]) =>
    _addDays(now ?? DateTime.now(), 1).toUtc().toIso8601String();

int _rank(VocabItem it, DateTime now) => isRelearning(it) ? 0 : (isPriority(it, now: now) ? 1 : 2);

int _byDue(VocabItem a, VocabItem b, DateTime now) {
  final r = _rank(a, now) - _rank(b, now);
  if (r != 0) return r;
  final d = (a.reviewState.due ?? '').compareTo(b.reviewState.due ?? '');
  if (d != 0) return d;
  return a.createdAt.compareTo(b.createdAt);
}

/// 背单词的出场顺序：先到期的，再没学过的，最后其它。
///
/// [newLimit] / [newToday] 用来限制「每天新词量」。
/// 到期组里：正在重学的排最前，其次「优先重排」（答错过的词），再按到期时间。
List<VocabItem> buildStudyQueue(
  List<VocabItem> items, [
  DateTime? now,
  int newLimit = 0,
  int newToday = 0,
]) {
  final at = now ?? DateTime.now();
  final due = items.where((it) => isDue(it, at)).toList()
    ..sort((a, b) => _byDue(a, b, at));
  final freshAll = items.where((it) => isFresh(it) && !isDue(it, at)).toList();
  final remaining = newLimit > 0 ? (newLimit - newToday).clamp(0, newLimit) : null;
  final fresh = remaining == null ? freshAll : freshAll.take(remaining).toList();
  final rest = items.where((it) => hasReviewHistory(it) && !isDue(it, at)).toList()
    ..sort((a, b) => _byDue(a, b, at));
  return [...due, ...fresh, ...rest];
}

/// 新学习队列：只取从来没排期过的新词，按加入时间。
///
/// 受每日新词配额限制（[newLimit] / [newToday]）。
/// 重学中的词**不在这里**：它们有学习记录，走复习队列（见 [buildReviewQueue]），
/// 否则「以前认识、这次忘了」会被当成新词再学一遍、还占配额。
List<VocabItem> buildLearnQueue(
  List<VocabItem> items, [
  DateTime? now,
  int newLimit = 0,
  int newToday = 0,
]) {
  final fresh = items.where(isFresh).toList()
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  final remaining = newLimit > 0 ? (newLimit - newToday).clamp(0, newLimit) : null;
  return remaining == null ? fresh : fresh.take(remaining).toList();
}

/// 复习队列：所有「学过且到期」的，重学中的排最前，其次优先重排，再按到期时间升序。
///
/// 判断用 [hasReviewHistory] 而不是 `repetitions > 0`：答错后 repetitions 会归零，
/// 但它仍然需要复习；把这类词排除掉，就等于把「记住过又忘」的词直接跳过了。
List<VocabItem> buildReviewQueue(List<VocabItem> items, [DateTime? now]) {
  final at = now ?? DateTime.now();
  return items.where((it) => hasReviewHistory(it) && isDue(it, at)).toList()
    ..sort((a, b) {
      final r = (isRelearning(a) ? 0 : 1) - (isRelearning(b) ? 0 : 1);
      if (r != 0) return r;
      final p = (isPriority(a, now: at) ? 0 : 1) - (isPriority(b, now: at) ? 0 : 1);
      if (p != 0) return p;
      final d = (a.reviewState.due ?? '').compareTo(b.reviewState.due ?? '');
      if (d != 0) return d;
      return a.createdAt.compareTo(b.createdAt);
    });
}

/// 「每组 N 词」的组末边界（纯函数）。
///
/// 学习模式学到组末要停下做拼写测试（本组学了多少就拼多少），
/// 组的切分只看**队列里的位置**：加练重排回队尾的词自然归到后面的组，不打乱前面的组。
/// `size <= 0` 或 ≥ 总数 = 不分组，整轮就是一组。
int groupEndOf(int index, int total, int size) {
  if (total <= 0) return 0;
  final n = size > 0 ? size : 0;
  if (n == 0 || n >= total) return total;
  final at = index < 0 ? 0 : index;
  final end = ((at ~/ n) + 1) * n;
  return end < total ? end : total;
}
