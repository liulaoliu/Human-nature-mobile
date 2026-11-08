/// 背单词会话的**状态机**（纯逻辑，零 IO、零 Flutter）。
///
/// 为什么单独一个文件：这一层在 Web 版里散在 `useStudySession`（448 行）和它下面
/// 五个子 hook 里（`useStudyGrading` / `useStudySequence` / `useStudySpellingRound` …）。
/// 拆成 ViewModel 时如果不先把「谁推进、推进到哪、什么时候先停下拼写」这套时序
/// 抽出来，规则就会一半在 ViewModel、一半在 widget 里，测试只能靠点界面去验。
///
/// 这里只管时序与记账，**不碰存储**：词库变了就放在 [library] 上，由 ViewModel
/// 比对外层持久化；UI 状态（输入框文字、翻面、动效）也不在这里。
///
/// 与 Web 版语义一一对应：
///   - 判分账本 → `useStudyGrading`
///   - 组末拼写 / 换卡 / 装轮 / 收尾重练 → `useStudySequence`
///   - 组末拼写状态机 → `useStudySpellingRound`
library;

import '../models/vocab.dart';
import 'vocab/extra.dart';
import 'vocab/learn_step.dart';
import 'vocab/meaning_options.dart';
import 'vocab/review.dart';
import 'vocab/spelling.dart';
import 'vocab/study_view.dart';
import 'vocab/word.dart';

/// 三个计数桶（小结页要显示「认识 / 模糊 / 忘记」各多少）。
class StudyCounts {
  const StudyCounts({this.know = 0, this.fuzzy = 0, this.forgot = 0});

  final int know;
  final int fuzzy;
  final int forgot;

  int get total => know + fuzzy + forgot;

  StudyCounts bump(ReviewGrade grade) => switch (grade) {
        ReviewGrade.again => StudyCounts(
            know: know,
            fuzzy: fuzzy,
            forgot: forgot + 1,
          ),
        ReviewGrade.hard => StudyCounts(
            know: know,
            fuzzy: fuzzy + 1,
            forgot: forgot,
          ),
        ReviewGrade.good || ReviewGrade.easy => StudyCounts(
            know: know + 1,
            fuzzy: fuzzy,
            forgot: forgot,
          ),
      };
}

/// 组末拼写测试里的一次拼错。
class SpellingMiss {
  const SpellingMiss({
    required this.typed,
    required this.word,
    required this.meaning,
  });

  /// 拼错那一次输入的内容。
  final String typed;
  final String word;
  final String meaning;
}

/// 组末拼写测试的可见状态。
class SpellingRound {
  const SpellingRound({
    required this.words,
    this.index = 0,
    this.input = '',
    this.miss,
  });

  /// 本组全部词（学到哪拼到哪，不封顶）。
  final List<VocabItem> words;

  /// 当前拼到第几个。
  final int index;

  /// 当前输入。
  final String input;

  /// 拼错了：显示原文 + 要求照着重打一遍。
  final SpellingMiss? miss;

  bool get active => words.isNotEmpty;

  VocabItem? get card => index >= 0 && index < words.length ? words[index] : null;

  int get total => words.length;

  SpellingRound copyWith({
    List<VocabItem>? words,
    int? index,
    String? input,
    SpellingMiss? Function()? miss,
  }) =>
      SpellingRound(
        words: words ?? this.words,
        index: index ?? this.index,
        input: input ?? this.input,
        miss: miss == null ? this.miss : miss(),
      );
}

/// 判一次分之后的账（给 ViewModel 决定要不要提示 / 落盘）。
class GradeOutcome {
  const GradeOutcome({
    required this.grade,
    this.interval = 0,
    required this.requeued,
    required this.advanced,
    this.firstNew = false,
  });

  final ReviewGrade grade;

  /// 下次复习间隔（天），提示文案用。
  final int interval;

  /// 是否被追加到队尾加练。
  final bool requeued;

  /// 是否推进到了下一张。
  final bool advanced;

  /// 这一判是不是「本轮头一回把一个新词判掉」——是的话今天的新词额度要扣一次。
  ///
  /// 由 [StudySession.takeFirstNewBump] 判：同一轮同一个新词判两次只算一次。
  final bool firstNew;

  String get label => switch (grade) {
        ReviewGrade.again => '忘记了',
        ReviewGrade.hard => '模糊',
        ReviewGrade.good || ReviewGrade.easy => '认识',
      };
}

/// 一轮背单词的状态机。
enum _Bucket { know, fuzzy, forgot }

class StudySession {
  /// 公开构造：参数名保持业务语义（`library` / `now` / `groupSize`）。
  StudySession({required VocabLibrary library, DateTime? now, int groupSize = 0})
      : this._(library, now, groupSize);

  StudySession._(this._library, this._now, this._groupSize);

  VocabLibrary _library;
  final DateTime? _now;
  final int _groupSize;

  List<VocabItem> _queue = const <VocabItem>[];
  int _index = 0;
  int _roundTotal = 0;
  bool _retrying = false;
  bool _meaningCleared = false;
  ExtraRound _extra = emptyExtraRound();
  final List<String> _forgot = <String>[];
  final Set<String> _bumped = <String>{};
  bool _lastFirstNew = false;
  StudyCounts _counts = const StudyCounts();
  int _extraCount = 0;
  String _gradeInfo = '';
  SpellingRound? _spelling;

  /// 正在拼写测试的这一组的组末下标。
  int? _pendingGroupEnd;

  /// 当前组在队列里的起点。
  int _groupCursor = 0;

  DateTime get _at => _now ?? DateTime.now();

  /// 最新词库（判分 / 拼错后由本类改写；ViewModel 据此落盘）。
  VocabLibrary get library => _library;

  /// 本轮队列（忘记的词会追加到队尾）。
  List<VocabItem> get queue => List.unmodifiable(_queue);

  int get index => _index;

  /// 本轮总数（进度分母）——开始时冻结，加练不撑大它。
  int get roundTotal => _roundTotal;

  bool get retrying => _retrying;

  /// 本卡是否已通过「选中文释义」这一关。
  bool get meaningCleared => _meaningCleared;

  StudyCounts get counts => _counts;

  /// 本轮加练了几张（不计入分母）。
  int get extraCount => _extraCount;

  /// 一句话判定提示（UI 显示后自己清）。
  String get gradeInfo => _gradeInfo;

  /// 本轮点过「忘记了」的词（按首次顺序）。
  List<String> get forgotIds => List.unmodifiable(_forgot);

  /// 组末拼写测试（没在测试时为 null）。
  SpellingRound? get spelling => _spelling;

  /// 本轮还能不能点「重练忘记的」（每轮只发起一次）。
  bool get canRetryForgot => !_extra.retried;

  /// 当前卡与两道门禁。
  StudyCardView get view => studyCardView(
        StudyCardViewParams(
          library: _library,
          queue: _queue,
          index: _index,
          roundTotal: _roundTotal,
          retrying: _retrying,
          meaningCleared: _meaningCleared,
          roundCard: _spelling?.card,
        ),
      );

  /// 当前卡（拼写测试中就是测试里的词）。
  VocabItem? get card => view.card;

  /// 选中文释义的四个选项（出不了题时为空）。
  List<MeaningOption> get options {
    final c = card;
    if (c == null) return const <MeaningOption>[];
    return meaningOptions(c, _library.items);
  }

  /// 正确项下标（出不了题时 -1）。
  int get correctOption {
    final c = card;
    if (c == null) return -1;
    return correctOptionIndex(c, _library.items);
  }

  /// 装一轮：重置账本 → 队列 → 分母 → 指针归零。
  void start(List<VocabItem> items, {bool retrying = false}) {
    _queue = List<VocabItem>.of(items);
    _index = 0;
    _roundTotal = items.length;
    _retrying = retrying;
    _extra = beginExtraRound(items.map((it) => it.id).toList());
    _pendingGroupEnd = null;
    _groupCursor = 0;
    _resetLedger();
    _resetCard();
    _gradeInfo = '';
  }

  /// 换一张卡时清掉卡片级 UI 状态（翻面 / 输入 / 门禁）。
  ///
  /// 不清 [gradeInfo]：判定提示要在换卡后还看得见一会儿（Web 版按 1.6s 自动消失）。
  void _resetCard() {
    _meaningCleared = false;
  }

  /// 账本归零（开新一轮 / 重练忘记的词时用）。不动 [extra]。
  void _resetLedger() {
    _forgot.clear();
    _bumped.clear();
    _counts = const StudyCounts();
    _extraCount = 0;
    _spelling = null;
  }

  /// 揭晓释义（选了中文释义那一刻）。
  void clearMeaningGate() {
    _meaningCleared = true;
  }

  /// 清掉提示文案。
  void clearGradeInfo() {
    _gradeInfo = '';
  }

  /// 回滚到上一个单词（不撤销已评分，只回看）。
  bool back() {
    if (_queue.isEmpty || _index <= 0) return false;
    _resetCard();
    _index -= 1;
    return true;
  }

  /// 切到下一个单词（不评分，只切换）；组末会先做拼写测试。
  ///
  /// 返回 true 表示已换到下一张；返回 false 表示正在拼写测试、或已到队尾。
  bool forward() {
    if (_spelling?.active == true) return false;
    if (_queue.isEmpty || _index >= _queue.length) return false;
    return _advanceFrom(_index);
  }

  /// 推进到下一张：到了「每组 N 词」的组末先停下把本组全部词拼一遍。
  bool _advanceFrom(int from) {
    if (from < _roundTotal) {
      final end = groupEndOf(from, _roundTotal, _groupSize);
      if (from + 1 >= end) {
        _pendingGroupEnd = end;
        final words = _queue.sublist(_groupCursor, end);
        _spelling = SpellingRound(words: words);
        _resetCard();
        return false;
      }
    }
    _resetCard();
    _index = from + 1;
    return true;
  }

  /// 本组拼写全过：把指针推到组末（下一组的头）；最后一组就进入本轮小结。
  void finishGroup() {
    final end = _pendingGroupEnd;
    if (end == null) return;
    _pendingGroupEnd = null;
    _groupCursor = end;
    _spelling = null;
    _resetCard();
    _index = end;
  }

  /// 正常评分：写 SRS（[learnPass] 非空时顺手记「这次没看答案就选对」）。
  ///
  /// 为什么合成一步：两次写库会互相覆盖 —— `recordLearnPass` 吃的是 `reviewItem`
  /// 的结果，分开写就会把 rating 冲掉。
  GradeOutcome grade(ReviewGrade grade, {bool? learnPass}) {
    final cur = card;
    if (cur == null) {
      return GradeOutcome(grade: grade, requeued: false, advanced: false);
    }
    final latest = _latestOf(cur.id) ?? cur;
    var next = reviewItem(_library, latest.id, grade, _at);
    if (learnPass != null) {
      next = recordLearnPass(next, latest.id, learnPass, _at);
    }
    _library = next;
    final firstNew = takeFirstNewBump(latest);
    _lastFirstNew = firstNew;
    final state = _latestOf(latest.id)?.reviewState;
    final interval = state?.interval ?? 0;
    _gradeInfo = '${_labelOf(grade)} · 下次复习：${fmtInterval(interval)}';

    _tally(grade == ReviewGrade.again
        ? _Bucket.forgot
        : grade == ReviewGrade.hard
            ? _Bucket.fuzzy
            : _Bucket.know,
        latest.id);
    if (grade == ReviewGrade.again) _noteForgot(latest.id);

    var requeued = false;
    if (grade == ReviewGrade.again || grade == ReviewGrade.hard) {
      requeued = _requeue(latest, grade);
    }
    final advanced = _advanceFrom(_index);
    return GradeOutcome(
      grade: grade,
      interval: interval,
      requeued: requeued,
      advanced: advanced,
      firstNew: firstNew,
    );
  }

  /// 「选中文释义」这一步的判定（学习模式）。
  ///
  /// 返回 [LearnStep]；判定为 [LearnStepKind.card] 时已经按它给的档位评过分并推进。
  /// 其余两种（hold / fallback）由 UI 决定：前者停在释义页高亮，后者退回普通卡。
  LearnStep learn(LearnAction action) {
    final c = card;
    final canQuiz = c != null && options.length == 4;
    final passes = c == null ? 0 : meaningPassesOf(c);
    final step = gradeLearnStep(action: action, passes: passes, canQuiz: canQuiz);
    if (step.kind == LearnStepKind.card) {
      final g = step.grade;
      if (g != null) grade(g, learnPass: step.pass);
    } else if (step.kind == LearnStepKind.hold) {
      // 停留期不改词库：等 UI 点「继续」/ 自动过场后再由调用方 grade。
      _gradeInfo = step.label;
    }
    return step;
  }

  /// 拼写判卷（卡面拼写 + 组末拼写测试共用）。
  ///
  /// 返回 true 表示拼对了。
  bool checkSpelling(String input) {
    final round = _spelling;
    if (round != null && round.active) {
      return _checkRoundSpelling(round, input);
    }
    final c = card;
    if (c == null) return false;
    if (spellingMatches(input, c.word)) {
      // 拼对 = 认识；推进由 [grade] 内部按组末规则处理
      grade(ReviewGrade.good);
      return true;
    }
    _library = markSpellingMiss(_library, c.id, _at);
    _gradeInfo = '「${c.word}」拼错了 · 已判为「不认识」';
    _tally(_Bucket.forgot, c.id);
    _noteForgot(c.id);
    _requeue(c, ReviewGrade.again);
    return false;
  }

  /// 组末拼写：拼错那一刻判定已定（again + 重学 + 标签），重打只是把词过一遍手。
  bool _checkRoundSpelling(SpellingRound round, String input) {
    final word = round.card;
    if (word == null) return false;
    if (round.miss != null) {
      // 重打阶段：打对才放行；再错就清空输入让原文重新显示出来
      if (spellingMatches(input, word.word)) {
        _spellingAdvance(round);
        return true;
      }
      _spelling = round.copyWith(input: '', miss: () => SpellingMiss(
            typed: input,
            word: round.miss!.word,
            meaning: round.miss!.meaning,
          ));
      return false;
    }
    if (spellingMatches(input, word.word)) {
      _spellingAdvance(round);
      return true;
    }
    // 判定在这里落库，本轮**不重排**（组末是验收，不是加练）
    _library = markSpellingMiss(_library, word.id, _at);
    _tally(_Bucket.forgot, word.id);
    _spelling = round.copyWith(
      input: '',
      miss: () => SpellingMiss(
        typed: input,
        word: word.word,
        meaning: displayMeaning(
          partOfSpeech: word.partOfSpeech,
          meaning: word.meaning,
        ),
      ),
    );
    return false;
  }

  void _spellingAdvance(SpellingRound round) {
    final next = round.index + 1;
    if (next >= round.words.length) {
      _spelling = null;
      finishGroup();
      return;
    }
    _spelling = round.copyWith(index: next, input: '', miss: () => null);
  }

  /// 设置组末拼写测试的输入（UI 受控输入框用）。
  void setSpellingInput(String value) {
    final round = _spelling;
    if (round == null) return;
    _spelling = round.copyWith(input: value);
  }

  /// 收尾重练本轮点过「忘记了」的词（每轮只发起一次）。
  ///
  /// 返回 true 表示真的开了一轮重练。
  bool retryForgot() {
    final ids = <String>{..._forgot};
    if (ids.isEmpty) return false;
    final items = _library.items.where((it) => ids.contains(it.id)).toList();
    if (items.isEmpty) return false;
    final plan = planRetryForgot(_extra, items.map((it) => it.id).toList());
    _extra = plan.round;
    if (plan.blocked || plan.ids.isEmpty) return false;
    final keep = plan.ids.toSet();
    final retryItems = items.where((it) => keep.contains(it.id)).toList();
    _pendingGroupEnd = null;
    _groupCursor = 0;
    _resetLedger();
    _queue = retryItems;
    _roundTotal = retryItems.length;
    _retrying = true;
    _index = 0;
    _resetCard();
    return true;
  }

  /// 词库里这条的最新版本（评分后要拿新状态算间隔）。
  VocabItem? _latestOf(String id) {
    for (final it in _library.items) {
      if (it.id == id) return it;
    }
    return null;
  }

  /// 新词头一回被判到时该计一次「今天已引入」（避免同一天重复扣额度）。
  ///
  /// 真正扣额度由 ViewModel 做（要读持久化的「今日新词数」），这里只负责
  /// **判断是不是头一回**：同一轮里同一个新词被判两次，只算一次。
  bool takeFirstNewBump(VocabItem item) =>
      isFresh(item) && _bumped.add(item.id);

  /// 最近一次 [grade] / [learn] 是否判掉了一个「本轮头一回」的新词。
  ///
  /// [learn] 走的是内部 `grade`，外部拿不到那个返回值，所以另留一个出口。
  bool get lastFirstNew => _lastFirstNew;

  /// 忘记 / 模糊的词本轮末尾再出现一次。
  bool _requeue(VocabItem cur, ReviewGrade grade) {
    final decision = planExtra(_extra, cur.id, grade);
    if (!decision.append) return false;
    _extra = decision.round;
    _queue = [..._queue, cur];
    _extraCount += 1;
    return true;
  }

  void _noteForgot(String id) {
    if (!_forgot.contains(id)) _forgot.add(id);
  }

  void _tally(_Bucket bucket, String id) {
    _counts = switch (bucket) {
      _Bucket.know => StudyCounts(
          know: _counts.know + 1,
          fuzzy: _counts.fuzzy,
          forgot: _counts.forgot,
        ),
      _Bucket.fuzzy => StudyCounts(
          know: _counts.know,
          fuzzy: _counts.fuzzy + 1,
          forgot: _counts.forgot,
        ),
      _Bucket.forgot => StudyCounts(
          know: _counts.know,
          fuzzy: _counts.fuzzy,
          forgot: _counts.forgot + 1,
        ),
    };
  }

  String _labelOf(ReviewGrade grade) => switch (grade) {
        ReviewGrade.again => '忘记了',
        ReviewGrade.hard => '模糊',
        ReviewGrade.good || ReviewGrade.easy => '认识',
      };
}

/// 间隔的天数文案（与 Web 版 `fmtInterval` 同口径）。
String fmtInterval(int days) {
  if (days <= 0) return '稍后';
  if (days == 1) return '1 天后';
  if (days < 30) return '$days 天后';
  final months = (days / 30).round();
  return months <= 1 ? '1 个月后' : '$months 个月后';
}
