/// 「强制锤炼」面板的状态机（纯逻辑，零 IO、零 Flutter）。
///
/// 三步走：拼写 → 选义 → 写搭配，缺哪步跳哪步。过完才解锁评分（`drill.cleared`）。
///
/// 与 Web 版 `src/reader/panels/StudyDrill.tsx` 一一对应。为什么单独一个文件：
/// 面板里有「拼错只判一次、错了直接判不认识」这种时序规则，留在 widget 里就只能
/// 靠点界面验证；这里全是纯数据，可以直接断言。
library;

import '../../models/vocab.dart';
import 'drill.dart';
import 'drill_step.dart';
import 'meaning_options.dart';
import 'spelling.dart';

/// 一次提交的结果。
enum DrillVerdict {
  /// 这一步过了，进下一步（或整块过完）。
  passed,

  /// 拼写错了：这一步只判一次，错了就整块结束并判「不认识」。
  spellMiss,

  /// 还没对（选义选错 / 搭配没写对），停在这一步重来。
  retry,
}

/// 锤炼面板。
class StudyDrill {
  StudyDrill({
    required this.reason,
    required VocabItem card,
    required List<VocabItem> items,
  })  : _card = card,
        steps = buildDrillSteps(card, items),
        _options = meaningOptions(card, items);

  final DrillReason reason;

  /// 要过的步骤（构造时按卡片内容定，之后不变）。
  final List<DrillStep> steps;

  final VocabItem _card;
  final List<MeaningOption> _options;

  int _stepIndex = 0;
  String _typed = '';
  int? _picked;
  bool _wrongPick = false;
  bool _usageOk = false;
  bool _spellMiss = false;

  /// 当前第几步（越界 = 全过完了）。
  int get stepIndex => _stepIndex;

  /// 当前这一步；全过完了是 null。
  DrillStep? get step => _stepIndex < steps.length ? steps[_stepIndex] : null;

  /// 全过完了（评分解锁）。
  bool get cleared => _stepIndex >= steps.length;

  /// 拼写拼错过（外面据此判「不认识」并结束这一轮锤炼）。
  bool get spellMiss => _spellMiss;

  /// 标题与说明（按来路换措辞）。
  DrillHead get head => drillHeadOf(reason);

  /// 当前卡片。
  VocabItem get card => _card;

  /// 选义那一步的四个选项（没到那一步也给，界面要预先布局）。
  List<MeaningOption> get options => _options;

  /// 拼写输入。
  String get typed => _typed;

  /// 选义选中的下标；没选是 null。
  int? get picked => _picked;

  /// 刚选错（界面标红，等用户再选）。
  bool get wrongPick => _wrongPick;

  /// 搭配写对了（界面给绿勾）。
  bool get usageOk => _usageOk;

  /// 这一步的题面（拼写 / 选义 / 搭配）。
  String get prompt => switch (step) {
        DrillStep.spell => '把这个词拼出来',
        DrillStep.meaning => '选出它在这里的意思',
        DrillStep.usage => '用它写个搭配（写出任意一条用法即可）',
        null => '',
      };

  /// 拼写输入（受控输入框）。
  void setTyped(String value) {
    _typed = value;
  }

  /// 提交拼写：对 = 进下一步；错 = 整块结束并记 [spellMiss]。
  ///
  /// 只判一次：拼错不再给第二次机会（SRS 那边直接判「不认识」），这是产品口径
  /// ——拼写是「能不能写出来」的硬门槛，重试就失去意义。
  DrillVerdict submitSpell(String input) {
    if (step != DrillStep.spell) return DrillVerdict.retry;
    if (_spellMiss) return DrillVerdict.retry;
    if (spellingMatches(input, _card.word)) {
      _advance();
      return DrillVerdict.passed;
    }
    _spellMiss = true;
    _typed = input;
    return DrillVerdict.spellMiss;
  }

  /// 选义：对 = 进下一步；错 = 停在原地标红。
  DrillVerdict pickMeaning(int index) {
    if (step != DrillStep.meaning) return DrillVerdict.retry;
    if (index < 0 || index >= _options.length) return DrillVerdict.retry;
    _picked = index;
    if (_options[index].correct) {
      _wrongPick = false;
      _advance();
      return DrillVerdict.passed;
    }
    _wrongPick = true;
    return DrillVerdict.retry;
  }

  /// 写搭配：包含任意一条用法/词组就算过。
  DrillVerdict submitUsage(String input) {
    if (step != DrillStep.usage) return DrillVerdict.retry;
    if (matchesCollocation(input, collocationsOf(_card))) {
      _usageOk = true;
      _advance();
      return DrillVerdict.passed;
    }
    return DrillVerdict.retry;
  }

  void _advance() {
    _stepIndex += 1;
    _typed = '';
    _picked = null;
    _wrongPick = false;
  }
}
