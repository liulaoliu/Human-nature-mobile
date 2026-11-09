/// 仿写训练的**草稿**：范句 / 我的仿写 / AI 给的任务 / 必须用上的词。
///
/// 这是本机会话状态，不进学习记录；真正的提交稿在写作历史里。
/// 刷新或退出再进来，写到一半的段落不该丢。
///
/// 对应 Web 版 `useWriting.ts` 里的 `reader:writingDraft`（那边直接存 JSON 到
/// localStorage，读回时用 `parseImitationTask` 重验 `task`；这里同一套口径）。
library;

import 'writing.dart' show ImitationTask;
import 'writing_json.dart' show imitationTaskFromJson;

/// 存草稿用的键（与 Web 版一致）。
const String writingDraftKeyName = 'reader:writingDraft';

/// 一组仿写草稿。
class WritingDraft {
  const WritingDraft({
    this.model = '',
    this.text = '',
    this.task,
    this.mustUse = const <String>[],
  });

  /// 范句（可改）。
  final String model;

  /// 我的仿写。
  final String text;

  /// AI 给的任务；还没生成时为 null。
  final ImitationTask? task;

  /// 必须用上的词块（可以手动加）。
  final List<String> mustUse;

  bool get isEmpty =>
      model.isEmpty && text.isEmpty && task == null && mustUse.isEmpty;

  WritingDraft copyWith({
    String? model,
    String? text,
    ImitationTask? Function()? task,
    List<String>? mustUse,
  }) =>
      WritingDraft(
        model: model ?? this.model,
        text: text ?? this.text,
        task: task != null ? task() : this.task,
        mustUse: mustUse ?? this.mustUse,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'model': model,
        'text': text,
        if (task != null) 'task': task!.toJson(),
        'mustUse': mustUse,
      };
}

/// 空草稿。
const WritingDraft emptyWritingDraft = WritingDraft();

String _asString(Object? v) => v is String ? v : '';

/// 从存库的 JSON 还原草稿；认不出就回空草稿（草稿丢了最多重写，不该让页面崩）。
///
/// `task` 一律过 [imitationTaskFromJson] 重验：手改过的 / 旧版本残留的形状不可信。
WritingDraft normalizeWritingDraft(Object? raw) {
  if (raw is! Map) return emptyWritingDraft;
  final mustUse = <String>[];
  final rawMust = raw['mustUse'];
  if (rawMust is List) {
    for (final e in rawMust) {
      final t = _asString(e).trim();
      if (t.isNotEmpty && !mustUse.contains(t)) mustUse.add(t);
    }
  }
  return WritingDraft(
    model: _asString(raw['model']),
    text: _asString(raw['text']),
    task: raw['task'] == null ? null : imitationTaskFromJson(raw['task']),
    mustUse: mustUse,
  );
}
