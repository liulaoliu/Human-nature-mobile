import 'package:flutter/foundation.dart';

import '../core/activity/activity.dart' show ActivityCat, dayKeyLocal;
import '../core/entry_kind.dart';
import '../core/learning.dart';
import '../core/study_pool.dart';
import '../core/study_pool.dart' as pool_rules show effectiveGroupSize;
import '../core/study_prefs.dart';
import '../core/study_session.dart';
import '../core/vocab/learn_step.dart';
import '../core/vocab/review.dart';
import '../data/prefs_store.dart';
import '../data/repositories/learning_repository.dart';
import '../data/repositories/vocab_repository.dart';
import '../models/vocab.dart';
import '../services/study_ledger.dart';
import 'study_settings.dart';

/// 背单词页的 ViewModel：设置 → 候选池 → 会话 → 落盘。
///
/// 分三层，各管一段：
///   - **池子**（`core/study_pool.dart`）：范围 / 牌组 / 组大小；
///   - **时序**（`core/study_session.dart`）：队列、评分、组末拼写、重练；
///   - **这里**：把两者接起来，并把「词库变了」「学习记录变了」写回仓库。
///
/// 为什么词库要冲突重放而不是直接覆盖：背上半小时里另一端（精读页）完全可能也在
/// 标词。`VocabRepository.save` 用乐观锁挡第二种写法，这里收到 [VocabConflict] 就
/// 「读最新 → 只把自己动过的那几条盖回去 → 再存一次」，而不是拿旧快照整体覆盖。
class StudyViewModel extends ChangeNotifier {
  StudyViewModel({
    required VocabRepository vocab,
    required LearningRepository learning,
    PrefsStore? prefsStore,
  })  : _vocabRepo = vocab,
        _learningRepo = learning,
        settings = StudySettings(store: prefsStore ?? PrefsStore.memory()) {
    // 设置变了也要让「watch StudyViewModel 的界面」重画：页面只订阅这一个
    // notifier，不能要求每个卡片自己再去 watch settings。
    settings.addListener(notifyListeners);
  }

  final VocabRepository _vocabRepo;
  final LearningRepository _learningRepo;

  /// 设置控制器（范围 / 牌组 / 每组 / 每日新词额度）。
  ///
  /// 单独一个 `ChangeNotifier`：设置写失败只回默认，会话写失败要保词库，
  /// 两件事不该共用一份「忙 / 报错」状态。
  final StudySettings settings;

  VocabLibrary? _library;
  String? _libraryUpdatedAt;
  StudySession? _session;
  StudyLedger? _ledger;
  GradeOutcome? _lastOutcome;
  bool _busy = false;
  String? _error;
  String? _saveError;
  String? _articleId;
  Set<String> _docLemmas = const <String>{};

  /// 当前设置（范围 / 牌组 / 每组 / 每日新词额度）。
  StudyPrefs get prefs => settings.prefs;

  /// 当前范围。
  StudyScope get scope => settings.prefs.scope;

  /// 当前牌组（只看单词 / 只看搭配）。
  StudyDeck get deck => settings.prefs.deck;

  /// 手动设的「每组 N 词」，0 = 跟随范围。
  int get groupSize => settings.prefs.groupSize;

  /// 每天最多引入多少新词，0 = 不限。
  int get newLimit => settings.prefs.newLimit;

  /// 今天已经引入多少（跨结算点自动归零）。
  int get newToday => settings.prefs.rollOver(dayKeyLocal()).newToday;

  /// 今天还能引入几个新词；[newLimit] 为 0 时返回 0（界面据此决定显不显示）。
  int get remainingNew => settings.prefs.rollOver(dayKeyLocal()).remainingNew;

  /// 正在读库 / 写库。
  bool get busy => _busy;

  /// 读库失败的原因。
  String? get error => _error;

  /// 词库写不进去的原因（界面可以只提示、不打断）。
  String? get saveError => _saveError;

  /// 当前词库（没有就是空库，不是 null——界面不用到处判空）。
  VocabLibrary get library => _library ?? const VocabLibrary();

  /// 当前这一轮的会话状态机；还没开始时是 null。
  StudySession? get session => _session;

  /// 有没有正在进行的这一轮。
  bool get started => _session != null && _session!.roundTotal > 0;

  /// 最近一次判分结果（界面读 `label` / `interval`）。
  GradeOutcome? get lastOutcome => _lastOutcome;

  /// 当前候选池（按范围 + 牌组筛）。
  List<VocabItem> get pool => studyPool(
        library: library,
        scope: scope,
        deck: deck,
        articleId: _articleId,
        docLemmas: _docLemmas,
      );

  /// 池子的三个计数（面板显示「到期 N · 新词 M」）。
  StudyPoolCounts get poolCounts => studyPoolCounts(pool);

  /// 组大小生效值（本篇 = 整篇，其它 = 20，手动设了就用手动值）。
  int get effectiveGroupSize => pool_rules.effectiveGroupSize(
        groupSize: groupSize,
        scope: scope,
        poolLength: pool.length,
      );

  /// 今天背过多少个不重复的词。
  int get studiedToday => _ledger?.studiedCount ?? 0;

  /// 初始化：读词库 + 读学习记录 + 读设置。
  Future<void> bootstrap() => _guard(() async {
        _library = await _vocabRepo.load();
        _libraryUpdatedAt = (await _vocabRepo.meta())?.at;
        _ledger = StudyLedger(data: await _learningRepo.load());
        // 设置由 StudySettings 自己读，这里只把「忙」状态管好。
        settings.load();
      });

  /// 「本篇」范围要传当前文章 id 与正文词形集合。
  void setArticleContext(String? articleId, {Set<String> docLemmas = const <String>{}}) {
    _articleId = articleId;
    _docLemmas = docLemmas;
    notifyListeners();
  }

  /// 开一轮：按当前池子装队列。
  ///
  /// [mode] 决定取哪一批：学习模式只要新词（[buildLearnQueue]），复习模式只要到期的
  /// （[buildReviewQueue]）。学习模式还要过「每日新词额度」：`newLimit > 0` 时今天
  /// 最多再引入 `newLimit - newToday` 个（跨结算点由 `StudyPrefs.rollOver` 归零）。
  /// 返回这一轮装了几张卡——0 就是没东西可背。
  int startRound({StudyMode mode = StudyMode.learn}) {
    final source = pool;
    final prefs = settings.prefs.rollOver(dayKeyLocal());
    final items = mode == StudyMode.learn
        ? buildLearnQueue(source, null, prefs.newLimit, prefs.newToday)
        : buildReviewQueue(source);
    if (items.isEmpty) {
      _session = null;
      _lastOutcome = null;
      if (mode == StudyMode.learn &&
          prefs.newLimit > 0 &&
          prefs.remainingNew == 0 &&
          source.isNotEmpty) {
        _error = '今天的新词额度用完了（${prefs.newToday}/${prefs.newLimit}），'
            '明天再来，或去设置里调高上限';
      }
      notifyListeners();
      return 0;
    }
    final next = StudySession(library: library, groupSize: effectiveGroupSize);
    next.start(items);
    _session = next;
    _lastOutcome = null;
    notifyListeners();
    return items.length;
  }

  /// 结束这一轮（回到设置页）。
  void endRound() {
    _session = null;
    _lastOutcome = null;
    notifyListeners();
  }

  /// 评一档（认识 / 模糊 / 忘记）。
  Future<void> grade(ReviewGrade value, {bool? learnPass}) async {
    final s = _session;
    if (s == null) return;
    final before = s.library;
    final card = s.card;
    final outcome = s.grade(value, learnPass: learnPass);
    _lastOutcome = outcome;
    if (card != null) _recordStudy(card.id);
    if (outcome.firstNew) await _bumpNewToday();
    await _persist(before: before, after: s.library);
    notifyListeners();
  }

  /// 「选中文释义」那一步：翻面（hold）不写库，选对/选错才写。
  Future<LearnStep?> learnStep(LearnAction action) async {
    final s = _session;
    if (s == null) return null;
    final before = s.library;
    final card = s.card;
    final step = s.learn(action);
    _lastOutcome = null;
    if (step.kind == LearnStepKind.card) {
      if (card != null) _recordStudy(card.id);
      if (s.lastFirstNew) await _bumpNewToday();
      await _persist(before: before, after: s.library);
    }
    notifyListeners();
    return step;
  }

  /// 卡面拼写判卷：对 = 认识，错 = 忘记 + 打标签。
  Future<bool> checkSpelling(String input) async {
    final s = _session;
    if (s == null) return false;
    final before = s.library;
    final card = s.card;
    final ok = s.checkSpelling(input);
    _lastOutcome = null;
    if (card != null) _recordStudy(card.id);
    await _persist(before: before, after: s.library);
    notifyListeners();
    return ok;
  }

  /// 组末拼写的受控输入框。
  void setSpellingInput(String value) {
    _session?.setSpellingInput(value);
    notifyListeners();
  }

  /// 放行「选中文释义」门禁。
  void clearMeaningGate() {
    _session?.clearMeaningGate();
    notifyListeners();
  }

  /// 清掉上一张的提示文案。
  void clearLastOutcome() {
    if (_lastOutcome == null) return;
    _lastOutcome = null;
    _session?.clearGradeInfo();
    notifyListeners();
  }

  /// 下一张（不评分）。
  void forward() {
    if (_session?.forward() ?? false) _lastOutcome = null;
    notifyListeners();
  }

  /// 上一张。
  void back() {
    _session?.back();
    notifyListeners();
  }

  /// 收尾重练忘记过的词（一轮只发起一次）。
  bool retryForgot() {
    final ok = _session?.retryForgot() ?? false;
    _lastOutcome = null;
    notifyListeners();
    return ok;
  }

  /// 把学习记录落盘（今天学过哪些词 + 背了几个）。
  ///
  /// 只写 `studiedDays` / `activity` 两段：别的段这一页根本不碰，写多了反而会
  /// 拿旧快照盖掉别处刚记的东西。
  Future<void> flushLedger() async {
    final ledger = _ledger;
    if (ledger == null || !ledger.dirty) return;
    final data = ledger.data;
    await _guard(() async {
      await _learningRepo.write(
        data,
        const [LearningSection.studiedDays, LearningSection.activity],
      );
    });
  }

  /// 记一次「今天引入了一个新词」并落盘。
  ///
  /// 跨结算点自动归零（`StudyPrefs.rollOver` 按 `dayKeyLocal` 判），所以页面一直
  /// 开着跨过 04:00 也不会把昨天的额度算到今天头上。
  Future<void> _bumpNewToday() async {
    await settings.bumpNewToday();
    if (settings.error != null) _saveError = settings.error;
  }

  void _recordStudy(String id) {
    final ledger = _ledger;
    if (ledger == null) return;
    ledger.markStudied(id);
    ledger.recordActivity(ActivityCat.vocab);
  }

  /// 词库变了就写盘。冲突时重读后把这次改动重放一遍，不是直接覆盖。
  ///
  /// 写盘带 [VocabRepository.save] 的乐观锁（`baseUpdatedAt`）：背上半小时里精读页
  /// 完全可能也在标词，没有这层就会互相盖掉。
  Future<void> _persist({
    required VocabLibrary before,
    required VocabLibrary after,
  }) async {
    if (identical(before, after)) return;
    try {
      final saved = await _vocabRepo.save(after, baseUpdatedAt: _libraryUpdatedAt);
      _library = after;
      _libraryUpdatedAt = saved.updatedAt;
      _saveError = null;
    } on VocabConflict {
      try {
        final fresh = await _vocabRepo.load() ?? const VocabLibrary();
        final merged = _replay(fresh, after, _touchedIds(before, after));
        final saved = await _vocabRepo.save(merged, baseUpdatedAt: (await _vocabRepo.meta())?.at);
        _library = merged;
        _libraryUpdatedAt = saved.updatedAt;
        _saveError = null;
      } catch (e) {
        _saveError = '词库写不进去：$e';
      }
    } catch (e) {
      _saveError = '词库写不进去：$e';
    }
  }

  /// 这次改动碰到的 id（按内容差异算，不看引用）。
  ///
  /// `VocabItem` 没有重载 `==`，只能挑能代表「判过一次分」的字段比：复习状态
  /// （有 `==`）、标签（拼错会加「不认识」）、更新时间。
  Set<String> _touchedIds(VocabLibrary before, VocabLibrary after) {
    final prev = {for (final it in before.items) it.id: it};
    final out = <String>{};
    for (final it in after.items) {
      final old = prev[it.id];
      if (old == null ||
          old.reviewState != it.reviewState ||
          old.tags.join('\u0000') != it.tags.join('\u0000')) {
        out.add(it.id);
      }
    }
    return out;
  }

  /// 把 [patched] 里 [ids] 覆盖到 [base] 上（顺序跟 [base] 走）。
  VocabLibrary _replay(VocabLibrary base, VocabLibrary patched, Set<String> ids) {
    final source = {for (final it in patched.items) it.id: it};
    final known = {for (final it in base.items) it.id};
    return base.copyWith(
      items: [
        for (final it in base.items)
          if (ids.contains(it.id)) (source[it.id] ?? it) else it,
        for (final it in patched.items)
          if (ids.contains(it.id) && !known.contains(it.id)) it,
      ],
    );
  }

  Future<void> _guard(Future<void> Function() body) async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await body();
    } catch (e) {
      _error = '$e';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}
