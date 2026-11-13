/// 仿写训练：范句 → AI 出题 → 我写 → AI 批改 → 落库。
///
/// 三层分工：
///   - **纯函数**在 `core/writing.dart`（拼提示词、严格解析、批改）+ `writing_history.dart`
///     （历史筛选）+ `writing_draft.dart`（草稿）；
///   - **本文件**只做状态编排：草稿读写、粘回结果、落库、历史增删；
///   - **界面**只读 getter、只调方法。
///
/// 与奶牛工棚的分工：那边是「有词块 / 主题的批量出题」，这里是「拿一句范句做仿写」，
/// 走的是同一套 [WritingFeedback] 与 `writingHistory` 段，只是 `source` 不同
/// （仿写 = `WritingSource.writing` / 造句 = `drillSentence`）。
library;

import 'package:flutter/foundation.dart';

import '../core/learning.dart';
import '../core/writing.dart';
import '../core/writing_draft.dart';
import '../core/writing_history.dart';
import '../core/writing_record_json.dart';
import '../data/prefs_store.dart';
import '../data/repositories/learning_repository.dart';
import '../services/writing_ledger.dart';

/// 仿写页的 ViewModel。
class WritingViewModel extends ChangeNotifier {
  WritingViewModel({
    required LearningRepository learning,
    PrefsStore? prefsStore,
  })  : _learningRepo = learning,
        _store = prefsStore ?? PrefsStore.memory();

  final LearningRepository _learningRepo;
  final PrefsStore _store;

  List<WritingRecord> _history = const <WritingRecord>[];
  WritingDraft _draft = emptyWritingDraft;
  WritingFeedback? _feedback;
  WritingHistoryFilter _filter = const WritingHistoryFilter();

  String _articleId = '';
  String _articleTitle = '';

  bool _busy = false;
  String? _error;
  String _notice = '';

  /// 全部仿写记录（含金句课 / 奶牛工棚 / 拷打造句）。
  List<WritingRecord> get history => _history;

  /// 当前草稿（范句 / 作答 / 任务 / 必须用上的词）。
  WritingDraft get draft => _draft;

  /// 范句（可改）。
  String get model => _draft.model;

  /// 我的仿写。
  String get text => _draft.text;

  /// AI 给的任务；还没生成时为 null。
  ImitationTask? get task => _draft.task;

  /// 必须用上的词块。
  List<String> get mustUse => _draft.mustUse;

  /// 最近一次批改结果（不落草稿，重进页面从历史读）。
  WritingFeedback? get feedback => _feedback;

  /// 历史筛选条件。
  WritingHistoryFilter get filter => _filter;

  /// 当前筛选后的历史（时间倒序）。
  List<WritingRecord> get filteredHistory =>
      filterWritingHistory(_history, _filter);

  /// 当前范围内各来源的条数。
  Map<WritingHistorySource, int> get historyCounts =>
      writingHistoryCounts(_history, _filter.scope, _articleId);

  /// 正在读写。
  bool get busy => _busy;

  /// 出错原因。
  String? get error => _error;

  /// 一次性提示。
  String get notice => _notice;

  /// 当前文章 id（空 → `manual`）。
  String get articleId => _articleId.isEmpty ? 'manual' : _articleId;

  /// 当前文章标题。
  String get articleTitle => _articleTitle;

  /// 初始化：读学习记录 + 读草稿。
  Future<void> bootstrap() => _guard(() async {
        final data = await _learningRepo.load();
        _history = writingRecordsFromJson(data.writingHistory);
        _draft = _store.loadWritingDraft();
      });

  /// 挂在某篇文章上（历史筛选的「本篇」按它归属）。
  void setArticleContext(String? articleId, {String articleTitle = ''}) {
    _articleId = articleId ?? '';
    _articleTitle = articleTitle;
    notifyListeners();
  }

  /// 换范句（同时清掉上一次的任务与批改：题目是给这句出的）。
  void setModel(String value) {
    if (_draft.model == value) return;
    _draft = _draft.copyWith(model: value, task: () => null);
    _feedback = null;
    notifyListeners();
    _persistDraft();
  }

  /// 改作答。
  void setText(String value) {
    if (_draft.text == value) return;
    _draft = _draft.copyWith(text: value);
    notifyListeners();
    _persistDraft();
  }

  /// 加 / 减必须用上的词块。
  void setMustUse(List<String> value) {
    _draft = _draft.copyWith(mustUse: value);
    notifyListeners();
    _persistDraft();
  }

  /// 拼出题提示词；没范句时记一条错误并返回 null。
  String? buildTaskPrompt({String? structure}) {
    final model = _draft.model.trim();
    if (model.isEmpty) {
      _error = '先选一句范句';
      notifyListeners();
      return null;
    }
    return buildImitationTaskPrompt(
      model: model,
      structure: structure,
      mustUse: _draft.mustUse.isEmpty ? null : _draft.mustUse,
    );
  }

  /// 粘回 AI 的任务。成功返回 null，失败返回给用户看的中文原因。
  String? applyTask(String raw) {
    final parsed = parseImitationTask(raw);
    if (parsed == null) {
      _error = '没认出任务 JSON；请确认粘的是 {"task":...} 那个对象';
      notifyListeners();
      return _error;
    }
    _draft = _draft.copyWith(task: () => parsed);
    _feedback = null;
    _error = null;
    notifyListeners();
    _persistDraft();
    return null;
  }

  /// 拼批改提示词；没任务 / 没作答时记错误并返回 null。
  String? buildFeedbackPrompt() {
    final task = _draft.task;
    if (task == null) {
      _error = '先生成仿写任务';
      notifyListeners();
      return null;
    }
    if (_draft.text.trim().isEmpty) {
      _error = '先写点东西再批改';
      notifyListeners();
      return null;
    }
    return buildWritingFeedbackPrompt(
      task,
      _draft.text,
      WritingFeedbackPromptOptions(
        previousIssues: task.round != null &&
                task.round! > 1 &&
                (_feedback?.issues.isNotEmpty ?? false)
            ? <PreviousIssue>[
                for (final issue in _feedback!.issues)
                  PreviousIssue(
                    original: issue.original,
                    suggestion: issue.suggestion,
                    reason: issue.reason,
                    rule: issue.rule,
                    key: issue.key,
                  ),
              ]
            : null,
      ),
    );
  }

  /// 粘回批改结果并落库。成功返回 null，失败返回中文原因。
  ///
  /// 解析带 `answer`：AI 编出来的 `original`（作答里根本没有那段字）直接丢掉，
  /// 不写进历史。与造句页 `applyFeedback` / 产出训练 `parseProductionFeedback` 同口径。
  Future<String?> applyFeedback(String raw) async {
    final task = _draft.task;
    if (task == null) return '先生成仿写任务';
    final parsed = parseWritingFeedback(
      raw,
      WritingFeedbackParseOptions(answer: _draft.text),
    );
    if (parsed == null) {
      _error = '没认出批改 JSON；请确认粘的是 v2 批改结果';
      notifyListeners();
      return _error;
    }
    final record = WritingRecord(
      at: DateTime.now().toUtc().toIso8601String(),
      articleId: articleId,
      articleTitle: _articleTitle.isEmpty ? null : _articleTitle,
      model: _draft.model,
      text: _draft.text,
      feedback: parsed,
      task: task,
      source: WritingSource.writing,
    );
    final ok = await _appendRecord(record);
    if (!ok) return '记录没写进去';
    _feedback = parsed;
    _error = null;
    notifyListeners();
    return null;
  }

  /// 载入一条历史记录回看（范句 / 作答 / 任务 / 批改一起回来）。
  void loadRecord(WritingRecord rec) {
    _draft = WritingDraft(
      model: rec.model,
      text: rec.text,
      task: rec.task,
      mustUse: const <String>[],
    );
    _feedback = rec.feedback;
    _error = null;
    notifyListeners();
    _persistDraft();
  }

  /// 改历史筛选条件。
  void setFilter(WritingHistoryFilter next) {
    _filter = next;
    notifyListeners();
  }

  /// 清空当前筛选范围（来源 + 本篇/全库）；金句课记录不在这个面板里清。
  Future<void> clearHistory() => _guard(() async {
        final next = removeWritingHistory(_history, _filter);
        final removed = _history.length - next.length;
        final data = await _learningRepo.load();
        data.writingHistory = writingRecordsToJson(next);
        await _learningRepo.writeSection(data, LearningSection.writingHistory);
        _history = next;
        _notice = '已清掉当前范围内的 $removed 条';
      });

  /// 清掉错误与提示。
  void clearNotice() {
    if (_error == null && _notice.isEmpty) return;
    _error = null;
    _notice = '';
    notifyListeners();
  }

  /// 追加一条记录并落盘（整段重写：`writing_records` 是先清后插）。
  ///
  /// 统一走 [appendWritingRecord]；同时给今天的「写」活动 +1
  /// （照 Web `applyWritingFeedback` 里的 `recordActivity('write')`），
  /// 重复粘回同一份批改不重复记账。
  Future<bool> _appendRecord(WritingRecord record) async {
    final result = await appendWritingRecord(
      repo: _learningRepo,
      current: _history,
      record: record,
      countActivity: true,
    );
    if (!result.ok) {
      _error = result.error;
      notifyListeners();
      return false;
    }
    _history = result.history;
    notifyListeners();
    return true;
  }

  /// 草稿落盘（失败不打断输入：草稿丢了最多重写）。
  void _persistDraft() {
    _store.saveWritingDraft(_draft);
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
