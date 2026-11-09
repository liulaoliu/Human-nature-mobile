/// 拷打造句（小课堂 · 造句）：一轮背完 → 每个考到的词 / 词块各出一道造句题。
///
/// 三层分工：
///   - **纯函数**在 `core/drill_sentence.dart`（素材 → 题目 → 稳定身份）、
///     `core/writing.dart`（批改提示词 + 严格解析）、`core/drill_sentence_draft.dart`
///     （按题存作答与批改）；
///   - **本文件**只做状态编排：批次认领、切题不丢字、批改落库、重写、草稿读写；
///   - **界面**只读 getter、只调方法。
///
/// 与仿写 / 奶牛工棚共用 `writingHistory` 段，只是 `source` 不同
/// （造句 = `WritingSource.drillSentence`）。一批有多道题，所以草稿是
/// 「题 id → 作答 + 批改」的表，切题、刷新、退回背单词再进来都不丢别的题的字。
library;

import 'package:flutter/foundation.dart';

import '../core/activity/activity.dart' show ActivityCat, addActivity, dayKeyLocal;
import '../core/drill_sentence.dart';
import '../core/drill_sentence_draft.dart';
import '../core/learning.dart';
import '../core/writing.dart';
import '../core/writing_record_json.dart';
import '../data/prefs_store.dart';
import '../data/repositories/learning_repository.dart';
import '../models/vocab.dart';

/// 小课堂 · 造句页的 ViewModel。
class DrillSentenceViewModel extends ChangeNotifier {
  DrillSentenceViewModel({
    required LearningRepository learning,
    PrefsStore? prefsStore,
  })  : _learningRepo = learning,
        _store = prefsStore ?? PrefsStore.memory();

  final LearningRepository _learningRepo;
  final PrefsStore _store;

  List<WritingRecord> _history = const <WritingRecord>[];
  DrillSentenceDraft _draft = emptyDrillSentenceDraft;

  /// 本批次的题目 / 素材（由结算页 `startBatch` 传入，不落草稿）。
  List<ImitationTask> _tasks = const <ImitationTask>[];
  List<DrillSentencePoint> _points = const <DrillSentencePoint>[];
  DrillSentenceKind _kind = DrillSentenceKind.memory;
  String _batchId = '';

  /// 每题当前写到第几稿（只存内存：批改写完即落库，刷新回到首稿可接受）。
  final Map<String, int> _rounds = <String, int>{};

  String _articleId = '';
  String _articleTitle = '';

  bool _busy = false;
  String? _error;
  String _notice = '';

  /// 全部写作记录（含仿写 / 奶牛工棚 / 金句课，供去重与回看）。
  List<WritingRecord> get history => _history;

  /// 当前草稿（批次身份 + 停在哪题 + 各题作答）。
  DrillSentenceDraft get draft => _draft;

  /// 本批次的题目；还没 `startBatch` 时为空。
  List<ImitationTask> get tasks => _tasks;

  /// 本批次的造句素材。
  List<DrillSentencePoint> get points => _points;

  /// 本批次的拷打种类。
  DrillSentenceKind get kind => _kind;

  /// 本批次的稳定身份。
  String get batchId => _batchId;

  /// 当前停在第几题（0 起）。
  int get index => _draft.activeIndex;

  /// 有没有题可做。
  bool get hasTasks => _tasks.isNotEmpty;

  /// 当前题；草稿里的 activeIndex 越界时返回 null。
  ImitationTask? get task => _draft.activeIndex < _tasks.length
      ? _tasks[_draft.activeIndex]
      : null;

  /// 当前题的作答。
  String get answer {
    final t = task;
    if (t == null) return '';
    return _draft.answerOf(drillTaskIdOf(t)).answer;
  }

  /// 当前题最近一次批改（第 2 稿时它就是「上一稿」，供复查）。
  WritingFeedback? get feedback {
    final t = task;
    if (t == null) return null;
    final raw = _draft.answerOf(drillTaskIdOf(t)).feedback;
    return raw == null ? null : writingFeedbackFromJson(raw);
  }

  /// 当前题写到第几稿（默认 1）。
  int get round {
    final t = task;
    if (t == null) return 1;
    return _rounds[drillTaskIdOf(t)] ?? 1;
  }

  /// 能不能重写：批过、且还没到第 2 稿（照 Web 口径只允许 1→2 一稿）。
  bool get canRewrite => hasTasks && feedback != null && round < 2;

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

  /// 初始化：读学习记录 + 读草稿（题目要等结算页 `startBatch` 重新传入）。
  Future<void> bootstrap() => _guard(() async {
        final data = await _learningRepo.load();
        _history = writingRecordsFromJson(data.writingHistory);
        _draft = _store.loadDrillSentenceDraft();
      });

  /// 结算页进来时开一轮：由「本轮考到的词条」反推题目，并认领草稿。
  ///
  /// 换批次（`batchId` 变了）时只保留新批次里同题 id 的作答，其余丢掉 ——
  /// 照 Web `DrillSentenceStage` 的口径，免得上一轮的字串到这一轮里。
  void startBatch(
    List<VocabItem> items,
    List<({String? id, String itemId})> results,
    DrillSentenceKind kind, {
    String? articleId,
    String articleTitle = '',
  }) {
    final pts = drillSentencePoints(items, results, kind);
    final ts = buildDrillSentenceTasks(kind, pts);
    final id = drillSentenceId(kind, pts);

    _points = pts;
    _tasks = ts;
    _kind = kind;
    _batchId = id;
    _articleId = articleId ?? '';
    _articleTitle = articleTitle;
    _rounds.clear();

    var next = _draft;
    if (next.batchId != id || ts.isEmpty) {
      final allowed = <String>{for (final t in ts) drillTaskIdOf(t)};
      next = DrillSentenceDraft(
        batchId: id,
        answers: <String, DrillAnswerDraft>{
          for (final e in next.answers.entries)
            if (allowed.contains(e.key)) e.key: e.value,
        },
      );
    }
    final index = next.activeIndex >= ts.length
        ? (ts.isEmpty ? 0 : ts.length - 1)
        : next.activeIndex;
    _draft = next.copyWith(batchId: id, activeIndex: index);
    _error = null;
    notifyListeners();
    _persistDraft();
  }

  /// 切题：只改 activeIndex，别的题的作答 / 批改原样留着。
  void openTask(int index) {
    if (index < 0 || index >= _tasks.length || index == _draft.activeIndex) return;
    _draft = _draft.copyWith(activeIndex: index);
    _error = null;
    notifyListeners();
    _persistDraft();
  }

  /// 改当前题的作答（保留已粘回的批改）。
  void setAnswer(String value) {
    final t = task;
    if (t == null) return;
    final id = drillTaskIdOf(t);
    final cur = _draft.answerOf(id);
    if (cur.answer == value) return;
    _draft = _draft.withAnswer(id, cur.copyWith(answer: value));
    notifyListeners();
    _persistDraft();
  }

  /// 拼当前题的批改提示词；没题 / 没作答时记错误并返回 null。
  /// 第 2 稿带上「上一稿指出过的问题」让 AI 专查改了没。
  String? buildFeedbackPrompt() {
    final t = task;
    if (t == null) {
      _error = '这一轮还没有题目';
      notifyListeners();
      return null;
    }
    final text = answer;
    if (text.trim().isEmpty) {
      _error = '先写点东西再批改';
      notifyListeners();
      return null;
    }
    final fb = feedback;
    final previous = round > 1 && fb != null && fb.issues.isNotEmpty
        ? <PreviousIssue>[
            for (final issue in fb.issues)
              PreviousIssue(
                original: issue.original,
                suggestion: issue.suggestion,
                reason: issue.reason,
                rule: issue.rule,
                key: issue.key,
              ),
          ]
        : null;
    return buildWritingFeedbackPrompt(
      t,
      text,
      WritingFeedbackPromptOptions(previousIssues: previous),
    );
  }

  /// 粘回批改结果并落库。成功返回 null，失败返回中文原因。
  Future<String?> applyFeedback(String raw) async {
    final t = task;
    if (t == null) return '这一轮还没有题目';
    final text = answer;
    final parsed = parseWritingFeedbackDetailed(
      raw,
      WritingFeedbackParseOptions(answer: text),
    );
    if (parsed == null) {
      _error = '没解析出批改结果：需要 v2 JSON（version / scores / issues / recommendations）';
      notifyListeners();
      return _error;
    }

    final record = WritingRecord(
      at: DateTime.now().toUtc().toIso8601String(),
      articleId: articleId,
      articleTitle: _articleTitle.isEmpty ? null : _articleTitle,
      model: '',
      text: text,
      feedback: parsed.feedback,
      task: t.copyWith(round: () => round),
      source: WritingSource.drillSentence,
    );
    final ok = await _appendRecord(record);
    if (!ok) return '记录没写进去';

    // 批改跟着题走：存回草稿，切回来还看得到这一稿的分数与问题。
    final id = drillTaskIdOf(t);
    final cur = _draft.answerOf(id);
    _draft = _draft.withAnswer(
      id,
      cur.copyWith(feedback: () => parsed.feedback.toJson()),
    );
    _persistDraft();

    final dropped = parsed.dropped;
    final notes = <String>[
      '第 $round 稿已记下：${parsed.feedback.total}/${parsed.feedback.max}',
      if (dropped.issues > 0) '已忽略 ${dropped.issues} 条无法定位的问题',
      if (dropped.recommendations > 0) '已忽略 ${dropped.recommendations} 条无效语言点',
      if (dropped.inferred > 0) '${dropped.inferred} 条缺 rule/key，已自动归类',
    ];
    _notice = notes.join('；');
    _error = null;
    notifyListeners();
    return null;
  }

  /// 重写一稿：只允许 1→2，保留作答与上一稿批改（第 2 稿提示词要用它复查）。
  void rewrite() {
    final t = task;
    if (t == null || !canRewrite) return;
    _rounds[drillTaskIdOf(t)] = round + 1;
    _error = null;
    _notice = '第 2 稿：保留原句，改完再粘回一次批改';
    notifyListeners();
  }

  /// 清空这一轮的造句草稿（题目不动，作答与批改全清）。
  Future<void> clearDraft() => _guard(() async {
        _draft = DrillSentenceDraft(batchId: _batchId);
        _rounds.clear();
        await _store.saveDrillSentenceDraft(_draft);
        _notice = '这一轮的造句草稿已清空';
      });

  /// 清掉错误与提示。
  void clearNotice() {
    if (_error == null && _notice.isEmpty) return;
    _error = null;
    _notice = '';
    notifyListeners();
  }

  /// 追加一条记录并落盘：`writing_records` 是先清后插，必须整段重写；
  /// 同时给今天的「写」活动 +1（照 Web `saveAttempt` 里 `recordActivity('write')`）。
  Future<bool> _appendRecord(WritingRecord record) async {
    final next =
        _hasSameAttempt(record) ? _history : addWritingRecord(_history, record);
    try {
      final data = await _learningRepo.load();
      data.writingHistory = writingRecordsToJson(next);
      data.activity = addActivity(data.activity, dayKeyLocal(), ActivityCat.write);
      await _learningRepo.write(data, <LearningSection>[
        LearningSection.writingHistory,
        LearningSection.activity,
      ]);
      _history = next;
      return true;
    } catch (e) {
      _error = '记录存不进去：$e';
      notifyListeners();
      return false;
    }
  }

  /// 同题、同稿、同文字只记一条（重复粘回不刷历史）。
  bool _hasSameAttempt(WritingRecord rec) {
    final key = _attemptKey(rec);
    for (final r in _history) {
      if (r.source == WritingSource.drillSentence && _attemptKey(r) == key) {
        return true;
      }
    }
    return false;
  }

  /// 去重键：文章 + 句子/考试 id + 题 focus + 稿数 + 作答文字，NUL 连接。
  String _attemptKey(WritingRecord r) => <String>[
        r.articleId,
        r.sentenceId ?? r.examId ?? '',
        r.task?.focus ?? '',
        '${r.task?.round ?? 1}',
        r.text.trim(),
      ].join('\u0000');

  /// 草稿落盘（失败不打断输入：草稿丢了最多重写一遍）。
  void _persistDraft() {
    _store.saveDrillSentenceDraft(_draft);
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
