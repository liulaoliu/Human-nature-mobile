/// 记忆 / 词块拷打结束后的「用学过的内容造句」。
///
/// 这里只做三件纯事：
///   1. 每个考到的词条各取一个能直接写进英文句子的内容（记忆 = 单词，词块 = 词组 / 习语 / 英文用法）；
///   2. 每个内容各拼一道 [ImitationTask]，让仿写那条批改链路原样复用；
///   3. 中文用法笔记不当 `mustUse`（「so-called 常带保留态度」没法写进英文句子）。
///
/// 为什么不是把所有词拼成一道题：不同词硬塞进同一句会变成「硬编」，
/// 每个内容独立一题才能真的练到「这个词怎么用」。
///
/// 对应 Web 版 `src/core/drillSentence.ts`（216 行）；那边每道题包成
/// `GoldenExamItem` 交给金句课，这里金句课还没移植，直接出 [ImitationTask]。
library;

import '../models/vocab.dart';
import 'lang_points.dart' show splitGlossText;
import 'quiz.dart';
import 'writing.dart' show ImitationTask, RubricItem;

/// 拷打种类：记忆（背单词）还是词块（搭配 / 习语）。
enum DrillSentenceKind { memory, chunk }

/// 一个造句点：必须用上的英文片段 + 中文提示。
class DrillSentencePoint {
  const DrillSentencePoint({
    required this.id,
    required this.itemId,
    required this.en,
    this.zh,
  });

  /// 同一轮里的稳定身份（词条 id + 英文片段）。
  final String id;
  final String itemId;

  /// 必须用上的英文片段。
  final String en;

  /// 中文提示：记忆拷打取词义，词块取「英文 — 中文」里的中文。
  final String? zh;
}

final RegExp _cjkRe = RegExp(r'[\u3400-\u9fff]');
final RegExp _hasLatinRe = RegExp(r'[a-z]', caseSensitive: false);

String _keyOf(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();

String _slugOf(String text) => _keyOf(text)
    .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
    .replaceAll(RegExp(r'^-+|-+$'), '');

String _pointId(DrillSentenceKind kind, String itemId, String en) =>
    'drill:${kind.name}:$itemId:${_slugOf(en).isEmpty ? 'x' : _slugOf(en)}';

/// 英文片段才配当 mustUse：中文说明、空串都跳过。
({String en, String? zh})? _usableChunk(String raw) {
  final (:word, :gloss) = splitGlossText(raw);
  final en = word.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (en.isEmpty || _cjkRe.hasMatch(en) || !_hasLatinRe.hasMatch(en)) {
    return null;
  }
  final zh = (gloss ?? '').trim();
  return (en: en, zh: zh.isEmpty ? null : zh);
}

/// 造句素材的取法（题面只出现这一个词 / 词块）。
class DrillSentenceOptions {
  const DrillSentenceOptions({this.limit, this.questions = const <QuizQuestion>[]});

  /// 默认不截断；只有测试 / 特殊入口才需要限制。
  final int? limit;

  /// 本轮题目。词块拷打时用它把 itemId 精确对到「这场考试实际考的那条词块」。
  ///
  /// 现状（2026-11-09 复查）：App 的背单词会话走的是释义四选一 + 拼写，
  /// 还没有「整卷 / 题型考试」那条链路，所以生产代码目前不传这个参数，
  /// [`testedChunk`] 恒返 null、只能退回「词条里第一条可用词块」。
  /// 参数与 `testedChunk` 一并保留（已翻自 Web 用例、有测试覆盖），
  /// 等 P6 之后接整卷考试时再由 `study_page` 的 `_openDrill` 传进来。
  final List<QuizQuestion> questions;
}

/// 由「本轮考到的词条」反推造句素材（题目是唯一事实来源）。
///
/// **一条判分结果 = 一个内容 = 一个点**：记忆拷打取单词 + 词义；
/// 词块拷打按 phrases / idioms / usage 的顺序取第一条没被用过的词块，
/// 一个都取不到时退回单词本身。同一词条考了多题只取第一次。
List<DrillSentencePoint> drillSentencePoints(
  List<VocabItem> items,
  List<({String? id, String itemId})> results,
  DrillSentenceKind kind, {
  DrillSentenceOptions options = const DrillSentenceOptions(),
}) {
  final byId = <String, VocabItem>{for (final it in items) it.id: it};
  final byQuestionId = <String, QuizQuestion>{
    for (final q in options.questions) q.id: q,
  };
  final seenItems = <String>{};
  final seenText = <String>{};
  final out = <DrillSentencePoint>[];
  final limit = options.limit;
  final max = limit == null ? -1 : (limit < 0 ? 0 : limit);
  if (max == 0) return out;

  /// 返回是否真的收下：重复文本会跳过，让词块继续试下一条。
  bool push(VocabItem item, String en, String? zh) {
    final key = _keyOf(en);
    if (key.isEmpty || seenText.contains(key)) return false;
    seenText.add(key);
    final z = (zh ?? '').trim();
    out.add(DrillSentencePoint(
      id: _pointId(kind, item.id, en),
      itemId: item.id,
      en: en,
      zh: z.isEmpty ? null : z,
    ));
    return true;
  }

  /// 词块题有完整 context 时，优先用这场考试实际考的那一条。
  ({String en, String? zh})? testedChunk(({String? id, String itemId}) row) {
    final qid = row.id;
    if (qid == null) return null;
    final question = byQuestionId[qid];
    if (question == null) return null;
    const kinds = <QuizKind>{
      QuizKind.usage,
      QuizKind.idiom,
      QuizKind.prep,
      QuizKind.collocation,
    };
    if (!kinds.contains(question.kind)) return null;
    // 搭配默写的 context 是「chunk1；chunk2…」，题目答案只取第一条。
    final raw = question.kind == QuizKind.collocation
        ? (question.context ?? '').split('；').first
        : (question.context ?? '');
    return raw.isEmpty ? null : _usableChunk(raw);
  }

  for (final row in results) {
    if (max > 0 && out.length >= max) break;
    if (!seenItems.add(row.itemId)) continue;
    final item = byId[row.itemId];
    if (item == null) continue;

    if (kind == DrillSentenceKind.memory) {
      final word = item.word.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (word.isNotEmpty) push(item, word, item.meaning);
      continue;
    }

    final exact = testedChunk(row);
    var picked = exact != null && push(item, exact.en, exact.zh);
    if (!picked) {
      final rawChunks = <String>[
        ...?item.phrases,
        ...?item.idioms,
        ...item.usage,
      ];
      for (final raw in rawChunks) {
        final chunk = _usableChunk(raw);
        if (chunk != null && push(item, chunk.en, chunk.zh)) {
          picked = true;
          break;
        }
      }
    }
    if (!picked) {
      final word = item.word.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (word.isNotEmpty && !_cjkRe.hasMatch(word)) {
        push(item, word, item.meaning);
      }
    }
  }

  return out;
}

/// 一轮的稳定身份：同一组内容（顺序无关）落在同一条历史里。
String drillSentenceId(DrillSentenceKind kind, List<DrillSentencePoint> points) {
  final signature = points.map((p) => _keyOf(p.en)).toList()..sort();
  final joined = signature.join('|');
  var h = 5381;
  for (var i = 0; i < joined.length; i++) {
    h = ((h << 5) + h + joined.codeUnitAt(i)) & 0xFFFFFFFF;
  }
  return 'drill:${kind.name}:${h.toRadixString(36)}';
}

/// 拷打种类的中文名。
String drillSentenceKindLabel(DrillSentenceKind kind) =>
    kind == DrillSentenceKind.chunk ? '词块拷打' : '记忆拷打';

/// 一个内容一道题：题面只出现这一个词 / 词块，不再要求把多个词硬塞进同一句。
ImitationTask buildDrillSentenceTask(
  DrillSentenceKind kind,
  DrillSentencePoint point,
) {
  final id = drillSentenceId(kind, <DrillSentencePoint>[point]);
  final label = drillSentenceKindLabel(kind);
  final unit = kind == DrillSentenceKind.chunk ? '词块' : '单词';
  final target = point.zh == null ? point.en : '${point.en}（${point.zh}）';
  final rubric = kind == DrillSentenceKind.chunk
      ? const <RubricItem>[
          RubricItem(
            dimension: '词块使用',
            weight: 50,
            description: '词块是否完整、搭配是否正确',
          ),
          RubricItem(
            dimension: '语法准确',
            weight: 30,
            description: '时态、单复数、冠词、介词等硬错',
          ),
          RubricItem(
            dimension: '自然与连贯',
            weight: 20,
            description: '句子是否像真实英语，而不是逐词拼凑',
          ),
        ]
      : const <RubricItem>[
          RubricItem(
            dimension: '词义与搭配',
            weight: 40,
            description: '词是否用在正确的词义和自然搭配上',
          ),
          RubricItem(
            dimension: '语法准确',
            weight: 30,
            description: '时态、单复数、冠词、介词等硬错',
          ),
          RubricItem(
            dimension: '自然与连贯',
            weight: 30,
            description: '句子是否像真实英语，而不是逐词拼凑',
          ),
        ];

  return ImitationTask(
    task: '用本轮$label考过的这个$unit写 1 句英文：$target。'
        '可以换主语或场景，不要照抄例句；这一题只练这一个$unit。',
    // 本轮没有「范句」可模仿：留空，批改提示词只写「要求用上」。
    model: '',
    mustUse: <String>[point.en],
    rubric: rubric,
    focus: id,
  );
}

/// 每个点各一道题；结算页按这个数组逐题切换。
List<ImitationTask> buildDrillSentenceTasks(
  DrillSentenceKind kind,
  List<DrillSentencePoint> points,
) =>
    <ImitationTask>[
      for (final p in points) buildDrillSentenceTask(kind, p),
    ];
