/// 精读页的 ViewModel：文章列表 + 当前文章 + 选词入库 + 本篇词表。
///
/// 分工（对应 `docs/ARCHITECTURE.md`）：
///   - 数据从仓储来（`ArticleRepository` / `VocabRepository`）；
///   - 判定与写入规则全在 `lib/core/`（`analysis.markWord`、`article_vocab`），
///     这里只做「读出来 → 调纯函数 → 存回去 → 通知界面」；
///   - 界面不自己算本篇词表，一律用 [currentEntries]。
library;

import 'package:flutter/foundation.dart';

import '../core/analyzer_parse.dart' show applyToSentence;
import '../core/analyzer_shared.dart' show AnalysisTask;
import '../core/article_vocab.dart';
import '../core/language.dart' show applyLanguage, parseLanguage;
import '../core/reader_view.dart';
import '../core/vocab/analysis.dart' as analysis;
import '../core/vocab/library.dart';
import '../core/vocab/word.dart' show lemmaOf;
import '../data/repositories/article_repository.dart';
import '../data/repositories/vocab_repository.dart';
import '../models/document.dart';
import '../models/vocab.dart';
import '../services/article_import_service.dart';

/// 一篇文章读写的全部状态。
class ReaderViewModel extends ChangeNotifier {
  ReaderViewModel({
    required ArticleRepository articlesRepo,
    required VocabRepository vocabRepo,
    required ArticleImportService importsService,
  })  : _articles = articlesRepo,
        _vocab = vocabRepo,
        _imports = importsService;

  final ArticleRepository _articles;
  final VocabRepository _vocab;
  final ArticleImportService _imports;

  List<ArticleRow> _list = const [];
  SavedArticle? _current;
  VocabLibrary _library = createLibrary();
  String? _libraryUpdatedAt;
  bool _busy = false;
  String? _error;
  String? _selectedSentenceId;
  ReaderViewFlagsInput _flags = const ReaderViewFlagsInput();

  /// 文章列表（按更新时间倒序，仓储保证）。
  List<ArticleRow> get articles => _list;

  /// 当前正在读的文章；没打开时为 null。
  SavedArticle? get current => _current;

  /// 全库词条（只读快照；写入一律经 [markCurrentWord]）。
  VocabLibrary get library => _library;

  /// 正在忙（加载 / 存盘），界面据此禁按钮。
  bool get busy => _busy;

  /// 上一次操作的错误提示；成功一次就清空。
  String? get error => _error;

  /// 当前选中的句子（长按选中整句用）；没有则 null。
  String? get selectedSentenceId => _selectedSentenceId;

  /// 阅读页当前开着的面板。
  ReaderViewFlagsInput get flags => _flags;

  /// 正文 / 工具栏的显示判定 —— 界面直接用它，不要再自己拼布尔。
  ReaderViewFlags get viewFlags => readerViewFlags(_flags);

  /// 本篇要显示的词条（按收录顺序，已去重、跳过已掌握）。
  List<ArticleEntryView> get currentEntries {
    final article = _current;
    if (article == null) return const [];
    return articleEntryViews(_library, article.id);
  }

  /// 本篇所有语言点（含词组 / 习语 / 用法；侧栏「语言点」用）。
  List<ArticleEntryView> get currentLangPoints {
    final article = _current;
    if (article == null) return const [];
    return articleEntryViews(_library, article.id, includeLang: true);
  }

  /// 载入词库（进入精读页时调一次）。
  Future<void> loadLibrary() async {
    await _guard(() async {
      final loaded = await _vocab.load();
      _library = loaded ?? createLibrary();
      final meta = await _vocab.meta();
      _libraryUpdatedAt = meta?.at;
    });
  }

  /// 载入文章列表。
  Future<void> loadArticles() async {
    await _guard(() async {
      _list = await _articles.list();
    });
  }

  /// 精读页首屏：列表 + 词库一起拉。
  Future<void> bootstrap() async {
    await _guard(() async {
      _list = await _articles.list();
      final loaded = await _vocab.load();
      _library = loaded ?? createLibrary();
      _libraryUpdatedAt = (await _vocab.meta())?.at;
    });
  }

  /// 打开一篇（会重新读一次词库，保证本篇词表是最新的）。
  Future<void> openArticle(String id) async {
    await _guard(() async {
      final article = await _articles.load(id);
      if (article == null) {
        _error = '这篇文章已经不在了';
        return;
      }
      final loaded = await _vocab.load();
      _library = loaded ?? createLibrary();
      _libraryUpdatedAt = (await _vocab.meta())?.at;
      _current = article;
      _selectedSentenceId = null;
      _flags = const ReaderViewFlagsInput();
    });
  }

  /// 关掉当前文章（返回列表）。
  void closeArticle() {
    _current = null;
    _selectedSentenceId = null;
    _flags = const ReaderViewFlagsInput();
    notifyListeners();
  }

  /// 选中 / 取消选中一句。
  void selectSentence(String? sentenceId) {
    if (_selectedSentenceId == sentenceId) return;
    _selectedSentenceId = sentenceId;
    notifyListeners();
  }

  /// 面板开关：从界面传进来，判定仍由 `readerViewFlags` 出。
  void updateFlags(ReaderViewFlagsInput flags) {
    _flags = flags;
    notifyListeners();
  }

  /// 标一个词（长按选词 / 侧栏点选都走这里）。
  ///
  /// 返回落库后的词条；失败（空词、库冲突重试仍失败）返回 null 并留 [error]。
  Future<VocabItem?> markCurrentWord(
    String word, {
    String? sentenceId,
    String? sentenceText,
    String? meaning,
    VocabItemKind? kind,
  }) async {
    final article = _current;
    if (article == null) {
      _error = '还没有打开文章';
      return null;
    }
    final input = analysis.MarkInput(
      word: word,
      articleId: article.id,
      fileName: article.book,
      sentenceId: sentenceId,
      sentenceText: sentenceText,
      meaning: meaning,
      kind: kind,
      origin: VocabOrigin.manual,
    );
    VocabItem? saved;
    await _guard(() async {
      final result = await _applyAndSave(
        (lib) => analysis.markWord(lib, input).library,
      );
      if (result == null) return;
      final lemma = lemmaOf(word);
      for (final it in result.items) {
        if (it.lemma == lemma) {
          saved = it;
          break;
        }
      }
    });
    return saved;
  }

  /// 对词库做一次纯函数变换并落盘；冲突时重读后**重放同一次变换**再写。
  ///
  /// 为什么要重放而不是「重读再拼一遍」：变换本身决定了写入内容，
  /// 重读后拿旧的变换结果去写，会把别人刚写的改动盖掉。
  Future<VocabLibrary?> _applyAndSave(
    VocabLibrary Function(VocabLibrary library) transform,
  ) async {
    var base = _library;
    for (var attempt = 0; attempt < 2; attempt++) {
      final next = transform(base);
      try {
        final saved = await _vocab.save(next, baseUpdatedAt: _libraryUpdatedAt);
        _library = next;
        _libraryUpdatedAt = saved.updatedAt;
        return next;
      } on VocabConflict {
        if (attempt == 1) {
          _error = '词库刚被别处改过，请重新打开这篇再标';
          return null;
        }
        base = await _vocab.load() ?? createLibrary();
        _libraryUpdatedAt = (await _vocab.meta())?.at;
      }
    }
    return null;
  }

  /// 把 AI 粘回来的自由文本落到某一句上（翻译 / 语法 / 搭配 / 生词）。
  ///
  /// 返回落到句子上的新对象；句子不存在或文本为空返回 null。
  Future<Sentence?> applySentenceAnalysis({
    required String sentenceId,
    required AnalysisTask task,
    required String raw,
  }) async {
    final article = _current;
    if (article == null) {
      _error = '还没有打开文章';
      return null;
    }
    Sentence? updated;
    await _guard(() async {
      final sentences = List<Sentence>.of(article.sentences);
      final idx = sentences.indexWhere((s) => s.id == sentenceId);
      if (idx < 0) {
        _error = '这一句已经不在了';
        return;
      }
      final next = applyToSentence(sentences[idx], task, raw);
      if (identical(next, sentences[idx])) {
        _error = '粘回的内容是空的';
        return;
      }
      sentences[idx] = next;
      final saved = article.copyWith(
        sentences: sentences,
        updatedAt: _nowIso(),
      );
      await _articles.save(saved);
      _current = saved;
      _list = await _articles.list();
      updated = next;
    });
    return updated;
  }

  /// 把查词 / 辨析结果写回词库（`applyWordAnalysis` 等纯函数由调用方给）。
  ///
  /// 与 [markCurrentWord] 共用同一条落盘路径（乐观锁 + 冲突重放）。
  Future<VocabLibrary?> applyLibraryTransform(
    VocabLibrary Function(VocabLibrary library) transform,
  ) async {
    VocabLibrary? out;
    await _guard(() async {
      out = await _applyAndSave(transform);
    });
    return out;
  }

  /// 把语言点 AI 结果落到文章里的若干句上。
  ///
  /// 走的是 `core/language.dart` 的 `parseLanguage` + `applyLanguage`：
  /// AI 生成的那条替换掉旧 AI 条，**手动添加的语言点保留**。
  /// 返回写进文章的条数；一条都没认出来返回 0 并留 [error]。
  Future<int> applyLanguageText(String raw) async {
    final article = _current;
    if (article == null) {
      _error = '还没有打开文章';
      return 0;
    }
    var applied = 0;
    await _guard(() async {
      final rows = parseLanguage(raw);
      if (rows.isEmpty) {
        _error = '没认出语言点，检查一下是不是粘错了';
        return;
      }
      final next = applyLanguage(article.sentences, rows);
      if (identical(next, article.sentences)) {
        _error = '粘回的内容没对上任何句子';
        return;
      }
      final saved = article.copyWith(
        sentences: next,
        updatedAt: _nowIso(),
      );
      await _articles.save(saved);
      _current = saved;
      _list = await _articles.list();
      final ids = {for (final r in rows) r.id};
      applied = next.where((s) => ids.contains(s.id)).length;
    });
    return applied;
  }

  String _nowIso() => DateTime.now().toUtc().toIso8601String();

  /// 粘贴一段正文新建一篇，成功后直接打开。
  Future<SavedArticle?> createFromPaste({
    required String raw,
    required String title,
  }) async {
    SavedArticle? created;
    await _guard(() async {
      created = await _imports.createFromText(raw: raw, title: title);
      if (created == null) {
        _error = '正文是空的，没法新建';
        return;
      }
      _list = await _articles.list();
      _current = created;
      _selectedSentenceId = null;
    });
    return created;
  }

  /// 删一篇（列表页长按删除）。
  Future<void> removeArticle(String id) async {
    await _guard(() async {
      await _articles.remove(id);
      if (_current?.id == id) _current = null;
      _list = await _articles.list();
    });
  }

  /// 统一的「忙 / 报错」包装：界面只读 [busy] / [error]。
  Future<void> _guard(Future<void> Function() run) async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await run();
    } catch (e) {
      _error = e.toString();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}
