/// 备份 / 导入 JSON 的**运行时守卫**（纯函数）。
///
/// 为什么不在导入界面里做：导入是外部输入，`as` 强转挡不住坏文件；
/// 一条缺 `lemma` / `createdAt` 的词条就能让合并逻辑算出空键，甚至把现有词库弄坏。
///
/// 规矩（与 Web 版 `src/core/backupParse.ts` 一致）：
/// - 逐段检查，坏条目**丢弃并计数**，不因一条脏数据整份失败；
/// - 词库交给 [migrateLibrary] 洗（它本身就会丢弃修不出来的条目）；
/// - 学习记录交给 `normalizeLearning`；
/// - 返回 `dropped` / `errors`，界面必须能提示用户（不许静默变成空库）。
///
/// 兼容四种形态：完整备份对象 / `{schemaVersion:1, items:[]}` 词库 /
/// 文章数组 / 单篇文章。
library;

import '../models/document.dart';
import '../models/vocab.dart';
import 'article_origin.dart';
// `defaultReviewState` 两边都有（learning 是函数、vocab 是常量），这里只用 vocab 的。
import 'learning.dart' hide defaultReviewState;
import 'migrations.dart';

/// 解析结果。`articles` 与 `library` 只会是「结构能用的」数据。
class ParsedBackup {
  ParsedBackup({
    List<SavedArticle>? articles,
    this.library,
    this.readGoal,
    this.goalMemo,
    this.productionDraft,
    this.dropped = 0,
    List<String>? errors,
    LearningData? learning,
  })  : articles = articles ?? <SavedArticle>[],
        errors = errors ?? <String>[],
        learning = learning ?? emptyLearning();

  final List<SavedArticle> articles;

  /// 空词库 / 全坏 → null（**不许**用空词库覆盖现有数据）。
  final VocabLibrary? library;

  /// 每日阅读目标；不是有效数字就不带（保持原值不变）。
  final int? readGoal;

  /// 目标备忘录（纯展示，原样保留）。
  final String? goalMemo;

  /// 奶牛工棚会话草稿；外部输入，交给导入侧的草稿守卫再处理。
  final Object? productionDraft;

  /// 学习记录（已按段守卫）。空段就是空列表，不会把现有记录清掉——是否合并由调用方决定。
  final LearningData learning;

  /// 被丢弃的条目总数（坏数据 / 修不出来的）。
  final int dropped;

  /// 给人看的丢弃原因（去重后）。
  final List<String> errors;
}

bool _isObject(Object? v) => v is Map;

/// 句子最小形状：id 与 text 都是字符串。
bool _isSentence(Object? v) =>
    v is Map && v['id'] is String && v['text'] is String;

/// 文章最小形状：id 非空、updatedAt 是字符串、段落与句子都是数组、
/// 且每个句子都有 id + text。
///
/// 为什么这么松：老备份里 `title` / `text` / `createdAt` 可能没有，
/// 这些由 [_sanitizeArticle] 补默认值，不能因此把整篇丢掉。
bool _isArticle(Object? v) {
  if (v is! Map) return false;
  final id = v['id'];
  if (id is! String || id.trim().isEmpty) return false;
  if (v['updatedAt'] is! String) return false;
  if (v['paragraphs'] is! List) return false;
  final sentences = v['sentences'];
  if (sentences is! List) return false;
  return sentences.every(_isSentence);
}

/// 单篇还原（不含备份其余部分）。
///
/// 给「从库里读一篇文章」这条路用：库里存的就是同一份 payload 形状，
/// 读的时候必须过同一套守卫，不然仓储一升级就会把旧文章读成空壳。
/// 形状不对返回 null，**不抛异常**。
SavedArticle? parseSavedArticle(Object? raw) {
  if (!_isArticle(raw)) return null;
  return _sanitizeArticle(raw as Map);
}

/// 老文章可能没有 title / text / createdAt：补默认值，别整篇丢。
SavedArticle _sanitizeArticle(Map raw) {
  final sentences = <Sentence>[];
  for (final item in raw['sentences']! as List) {
    final s = _parseSentence(item);
    if (s != null) sentences.add(s);
  }
  final paragraphs = <Paragraph>[];
  for (final item in raw['paragraphs']! as List) {
    final p = _parseParagraph(item);
    if (p != null) paragraphs.add(p);
  }
  final title = raw['title'];
  final text = raw['text'];
  final sourceKey = raw['sourceKey'];
  final created = raw['createdAt'];
  final book = raw['book'];
  // 金句课内容：P5 移植小课堂时换成 normalizeGoldenLesson 的强类型守卫。
  // 现在只保证「是对象」，坏结构原样留在原始 JSON 里，不阻塞文章本身。
  final goldenRaw = raw['golden'];
  return SavedArticle(
    id: raw['id']! as String,
    title: title is String && title.trim().isNotEmpty ? title : '未命名',
    book: book is String ? book : null,
    sourceKey: sourceKey is String ? sourceKey : null,
    // 外部备份里的来源只接受白名单；坏值当未知，不整篇丢。
    origin: parseArticleOrigin(raw['origin']),
    text: text is String ? text : '',
    paragraphs: paragraphs,
    sentences: sentences,
    golden: goldenRaw is Map
        ? <String, Object?>{
            for (final e in goldenRaw.entries) '${e.key}': e.value,
          }
        : null,
    createdAt: created is String ? created : null,
    updatedAt: raw['updatedAt']! as String,
  );
}

Paragraph? _parseParagraph(Object? raw) {
  if (raw is! Map) return null;
  final id = raw['id'];
  if (id is! String || id.isEmpty) return null;
  return Paragraph(id: id, sentenceIds: _stringList(raw['sentenceIds']));
}

List<String> _stringList(Object? v) =>
    v is List ? v.whereType<String>().toList() : <String>[];

String? _strOrNull(Object? v) => v is String && v.isNotEmpty ? v : null;

double _num(Object? v, double fallback) => switch (v) {
      num n when n.isFinite => n.toDouble(),
      _ => fallback,
    };

/// 单句还原：只认形状对的字段；缺省用模型默认值。
Sentence? _parseSentence(Object? raw) {
  if (raw is! Map) return null;
  final id = raw['id'];
  final text = raw['text'];
  if (id is! String || text is! String) return null;
  final audioRaw = raw['audio'];
  final languagesRaw = raw['languages'];
  final languageRaw = raw['language'];
  return Sentence(
    id: id,
    paraId: raw['paraId'] is String ? raw['paraId']! as String : '',
    text: text,
    audio: audioRaw is Map
        ? AudioSegment(
            start: _num(audioRaw['start'], 0),
            end: _num(audioRaw['end'], 0),
          )
        : null,
    translation: _strOrNull(raw['translation']),
    grammarNote: _strOrNull(raw['grammarNote']),
    collocations: _stringList(raw['collocations']),
    vocab: _stringList(raw['vocab']),
    language: _parseLanguage(languageRaw),
    languages: languagesRaw is List
        ? languagesRaw.map(_parseLanguage).whereType<SentenceLanguage>().toList()
        : null,
    tags: _stringList(raw['tags']),
    reviewState: _parseReviewState(raw['reviewState']),
  );
}

SentenceLanguage? _parseLanguage(Object? raw) {
  if (raw is! Map) return null;
  List<String>? list(Object? v) => v is List ? v.whereType<String>().toList() : null;
  final source = raw['source'];
  return SentenceLanguage(
    structure: _strOrNull(raw['structure']),
    grammar: _strOrNull(raw['grammar']),
    idioms: list(raw['idioms']),
    phrases: list(raw['phrases']),
    usage: list(raw['usage']),
    source: source == 'ai'
        ? LanguageSource.ai
        : source == 'manual'
            ? LanguageSource.manual
            : null,
    at: _strOrNull(raw['at']),
  );
}

ReviewState _parseReviewState(Object? raw) {
  if (raw is! Map) return defaultReviewState;
  int intOf(Object? v) => v is num && v.isFinite ? v.toInt() : 0;
  final ease = raw['ease'];
  return ReviewState(
    ease: ease is num && ease.isFinite && ease > 0 ? ease.toDouble() : 2.5,
    due: _strOrNull(raw['due']),
    interval: intOf(raw['interval']),
    repetitions: intOf(raw['repetitions']),
    lapses: intOf(raw['lapses']),
    relearn: intOf(raw['relearn']),
    meaningPasses: intOf(raw['meaningPasses']),
  );
}

/// 解析导入的 JSON：兼容「全部备份」「词库 JSON」「文章数组」「单篇」。
///
/// 只返回结构能用的数据；`dropped > 0` 时调用方必须提示用户。
ParsedBackup parseBackupPayload(Object? data) {
  final articles = <SavedArticle>[];
  final errors = <String>[];
  var dropped = 0;
  void drop(String reason, [int n = 1]) {
    if (n <= 0) return;
    dropped += n;
    if (!errors.contains(reason)) errors.add(reason);
  }

  VocabLibrary? library;
  int? readGoal;
  String? goalMemo;
  Object? productionDraft;
  var learning = emptyLearning();

  /// 词库统一入口：空词库不导入，防止坏文件把现有词库清空。
  void takeLibrary(Object? rawLib) {
    final items = rawLib is Map ? rawLib['items'] : null;
    final before = items is List ? items.length : 0;
    final lib = migrateLibrary(rawLib);
    if (lib.items.isNotEmpty) {
      library = lib;
      drop('词条缺少必要字段', before - lib.items.length);
    } else {
      drop('词库为空或全部无效，已忽略', before > 0 ? before : 1);
    }
  }

  if (data is List) {
    if (data.isNotEmpty && _isObject(data.first)) {
      final first = data.first as Map;
      if (first.containsKey('sentences')) {
        for (final item in data) {
          if (_isArticle(item)) {
            articles.add(_sanitizeArticle(item as Map));
          } else {
            drop('文章结构不完整');
          }
        }
      } else if (first.containsKey('lemma')) {
        takeLibrary(<String, Object?>{'schemaVersion': 1, 'items': data});
      }
    }
    return ParsedBackup(
      articles: articles,
      library: library,
      dropped: dropped,
      errors: errors,
    );
  }

  if (data is! Map) {
    drop('不是对象也不是数组');
    return ParsedBackup(dropped: dropped, errors: errors);
  }

  // ── 文章 ──────────────────────────────────────────────────────────────
  final rawArticles = data['articles'];
  if (rawArticles is List) {
    for (final item in rawArticles) {
      if (_isArticle(item)) {
        articles.add(_sanitizeArticle(item as Map));
      } else {
        drop('文章结构不完整');
      }
    }
  } else if (data.containsKey('sentences') && data.containsKey('paragraphs')) {
    if (_isArticle(data)) {
      articles.add(_sanitizeArticle(data));
    } else {
      drop('文章结构不完整');
    }
  } else if (rawArticles != null) {
    drop('articles 不是数组');
  }

  // ── 词库：整库 / 只有 items ────────────────────────────────────────────
  final rawLib = data.containsKey('library') && data['library'] != null
      ? data['library']
      : (data['items'] is List ? data : null);
  if (rawLib != null) takeLibrary(rawLib);

  // ── 学习记录：老键名映射到 LearningData ────────────────────────────────
  //
  // Web 版把 `studyStats` / `stats` 这两个历史键名当成 studyDays / sessions，
  // 新数据只用新键名。两者都给时**新键名优先**。
  final learningRaw = <String, Object?>{
    for (final key in LearningSection.values)
      key.name: switch (key) {
        LearningSection.studyDays => data['studyDays'] ?? data['studyStats'],
        LearningSection.sessions => data['sessions'] ?? data['stats'],
        _ => data[key.name],
      },
  };
  final normalized = normalizeLearning(learningRaw);
  for (final key in LearningSection.values) {
    final raw = learningRaw[key.name];
    if (raw == null) continue;
    if (raw is! List && raw is! Map) {
      drop('${learningLabel[key]}格式不对');
      continue;
    }
    final valid = normalizeLearningSection(key, raw);
    if (key == LearningSection.kindStats) {
      final before = raw is Map ? raw.length : 0;
      final after = (valid is Map) ? valid.length : 0;
      drop('题型统计格式不对', before - after);
      continue;
    }
    final validLength = valid is List ? valid.length : 0;
    final rawLength = raw is List ? raw.length : 0;
    drop('${learningLabel[key]}含无效条目', rawLength - validLength);
  }
  learning = normalized;

  // ── 目标 / 草稿 ────────────────────────────────────────────────────────
  final rawGoal = data['readGoal'];
  if (rawGoal is num && rawGoal.isFinite && rawGoal >= 0) {
    readGoal = rawGoal.toInt();
  } else if (rawGoal != null) {
    drop('阅读目标不是有效数字');
  }
  final memo = data['goalMemo'];
  if (memo is String) goalMemo = memo;
  if (data.containsKey('productionDraft')) productionDraft = data['productionDraft'];

  return ParsedBackup(
    articles: articles,
    library: library,
    readGoal: readGoal,
    goalMemo: goalMemo,
    productionDraft: productionDraft,
    dropped: dropped,
    errors: errors,
    learning: learning,
  );
}
