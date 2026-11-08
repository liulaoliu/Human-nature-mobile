/// 一次产出训练会话的状态机：题目 → 作答 → 批改 → 跳过 / 重写。
///
/// 为什么从 [ProductionViewModel] 里拆出来：
///   - 设置、选目标块、出题、落库是「准备与收尾」，而这里是「一道题的生命周期」，
///     两组状态的写入方完全不同（换题不该碰到设置，改设置也不该清作答）；
///   - 拆开后两边都远低于上帝类阈值，页面也能直接读 `vm.session.xxx`。
///
/// 本类不认识仓储：要写记录时回调 [appendRecord]（由 ViewModel 收到学习记录仓储里），
/// 记录里需要的文章身份、设置也从回调里现取，避免存一份会过期的副本。
library;

import 'package:flutter/foundation.dart';

import '../core/activity/activity.dart' show dayKeyLocal;
import '../core/production.dart';
import '../core/production_draft.dart';
import '../core/production_history.dart' show makeSkippedProductionRecord;
import '../core/production_task.dart';
import '../core/writing.dart';

/// 会话状态机。
class ProductionSession extends ChangeNotifier {
  ProductionSession({
    required this.settingsOf,
    required this.articleIdOf,
    required this.articleTitleOf,
    required this.appendRecord,
  });

  /// 现取当前设置（换吃法 / 换主题后立刻生效）。
  final ProductionSettings Function() settingsOf;

  /// 现取当前文章 id（`manual` 表示没挂在文章上）。
  final String Function() articleIdOf;

  /// 现取当前文章标题（空串表示没有）。
  final String Function() articleTitleOf;

  /// 把一条记录写进学习记录；返回 false 表示没写成功（错误已由 ViewModel 记下）。
  final Future<bool> Function(WritingRecord record) appendRecord;

  List<ProductionPrompt> _prompts = const <ProductionPrompt>[];
  int _index = 0;
  ProductionTask? _task;
  String _answer = '';
  WritingFeedback? _feedback;
  WritingFeedback? _previousFeedback;
  int _round = 1;
  String? _error;

  /// 当前这一组的题目。
  List<ProductionPrompt> get prompts => _prompts;

  /// 正在做第几题（0 起）。
  int get index => _index;

  /// 当前题的评分任务（还没出题时是 null）。
  ProductionTask? get task => _task;

  /// 当前作答。
  String get answer => _answer;

  /// 当前题的批改结果。
  WritingFeedback? get feedback => _feedback;

  /// 上一稿的批改（重写时对照用）。
  WritingFeedback? get previousFeedback => _previousFeedback;

  /// 第几稿（跳过 / 重写会 +1）。
  int get round => _round;

  /// 这一层自己的错误（拼批改提示词、认不出批改结果）；ViewModel 会跟自己的合并。
  String? get error => _error;

  /// 有没有题目。
  bool get hasPrompts => _prompts.isNotEmpty;

  /// 换了新的一组题：回到第 1 题、第 1 稿，清掉作答与批改。
  void begin(List<ProductionPrompt> prompts) {
    _prompts = prompts;
    _index = 0;
    _round = 1;
    _feedback = null;
    _previousFeedback = null;
    _error = null;
    _openCurrent();
  }

  /// 题目没变、只挪了题号（风味酸奶重新拆句后按原文找回同一句）。
  void restore(List<ProductionPrompt> prompts, int index) {
    if (prompts.isEmpty) {
      _prompts = const <ProductionPrompt>[];
      _task = null;
      notifyListeners();
      return;
    }
    _prompts = prompts;
    _index = index.clamp(0, prompts.length - 1);
    _openCurrent();
  }

  /// 从草稿续做：题目 / 题号 / 稿数 / 作答 / 批改一起填回来。
  void hydrate(ProductionDraft draft) {
    if (draft.prompts.isEmpty) return;
    _prompts = draft.prompts;
    _index = draft.index.clamp(0, draft.prompts.length - 1);
    _round = draft.round;
    // `_openCurrent` 会清空作答与批改（换题就该清），续做要在这之后再填回去。
    _openCurrent();
    _answer = draft.answer;
    _feedback = writingFeedbackFromJson(draft.feedback);
    _previousFeedback = writingFeedbackFromJson(draft.previousFeedback);
    notifyListeners();
  }

  /// 跳到第 [i] 题（越界忽略）。换题会把作答 / 批改清掉。
  void openPrompt(int i) {
    if (i < 0 || i >= _prompts.length) return;
    _index = i;
    _round = 1;
    _feedback = null;
    _previousFeedback = null;
    _openCurrent();
  }

  /// 下一题；已是最后一题返回 false。
  bool nextPrompt() {
    if (_index + 1 >= _prompts.length) return false;
    openPrompt(_index + 1);
    return true;
  }

  /// 上一题；已是第一题返回 false。
  bool prevPrompt() {
    if (_index <= 0) return false;
    openPrompt(_index - 1);
    return true;
  }

  /// 改作答。
  void setAnswer(String value) {
    if (_answer == value) return;
    _answer = value;
    notifyListeners();
  }

  /// 拼批改提示词。没作答时记一条错误并返回 null。
  String? buildFeedbackPrompt() {
    final task = _task;
    if (task == null) return null;
    if (_answer.trim().isEmpty) {
      _error = '先写点什么再批改';
      notifyListeners();
      return null;
    }
    return buildProductionFeedbackPrompt(
      task,
      _answer,
      previousIssues: _previousIssues(),
    );
  }

  /// 粘回批改结果并落库。成功返回 null，失败返回给用户看的中文原因。
  Future<String?> applyFeedback(String raw) async {
    final task = _task;
    if (task == null) return null;
    final parsed = parseProductionFeedback(raw, _answer);
    if (parsed == null) {
      _error = '没认出批改 JSON；请确认粘的是 v2 批改结果';
      notifyListeners();
      return _error;
    }
    final hits = checkProductionTargets(_answer, task.targets);
    final record = WritingRecord(
      at: DateTime.now().toUtc().toIso8601String(),
      articleId: articleIdOf(),
      articleTitle: articleTitleOf().isEmpty ? null : articleTitleOf(),
      model: task.model,
      text: _answer,
      feedback: parsed.feedback,
      task: task.copyWith(round: () => _round, hits: hits),
      source: WritingSource.production,
    );
    final ok = await appendRecord(record);
    if (!ok) return '记录没写进去';
    _previousFeedback = _feedback;
    _feedback = parsed.feedback;
    _error = null;
    notifyListeners();
    return null;
  }

  /// 跳过这一题：留一条「跳过（未提交）」的记录，不伪造分数。
  Future<bool> skipCurrent() async {
    final task = _task;
    if (task == null) return false;
    final record = makeSkippedProductionRecord(
      task: task,
      text: _answer,
      at: DateTime.now().toUtc().toIso8601String(),
      articleId: articleIdOf(),
      articleTitle: articleTitleOf(),
      round: _round,
    );
    final ok = await appendRecord(record);
    if (!ok) return false;
    _round++;
    _feedback = null;
    _error = null;
    notifyListeners();
    return true;
  }

  /// 重写这一题：稿数 +1，作答清空，上一稿批改留作对照。
  void startRewrite() {
    _round++;
    _answer = '';
    _previousFeedback = _feedback;
    _feedback = null;
    _error = null;
    notifyListeners();
  }

  /// 清掉本层的错误。
  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }

  void _openCurrent() {
    if (_prompts.isEmpty) {
      _task = null;
      notifyListeners();
      return;
    }
    _task = makeProductionTask(
      _prompts[_index],
      settingsOf().topic,
      mode: settingsOf().mode,
      sessionId: _sessionId(),
    );
    _answer = '';
    _feedback = null;
    notifyListeners();
  }

  /// 同一组训练共用的 id（历史里把第 1 / 2 稿并排）。
  String _sessionId() =>
      '${articleIdOf()}|${dayKeyLocal()}|${settingsOf().mode.name}|${settingsOf().topic}';

  /// 上一稿还没被采纳的问题（重写时让 AI 重点盯这些）。
  List<PreviousIssue> _previousIssues() => <PreviousIssue>[
        for (final issue in _previousFeedback?.issues ?? const <WritingIssue>[])
          PreviousIssue(
            original: issue.original,
            suggestion: issue.suggestion,
            reason: issue.reason,
            rule: issue.rule,
            key: issue.key,
          ),
      ];
}
