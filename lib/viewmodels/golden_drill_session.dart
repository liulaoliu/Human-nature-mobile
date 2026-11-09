/// 单句金句练习的会话状态：填空（多轮）→ 拼句 → 小结。
///
/// 为什么和 `GoldenViewModel` 分开：一句的练习有自己的一整套临时状态
/// （第几轮、每一轮填了什么、拼句选了哪几个），换句就整体重置；
/// 放在页面级 ViewModel 里会让「换句」和「改课程设置」互相打架，
/// 也很快把那个类撑成上帝类（`tool/check_god_class.dart` 方法上限 40）。
///
/// 纯判定一律走 `lib/core/golden_drill.dart`，这里只做编排：
/// 建计划 → 收作答 → 判分 → 把结果交给上层记账。
library;

import 'package:flutter/foundation.dart';

import '../core/golden.dart';
import '../core/golden_drill.dart';
import '../core/golden_progress.dart';

/// 一句金句的练习阶段。
enum GoldenDrillPhase { fill, assemble, summary }

/// 一句金句的逐轮练习。
class GoldenDrillSession extends ChangeNotifier {
  GoldenDrillSession({
    required this.lessonOf,
    required this.sentenceTextOf,
    required this.recordStep,
  });

  /// 现取课程（不存副本：课程的选句 / 去重开关随时会变）。
  final GoldenLesson? Function() lessonOf;

  /// 按句 id 取原文。
  final String Function(String sentenceId) sentenceTextOf;

  /// 记一步练习结果（由上层落库）。
  final void Function(String sentenceId, GoldenStep step, bool correct)
      recordStep;

  String _sentenceId = '';
  String _text = '';
  List<GoldenTarget> _targets = const <GoldenTarget>[];
  List<GoldenFillRound> _rounds = const <GoldenFillRound>[];
  int _roundIndex = 0;
  bool _roundScored = false;
  List<bool> _roundResults = const <bool>[];
  GoldenAssembly? _assembly;
  List<String> _order = const <String>[];
  bool _assembleScored = false;
  bool _assembleOk = false;
  bool _summaryRecorded = false;
  GoldenDrillPhase _phase = GoldenDrillPhase.fill;

  /// 当前在练哪一句；没开始为空串。
  String get sentenceId => _sentenceId;

  /// 这一句的原文。
  String get text => _text;

  /// 这一句的学习点。
  List<GoldenTarget> get targets => _targets;

  /// 当前阶段。
  GoldenDrillPhase get phase => _phase;

  /// 有题可做（这句至少有一个能挖空的学习点）。
  bool get hasRounds => _rounds.isNotEmpty;

  /// 填空共几轮。
  int get roundCount => _rounds.length;

  /// 第几轮（0 起）。
  int get roundIndex => _roundIndex;

  /// 当前轮的挖空；没有题时为 null。
  GoldenCloze? get round =>
      _roundIndex >= 0 && _roundIndex < _rounds.length
          ? _rounds[_roundIndex].cloze
          : null;

  /// 当前轮是否已经判过分。
  bool get roundScored => _roundScored;

  /// 当前轮逐空判定结果。
  List<bool> get roundResults => _roundResults;

  /// 当前轮是否全对。
  bool get roundOk => goldenFillAllCorrect(_roundResults);

  /// 拼句银行（打乱后的目标英文）；这句没有拼句时为 null。
  GoldenAssembly? get assembly => _assembly;

  /// 拼句已经点选的顺序。
  List<String> get order => _order;

  /// 拼句是否已判分 / 判定结果。
  bool get assembleScored => _assembleScored;
  bool get assembleOk => _assembleOk;

  /// 是否已经到小结阶段。
  bool get readyForSummary => _phase == GoldenDrillPhase.summary;

  /// 打开某一句：按课程设置建填空计划 + 拼句银行，全部从头开始。
  void open(String sentenceId) {
    final lesson = lessonOf();
    _sentenceId = sentenceId;
    _text = lesson == null ? '' : sentenceTextOf(sentenceId);
    _targets = lesson == null
        ? const <GoldenTarget>[]
        : goldenTargetsFor(lesson, sentenceId);
    final options = lesson?.options;
    _rounds = buildGoldenFillPlan(
      _text,
      _targets,
      GoldenFillPlanOptions(
        blankUnit: options?.blankUnit?.name ?? 'word',
        sentenceFill: options?.sentenceFill ?? true,
      ),
    );
    _roundIndex = 0;
    _roundScored = false;
    _roundResults = const <bool>[];
    _assembly = buildGoldenAssembly(_text, _targets);
    _order = const <String>[];
    _assembleScored = false;
    _assembleOk = false;
    _summaryRecorded = false;
    _phase =
        _rounds.isEmpty ? GoldenDrillPhase.assemble : GoldenDrillPhase.fill;
    notifyListeners();
  }

  /// 交这一轮的填空。
  ///
  /// **每次交卷都交给上层记账**：`recordGoldenStep` 用 tries 判断是不是第一次
  /// （只有第一次才写 `*First`），所以「重做不刷首次答对」由 core 负责；
  /// 这里自己吞掉的话，tries 永远停在 1，掌握口径就再也对不上。
  List<bool> submitFill(List<String> inputs) {
    final cloze = round;
    if (cloze == null) return const <bool>[];
    final results = checkGoldenFill(cloze, inputs);
    _roundResults = results;
    _roundScored = true;
    recordStep(_sentenceId, GoldenStep.fill, goldenFillAllCorrect(results));
    notifyListeners();
    return results;
  }

  /// 换到下一轮；已经是最后一轮就进拼句阶段。
  void nextRound() {
    if (_roundIndex + 1 < _rounds.length) {
      _roundIndex += 1;
      _roundScored = false;
      _roundResults = const <bool>[];
      notifyListeners();
      return;
    }
    _phase = GoldenDrillPhase.assemble;
    notifyListeners();
  }

  /// 重做这一轮（不清「首次答对」）。
  void retryRound() {
    _roundScored = false;
    _roundResults = const <bool>[];
    notifyListeners();
  }

  /// 拼句：点一个词块加进顺序表。
  void pick(String word) {
    if (_assembleScored) return;
    _order = <String>[..._order, word];
    notifyListeners();
  }

  /// 拼句：撤掉最后一个。
  void undo() {
    if (_assembleScored || _order.isEmpty) return;
    _order = _order.sublist(0, _order.length - 1);
    notifyListeners();
  }

  /// 拼句：清空重来。
  void clearOrder() {
    if (_assembleScored) return;
    _order = const <String>[];
    notifyListeners();
  }

  /// 交拼句。
  bool submitAssembly() {
    final ok = checkGoldenAssembly(_targets, _order);
    _assembleScored = true;
    _assembleOk = ok;
    if (ok) {
      recordStep(_sentenceId, GoldenStep.assemble, true);
      _phase = GoldenDrillPhase.summary;
    }
    notifyListeners();
    return ok;
  }

  /// 重新拼一次（拼对之后就不给再练了，避免反复刷）。
  void retryAssembly() {
    if (_assembleOk) return;
    _assembleScored = false;
    _order = const <String>[];
    notifyListeners();
  }

  /// 到小结；`summary` 这一步只记「看过」，重复进小结不再记账。
  void finish() {
    if (_sentenceId.isNotEmpty && !_summaryRecorded) {
      _summaryRecorded = true;
      recordStep(_sentenceId, GoldenStep.summary, true);
    }
    _phase = GoldenDrillPhase.summary;
    notifyListeners();
  }
}
