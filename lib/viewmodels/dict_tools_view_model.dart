/// 「⚡ 一键处理」的界面状态：跑到第几步、每步结果、词典加载状态。
///
/// 真正的读库 / 变换 / 写库在 `services/dict_tools_service.dart`；
/// 这里只做状态机与错误提示，方便页面测试注入假服务。
library;

import 'package:flutter/foundation.dart';

import '../core/dict_tools.dart';
import '../core/ecdict.dart' show Ecdict, EcdictLevel;
import '../data/dictionary_loader.dart' as dict_loader;
import '../services/dict_tools_service.dart'
    show DictStepOutcome, DictToolsRunner;

/// 一键处理的 ViewModel。
class DictToolsViewModel extends ChangeNotifier {
  DictToolsViewModel({
    required this.service,
    Future<bool> Function()? loadDict,
    Ecdict? Function()? dictionaryOf,
    this.examplesReady = true,
  })  : _loadDict = loadDict ?? dict_loader.loadDictionary,
        _dictionaryOf = dictionaryOf ?? dict_loader.dictionary,
        _dictReady = dict_loader.dictionaryReady();

  final DictToolsRunner service;
  final Future<bool> Function() _loadDict;
  final Ecdict? Function() _dictionaryOf;

  bool _dictReady;
  final bool examplesReady;
  bool _busy = false;
  bool _loadingDict = false;
  bool _disposed = false;
  String? _runningStep;
  String? _error;
  String _notice = '';
  EcdictLevel _level = EcdictLevel.cet6;
  final Map<String, DictStepOutcome> _outcomes = <String, DictStepOutcome>{};

  // ---- getters ----

  bool get dictionaryReady => _dictReady;
  bool get busy => _busy;
  bool get loadingDictionary => _loadingDict;
  String? get runningStep => _runningStep;
  String? get error => _error;
  String get notice => _notice;
  EcdictLevel get level => _level;

  /// 最近一次跑出来的结果（没有 = null）。
  DictStepOutcome? outcomeOf(String id) => _outcomes[id];

  /// 有没有跑过任何一步。
  bool get hasRun => _outcomes.isNotEmpty;

  /// 某一步现在能不能点。
  bool enabled(String id, {required bool hasArticle}) {
    final step = _stepOf(id);
    if (step == null) return false;
    if (_busy) return false;
    return dictStepEnabled(
      step,
      dictionaryReady: _dictReady,
      examplesReady: examplesReady,
      hasArticle: hasArticle,
    );
  }

  // ---- 生命周期 ----

  /// 进面板时调一次：词典没加载就后台加载（已有加载中的 Future 会共用）。
  Future<void> bootstrap() async {
    if (_dictReady) return;
    await _ensureDictionary();
  }

  void setLevel(EcdictLevel value) {
    if (_level == value) return;
    _level = value;
    _safeNotify();
  }

  // ---- 执行 ----

  /// 单独跑一步。
  Future<DictStepOutcome?> runStep(String id, {String? articleId}) async {
    if (_busy) return null;
    return _runOne(id, articleId: articleId);
  }

  /// 依次跑五步。每步结束后立刻刷新界面；失败的步骤不阻断后面。
  Future<List<DictStepOutcome>> runAll({String? articleId}) async {
    if (_busy) return const [];
    final out = <DictStepOutcome>[];
    for (final step in dictToolSteps) {
      final r = await _runOne(step.id, articleId: articleId);
      if (r != null) out.add(r);
    }
    _notice = '一键处理完成：${out.where((o) => o.ok).length}/${dictToolSteps.length} 步有更新';
    _safeNotify();
    return out;
  }

  Future<DictStepOutcome?> _runOne(
    String id, {
    String? articleId,
  }) async {
    final step = _stepOf(id);
    if (step == null) return null;
    if (step.needsDictionary && !_dictReady) {
      await _ensureDictionary();
      if (!_dictReady) {
        _error = '离线词典还没加载好，稍后再试';
        _safeNotify();
        return null;
      }
    }

    _busy = true;
    _runningStep = id;
    _error = null;
    _safeNotify();
    try {
      final result = await service.run(
        id,
        dict: step.needsDictionary ? _dictionaryOf() : null,
        articleId: articleId,
        level: _level,
      );
      _outcomes[id] = result;
      _notice = result.message;
      if (result.failed) _error = result.message;
      return result;
    } on Object catch (e) {
      _error = '这一步失败了：$e';
      return null;
    } finally {
      _busy = false;
      _runningStep = null;
      _safeNotify();
    }
  }

  Future<void> _ensureDictionary() async {
    if (_dictReady || _loadingDict) return;
    _loadingDict = true;
    _safeNotify();
    try {
      _dictReady = await _loadDict();
    } on Object {
      _dictReady = false;
    } finally {
      _loadingDict = false;
      _safeNotify();
    }
  }

  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  static DictToolStep? _stepOf(String id) {
    for (final step in dictToolSteps) {
      if (step.id == id) return step;
    }
    return null;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
