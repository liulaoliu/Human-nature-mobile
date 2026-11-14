/// 单词卡「正面拼写」这一步的状态机。
///
/// 为什么单开一个类：这一组状态（输入 / 检查过 / 拼对没 / 拼错确认过）换卡就清零，
/// 和 [StudyCardFlow] 的翻面 / 计时 / 复习出口是**两套生命周期**；塞在一起会让
/// `StudyCardFlow` 越过 40 个方法的门禁，也确实不该由它记「拼写输入框里写了什么」。
///
/// 与 Web 版 `useStudySpellGate.ts` + `useStudySpelling.ts` 的分工一一对应：
/// 状态机在这里，落库（SRS again + 「不认识」标签 + 队尾重排）在 `StudyViewModel.checkSpelling`。
///
/// **口径**：拼写是「写得出来吗」的硬门槛，错一次定生死 —— 不给第二次输入，
/// 能再输一次等于把判断变成抄写（见 `core/vocab/spelling.dart`）。
library;

import 'package:flutter/foundation.dart';

import '../core/vocab/word.dart' show displayMeaning;
import 'study_view_model.dart';

/// 拼错卡上要显示的三样东西。
class SpellMissCard {
  const SpellMissCard({
    required this.word,
    required this.typed,
    required this.meaning,
  });

  /// 正确写法。
  final String word;

  /// 用户拼的那一版。
  final String typed;

  /// 中文释义（帮助用户回忆）。
  final String meaning;
}

class StudySpellingFront extends ChangeNotifier {
  StudySpellingFront(this._vm) {
    _vm.addListener(_onVm);
    _syncKey();
  }

  final StudyViewModel _vm;

  bool _checked = false;
  bool _ok = false;
  bool _missAcked = false;
  String _input = '';

  /// 检查那一刻输入框里的内容（判卷结果定格，之后用户再打字也不该改它）。
  String _typed = '';
  String _cardKey = '';

  /// 这一张该不该在正面出输入框。
  ///
  /// 三个条件与 Web `spellingFront = spelling && !checked && !relearning` 同义：
  /// 设置里开着卡面拼写、这一张还没检查、**不是重学卡**。
  /// 重学卡不考拼写 —— 那是「从头重学」，先看词看释义，再进锤炼。
  bool get front {
    final s = _vm.session;
    final card = s?.card;
    if (s == null || card == null) return false;
    if (!_vm.prefs.spelling) return false;
    if (_checked) return false;
    return !s.view.relearning;
  }

  /// 检查过了（此时卡面翻到背面，可以评分）。
  bool get checked => _checked;

  /// 拼对了（拼错时看 [miss]）。
  bool get ok => _ok;

  /// 输入框内容。
  String get input => _input;

  /// 拼错卡；null = 不在拼错确认态。
  SpellMissCard? get miss {
    if (!_checked || _ok || _missAcked) return null;
    final card = _vm.session?.card;
    if (card == null) return null;
    return SpellMissCard(
      word: card.word,
      typed: _typed,
      meaning: displayMeaning(
        partOfSpeech: card.partOfSpeech,
        meaning: card.meaning,
      ),
    );
  }

  /// 输入框回写。
  void setInput(String value) {
    if (value == _input) return;
    _input = value;
    notifyListeners();
  }

  /// 回车 / 点「检查」。
  ///
  /// 拼对**不写库**（`advance: false`）：拼写只当门槛，认识 / 模糊 / 忘记了
  /// 留给用户点，这样复习三档的出口矩阵才对得上。
  Future<void> check() async {
    if (_checked) return;
    final typed = _input;
    _checked = true;
    _typed = typed;
    final passed = await _vm.checkSpelling(typed, advance: false);
    _ok = passed;
    notifyListeners();
  }

  /// 拼错卡上点「知道了」：这个词已重排在队尾，推进到下一张。
  Future<void> ack() async {
    if (miss == null) return;
    _missAcked = true;
    notifyListeners();
    _vm.forward();
  }

  /// 换卡 / 重开一轮 / 切换拼写开关：清干净。
  void reset() {
    if (!_checked && _input.isEmpty && !_missAcked) return;
    _clear();
    notifyListeners();
  }

  void _clear() {
    _checked = false;
    _ok = false;
    _missAcked = false;
    _input = '';
    _typed = '';
  }

  /// 会话换卡了就自动清（与 [StudyCardFlow._syncKey] 同一个 key 口径）。
  void _onVm() {
    if (_syncKey()) notifyListeners();
  }

  bool _syncKey() {
    final s = _vm.session;
    final card = s?.card;
    final key = s == null || card == null ? '' : '${s.index}:${card.id}';
    if (key == _cardKey) return false;
    _cardKey = key;
    _clear();
    return true;
  }

  @override
  void dispose() {
    _vm.removeListener(_onVm);
    super.dispose();
  }
}
