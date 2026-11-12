/// 选词模式的共享状态：开关 + 这一轮点了哪些词。
///
/// 为什么是独立的 ViewModel 而不是各页自己存：用户明确要求「速读里也要有选词模式，
/// 并且和精读复用」—— 同一个 App 进程里只能有一份开关，否则从精读切到速读
/// 开关就「自己关了」，正是最让人困惑的 bug。
///
/// 选中集合按「句子 + 词序号」记（见 `core/word_pick.dart`），跨页面共享，
/// 但**加入生词本由调用方负责**：精读和速读各自知道当前文章与上下文。
library;

import 'package:flutter/foundation.dart';

import '../core/vocab_stats.dart' show PickSession;
import '../core/word_pick.dart';

/// 选词模式的开关与选中集合。
class PickModeViewModel extends ChangeNotifier {
  PickModeViewModel({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  bool _enabled = false;
  PickState _state = const PickState();

  /// 是否允许一次选多个词。
  ///
  /// 默认**不开**：手机上一不小心连点两下就变成词组，收进去的东西跟想的不一样。
  /// 要词组（`keep up with`）时由用户自己打开这个开关 —— 加单词还是加词组
  /// 是他当场决定的，不该由「点了几个」隐式推断。
  bool _multi = false;

  /// 本轮点选开始的时间（开关打开那一刻）。
  DateTime? _startedAt;

  /// 开关是否打开。
  bool get enabled => _enabled;

  /// 当前选中集合。
  PickState get state => _state;

  /// 选中了几个。
  int get count => _state.length;

  /// 是否允许一次选多个词（默认关 = 单选）。
  bool get multi => _multi;

  /// 这一轮会入几条（连续同句的相邻词算一条）。
  int get entryCount => _state.entries.length;

  /// 打开 / 关掉多选。
  ///
  /// 从多选切回单选时只留**最后点的那一个**：用户的意图是「我刚才点多了」，
  /// 保留最后一下最贴近他当时的注意力（保留第一个反而要重新找他想要的词）。
  void setMulti(bool value) {
    if (_multi == value) return;
    _multi = value;
    if (!value && _state.length > 1) {
      _state = PickState(targets: [_state.targets.last]);
    }
    notifyListeners();
  }

  /// 切换多选开关。
  void toggleMulti() => setMulti(!_multi);

  /// 打开或关掉选词模式。
  ///
  /// 关掉时清空选中：留着反而会让人以为「这些词已经加了」。
  void setEnabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    _state = const PickState();
    _startedAt = value ? _now() : null;
    notifyListeners();
  }

  /// 切换开关。
  void toggleEnabled() => setEnabled(!_enabled);

  /// 点一个词：选中 / 取消。
  ///
  /// 单选模式下是「替换」而不是「追加」：这次只想收这一个词。
  /// 已选的那个再点一下就取消（与之前一致）。
  ///
  /// 没打开选词模式时什么也不做 —— 调用方照常处理自己的点击（打开取词面板）。
  bool toggle(String sentenceId, int index, String word) {
    if (!_enabled) return false;
    final target = PickTarget(sentenceId: sentenceId, index: index, word: word);
    if (!_multi) {
      final sameOne = _state.length == 1 && _state.contains(sentenceId, index);
      _state = sameOne ? const PickState() : _state.selectOnly(target);
    } else {
      _state = _state.toggle(target);
    }
    notifyListeners();
    return true;
  }

  /// 清空选中（加入生词本之后、换文章时）。
  void clear() {
    if (_state.isEmpty) return;
    _state = const PickState();
    notifyListeners();
  }

  /// 这一轮要不要记进「选词会话」统计。
  ///
  /// 口径照 Web `useVocabMode.recordSession`：**停留不到 1 秒且一个词都没选就跳过**，
  /// 否则每次手滑点开开关都会污染统计。
  PickSession? takeSession() {
    final started = _startedAt;
    _startedAt = _enabled ? _now() : null;
    if (started == null) return null;
    final seconds = _now().difference(started).inSeconds;
    final picked = _state.length;
    if (seconds < 1 && picked == 0) return null;
    return PickSession(at: started.toIso8601String(), seconds: seconds, picked: picked);
  }
}
