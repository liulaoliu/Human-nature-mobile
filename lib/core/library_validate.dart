import '../models/vocab.dart';
import 'entry_kind.dart';
import 'migrations.dart';

/// 词库**不变量校验**（纯函数）。
///
/// 为什么要有它：数据是唯一资产，但「结构对不对」以前只靠类型系统（运行时挡不住导入的 JSON、
/// 手改的库、老版本残留）。这里把不变量写成可执行断言，用在三处：
///   1. 单测：夹具库、迁移结果、找回工具产出的文件都必须过；
///   2. 迁移后自检：`migrateLibrary` 的结果不该有 error；
///   3. 排查数据问题时，一条命令看出问题在哪。
///
/// 级别：`error` = 结构坏了（我们的代码依赖它，必须修）；`warn` = 可疑但不致命。
///
/// 对应 Web 版 `src/core/libraryValidate.ts`（88 行）。
enum LibraryIssueLevel { error, warn }

class LibraryIssue {
  const LibraryIssue(this.level, this.message, {this.id});

  final LibraryIssueLevel level;

  /// 出问题的词条 id（库级问题为空）。
  final String? id;
  final String message;

  @override
  String toString() =>
      '${level == LibraryIssueLevel.error ? 'error' : 'warn'}${id != null ? ' [$id]' : ''}: $message';
}

final Set<String> _kindNames = kindOrder.map((k) => k.name).toSet();
const Set<String> _statusNames = {'unqueried', 'queried', 'edited', 'mastered'};

bool _isIso(String? s) => s != null && isoIsh.hasMatch(s) && DateTime.tryParse(s) != null;

void _checkItem(
  VocabItem it,
  Set<String> seenIds,
  Set<String> seenLemmas,
  List<LibraryIssue> out,
) {
  void push(LibraryIssueLevel level, String message) =>
      out.add(LibraryIssue(level, message, id: it.id));

  if (it.id.isEmpty) {
    push(LibraryIssueLevel.error, '缺少 id');
  } else if (!seenIds.add(it.id)) {
    push(LibraryIssueLevel.error, 'id 重复：${it.id}');
  }
  if (it.word.trim().isEmpty) push(LibraryIssueLevel.error, 'word 为空');
  if (it.lemma.trim().isEmpty) {
    push(LibraryIssueLevel.error, 'lemma 为空');
  } else if (!seenLemmas.add(it.lemma)) {
    push(LibraryIssueLevel.error, 'lemma 重复：${it.lemma}（去重没生效）');
  }
  final kind = it.kind;
  if (kind != null && !_kindNames.contains(kind.name)) {
    push(LibraryIssueLevel.error, 'kind 非法：${kind.name}');
  }
  if (!_statusNames.contains(it.status.name)) {
    push(LibraryIssueLevel.error, 'status 非法：${it.status.name}');
  }
  if (it.id.isNotEmpty && it.lemma.isNotEmpty && it.id != 'vocab:${it.lemma}') {
    push(LibraryIssueLevel.warn, 'id 与 lemma 不一致（改名后没同步？）');
  }
  if (it.examples.any((e) => e.text.trim().isEmpty)) {
    push(LibraryIssueLevel.warn, '有例句缺少 text');
  }
  final source = it.source;
  if (source != null && source.articleId.trim().isEmpty) {
    push(LibraryIssueLevel.warn, 'source.articleId 为空');
  }
  if ((it.contexts ?? const <VocabContext>[]).any((c) => c.articleId.trim().isEmpty)) {
    push(LibraryIssueLevel.warn, '有语境缺少 articleId');
  }
  if (!_isIso(it.createdAt)) {
    push(LibraryIssueLevel.error, 'createdAt 不是 ISO：${it.createdAt}');
  }
  if (!_isIso(it.updatedAt)) {
    push(LibraryIssueLevel.error, 'updatedAt 不是 ISO：${it.updatedAt}');
  }
  final due = it.reviewState.due;
  if (due != null && DateTime.tryParse(due) == null) {
    push(LibraryIssueLevel.warn, 'reviewState.due 不是 ISO：$due');
  }
}

/// 校验整个词库；返回所有问题（空数组 = 干净）。
List<LibraryIssue> validateLibrary(Object? library) {
  final out = <LibraryIssue>[];
  if (library is! VocabLibrary) {
    return const [LibraryIssue(LibraryIssueLevel.error, '词库不是对象')];
  }
  if (library.schemaVersion < 0) {
    out.add(const LibraryIssue(LibraryIssueLevel.error, 'schemaVersion 缺失'));
  }
  final seenIds = <String>{};
  final seenLemmas = <String>{};
  for (final it in library.items) {
    _checkItem(it, seenIds, seenLemmas, out);
  }
  final seen = <String>{};
  for (final e in library.articleEntries) {
    if (e.articleId.trim().isEmpty) {
      out.add(const LibraryIssue(LibraryIssueLevel.error, 'articleEntries 有条目缺 articleId'));
    }
    if (e.lemma.trim().isEmpty) {
      out.add(const LibraryIssue(LibraryIssueLevel.error, 'articleEntries 有条目缺 lemma'));
    } else if (!seenLemmas.contains(e.lemma)) {
      out.add(LibraryIssue(
        LibraryIssueLevel.error,
        'articleEntries 指向不存在的词：${e.lemma}',
      ));
    }
    if (!seen.add(e.key)) {
      out.add(LibraryIssue(
        LibraryIssueLevel.error,
        'articleEntries 重复：${e.articleId} / ${e.lemma}',
      ));
    }
    if (!_isIso(e.addedAt)) {
      out.add(const LibraryIssue(LibraryIssueLevel.error, 'articleEntries addedAt 不是 ISO'));
    }
  }
  return out;
}

/// 只要「致命问题」（测试里断言用）。
List<LibraryIssue> libraryErrors(Object? library) =>
    validateLibrary(library).where((i) => i.level == LibraryIssueLevel.error).toList();
