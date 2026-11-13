/// AI 跑批的 ViewModel：把「缺释义的词」一批批发给模型，解析后回填词库。
///
/// 对应 Web `src/reader/hooks/useAiLocalBatch.ts` 的语义，但**没有服务端**：
/// - 稳定 id（[AiJob.id]）防同一块被重跑；
/// - 已成功的块落库后自然从待办里消失（词库本身是事实来源，不另存 done 账本）；
/// - 失败的块留着，点「继续」才重试，不自动无限刷；
/// - 暂停时把当前这块跑完就停，已经拿到的结果照常落库。
///
/// 网络能力通过构造参数 [complete] 注入：页面给 [AiClient.complete]，测试给假实现，
/// 这样整个跑批能离线测，且 `lib/core` 完全不认识 `http`。
library;

import 'package:flutter/foundation.dart';

import '../core/ai_config.dart';
import '../core/ai_jobs.dart';
import '../core/analyzer_parse.dart' show parseAnalysis;
import '../core/vocab/analysis.dart' show applyWordAnalysis;
import '../data/prefs_store.dart';
import '../data/repositories/article_repository.dart' show ArticleRepository, ArticleRow;
import '../data/repositories/vocab_repository.dart';
import '../models/vocab.dart' show VocabLibrary;
import '../services/ai_client.dart' show AiReply;
import 'current_article_view_model.dart';

/// 跑批状态。
enum AiBatchPhase { idle, running, paused, done }

/// 一块任务的结果（界面显示「完成 N / 失败 M」）。
class AiBatchOutcome {
  const AiBatchOutcome({
    required this.doneIds,
    required this.failedIds,
    required this.total,
  });

  final Set<String> doneIds;
  final Map<String, String> failedIds;
  final int total;

  int get doneCount => doneIds.length;
  int get failedCount => failedIds.length;
  int get remaining => total - doneIds.length;
}

/// 一条提示词 → 一次模型回复。页面注入真客户端，测试注入假函数。
typedef AiComplete = Future<AiReply> Function(AiConfig config, String prompt);

class AiBatchViewModel extends ChangeNotifier {
  AiBatchViewModel({
    required VocabRepository vocab,
    required this.complete,
    this.articles,
    this.currentArticle,
    PrefsStore? prefsStore,
    this.onDispose,
  })  : _vocabRepo = vocab,
        _store = prefsStore ?? PrefsStore.memory();

  final VocabRepository _vocabRepo;

  /// 选篇用（拿文章标题做下拉）。测试里不传就只按 id 跑。
  final ArticleRepository? articles;

  /// 全局「当前文章」：只读，页内换篇不改它。
  final CurrentArticleViewModel? currentArticle;
  final AiComplete complete;
  final PrefsStore _store;

  /// 释放上游资源用（装配层把 `AiClient.close` 传进来，测试不传）。
  ///
  /// 网络客户端是在 `main.dart` 那一层 new 出来的，只有它知道该不该关；
  /// ViewModel 只负责在自己 dispose 时通知一声，不 import `http` 的任何东西。
  final VoidCallback? onDispose;

  AiConfig _config = defaultAiConfig;
  List<AiJob> _jobs = <AiJob>[];
  final Set<String> _doneIds = <String>{};
  final Map<String, String> _failedIds = <String, String>{};
  int _index = 0;
  AiBatchPhase _phase = AiBatchPhase.idle;
  bool _busy = false;
  String _error = '';
  String _notice = '';

  /// 当前要跑的篇（= 全局「当前文章」）；没选（或文章被删）为 null。
  String? _articleId;
  List<ArticleRow> _articleList = const <ArticleRow>[];

  /// 本轮被丢掉的「不是本块请求」的词数，收尾时并进提示。
  int _skippedWords = 0;
  bool _disposed = false;

  // ---- getters ----

  AiConfig get config => _config;
  List<AiJob> get jobs => _jobs;
  Set<String> get doneIds => Set<String>.unmodifiable(_doneIds);
  Map<String, String> get failedIds => Map<String, String>.unmodifiable(_failedIds);
  int get index => _index;
  AiBatchPhase get phase => _phase;
  bool get running => _phase == AiBatchPhase.running;
  bool get paused => _phase == AiBatchPhase.paused;
  bool get busy => _busy;
  String? get error => _error.isEmpty ? null : _error;
  String get notice => _notice;
  bool get hasJobs => _jobs.isNotEmpty;
  bool get allDone => _jobs.isNotEmpty && _doneIds.length == _jobs.length;

  AiBatchOutcome get outcome => AiBatchOutcome(
        doneIds: _doneIds,
        failedIds: _failedIds,
        total: _jobs.length,
      );

  String get progressText {
    if (_jobs.isEmpty) return '待办：0 块';
    return '第 ${(_index + 1).clamp(1, _jobs.length)}/${_jobs.length} 块'
        ' · 完成 ${_doneIds.length} · 失败 ${_failedIds.length}';
  }

  /// 当前要跑的篇（= 全局「当前文章」）。
  String? get articleId => _articleId;

  /// 选篇下拉的数据源（按更新时间倒序，仓储保证）。
  List<ArticleRow> get articleList => _articleList;

  /// 当前篇的标题（下拉框显示用）；找不到回 id。
  String get articleTitle {
    final id = _articleId;
    if (id == null) return '没选文章';
    for (final a in _articleList) {
      if (a.id == id) return a.title;
    }
    return id;
  }

  // ---- 生命周期 ----

  /// 读本机设置 + 文章列表 + 重新从词库算待办。跑过一轮后再调一次，成功的块自然消失。
  Future<void> bootstrap() async {
    _config = _store.loadAiConfig();
    await _loadArticles();
    await refresh();
  }

  /// 拉文章列表，并把「要跑的篇」钉在全局当前文章上。
  ///
  /// 这里**不退回第一篇**：全局还没选文章时宁可空着（界面上显示
  /// 「精读页还没选文章」），也不能悄悄拿一篇别的去跑掉额度。
  Future<void> _loadArticles() async {
    final repo = articles;
    if (repo == null) return;
    try {
      final list = await repo.list();
      _articleList = list;
      final global = currentArticle?.articleId;
      // 全局当前篇是唯一事实来源：全局没选就空着，全局那篇被删也空着。
      _articleId = (global != null && list.any((a) => a.id == global))
          ? global
          : null;
    } on Object catch (e) {
      _error = '读文章列表失败：$e';
    }
  }

  /// 换一篇（一般用不到：范围就是全局当前篇）。
  ///
  /// 留着是给「页内临时看别的篇」这类调用，不改全局。
  Future<void> setArticle(String? articleId) async {
    final next = (articleId ?? '').trim().isEmpty ? null : articleId!.trim();
    if (next == _articleId) return;
    _articleId = next;
    _notice = '';
    _notify();
    await refresh();
  }

  /// 重建任务列表。
  ///
  /// 词库变了，旧的「完成 / 失败」标记对应的块可能已经不存在（或者 id 撞上别的
  /// 词块），所以一并清空 —— 否则进度显示「完成 3」而实际只剩 2 块，
  /// `run()` 也会拿旧 id 误跳过。
  Future<void> refresh() async {
    _busy = true;
    _error = '';
    _notify();
    try {
      final library = await _vocabRepo.load() ?? const VocabLibrary();
      _jobs = buildAiLookupJobs(library, articleId: _articleId);
      _index = 0;
      _phase = AiBatchPhase.idle;
      _doneIds.clear();
      _failedIds.clear();
    } on Object catch (e) {
      _error = '读词库失败：$e';
    } finally {
      _busy = false;
      _notify();
    }
  }

  /// 保存连接设置（key 只写本机 SharedPreferences，不进任何备份 / git 文件）。
  ///
  /// 写路径与读路径必须过同一道守卫：`PrefsStore.loadAiConfig()` 读回来时走
  /// [normalizeAiConfig]，这里如果直接落原值，同一份配置「从盘上读」和
  /// 「刚手输」会获得两种强度的校验（越界温度、`ftp://` 之类的地址就漏过去了）。
  Future<void> updateConfig(AiConfig config) async {
    _config = normalizeAiConfig(aiConfigToJson(config));
    _error = '';
    await _store.saveAiConfig(_config);
    _notify();
  }

  /// 「测试连接」：只发一条短消息，不改数据。
  Future<AiReply> testConnection() =>
      complete(_config, '请只回复两个汉字：正常');

  // ---- 跑批 ----

  /// 跑完待办（或跑到暂停 / 全部处理完）。
  ///
  /// 已经是成功的块会跳过；失败的块在本次调用里会重试（用户主动点「继续」才进来）。
  Future<void> run() async {
    if (_runningGuard()) return;
    if (!_config.hasApiKey) {
      _error = '还没填 API key，先在上面填好再跑';
      _notify();
      return;
    }
    if (_jobs.isEmpty) {
      _notice = _articleId == null ? '精读页还没选文章' : '本篇没有待查的词，都补齐了';
      _notify();
      return;
    }
    _phase = AiBatchPhase.running;
    _error = '';
    _notice = '';
    _skippedWords = 0;
    _notify();

    while (_index < _jobs.length) {
      if (_disposed) return;
      final job = _jobs[_index];
      if (_doneIds.contains(job.id)) {
        _index++;
        _notify();
        continue;
      }
      final reply = await _runOne(job);
      if (_disposed) return;
      if (reply == null) {
        // 失败：留在这块，等用户点「继续」再重试；先跳出这一轮。
        break;
      }
      _index++;
      _notify();
      if (_phase == AiBatchPhase.paused) break;
    }

    if (_disposed) return;
    final skipped = _skippedWords > 0 ? '；另有 $_skippedWords 个不是请求的词已跳过' : '';
    if (_phase == AiBatchPhase.paused) {
      _notice = '已暂停：完成 ${_doneIds.length} 块，点「继续」接着跑$skipped';
    } else {
      _phase = _failedIds.isEmpty ? AiBatchPhase.done : AiBatchPhase.idle;
      _notice = _failedIds.isEmpty
          ? '跑完了：补齐 ${_doneIds.length} 块$skipped'
          : '有 ${_failedIds.length} 块没成功，点「继续」重试$skipped';
    }
    _notify();
  }

  /// 暂停：当前这块跑完就停（结果照常落库），不丢已拿到的回复。
  /// 只改状态；提示文案由 `run()` 收尾统一给，避免两块状态各说各话。
  void pause() {
    if (_phase != AiBatchPhase.running) return;
    _phase = AiBatchPhase.paused;
    _notify();
  }

  /// 继续（从当前块重跑失败的，成功的跳过）。
  ///
  /// 已经全部跑完（`done`）时再点「继续」没有意义：`run()` 的 while 不会再进，
  /// 但收尾会给一条重复的「跑完了」提示，状态机来回切一次。这里直接挡掉。
  Future<void> resume() async {
    if (_phase == AiBatchPhase.running || _phase == AiBatchPhase.done) return;
    await run();
  }

  /// 把失败的块标记为「先跳过」：不改数据，下一轮 refresh 会按词库重新算。
  void skipFailed() {
    if (_failedIds.isEmpty) return;
    _failedIds.clear();
    _notice = '已清掉失败标记，点「继续」重跑或下拉刷新重算待办';
    _notify();
  }

  void clearNotice() {
    if (_notice.isEmpty && _error.isEmpty) return;
    _notice = '';
    _error = '';
    _notify();
  }

  // ---- 私有 ----

  /// 跑一块；成功返回回复对象，失败返回 null（并记进 `_failedIds`）。
  Future<AiReply?> _runOne(AiJob job) async {
    late final AiReply reply;
    try {
      reply = await complete(_config, job.prompt);
    } on Object catch (e) {
      _failedIds[job.id] = '请求抛异常：$e';
      _notify();
      return null;
    }
    if (!reply.isOk) {
      _failedIds[job.id] = reply.error ?? '请求失败';
      _notify();
      return null;
    }
    final parsed = parseAnalysis(reply.text);
    if (parsed.words.isEmpty) {
      _failedIds[job.id] = '模型没给回可解析的查词表格';
      _notify();
      return null;
    }
    // 只认本块请求过的词：模型偶尔会多回 / 拼错一个词，直接全量落库会在
    // 用户词库里凭空多出词条，而且事后查不出是哪一块带进来的。
    final requested = <String>{
      for (final w in job.words) w.trim().toLowerCase(),
    };
    final words = parsed.words
        .where((wa) => requested.contains(wa.word.trim().toLowerCase()))
        .toList(growable: false);
    if (words.isEmpty) {
      _failedIds[job.id] = '模型没给回本块请求的词';
      _notify();
      return null;
    }
    final dropped = parsed.words.length - words.length;
    try {
      final library = await _vocabRepo.load() ?? const VocabLibrary();
      await _vocabRepo.save(applyWordAnalysis(library, words));
    } on Object catch (e) {
      _failedIds[job.id] = '回填词库失败：$e';
      _notify();
      return null;
    }
    if (dropped > 0) {
      // 攒着，等 run() 收尾统一播报（中途设 _notice 会被收尾文案覆盖）。
      _skippedWords += dropped;
    }
    _doneIds.add(job.id);
    _failedIds.remove(job.id);
    return reply;
  }

  bool _runningGuard() => _phase == AiBatchPhase.running;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    onDispose?.call();
    super.dispose();
  }
}
