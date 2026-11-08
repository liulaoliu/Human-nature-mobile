/// 听力理解题的数据形状（纯数据，零逻辑）。
///
/// 出题提示词与判分在 `lib/core/listening.dart`；这里只放题本身，
/// 因为「错题本」也要存题目，不放这儿会让 mistakes 反向依赖 listening。
library;

/// 题型：单选 / 填空 / 简答。
enum ListeningQType { mcq, gap, short }

const Map<ListeningQType, String> listeningQTypeName = {
  ListeningQType.mcq: 'mcq',
  ListeningQType.gap: 'gap',
  ListeningQType.short: 'short',
};

ListeningQType? parseListeningQType(Object? raw) {
  for (final t in ListeningQType.values) {
    if (listeningQTypeName[t] == raw) return t;
  }
  return null;
}

/// 一道听力题。答案与解析都由 AI 给出，本地只判分。
class ListeningQuestion {
  const ListeningQuestion({
    required this.id,
    required this.type,
    required this.stem,
    required this.answer,
    this.options = const [],
    this.accept = const [],
    this.explanation,
  });

  final String id;
  final ListeningQType type;

  /// 题干；`gap` 题里用 `____` 表示空。
  final String stem;

  /// `mcq` 的选项（≥2）。
  final List<String> options;

  /// 标准答案（`mcq` = 选项原文；`gap`/`short` = 文本）。
  final String answer;

  /// 另外可接受的答案。
  final List<String> accept;

  /// 解析：为什么是这个答案、在原文哪里。
  final String? explanation;

  ListeningQuestion copyWith({
    String? id,
    ListeningQType? type,
    String? stem,
    List<String>? options,
    String? answer,
    List<String>? accept,
    String? Function()? explanation,
  }) =>
      ListeningQuestion(
        id: id ?? this.id,
        type: type ?? this.type,
        stem: stem ?? this.stem,
        options: options ?? this.options,
        answer: answer ?? this.answer,
        accept: accept ?? this.accept,
        explanation: explanation != null ? explanation() : this.explanation,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'type': listeningQTypeName[type],
        'stem': stem,
        if (options.isNotEmpty) 'options': options,
        'answer': answer,
        if (accept.isNotEmpty) 'accept': accept,
        if (explanation != null) 'explanation': explanation,
      };

  @override
  String toString() => 'ListeningQuestion($id, ${listeningQTypeName[type]}, "$stem")';
}

List<String> _strList(Object? raw) =>
    raw is List ? raw.whereType<String>().where((s) => s.isNotEmpty).toList() : const <String>[];

/// 宽容解析一道听力题（导入备份 / 读数据库时用）。
///
/// `id`/`type`/`stem`/`answer` 缺一不可；选择题的 `options` 少于 2 个也当坏题丢掉
/// （留着也没法答）。解析不了就返回 null，由调用方决定是丢整条还是置空。
ListeningQuestion? listeningQuestionFromJson(Object? raw) {
  if (raw is! Map) return null;
  final id = raw['id'];
  final stem = raw['stem'];
  final answer = raw['answer'];
  final type = parseListeningQType(raw['type']);
  if (id is! String || id.isEmpty || stem is! String || answer is! String || type == null) return null;
  final options = _strList(raw['options']);
  if (type == ListeningQType.mcq && options.length < 2) return null;
  final explanation = raw['explanation'];
  return ListeningQuestion(
    id: id,
    type: type,
    stem: stem,
    options: options,
    answer: answer,
    accept: _strList(raw['accept']),
    explanation: explanation is String && explanation.isNotEmpty ? explanation : null,
  );
}
