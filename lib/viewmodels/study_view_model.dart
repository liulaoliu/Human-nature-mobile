import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/activity/activity.dart' show ActivityCat, dayKeyLocal;
import '../core/entry_kind.dart';
import '../core/learning.dart';
import '../core/ports.dart' show SpeechPort;
import '../core/study_pool.dart';
import '../core/study_round_hint.dart';
import '../core/study_pools.dart';
import '../core/study_prefs.dart';
import '../core/study_session.dart';
import '../core/vocab/learn_step.dart';
import '../core/vocab/replay.dart';
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
    this.speech,
  })  : _vocabRepo = vocab,
        _learningRepo = learning,
        settings = StudySettings(store: prefsStore ?? PrefsStore.memory()) {
    // 设置变了也要让「watch StudyViewModel 的界面」重画：页面只订阅这一个
    // notifier，不能要求每个卡片自己再去 watch settings。
    settings.addListener(notifyListeners);
  }

  final VocabRepository _vocabRepo;
  final LearningRepository _learningRepo;

  /// 朗读端口（卡片上的 🔊）；测试里不传，页面就静默不读。
  final SpeechPort? speech;

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
  StudyMode _mode = StudyMode.learn;

  /// 正在跑的写盘任务。连点「下一个」时前一次还没写完，新的一次不能排队，
  /// 只更新 [_pending]，让当前这次收尾时把最新状态补写一次。
  bool _writing = false;

  /// 等待落盘的最新词库（`null` = 没有待写的）。
  VocabLibrary? _pending;

  /// 写盘排空时 complete 的 future（[flushWrites] 等它）。
  Completer<void>? _idle;

  /// 当前设置（牌组 / 每组 / 每日新词额度 / 锤炼 / 回顾筛选）。
  StudyPrefs get prefs => settings.prefs;

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

  /// 当前绑定的文章 id（「学习」只看这一篇）；没绑就是 null。
  String? get articleId => _articleId;

  /// 这一轮是「学习」「复习」还是「回顾」。
  StudyMode get mode => _mode;

  /// 「回顾」默认按什么筛。
  RecallScope get recallScope => settings.prefs.recallScope;

  /// 三个入口的候选池 + 组大小。
  ///
  /// 池子这件事只依赖「词库 + 设置 + 当前文章」，全在 [StudyPools] 里算；
  /// 这里只负责把参数凑齐（方法数留给上帝类门禁）。
  StudyPools get pools => StudyPools(
        library: library,
        deck: deck,
        articleId: _articleId,
        docLemmas: _docLemmas,
        recallScope: recallScope,
        recentIds: _recentIds,
        groupSize: groupSize,
      );

  /// 最近 7 天学过的词 id（回顾用）。
  Set<String> get _recentIds =>
      _ledger?.studiedIdsWithin(recallRecentDays) ?? const <String>{};

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

  /// 「本篇」要传当前文章 id 与正文词形集合。
  void setArticleContext(String? articleId, {Set<String> docLemmas = const <String>{}}) {
    _articleId = articleId;
    _docLemmas = docLemmas;
    notifyListeners();
  }

  /// 开一轮：按入口装队列。
  ///
  /// [entry] 决定取哪一批：
  ///   - [StudyEntry.learn] 只要本篇新词（[StudyPools.learn]），过每日新词额度；
  ///   - [StudyEntry.review] 只要到期的（[buildReviewQueue]）；
  ///   - [StudyEntry.recall] 只要已经学过的（[StudyPools.recall]），**不过额度**。
  ///
  /// 返回这一轮装了几张卡——0 就是没东西可背，原因写进 [error]。
  ///
  /// **队列长度在这一刻定死**：学到一半又去精读收词，新词排到下一轮，
  /// 不插队（否则进度条和小结数字都对不上）。
  int startRound({StudyEntry entry = StudyEntry.learn}) {
    final source = pools.of(entry);
    final prefs = settings.prefs.rollOver(dayKeyLocal());
    final items = switch (entry) {
      StudyEntry.learn => buildLearnQueue(source, null, prefs.newLimit, prefs.newToday),
      StudyEntry.review => buildReviewQueue(source),
      StudyEntry.recall => source,
    };
    if (items.isEmpty) {
      _session = null;
      _lastOutcome = null;
      _error = emptyRoundReason(
        entry: entry,
        source: source,
        prefs: prefs,
        deck: deck,
        articleId: _articleId,
      );
      notifyListeners();
      return 0;
    }
    final next = StudySession(
      library: library,
      groupSize: pools.groupSizeFor(entry),
    );
    next.start(items);
    _session = next;
    _mode = switch (entry) {
      StudyEntry.learn => StudyMode.learn,
      StudyEntry.review => StudyMode.review,
      StudyEntry.recall => StudyMode.review,
    };
    _lastOutcome = null;
    _error = null;
    notifyListeners();
    return items.length;
  }

  /// 结束这一轮（回到设置页）。
  void endRound() {
    _session = null;
    _lastOutcome = null;
    notifyListeners();
  }

  /// 今天背过的词（按首次顺序），给「再过一遍」用。
  List<VocabItem> get studiedTodayItems {
    final ids = _ledger?.studiedIds ?? const <String>[];
    if (ids.isEmpty) return const <VocabItem>[];
    final byId = {for (final it in library.items) it.id: it};
    return [
      for (final id in ids)
        if (byId[id] != null) byId[id]!,
    ];
  }

  /// 换「回顾」的筛选维度（本篇学过 / 最近 7 天）。
  /// 评一档（认识 / 模糊 / 忘记）。
  ///
  /// **先切题再落盘**：评分本身是纯内存操作，落盘要「序列化 16MB + gzip + 重建
  /// 派生表」约 1.6 秒。以前 `await` 完才 `notifyListeners()`，用户看到的就是
  /// 「点下一个卡一秒」。现在界面立刻翻到下一张，写盘在背后跑；写完再通知一次
  /// 把失败提示刷出来。
  Future<void> grade(ReviewGrade value, {bool? learnPass, bool advance = true}) async {
    final s = _session;
    if (s == null) return;
    final before = s.library;
    final card = s.card;
    final outcome = s.grade(value, learnPass: learnPass, advance: advance);
    final after = s.library;
    _lastOutcome = outcome;
    if (card != null) _recordStudy(card.id);
    notifyListeners();
    if (outcome.firstNew) await _bumpNewToday();
    await _persist(before: before, after: after);
    notifyListeners();
  }

  /// 「选中文释义」那一步：翻面（hold）不写库，选对/选错才写。
  ///
  /// 同 [grade]：先回界面，再落盘。
  Future<LearnStep?> learnStep(LearnAction action, {bool advance = true}) async {
    final s = _session;
    if (s == null) return null;
    final before = s.library;
    final card = s.card;
    final step = s.learn(action, advance: advance);
    final after = s.library;
    _lastOutcome = null;
    if (step.kind == LearnStepKind.card) {
      if (card != null) _recordStudy(card.id);
      notifyListeners();
      if (s.lastFirstNew) await _bumpNewToday();
      await _persist(before: before, after: after);
      notifyListeners();
      return step;
    }
    notifyListeners();
    return step;
  }

  /// 卡面拼写判卷：对 = 解锁评分，错 = 忘记 + 打标签 + 回队尾。
  ///
  /// [advance] 传 false 时拼对**不写库也不推进**（卡面拼写只当门槛，
  /// 认识 / 模糊 / 忘记了留给用户点）；组末拼写忽略这个参数。
  ///
  /// 同 [grade]：先回界面，再落盘。
  Future<bool> checkSpelling(String input, {bool advance = true}) async {
    final s = _session;
    if (s == null) return false;
    final before = s.library;
    final card = s.card;
    final ok = s.checkSpelling(input, advance: advance);
    final after = s.library;
    _lastOutcome = null;
    if (card != null) _recordStudy(card.id);
    notifyListeners();
    await _persist(before: before, after: after);
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
  ///
  /// **合并写**：一次保存实测要 2.5 秒（16MB 序列化 + gzip + 重建派生表）。用户
  /// 连点「下一个」时不能排 5 个队，否则越点越积压。这里只保留**最新那份**词库：
  /// 写盘期间又改了，就等这一次写完再拿最新的写一次 —— 中间那些状态本来就已被
  /// 后一次包含（`session.library` 是累积的）。
  Future<void> _persist({
    required VocabLibrary before,
    required VocabLibrary after,
  }) async {
    if (identical(before, after)) return;
    _pending = after;
    if (_writing) return; // 已有一次在跑，它收尾时会把最新的补上
    _writing = true;
    final idle = Completer<void>();
    _idle = idle;
    try {
      while (_pending != null) {
        final target = _pending!;
        _pending = null;
        await _write(target);
      }
    } finally {
      _writing = false;
      _idle = null;
      idle.complete();
    }
  }

  /// 等写盘彻底排空。
  ///
  /// 切后台 / 退出页面前调一次：合并写意味着最后一次评分可能还只在内存里，
  /// 进程被系统杀掉就丢了。界面本身不用等它（那正是合并写的意义）。
  Future<void> flushWrites() async {
    while (_idle != null) {
      await _idle!.future;
    }
  }

  Future<void> _write(VocabLibrary after) async {
    try {
      final saved = await _vocabRepo.save(after, baseUpdatedAt: _libraryUpdatedAt);
      _library = after;
      _libraryUpdatedAt = saved.updatedAt;
      _saveError = null;
    } on VocabConflict {
      try {
        final fresh = await _vocabRepo.load() ?? const VocabLibrary();
        final merged = replayPatched(fresh, after, touchedIds(fresh, after));
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
