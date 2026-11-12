/// 把选中的词加进某一篇（选词模式用）。
///
/// 为什么不复用 `ReaderViewModel.markCurrentWord`：精读页的 ViewModel 只认识
/// 它自己打开的那一篇，而速读页读的可能是另一篇。选词模式是跨页共用的，
/// 加词这件事只能按「当前这一篇的 id」来，不能按「阅读页当前那篇」来。
///
/// 冲突重试的逻辑照 `ReaderViewModel._applyAndSave`：重读后**重放同一次变换**，
/// 而不是拿旧结果去写，否则会把别人刚写的改动盖掉。
library;

import '../core/vocab/analysis.dart' show MarkInput, markWord;
import '../core/vocab/library.dart' show createLibrary;
import '../data/repositories/vocab_repository.dart';
import '../models/vocab.dart' show VocabOrigin;

/// 把 [words] 逐个收进 [articleId] 这一篇，返回真正新建的词条数。
///
/// 已有的词只会补上「这篇收过它」的关联，不会重复建词条 —— 所以老词重复点是安全的。
Future<int> addWordsToArticle({
  required VocabRepository repo,
  required String articleId,
  String? fileName,
  required List<String> words,
}) async {
  final clean = <String>[];
  for (final w in words) {
    final t = w.trim();
    if (t.isNotEmpty && !clean.contains(t)) clean.add(t);
  }
  if (clean.isEmpty) return 0;

  var base = await repo.load() ?? createLibrary();
  var updatedAt = (await repo.meta())?.at;
  for (var attempt = 0; attempt < 2; attempt++) {
    var library = base;
    final before = library.items.length;
    for (final word in clean) {
      library = markWord(
        library,
        MarkInput(
          word: word,
          articleId: articleId,
          fileName: fileName,
          origin: VocabOrigin.manual,
        ),
      ).library;
    }
    try {
      await repo.save(library, baseUpdatedAt: updatedAt);
      // 新建词条数 = 条数差；只补关联的老词不算。
      return library.items.length - before;
    } on VocabConflict {
      if (attempt == 1) rethrow;
      base = await repo.load() ?? createLibrary();
      updatedAt = (await repo.meta())?.at;
    }
  }
  return 0;
}
