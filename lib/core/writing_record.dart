/// 仿写批改的**记录层**：一条练习记录的身份、守卫、叫法、分页。
///
/// 从 Web 版 `src/core/writing.ts`（689 行）的 512 行之后拆出来，避免单个文件超 800 行。
library;

import 'activity/activity.dart' show dayKeyLocal;
import 'writing.dart' show ImitationTask, WritingFeedback;

/// 一次仿写练习的记录（存本机，供回看进步）。
class WritingRecord {
  const WritingRecord({
    required this.at,
    required this.articleId,
    required this.text,
    required this.feedback,
    this.articleTitle,
    this.model = '',
    this.task,
    this.source,
    this.examId,
    this.sentenceId,
    this.recordKey,
  });

  /// 提交时间（ISO 串）。
  final String at;
  final String articleId;
  final String? articleTitle;

  /// 范句原文（历史列表里显示用）。
  final String model;

  /// 学生作答。
  final String text;
  final WritingFeedback feedback;

  /// 当时的仿写任务（题目 + rubric），可能没有。
  final ImitationTask? task;

  /// 普通仿写缺省；金句课 / 奶牛工棚 / 拷打造句分开标记，历史可分流。
  final WritingSource? source;

  /// 金句课考试题 id（`source == goldenExam` 时）。
  final String? examId;

  /// 金句课单句 id（`source == goldenSentence` 时）。
  final String? sentenceId;

  /// 记录级稳定键：数据库自增 id 每次同步都会变（整段删了重插），
  /// 错因进度 / 复习卡不能拿它当身份。旧记录没有时用 [writingRecordKey] 现算。
  final String? recordKey;

  WritingRecord copyWith({
    String? at,
    String? articleId,
    String? Function()? articleTitle,
    String? model,
    String? text,
    WritingFeedback? feedback,
    ImitationTask? Function()? task,
    WritingSource? Function()? source,
    String? Function()? examId,
    String? Function()? sentenceId,
    String? Function()? recordKey,
  }) =>
      WritingRecord(
        at: at ?? this.at,
        articleId: articleId ?? this.articleId,
        articleTitle: articleTitle != null ? articleTitle() : this.articleTitle,
        model: model ?? this.model,
        text: text ?? this.text,
        feedback: feedback ?? this.feedback,
        task: task != null ? task() : this.task,
        source: source != null ? source() : this.source,
        examId: examId != null ? examId() : this.examId,
        sentenceId: sentenceId != null ? sentenceId() : this.sentenceId,
        recordKey: recordKey != null ? recordKey() : this.recordKey,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'at': at,
        'articleId': articleId,
        if (articleTitle != null) 'articleTitle': articleTitle,
        'model': model,
        'text': text,
        'feedback': feedback.toJson(),
        if (task != null) 'task': task!.toJson(),
        if (source != null) 'source': source!.id,
        if (examId != null) 'examId': examId,
        if (sentenceId != null) 'sentenceId': sentenceId,
        if (recordKey != null) 'recordKey': recordKey,
      };

  @override
  String toString() => 'WritingRecord($at, $articleId, ${source?.id ?? 'writing'})';
}

/// 一条批改记录的来源（历史列表分流用）。
enum WritingSource {
  writing('writing', '仿写'),
  goldenSentence('goldenSentence', '单句仿写'),
  goldenExam('goldenExam', '整课考试'),
  goldenError('goldenError', '错因订正'),
  production('production', '奶牛工棚'),
  drillSentence('drillSentence', '拷打造句');

  const WritingSource(this.id, this.label);

  /// 存库 / 备份里的稳定 id（与 Web 版一致）。
  final String id;

  /// 中文名。
  final String label;

  /// 按 id 反查；认不出返回 null（脏值当普通仿写，别把金句课历史带歪）。
  static WritingSource? byId(Object? raw) {
    if (raw is! String) return null;
    for (final s in WritingSource.values) {
      if (s.id == raw) return s;
    }
    return null;
  }
}

/// 一条批改记录的稳定身份（不依赖 DB 自增 id）。
String writingRecordKey({
  required String at,
  required String articleId,
  required String text,
  String? sentenceId,
  String? examId,
  ImitationTask? task,
}) {
  final focus = (task?.focus ?? '').trim();
  final round = task?.round ?? 1;
  final owner = sentenceId ?? examId ?? '';
  return <String>[
    at,
    articleId,
    owner,
    focus,
    '$round',
    _textFingerprint(text),
  ].join('|');
}

/// 「同一次尝试」的键：文章 + 句子/考试 + 题 focus + 稿数 + 作答文字。
///
/// 与 [writingRecordKey] 的区别：**不含 `at`**。`at` 是记录时刻，重复粘回同一份
/// 批改会拿到新的 `at`，用它去重等于没去重；真正重复的是「同一题、同一稿、同一段字」。
String writingAttemptKey(WritingRecord rec) => <String>[
      rec.articleId,
      rec.sentenceId ?? rec.examId ?? '',
      rec.task?.focus ?? '',
      '${rec.task?.round ?? 1}',
      rec.text.trim(),
    ].join('\u0000');

/// 列表里是否已有同来源、同一次尝试的记录（重复粘回批改不刷历史）。
bool hasSameWritingAttempt(List<WritingRecord> list, WritingRecord rec) {
  final key = writingAttemptKey(rec);
  for (final r in list) {
    if (r.source == rec.source && writingAttemptKey(r) == key) return true;
  }
  return false;
}

/// djb2 变体：`h = ((h << 5) + h + code)`，取无符号 36 进制。
String _textFingerprint(String text) {
  var h = 5381;
  for (var i = 0; i < text.length; i++) {
    h = ((h << 5) + h + text.codeUnitAt(i)) & 0xFFFFFFFF;
  }
  return h.toRadixString(36);
}

/// 金句课产生的记录（单句仿写 / 整课考试 / 错因订正），普通仿写历史不混入。
bool isGoldenWritingRecord(WritingRecord rec) =>
    rec.source == WritingSource.goldenExam ||
    rec.source == WritingSource.goldenSentence ||
    rec.source == WritingSource.goldenError;

String? _idOrNull(Object? v) => v is String && v.isNotEmpty ? v : null;

/// 一条批改记录的**外部数据守卫**（localStorage / 服务端 / 备份都可能带脏值）。
///
/// 只做两件事：来源按白名单（坏值当普通仿写，别让一条脏数据把金句课历史带歪），
/// 关联 id 必须是字符串（数字 / 对象一律丢掉）。服务端 `sqliteLearning` 写读两侧
/// 也是同一套白名单，两侧口径必须一致，否则「刷新前有、刷新后没」。
WritingRecord normalizeWritingRecord(WritingRecord rec) {
  final sentenceId = _idOrNull(rec.sentenceId);
  final examId = _idOrNull(rec.examId);
  final key = rec.recordKey;
  return WritingRecord(
    at: rec.at,
    articleId: rec.articleId,
    articleTitle: rec.articleTitle,
    model: rec.model,
    text: rec.text,
    feedback: rec.feedback,
    task: rec.task,
    source: WritingSource.byId(rec.source?.id),
    sentenceId: sentenceId,
    examId: examId,
    recordKey: key != null && key.isNotEmpty
        ? key
        : writingRecordKey(
            at: rec.at,
            articleId: rec.articleId,
            text: rec.text,
            sentenceId: sentenceId,
            examId: examId,
            task: rec.task,
          ),
  );
}

/// 一条批改记录叫什么（历史列表 / 导出 / 打印共用这一处口径）。
///
/// 金句课的「语言点造句」和「单句仿写」都属于 `source == goldenSentence`，
/// 靠 `task.focus` 区分：有 focus 就是只练一个词块的那道题。
String writingRecordLabel(WritingRecord rec) {
  final base = _baseLabel(rec);
  final round = rec.task?.round ?? 1;
  return round > 1 ? '$base（第 $round 稿）' : base;
}

String _baseLabel(WritingRecord rec) {
  final focus = (rec.task?.focus ?? '').trim();
  switch (rec.source) {
    case WritingSource.goldenError:
      return WritingSource.goldenError.label;
    case WritingSource.goldenExam:
      return WritingSource.goldenExam.label;
    case WritingSource.goldenSentence:
      return focus.isNotEmpty ? '语言点造句 · $focus' : WritingSource.goldenSentence.label;
    case WritingSource.production:
      return focus.isNotEmpty ? '奶牛工棚 · $focus' : WritingSource.production.label;
    case WritingSource.drillSentence:
      return WritingSource.drillSentence.label;
    case WritingSource.writing:
    case null:
      return WritingSource.writing.label;
  }
}

/// 仿写 / 语言点造句的历史：**存不截断，只分页显示**。
///
/// 这些记录是学习资产（AI 批改原文只有这一份），200 条时几篇文章就满了，旧记录会被静默截掉。
/// 所以落盘一条都不删；到 [writingHistoryWarnAt] 时提示导出归档，
/// 列表渲染用 [historyPage] 分页（一页 [writingHistoryPage] 条），避免一次画几千行。
const int writingHistoryWarnAt = 5000;

/// 学习历史一页显示多少条（只是渲染分页，数据一条都不丢）。
const int writingHistoryPage = 100;

/// 渲染分页：取前 `limit` 条，并告诉界面还剩几条没显示（纯函数）。
({List<T> rows, int rest, int next}) historyPage<T>(
  List<T> list,
  int shown, [
  int page = writingHistoryPage,
]) {
  final limit = shown > page ? shown : page;
  final rows = list.length <= limit ? list : list.sublist(0, limit);
  final rest = list.length - rows.length;
  return (rows: rows, rest: rest < 0 ? 0 : rest, next: limit + page);
}

/// 追加一条记录到最前，并按上限截断（纯函数）。默认不截断。
List<WritingRecord> addWritingRecord(
  List<WritingRecord> list,
  WritingRecord rec, {
  int? cap,
}) {
  final out = <WritingRecord>[rec, ...list];
  if (cap == null) return out;
  final limit = cap < 0 ? 0 : cap;
  return out.length <= limit ? out : out.sublist(0, limit);
}

/// 数某「逻辑日」写了几条（今日计划用）。`todayKey` 由 `core/activity.dart` 的
/// `dayKeyLocal` 算好传进来，这里不自己拼日期键；坏时间戳直接忽略。
int countWritesOnDay(List<WritingRecord> list, String todayKey) {
  var n = 0;
  for (final r in list) {
    final d = DateTime.tryParse(r.at);
    if (d == null) continue;
    // `at` 存的是 UTC ISO 串，`dayKeyLocal` 按本地日历日算，必须先转本地。
    if (dayKeyLocal(d.toLocal()) == todayKey) n++;
  }
  return n;
}

/// 一道题的历史批改：按题身份筛出来，按时间正序（最早在前，最后一条就是最新一稿）。
class WritingAttemptIdentity {
  const WritingAttemptIdentity({
    required this.articleId,
    this.sentenceId,
    this.examId,
    this.focus,
  });

  final String articleId;

  /// 单句仿写 / 语言点造句用句子 id。
  final String? sentenceId;

  /// 整课考试用题目 id。
  final String? examId;

  /// 语言点造句用 focus；普通仿写为空。
  final String? focus;
}

/// 取同一道题的全部历史批改（时间正序）。
List<WritingRecord> writingAttemptsFor(
  List<WritingRecord> list,
  WritingAttemptIdentity id,
) {
  final focus = (id.focus ?? '').trim();
  final out = list.where((r) {
    if (r.articleId != id.articleId) return false;
    final examId = id.examId;
    if (examId != null && examId.isNotEmpty) return (r.examId ?? '') == examId;
    if ((r.sentenceId ?? '') != (id.sentenceId ?? '')) return false;
    return (r.task?.focus ?? '').trim() == focus;
  }).toList()
    ..sort((a, b) => a.at.compareTo(b.at));
  return out;
}
