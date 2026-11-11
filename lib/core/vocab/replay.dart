import '../../models/vocab.dart';

/// 冲突重放：把「这次改了什么」挑出来，重新盖到刚读回来的那份词库上。
///
/// 场景：背上半小时里精读页也可能在标词，写盘时 `baseUpdatedAt` 对不上就会
/// 撞 `VocabConflict`。这时不能直接覆盖（会丢别人的改动），也不能整份重读后
/// 再判一次分（判分是交互式的，重放不了）。做法是：算出差集 → 重读 → 只把
/// 差集里那几个词盖上去。
///
/// 两个函数都是纯的：库进 → 库出，不改入参。

/// 这次改动碰到的词条 id（按内容差异算，不看对象引用）。
///
/// `VocabItem` 没有重载 `==`，只能挑能代表「判过一次分」的字段比：复习状态
/// （有 `==`）、标签（拼错会加「不认识」）、更新时间。
Set<String> touchedIds(VocabLibrary before, VocabLibrary after) {
  final prev = {for (final it in before.items) it.id: it};
  final out = <String>{};
  for (final it in after.items) {
    final old = prev[it.id];
    if (old == null ||
        old.reviewState != it.reviewState ||
        old.tags.join('\u0000') != it.tags.join('\u0000')) {
      out.add(it.id);
    }
  }
  return out;
}

/// 把 [patched] 里 [ids] 那几个词条覆盖到 [base] 上（顺序跟 [base] 走）。
///
/// [base] 是刚从库里读回来的最新一份，[patched] 是本地攒的那份。
/// 只在 [patched] 里出现的 id 追加到末尾。
VocabLibrary replayPatched(
  VocabLibrary base,
  VocabLibrary patched,
  Set<String> ids,
) {
  final source = {for (final it in patched.items) it.id: it};
  final known = {for (final it in base.items) it.id};
  return base.copyWith(
    items: [
      for (final it in base.items)
        if (ids.contains(it.id)) (source[it.id] ?? it) else it,
      for (final it in patched.items)
        if (ids.contains(it.id) && !known.contains(it.id)) it,
    ],
  );
}
