import '../../models/vocab.dart';
import 'word.dart';

/// 「选中文释义」的四个选项（纯函数）。
///
/// 以前这段写在视图里，但会话要知道「正确项是第几个」
/// （学习模式揭示答案时要给正确项上浅绿），规则就不能只活在视图层：
/// 两边各算一份，顺序迟早会不一致。
///
/// 选项顺序用**卡 id 做种子的稳定哈希**排：同一张卡每次出场顺序都一样，
/// 不会因为词库增删而跳来跳去（否则用户会以为"正确答案换了位置"）。
/// 与 Web 版 `src/core/vocab/meaningOptions.ts` 一一对应。

/// FNV-1a：够快、够散，同一字符串永远得同一个数。
///
/// 必须和 Web 版逐位一致（`Math.imul(h ^ c, 16777619) >>> 0`）：
/// 就是「异或后乘 16777619、只留低 32 位」。Dart 的 int 是 64 位，
/// 所以每次乘法后都要 `& 0xFFFFFFFF` 手动截断，否则高位会污染下一次异或。
/// 导出只为让测试拿 JS 侧的参考值对拍（`test/core/vocab/meaning_options_test.dart`）。
int optionHash(String s) {
  var h = 0x811C9DC5; // 2166136261
  for (var i = 0; i < s.length; i++) {
    h ^= s.codeUnitAt(i);
    h = (h * 0x01000193) & 0xFFFFFFFF; // 16777619
  }
  return h;
}

class MeaningOption {
  const MeaningOption({required this.text, required this.correct});

  final String text;
  final bool correct;
}

class _Keyed {
  const _Keyed(this.text, this.key);

  final String text;
  final int key;
}

String _meaningOf(VocabItem item) =>
    displayMeaning(partOfSpeech: item.partOfSpeech, meaning: item.meaning);

/// 正确释义 + 3 个来自其它词的释义（同义去重）。词库不足时返回空数组（调用方退回普通卡）。
List<MeaningOption> meaningOptions(VocabItem card, List<VocabItem> items) {
  final correct = _meaningOf(card);
  if (correct.isEmpty) return const [];
  final pool = <String>{};
  for (final it in items) {
    if (it.id == card.id) continue;
    final m = _meaningOf(it);
    if (m.isNotEmpty) pool.add(m);
  }
  pool.remove(correct);
  final picked = pool.map((m) => _Keyed(m, optionHash('${card.id}|$m'))).toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  final top = picked.take(3).map((x) => x.text).toList();
  if (top.length < 3) return const [];
  final all = [correct, ...top]
      .map((t) => _Keyed(t, optionHash('${card.id}#$t')))
      .toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  return [for (final x in all) MeaningOption(text: x.text, correct: x.text == correct)];
}

/// 正确项的下标；出不了题（词库不足）时是 -1。
int correctOptionIndex(VocabItem card, List<VocabItem> items) =>
    meaningOptions(card, items).indexWhere((o) => o.correct);
