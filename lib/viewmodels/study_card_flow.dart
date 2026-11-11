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
  ReviewGrade? _pendingGrade;

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

  /// 当前会话是不是复习模式。
  bool get reviewMode => _vm.mode == StudyMode.review;

  /// 卡片热度（0–4，越大越该锤炼）。
  int get heat => cardHeat(seconds: _cardSeconds, drillAfter: _vm.prefs.drillAfter);

  /// 计时文案（「12s」/「26s · 别墨迹」）。
  String get timerLabel => cardTimerLabel(_cardSeconds);

  /// 现在该不该拦下来锤炼（原因见 [drillReason]）。
  DrillReason? get drillReasonNow {
    final s = _vm.session;
    if (s == null) return null;
    final parked = _reviewGraded || _reviewFuzzy || _pendingGrade != null;
    return drillReason(DrillInput(
      active: _vm.started,
      spellMiss: s.spelling?.active == true,
      learnPhase: false,
      parked: parked,
      timedOut: _timedOut,
      relearnScoring: _relearnScoring,
      cleared: _drillCleared,
    ));
  }

  bool get _timedOut {
    final after = _vm.prefs.drillAfter;
    return after > 0 && _cardSeconds >= after && !_drillCleared;
  }

  bool get _relearnScoring {
    final s = _vm.session;
    final card = s?.card;
    if (s == null || card == null) return false;
    return s.view.relearning && _revealed && _pendingGrade != null;
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

  /// 三键之一：按 [planReviewGrade] 决定落不落库、推不推进、摊不摊卡。
  Future<void> chooseGrade(ReviewGrade grade) async {
    final plan = planReviewGrade(grade);
    _revealed = true;
    if (plan.commit == null) {
      // 模糊：先不写库，等用户在卡上选「下一词 / 记错了」
      _pendingGrade = grade;
      _reviewFuzzy = true;
      notifyListeners();
      return;
    }
    _pendingGrade = grade;
    _reviewFuzzy = false;
    _reviewGraded = !plan.advance;
    notifyListeners();
    await _vm.grade(plan.commit!);
  }

  /// 模糊摊卡后的两个出口。
  Future<void> chooseFuzzy(ReviewFuzzyChoice choice) async {
    final plan = planReviewFuzzyChoice(choice);
    _pendingGrade = plan.commit;
    _reviewFuzzy = false;
    _reviewGraded = !plan.advance;
    notifyListeners();
    final commit = plan.commit;
    if (commit != null) await _vm.grade(commit);
  }

  /// 「不认识」：直接判 again 并换下一张（不弹卡）。
  Future<void> markUnknown() async {
    _pendingGrade = ReviewGrade.again;
    _reviewFuzzy = false;
    _reviewGraded = false;
    notifyListeners();
    await _vm.grade(ReviewGrade.again);
  }

  /// 学习模式选释义：选错 / 选对后按它给的档位落库。
  Future<LearnStep?> pickMeaning(int index, bool correct) async {
    final step = await _vm.learnStep(
      correct ? LearnAction.correct : LearnAction.wrong,
    );
    if (step == null) return null;
    if (step.kind == LearnStepKind.card) {
      _revealed = true;
      notifyListeners();
      return step;
    }
    await Future<void>.delayed(learnRevealHold);
    await _vm.grade(step.grade ?? ReviewGrade.again, learnPass: step.pass);
    return step;
  }

  /// 「不认识，看答案」：先摊开，再按 again 落库。
  Future<void> revealAnswer() async {
    await _vm.learnStep(LearnAction.reveal);
    await Future<void>.delayed(learnRevealHold);
    _revealed = true;
    notifyListeners();
    await _vm.grade(ReviewGrade.again, learnPass: false);
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
    _pendingGrade = null;
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
