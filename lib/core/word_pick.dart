/// 选词模式：用户点了哪些词（精读与速读共用）。
///
/// 为什么单独一个 core 文件：Web 版 `useVocabMode` + `useSpeedReadWords` 干的是同一件事 ——
/// 「在一次阅读里点一堆词，攒够了再一起加进生词本」。手机上没有鼠标划词，
/// 只能一个词一个词点，所以「选中集合 + 合成词组 + 会话统计」必须是一份纯逻辑，
/// 精读和速读各自只负责渲染。
///
/// 零 IO、零状态：输入是点到的位置，输出是选中集合与最终要入的词。
library;

import '../models/vocab.dart' show VocabItemKind;

/// 一条要入词库的东西：单个词，或同句相邻几个词拼成的词组。
class PickEntry {
  const PickEntry({
    required this.sentenceId,
    required this.word,
    required this.count,
    this.kind,
  });

  /// 来自哪一句。
  final String sentenceId;

  /// 合成后的词面（一个词时就是原词，多个词用空格连）。
  final String word;

  /// 覆盖了几个词：1 = 单词，>1 = 词组。
  final int count;

  /// 单词不标类型（null）；多个词合成时标 [VocabItemKind.phrase]。
  final VocabItemKind? kind;

  bool get isPhrase => count > 1;

  @override
  String toString() => 'PickEntry($sentenceId, $word ×$count)';
}

/// 词在正文里的位置：哪一句、该句第几个词。
///
/// 用「句子 id + 词序号」而不是词本身做身份：同一句里 `the` 出现三次，
/// 用户只想收其中一个位置的语境时不能混在一起（Web 的 `selIdx` 也是这个口径）。
class PickTarget {
  const PickTarget({
    required this.sentenceId,
    required this.index,
    required this.word,
  });

  /// 句子 id（`Sentence.id`）。
  final String sentenceId;

  /// 该句 `wordSpans` / `mergeHyphenated` 结果里的下标。
  final int index;

  /// 词面（原文大小写，入词库时再统一 normalize）。
  final String word;

  /// 去重键。
  String get key => '$sentenceId\u0000$index';

  @override
  bool operator ==(Object other) =>
      other is PickTarget &&
      other.sentenceId == sentenceId &&
      other.index == index;

  @override
  int get hashCode => Object.hash(sentenceId, index);

  @override
  String toString() => 'PickTarget($sentenceId#$index, $word)';
}

/// 一次选词会话的选中集合。
///
/// 不可变：每次 toggle 返回新对象，方便 `ChangeNotifier` 直接比 `identical`。
class PickState {
  const PickState({this.targets = const <PickTarget>[]});

  /// 按点选顺序排列、已去重。
  final List<PickTarget> targets;

  bool get isEmpty => targets.isEmpty;
  bool get isNotEmpty => targets.isNotEmpty;
  int get length => targets.length;

  /// 这个位置选中了没有。
  bool contains(String sentenceId, int index) =>
      targets.any((t) => t.sentenceId == sentenceId && t.index == index);

  /// 点一下：选中就取消，没选就加进来。
  PickState toggle(PickTarget t) {
    if (contains(t.sentenceId, t.index)) {
      return PickState(
        targets: [
          for (final x in targets)
            if (x.sentenceId != t.sentenceId || x.index != t.index) x,
        ],
      );
    }
    return PickState(targets: [...targets, t]);
  }

  /// 单选：只留这一个（多选关掉时点词走这里）。
  ///
  /// 单选模式的意义是「我这一下只想要一个词」：不能让之前点的留在集合里，
  /// 否则用户永远分不清这次到底加进去几个。
  PickState selectOnly(PickTarget t) => PickState(targets: [t]);

  /// 清空（换文章、加入生词本之后都要清）。
  PickState clear() => const PickState();

  /// 按句子分组，句内按词序排好 —— 合成词组要按原文顺序连。
  Map<String, List<PickTarget>> get bySentence {
    final map = <String, List<PickTarget>>{};
    for (final t in targets) {
      map.putIfAbsent(t.sentenceId, () => <PickTarget>[]).add(t);
    }
    for (final list in map.values) {
      list.sort((a, b) => a.index.compareTo(b.index));
    }
    return map;
  }

  /// 最终要入词库的条目：单词 / 词组各带类型。
  ///
  /// 1 个词 → 单词（kind 为 null，与 Web 一致：单词不标类型）；
  /// 同句连续 ≥2 个词 → 拼成一条 [VocabItemKind.phrase]。
  List<PickEntry> get entries => [
        for (final run in _runs)
          PickEntry(
            sentenceId: run.sentenceId,
            word: run.phrase,
            count: run.count,
            kind: run.count > 1 ? VocabItemKind.phrase : null,
          ),
      ];

  /// 合成后的每条词组（只要词面，老调用方用）。
  List<({String sentenceId, String phrase})> get phrases => [
        for (final e in entries) (sentenceId: e.sentenceId, phrase: e.word),
      ];

  /// 同句里连续选中的词，按句分组、句内按词序。
  ///
  /// 不连续的词分属不同词条：`in` 和 `terms` 中间隔着没选的 `of`，
  /// 合成 `in terms` 是错的，得让用户自己再点一次补齐。
  List<({String sentenceId, String phrase, int count})> get _runs {
    final out = <({String sentenceId, String phrase, int count})>[];
    for (final entry in bySentence.entries) {
      final list = entry.value;
      if (list.isEmpty) continue;
      var run = <PickTarget>[list.first];
      for (var i = 1; i < list.length; i++) {
        final prev = list[i - 1];
        final cur = list[i];
        if (cur.index == prev.index + 1) {
          run.add(cur);
        } else {
          out.add((
            sentenceId: entry.key,
            phrase: _join(run),
            count: run.length,
          ));
          run = <PickTarget>[cur];
        }
      }
      out.add((
        sentenceId: entry.key,
        phrase: _join(run),
        count: run.length,
      ));
    }
    return out;
  }

  /// 该句里所有选中词的词面（单词语气，给「加入」用）。
  List<String> wordsOf(String sentenceId) => [
        for (final t in bySentence[sentenceId] ?? const <PickTarget>[]) t.word,
      ];

  static String _join(List<PickTarget> run) =>
      run.map((t) => t.word).join(' ');

  @override
  String toString() => 'PickState(${targets.length} 个)';
}
