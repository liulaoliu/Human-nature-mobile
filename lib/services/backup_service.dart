/// 备份编排：导出整库 / 覆盖导入 / 合并导入。
///
/// 为什么在 `services/` 而不是 `core/`：它要读写三个仓储（文章、词库、学习记录），
/// core 不许碰 data。为什么不让界面直接做：三步落库有先后顺序（词库 → 文章 → 统计），
/// 任何一步失败都得告诉用户停在哪一步，散在界面里迟早写漏。
///
/// 与 Web 版 `src/reader/hooks/backupIO.ts` 的 `onImportBackup` / `onMergeBackup` 同口径：
///   - **覆盖导入**：整份替换。词库空 / 全坏时不覆盖（否则一份坏文件就把词库清空）。
///   - **合并导入**：词库互补（本机优先）、学习记录按段累加去重、文章按指纹去重保存。
///   - **同一份文件不重复合并**：先算 `backupFingerprint` 查导入账本。
///     指纹**必须**在词库落盘成功之后才记 —— 写库失败却记了指纹，用户重导同一份会被跳过。
///
/// 只收文本、只吐结果，不碰文件与分享：选文件 / 分享交给界面
/// （`file_picker` / `share_plus` 是平台能力，塞进来就没法用内存库测了）。
library;

import 'dart:convert';

import '../core/backup_parse.dart';
import '../core/golden_article.dart';
import '../core/golden_parse.dart';
import '../core/import_ledger.dart';
import '../core/merge_backup.dart';
import '../data/db/backup_export.dart';
import '../data/prefs_store.dart';
import '../data/repositories/article_repository.dart';
import '../data/repositories/learning_repository.dart';
import '../data/repositories/vocab_repository.dart';

/// 导出结果：JSON 文本 + 文件名 + 一句能念给用户的概况。
class BackupExportResult {
  const BackupExportResult({
    required this.json,
    required this.fileName,
    required this.articleCount,
    required this.vocabCount,
  });

  final String json;
  final String fileName;
  final int articleCount;
  final int vocabCount;

  String get summary => '文章 $articleCount 篇 · 生词 $vocabCount 个';
}

/// 导入结果。
///
/// [skipped] 为 true 表示这份文件以前合并过（按指纹判），什么都没动。
class BackupImportResult {
  const BackupImportResult({
    required this.articleCount,
    required this.vocabCount,
    required this.dropped,
    this.errors = const <String>[],
    this.skipped = false,
  });

  final int articleCount;
  final int vocabCount;

  /// 守卫丢掉的坏条目数（界面必须提示，不许静默变成空库）。
  final int dropped;
  final List<String> errors;

  /// 同一份文件已经合并过。
  final bool skipped;

  String get summary {
    if (skipped) return '这份文件已经合并过了，没有重复导入';
    final base = '文章 $articleCount 篇 · 生词 $vocabCount 个';
    if (dropped == 0) return base;
    return '$base · 跳过 $dropped 条坏数据';
  }
}

/// 备份编排。
class BackupService {
  BackupService({
    required ArticleRepository articles,
    required VocabRepository vocab,
    required LearningRepository learning,
    PrefsStore? prefsStore,
  })  : _articlesRepo = articles,
        _vocabRepo = vocab,
        _learningRepo = learning,
        _store = prefsStore ?? PrefsStore.memory();

  final ArticleRepository _articlesRepo;
  final VocabRepository _vocabRepo;
  final LearningRepository _learningRepo;
  final PrefsStore _store;

  /// 把整库打成一份能换电脑用的 JSON。
  ///
  /// `readGoal` / `goalMemo` 目前 App 里没有存储侧（还没有「每日目标」界面），
  /// 所以不写 —— 与 Web 版导出的差值就只有这两个可选键。
  Future<BackupExportResult> exportAll({DateTime? now}) async {
    final at = now ?? DateTime.now();
    final library = await _vocabRepo.load();
    final articles = await _articlesRepo.loadAll();
    final learning = await _learningRepo.load();

    final payload = backupPayload(
      library: library,
      articles: articles,
      learning: learning,
      exportedAt: at.toUtc().toIso8601String(),
    );

    return BackupExportResult(
      json: encodeBackupJson(payload),
      fileName: backupFileName(_dayKey(at)),
      articleCount: articles.length,
      vocabCount: library?.items.length ?? 0,
    );
  }

  /// 解析一份备份文本。
  ///
  /// 抛 [FormatException] 表示根本不是 JSON；结构不对不抛，交给守卫计数。
  ParsedBackup parse(String text) {
    final decoded = jsonDecode(text);
    return parseBackupPayload(decoded);
  }

  /// 覆盖导入：整份替换。
  ///
  /// 词库为 null（空 / 全坏）时不覆盖现有词库；备份里根本没有学习记录键时
  /// 也不清空现有统计 —— 「没写」不等于「要清空」。
  Future<BackupImportResult> replace(String text) async {
    final decoded = jsonDecode(text);
    final parsed = parseBackupPayload(decoded);

    final library = parsed.library;
    if (library != null) {
      await _vocabRepo.save(library);
    }

    for (final article in parsed.articles) {
      await _articlesRepo.save(article);
    }

    if (_hasLearningKeys(decoded)) {
      await _learningRepo.writeAll(parsed.learning);
    }

    return BackupImportResult(
      articleCount: parsed.articles.length,
      vocabCount: library?.items.length ?? 0,
      dropped: parsed.dropped,
      errors: parsed.errors,
    );
  }

  /// 合并导入：词库互补、记录累加、同一份文件只合并一次。
  Future<BackupImportResult> merge(String text) async {
    final fingerprint = backupFingerprint(text);
    final ledger = _store.loadImportedBackups();
    if (hasImported(ledger, fingerprint)) {
      return const BackupImportResult(
        articleCount: 0,
        vocabCount: 0,
        dropped: 0,
        skipped: true,
      );
    }

    final decoded = jsonDecode(text);
    final parsed = parseBackupPayload(decoded);

    // ① 词库：先合并落盘。这一步失败不能记账（下面才 rememberImport）。
    final incomingLibrary = parsed.library;
    if (incomingLibrary != null) {
      final current = await _vocabRepo.load();
      final merged = current == null
          ? incomingLibrary
          : mergeLibraries(current, incomingLibrary);
      await _vocabRepo.save(merged);
    }

    // ② 文章：逐篇保存，金句课两边取并集（旧备份没 golden 就保留现有的）。
    for (final incoming in parsed.articles) {
      final existing = await _articlesRepo.load(incoming.id);
      final golden = mergeGoldenIntoArticle(
        existing: existing == null ? null : goldenLessonOf(existing),
        incoming: goldenLessonOf(incoming),
        existingUpdatedAt: existing?.updatedAt ?? '',
        incomingUpdatedAt: incoming.updatedAt,
      );
      await _articlesRepo.save(withGoldenLesson(incoming, golden));
    }

    // ③ 学习记录：16 段各自去重 / 累加。
    final current = await _learningRepo.load();
    final mergedLearning = mergeLearningData(current, parsed.learning);
    await _learningRepo.writeAll(mergedLearning);

    await _store.saveImportedBackups(rememberImport(ledger, fingerprint));

    return BackupImportResult(
      articleCount: parsed.articles.length,
      vocabCount: incomingLibrary?.items.length ?? 0,
      dropped: parsed.dropped,
      errors: parsed.errors,
    );
  }
}

/// 备份里有没有任何一段学习记录（键名沿用历史名，见 `backupLearningKeys`）。
///
/// 只看「有没有这个键」，不看内容空不空：整份覆盖导入时键在就是要按备份走，
/// 键不在才说明这份文件没带学习记录（比如只导一个词库）。
bool _hasLearningKeys(Object? decoded) {
  if (decoded is! Map) return false;
  final data = decoded['data'];
  final root = data is Map ? data : decoded;
  for (final key in backupLearningKeys.values) {
    if (root.containsKey(key)) return true;
  }
  return false;
}

String _dayKey(DateTime at) {
  final local = at.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '${local.year}-$month-$day';
}
