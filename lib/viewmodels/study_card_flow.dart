/// 单词卡的「这一张」状态：翻面 / 计时 / 锤炼 / 复习三键的两步确认。
///
/// 为什么单开一个类而不是塞进 [StudyViewModel]：那些是**卡片级**的临时态，换卡就清零；
/// ViewModel 管的是「池子 + 会话 + 落盘」，两件事混在一起会让 ViewModel 越过 40 个方法
/// 的门禁（也确实不该由它记「这一张翻没翻面」）。
///
/// 与 Web 版 `useStudyReviewStep` + `StudyPanel` 里的 `revealed` / `cardSeconds` / `drill`
/// 三个本地态一一对应。
library;

import 'package:flutter/foundation.dart';

import '../core/vocab/drill.dart';
import '../core/vocab/learn_step.dart';
import '../core/vocab/review.dart';
import '../core/vocab/review_step.dart';
import '../core/vocab/study_card.dart';
import '../core/vocab/study_drill.dart';
import '../models/vocab.dart';
import 'study_view_model.dart';

class StudyCardFlow extends ChangeNotifier {
  StudyCardFlow(this._vm) {
    _vm.addListener(_onVm);
    _syncKey();
  }

  final StudyViewModel _vm;

  bool _revealed = false;
  int _cardSeconds = 0;
  String _cardKey = '';
  StudyDrill? _drill;
  bool _drillCleared = false;
  bool _reviewFuzzy = false;
  bool _reviewGraded = false;
  bool _learnGraded = false;
  int? _learnPick;
  bool _learnWrong = false;
  bool _learnContinued = false;
  ReviewGrade? _reviewPending;
  bool _reviewParked = false;

  /// 这一张卡翻面了没有（看见释义）。
  bool get revealed => _revealed;

  /// 这一张卡停了多少秒。
  int get cardSeconds => _cardSeconds;

  /// 正在做的锤炼；null = 没在锤炼。
  StudyDrill? get drill => _drill;

  /// 这一张卡本轮锤炼过了（别再拦）。
  bool get drillCleared => _drillCleared;

  /// 复习模式点了「模糊」，停在卡上等「下一词 / 记错了」。
  bool get reviewFuzzy => _reviewFuzzy;

  /// 复习模式已评过分，停在卡上等「下一词」。
  bool get reviewGraded => _reviewGraded;

  /// 摊卡待定档位（「记错了」只在它非空时给）。
  ReviewGrade? get reviewPending => _reviewPending;

  /// 当前会话是不是复习模式。
  bool get reviewMode => _vm.mode == StudyMode.review;

  /// 学习新词「四选一释义」这一关还在不在。
  ///
  /// 与 Web `useStudyLearnStep.ts` 的 `learnPhase` 同义：学习模式 + 生词（没排期过）
  /// + 不是重学卡 + 词库里凑得够干扰项，且这一张还没判过。
  ///
  /// 为什么不能复用 [StudyCardView.meaningGate]：那个门禁只在 `needsMeaningCheck`
  /// （重学 / 拼错过的词）时成立，普通生词从来不走 —— 这就是「学习新词没有四选一」的根因。
  bool get learnPhase {
    final s = _vm.session;
    final card = s?.card;
    if (s == null || card == null) return false;
    if (_learnGraded) return false;
    if (_vm.mode != StudyMode.learn) return false;
    if (!isFresh(card) || isRelearning(card)) return false;
    return s.options.length == 4;
  }

  /// 学习四选一里选了第几项（没选为 null）。
  int? get learnPick => _learnPick;

  /// 学习四选一选错了没有。
  bool get learnWrong => _learnWrong;

  /// 学习四选一已经判过了（此时只等「继续（看单词卡）」）。
  bool get learnGraded => _learnGraded;

  /// 学习四选一判完、用户已经点了「继续」——该进单词卡了。
  bool get learnContinued => _learnContinued;

  /// 卡片热度（0–4，越大越该锤炼）。
  int get heat => cardHeat(seconds: _cardSeconds, drillAfter: _vm.prefs.drillAfter);

  /// 计时文案（「12s」/「26s · 别墨迹」）。
  String get timerLabel => cardTimerLabel(_cardSeconds);

  /// 现在该不该拦下来锤炼（原因见 [drillReason]）。
  DrillReason? get drillReasonNow {
    final s = _vm.session;
    if (s == null) return null;
    final card = s.card;
    final parked = _reviewParked || _reviewGraded || _reviewFuzzy || _learnGraded;
    // 停太久要锤炼（拼写错/四选一/摊卡待出口时都不该再叠一次）
    final after = _vm.prefs.drillAfter;
    final timedOut = after > 0 && _cardSeconds >= after && !_drillCleared;
    // 重学卡摊开释义又停了：这时候该评分，不该锤炼
    final relearnScoring =
        card != null && s.view.relearning && _revealed && _reviewParked;
    return drillReason(DrillInput(
      active: _vm.started,
      spellMiss: s.spelling?.active == true,
      // 学习四选一本身就是一次释义考试，别再叠一遍锤炼
      learnPhase: learnPhase,
      parked: parked,
      timedOut: timedOut,
      relearnScoring: relearnScoring,
      cleared: _drillCleared,
    ));
  }

  /// 卡片被点了一下：没翻就翻，翻了不动。
  void reveal() {
    if (_revealed) return;
    _revealed = true;
    notifyListeners();
  }

  /// 每秒一次（页面里的 `Timer.periodic` 调）。
  void tick() {
    if (_drill != null) return;
    _cardSeconds += 1;
    notifyListeners();
  }

  /// 三键之一：**一律先摊卡停住，不写库**（口径见 `core/vocab/review_step.dart`）。
  ///
  /// 用户看过释义之后才选出口（下一词 / 记错了），那时才落一次库 ——
  /// 这样「认识」后反悔点「记错了」也不会 good + again 双写。
  Future<void> chooseGrade(ReviewGrade grade) async {
    _revealed = true;
    _reviewParked = true;
    _reviewPending = grade;
    _reviewFuzzy = true;
    _reviewGraded = false;
    notifyListeners();
  }

  /// 摊卡之后的出口：下一词（认下这一档）/ 记错了（改判不认识）。
  Future<void> chooseReviewExit(ReviewExitChoice choice) async {
    final grade = _reviewPending;
    if (grade == null) {
      // 已经判过了（只剩「下一词」），直接换下一张
      _clearReviewPark();
      notifyListeners();
      await _advance();
      return;
    }
    final plan = planReviewExit(grade, choice);
    if (choice == ReviewExitChoice.next) {
      _clearReviewPark();
      notifyListeners();
      final commit = plan.commit;
      if (commit != null) await _vm.grade(commit);
      return;
    }
    // 记错了：改成 again 落库，继续停在卡上看答案（只剩「下一词」）
    _reviewPending = null;
    _reviewFuzzy = false;
    _reviewGraded = true;
    notifyListeners();
    final commit = plan.commit;
    if (commit != null) await _vm.grade(commit, advance: false);
  }

  /// 落库后推进到下一张（复习模式：`grade` 已经写了库，这里只推指针）。
  Future<void> _advance() async {
    _vm.forward();
  }

  void _clearReviewPark() {
    _reviewParked = false;
    _reviewPending = null;
    _reviewFuzzy = false;
    _reviewGraded = false;
  }

  /// 「不认识」：直接判 again 并换下一张（不弹卡）。
  Future<void> markUnknown() async {
    _reviewFuzzy = false;
    _reviewGraded = false;
    _reviewParked = false;
    _reviewPending = null;
    notifyListeners();
    await _vm.grade(ReviewGrade.again);
  }

  /// 学习模式选释义：选错 / 选对后按它给的档位落库，**但先停在原题高亮**。
  ///
  /// 口径：选对 → 绿色高亮正确项 + 给「继续（看单词卡）」；选错 → 红色高亮错项 +
  /// 绿色高亮正确项 + 同样停在原题。两种情况都**不立刻换词**，等用户点「继续」。
  Future<LearnStep?> pickMeaning(int index, bool correct) async {
    _learnPick = index;
    _learnWrong = !correct;
    _learnGraded = true;
    _learnContinued = false;
    notifyListeners();
    final step = await _vm.learnStep(
      correct ? LearnAction.correct : LearnAction.wrong,
      advance: false,
    );
    notifyListeners();
    return step;
  }

  /// 学习四选一判完后点「继续（看单词卡）」。
  ///
  /// 选对 / 选错的档位已经在 [pickMeaning] 里写进库了，这里只把界面推进到单词卡。
  void continueAfterLearn() {
    _learnContinued = true;
    _revealed = true;
    notifyListeners();
  }

  /// 「不认识，看答案」：摊开正确项 + 停住等「继续」。
  Future<void> revealAnswer() async {
    _learnPick = null;
    _learnWrong = false;
    _learnGraded = true;
    _learnContinued = false;
    notifyListeners();
    await _vm.learnStep(LearnAction.reveal, advance: false);
    notifyListeners();
  }

  /// 开始锤炼（卡片停太久 / 重学卡要评分）。
  void startDrill(DrillReason reason) {
    final s = _vm.session;
    final card = s?.card;
    if (card == null) return;
    _drill = StudyDrill(
      reason: reason,
      card: card,
      items: _vm.library.items,
    );
    notifyListeners();
  }

  /// 锤炼里提交拼写。
  DrillVerdict submitDrillSpell(String input) {
    final d = _drill;
    if (d == null) return DrillVerdict.retry;
    final verdict = d.submitSpell(input);
    if (verdict == DrillVerdict.spellMiss) {
      // 拼错 = 直接判不认识，整块收工
      _drillCleared = true;
      _drill = null;
      notifyListeners();
      return verdict;
    }
    if (d.cleared) _finishDrill();
    notifyListeners();
    return verdict;
  }

  /// 锤炼里选释义。
  DrillVerdict pickDrillMeaning(int index) {
    final d = _drill;
    if (d == null) return DrillVerdict.retry;
    final verdict = d.pickMeaning(index);
    if (d.cleared) _finishDrill();
    notifyListeners();
    return verdict;
  }

  /// 锤炼里写搭配。
  DrillVerdict submitDrillUsage(String input) {
    final d = _drill;
    if (d == null) return DrillVerdict.retry;
    final verdict = d.submitUsage(input);
    if (d.cleared) _finishDrill();
    notifyListeners();
    return verdict;
  }

  /// 锤炼输入框。
  void setDrillTyped(String value) {
    _drill?.setTyped(value);
    notifyListeners();
  }

  void _finishDrill() {
    _drill = null;
    _drillCleared = true;
  }

  /// 读一遍当前卡的单词（卡片上的 🔊）。
  ///
  /// 没有注入语音端口就静默跳过——背单词页不装 TTS 也能用（测试里就没有）。
  Future<void> speak() async {
    final word = card?.word;
    final port = _vm.speech;
    if (word == null || word.isEmpty || port == null) return;
    try {
      await port.speak(word);
    } catch (_) {
      // 朗读失败不该打断背单词（有的机型没装英文引擎）
    }
  }

  /// 会话变了（换卡 / 结束）就清卡片态。
  void _onVm() {
    if (_syncKey()) notifyListeners();
  }

  bool _syncKey() {
    final s = _vm.session;
    final card = s?.card;
    final key = s == null || card == null ? '' : '${s.index}:${card.id}';
    if (key == _cardKey) return false;
    _cardKey = key;
    _revealed = false;
    _cardSeconds = 0;
    _drill = null;
    _drillCleared = false;
    _reviewFuzzy = false;
    _reviewGraded = false;
    _reviewParked = false;
    _reviewPending = null;
    _learnGraded = false;
    _learnPick = null;
    _learnWrong = false;
    _learnContinued = false;
    return true;
  }

  /// 卡片对象（界面少写一行判空）。
  VocabItem? get card => _vm.session?.card;

  /// 这一张卡的 SRS 行文案。
  String get srsLine => card == null
      ? ''
      : cardSrsLine(
          card: card!,
          gradeable: _canGrade,
          reviewMode: reviewMode,
          relearning: _vm.session?.view.relearning ?? false,
        );

  bool get _canGrade => reviewMode || _revealed;

  @override
  void dispose() {
    _vm.removeListener(_onVm);
    super.dispose();
  }
}
