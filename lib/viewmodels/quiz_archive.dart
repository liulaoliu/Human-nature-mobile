import '../core/quiz_history.dart';
import '../core/quiz_session.dart';
import '../core/quiz_settings.dart';
import '../data/prefs_store.dart';

/// 整卷考试的「档案」：历史轮次 + 上一场没考完的卷。
///
/// 单独成类是为了让 `QuizViewModel` 只管一场考试的生命周期；读写都走
/// `PrefsStore.saveQuizState`（设置 / 历史 / 快照一起落，避免只更新一半）。
class QuizArchive {
  QuizArchive(this._store);

  final PrefsStore _store;

  List<QuizRoundRow> _history = const <QuizRoundRow>[];
  QuizSession? _saved;

  /// 读盘时灌进来（设置留在 ViewModel 自己那边）。
  void adopt({required List<QuizRoundRow> history, QuizSession? session}) {
    _history = history;
    _saved = session;
  }

  List<QuizRoundRow> get history => List<QuizRoundRow>.unmodifiable(_history);

  QuizSession? get saved => _saved;

  bool get hasSaved => _saved?.resumable ?? false;

  /// 记一轮成绩（新的在前），并落盘。
  void record(QuizRoundRow row, {required QuizSettings settings}) {
    _history = addQuizRound(_history, row);
    persist(settings: settings);
  }

  /// 记下「当前停在哪」/ 清掉（传 null），并落盘。
  void saveSession(QuizSession? session, {required QuizSettings settings}) {
    _saved = session;
    persist(settings: settings);
  }

  /// 三块状态一起写；出错只吞掉（丢了最多回默认，不挡答题）。
  void persist({required QuizSettings settings}) {
    final history = _history;
    final session = _saved;
    _store
        .saveQuizState(settings: settings, history: history, session: session)
        .catchError((Object _) {});
  }
}
