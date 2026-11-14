import 'package:flutter/foundation.dart';

import '../core/quiz.dart' show QuizKind, articleKinds, vocabKinds;
import '../core/quiz_pool.dart'
    show QuizMode, QuizScope, normalizeQuizLimit, quizModeNeedsArticle;
import '../core/quiz_settings.dart';

/// 整卷考试的「设置」半边：模式 / 范围 / 题型 / 题量 / 四个开关。
///
/// 从 `QuizViewModel` 里拆出来，是因为那个类同时管「设置」和「一场考试的
/// 生命周期」两件事，方法数一度顶到 60。拆开之后两边都远低于上帝类阈值，
/// 页面照旧读 `vm.mode` / `vm.setLimit(...)`（mixin 的方法在调用方看来
/// 跟原来的成员没区别）。
///
/// 子类要实现的四个钩子：
/// - [hasArticleForScope]：有没有选好一篇（决定「词级卷」能不能收窄到本篇）
/// - [onSettingsChanged]：设置变了（落盘 + 清掉过期的快照）
/// - [onRoundInvalidated]：改了模式 / 范围，当前这一轮作废
mixin QuizSettingsMixin on ChangeNotifier {
  QuizSettings _settings = const QuizSettings();

  /// 当前这套设置（只读；改设置请走下面的 setter）。
  QuizSettings get settings => _settings;

  QuizMode get mode => _settings.mode;
  QuizScope get scope => _settings.scope;

  Set<QuizKind> get kinds => Set<QuizKind>.unmodifiable(_settings.kindsForMode);

  int get limit => _settings.limit;
  bool get auto => _settings.auto;
  bool get speakAfter => _settings.speakAfter;
  bool get loopWrong => _settings.loopWrong;
  bool get unique => _settings.unique;

  /// 听写 / 混合卷的题型是固定组合，不能逐项改。
  bool get kindsEditable => _settings.kindsEditable;

  /// 有没有选好一篇（词级卷没选就退回全库）。
  bool get hasArticleForScope;

  /// 设置变了：子类负责落盘、清掉跟新口径对不上的快照。
  void onSettingsChanged();

  /// 模式 / 范围变了，当前这一轮作废。
  void onRoundInvalidated();

  /// 读盘 / 恢复时直接换一套设置（不发通知、不落盘）。
  @protected
  void adoptSettings(QuizSettings next) {
    _settings = next;
  }

  void setMode(QuizMode value) {
    if (mode == value) return;
    _settings = _settings.withMode(value);
    // 切模式时范围跟着走：文章 / 听写 / 混合只能本篇；词级卷没选篇就退回全库。
    if (value != QuizMode.vocab) {
      _settings = _settings.copyWith(scope: QuizScope.article);
    } else if (!hasArticleForScope) {
      _settings = _settings.copyWith(scope: QuizScope.all);
    }
    onRoundInvalidated();
    onSettingsChanged();
    notifyListeners();
  }

  void setScope(QuizScope value) {
    if (scope == value) return;
    _settings = _settings.copyWith(scope: value);
    onSettingsChanged();
    notifyListeners();
  }

  /// 勾 / 取消一个题型；至少留一个（全空出不了卷）。
  void toggleKind(QuizKind kind) {
    if (!kindsEditable) return;
    if (!availableKinds.contains(kind)) return;
    final next = <QuizKind>{...kinds};
    if (next.contains(kind)) {
      if (next.length <= 1) return;
      next.remove(kind);
    } else {
      next.add(kind);
    }
    final ordered = [
      for (final k in availableKinds)
        if (next.contains(k)) k,
    ];
    _settings = mode == QuizMode.vocab
        ? _settings.copyWith(vocabKinds: ordered)
        : _settings.copyWith(articleKinds: ordered);
    onSettingsChanged();
    notifyListeners();
  }

  void setLimit(int value) {
    final next = normalizeQuizLimit(value);
    if (limit == next) return;
    _settings = _settings.copyWith(limit: next);
    onSettingsChanged();
    notifyListeners();
  }

  /// 自动切题 / 答完朗读 / 反复鞭打 / 每个词只考一次。
  void setAuto(bool value) {
    if (auto == value) return;
    _settings = _settings.copyWith(auto: value);
    onSettingsChanged();
    notifyListeners();
  }

  void setSpeakAfter(bool value) {
    if (speakAfter == value) return;
    _settings = _settings.copyWith(speakAfter: value);
    onSettingsChanged();
    notifyListeners();
  }

  void setLoopWrong(bool value) {
    if (loopWrong == value) return;
    _settings = _settings.copyWith(loopWrong: value);
    onSettingsChanged();
    notifyListeners();
  }

  void setUnique(bool value) {
    if (unique == value) return;
    _settings = _settings.copyWith(unique: value);
    onSettingsChanged();
    notifyListeners();
  }

  /// 当前模式下能选的题型（听写固定只有「听音填空」）。
  List<QuizKind> get availableKinds => switch (mode) {
        QuizMode.vocab => vocabKinds,
        QuizMode.article => articleKinds,
        QuizMode.dictation => const <QuizKind>[QuizKind.listen],
        QuizMode.mixed => <QuizKind>[...vocabKinds, ...articleKinds],
      };

  /// 这一卷要不要先选一篇。
  bool get needsArticle => quizModeNeedsArticle(mode) || scope == QuizScope.article;
}
