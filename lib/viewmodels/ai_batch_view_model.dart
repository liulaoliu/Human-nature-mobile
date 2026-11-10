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
import '../data/repositories/vocab_repository.dart';
import '../models/vocab.dart' show VocabLibrary;
import '../services/ai_client.dart' show AiReply;

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
    PrefsStore? prefsStore,
  })  : _vocabRepo = vocab,
        _store = prefsStore ?? PrefsStore.memory();

  final VocabRepository _vocabRepo;
  final AiComplete complete;
  final PrefsStore _store;

  AiConfig _config = defaultAiConfig;
  List<AiJob> _jobs = <AiJob>[];
  final Set<String> _doneIds = <String>{};
  final Map<String, String> _failedIds = <String, String>{};
  int _index = 0;
  AiBatchPhase _phase = AiBatchPhase.idle;
  bool _busy = false;
  String _error = '';
  String _notice = '';
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

  // ---- 生命周期 ----

  /// 读本机设置 + 重新从词库算待办。跑过一轮后再调一次，成功的块自然消失。
  Future<void> bootstrap() async {
    _config = _store.loadAiConfig();
    await refresh();
  }

  /// 重建任务列表（保留本次会话已完成 / 失败的标记，供界面显示）。
  Future<void> refresh() async {
    _busy = true;
    _error = '';
    _notify();
    try {
      final library = await _vocabRepo.load() ?? const VocabLibrary();
      _jobs = buildAiLookupJobs(library);
      _index = 0;
      _phase = AiBatchPhase.idle;
    } on Object catch (e) {
      _error = '读词库失败：$e';
    } finally {
      _busy = false;
      _notify();
    }
  }

  /// 保存连接设置（key 只写本机 SharedPreferences，不进任何备份 / git 文件）。
  Future<void> updateConfig(AiConfig config) async {
    _config = config;
    _error = '';
    await _store.saveAiConfig(config);
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
      _notice = '词库里没有待查的词，都补齐了';
      _notify();
      return;
    }
    _phase = AiBatchPhase.running;
    _error = '';
    _notice = '';
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
    if (_phase == AiBatchPhase.paused) {
      _notice = '已暂停：完成 ${_doneIds.length} 块，点「继续」接着跑';
    } else {
      _phase = _failedIds.isEmpty ? AiBatchPhase.done : AiBatchPhase.idle;
      _notice = _failedIds.isEmpty
          ? '跑完了：补齐 ${_doneIds.length} 块'
          : '有 ${_failedIds.length} 块没成功，点「继续」重试';
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
  Future<void> resume() async {
    if (_phase == AiBatchPhase.running) return;
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
    try {
      final library = await _vocabRepo.load() ?? const VocabLibrary();
      await _vocabRepo.save(applyWordAnalysis(library, parsed.words));
    } on Object catch (e) {
      _failedIds[job.id] = '回填词库失败：$e';
      _notify();
      return null;
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
    super.dispose();
  }
}
