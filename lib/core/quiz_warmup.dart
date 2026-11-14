/// 拷打前「先看一遍」的预习卡（对应 Web `src/core/quizWarmup.ts`）。
///
/// 记忆拷打 / 词块拷打是**闭卷回忆**：直接开考，第一次见到的词只能靠猜，
/// 猜错还会记进错题本 —— 等于把「没见过」当成「没记住」。所以开考前先把
/// 这轮要考的词连同释义 / 词块摊开看一遍。
///
/// 题目是唯一事实来源：由这一轮的题目反查词条，不另写一遍筛选规则。
/// 纯函数、零 IO、不碰界面（core 层 R1）。
library;

import '../models/vocab.dart';
import 'quiz.dart';
import 'quiz_drill.dart' show QuizDrillKind;

/// 一张预习卡。
class DrillWarmupCard {
  const DrillWarmupCard({
    required this.id,
    required this.word,
    this.phonetic,
    this.meaning,
    this.chunks = const <String>[],
    this.example,
  });

  /// 词条 id（同时作列表 key）。
  final String id;

  /// 单词本身。
  final String word;

  /// 音标。
  final String? phonetic;

  /// 中文释义。
  final String? meaning;

  /// 词块拷打要看的：词组 / 习语 / 用法（最多 6 条，去空）。
  final List<String> chunks;

  /// 记忆拷打给一条例句当语境。
  final String? example;
}

/// 由这一轮的题目反推「会考到哪些词」，取词条内容做成预习卡。
///
/// [kind] 是 [QuizDrillKind.memory] 或 [QuizDrillKind.chunk]：
///   - chunk：摊开词组 / 习语 / 用法，方便先认一遍搭配；
///   - memory：给一条非空例句当语境。
/// 其它档位不进预习页（Web 也只有这两档有），传进来按 memory 处理。
List<DrillWarmupCard> buildWarmupCards(
  List<VocabItem> items,
  List<QuizQuestion> questions,
  QuizDrillKind kind,
) {
  final byId = <String, VocabItem>{for (final it in items) it.id: it};
  final seen = <String>{};
  final cards = <DrillWarmupCard>[];
  final isChunk = kind == QuizDrillKind.chunk;

  for (final q in questions) {
    if (!seen.add(q.itemId)) continue;
    final it = byId[q.itemId];
    if (it == null) continue; // 文章级题的 itemId 是句子 id，查不到词条就跳过。

    final chunks = isChunk
        ? <String>[
              ...(it.phrases ?? const <String>[]),
              ...(it.idioms ?? const <String>[]),
              ...it.usage,
            ].where((s) => s.trim().isNotEmpty).take(6).toList(growable: false)
        : const <String>[];

    String? example;
    if (!isChunk) {
      for (final e in it.examples) {
        if (e.text.trim().isNotEmpty) {
          example = e.text;
          break;
        }
      }
    }

    cards.add(DrillWarmupCard(
      id: it.id,
      word: it.word,
      phonetic: it.phonetic,
      meaning: it.meaning,
      chunks: chunks,
      example: example,
    ));
  }
  return cards;
}

/// 预习页标题（照 Web `useDrillWarmup.showWarmup` 的口径）。
String warmupTitle(QuizDrillKind kind) => kind == QuizDrillKind.chunk
    ? '词块拷打 · 先看一遍'
    : '记忆拷打 · 先看一遍';

/// 预习页提示（照 Web `DrillWarmup.tsx` 的 hint）。
String warmupHint(QuizDrillKind kind) => kind == QuizDrillKind.chunk
    ? '先认一遍词块（词组 / 习语）再开考 —— 不认识的搭配，考出来只是猜。'
    : '先认一遍词和释义再开考 —— 第一次见的词答错，不算没记住。';
