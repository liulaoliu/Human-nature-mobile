/// 词库浏览页的 ViewModel：把筛选条件攒成一个 [VocabBrowseInput]，
/// 结果全交给 `core/vocab_browse.dart` 算 —— 这里只做「读库 / 传条件 / 排序」。
///
/// 为什么筛选不放界面：`browseVocab` 的口径（已掌握怎么算、日期怎么分天、
/// 本篇怎么认别名）都有测试兜着，界面自己再拼一遍布尔就必然漂移。
library;

import 'package:flutter/foundation.dart';

import '../core/article_vocab.dart' show articleEntries;
import '../core/vocab/library.dart';
import '../core/vocab_browse.dart';
import '../data/repositories/article_repository.dart';
import '../data/repositories/vocab_repository.dart';
import '../models/vocab.dart';

/// 列表排序口径。
enum BrowseSort {
  /// 最近收的在前（`createdAt` 倒序）。
  recent,

  /// 字母序（按 lemma）。
  alphabet,

  /// 快到期 / 已逾期的在前。
  due,
}

/// 排序口径的中文名。
const Map<BrowseSort, String> browseSortLabel = <BrowseSort, String>{
  BrowseSort.recent: '最近',
  BrowseSort.alphabet: '字母',
  BrowseSort.due: '到期',
};

/// 范围 / 类型 / 状态的中文名。
const Map<BrowseScope, String> browseScopeLabel = <BrowseScope, String>{
  BrowseScope.all: '全部',
  BrowseScope.article: '本篇',
  BrowseScope.picked: '选篇',
};

const Map<BrowseKind, String> browseKindLabel = <BrowseKind, String>{
  BrowseKind.all: '全部',
  BrowseKind.word: '单词',
  BrowseKind.lang: '语言点',
};

const Map<BrowseStatus, String> browseStatusLabel = <BrowseStatus, String>{
  BrowseStatus.all: '全部',
  BrowseStatus.due: '该复习',
  BrowseStatus.fresh: '没学过',
  BrowseStatus.lapsed: '忘过',
  BrowseStatus.mastered: '已掌握',
};

/// 词库浏览页的状态。
class VocabBrowseViewModel extends ChangeNotifier {
  VocabBrowseViewModel({
    required VocabRepository vocab,
    required ArticleRepository articles,
  })  : _vocabRepo = vocab,
        _articlesRepo = articles;

  final VocabRepository _vocabRepo;
  final ArticleRepository _articlesRepo;

  VocabLibrary _library = createLibrary();
  List<BrowseArticleRef> _articles = const [];
  bool _busy = false;
  String? _error;

  BrowseScope _scope = BrowseScope.all;
  BrowseKind _kind = BrowseKind.all;
  BrowseStatus _status = BrowseStatus.all;
  BrowseSort _sort = BrowseSort.recent;
  String _query = '';
  Set<String> _days = const <String>{};
  Set<String> _picked = const <String>{};
  bool _includeMastered = false;

  /// 整个词库。
  VocabLibrary get library => _library;

  /// 可选的篇（选篇 / 本篇下拉用）。
  List<BrowseArticleRef> get articles => _articles;

  bool get busy => _busy;
  String? get error => _error;

  BrowseScope get scope => _scope;
  BrowseKind get kind => _kind;
  BrowseStatus get status => _status;
  BrowseSort get sort => _sort;
  String get query => _query;
  Set<String> get days => _days;
  Set<String> get pickedArticleIds => _picked;
  bool get includeMastered => _includeMastered;

  /// 当前筛选结果（已排序）。
  List<VocabItem> get items {
    final result = _result;
    final list = List<VocabItem>.of(result.items);
    switch (_sort) {
      case BrowseSort.recent:
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case BrowseSort.alphabet:
        list.sort((a, b) => a.lemma.compareTo(b.lemma));
      case BrowseSort.due:
        list.sort((a, b) => _dueKey(a).compareTo(_dueKey(b)));
    }
    return list;
  }

  /// 未排序的筛选结果（日期 / 每篇条数也在这里）。
  VocabBrowseResult get result => _result;

  /// 当前范围里出现过的入库日（倒序）+ 条数。
  List<({String day, int count})> get dayOptions => _result.days;

  /// 选篇列表每篇的条数。
  Map<String, int> get articleCounts => _result.articleCounts;

  /// 范围 + 含已掌握之后的条数（筛选前）。
  int get scopeCount => _result.scopeCount;

  VocabBrowseResult get _result => browseVocab(_input);

  VocabBrowseInput get _input => VocabBrowseInput(
        items: _library.items,
        scope: _scope,
        articleId: _scope == BrowseScope.article ? currentArticleId : null,
        articleEntries: articleEntries(_library),
        articles: _articles,
        pickedArticleIds: _picked,
        kind: _kind,
        query: _query.trim().toLowerCase(),
        days: _days,
        status: _status,
        includeMastered: _includeMastered,
      );

  /// 本篇范围指定的那一篇（没指定就取列表第一篇）。
  String? _articleIdOverride;

  /// 本篇范围当前指向的篇。
  String? get currentArticleId =>
      _articleIdOverride ?? (_articles.isEmpty ? null : _articles.first.id);

  void setCurrentArticle(String id) {
    if (currentArticleId == id) return;
    _articleIdOverride = id;
    notifyListeners();
  }

  /// 到期排序的键：没有 due 的排最后，其余按时间升序。
  String _dueKey(VocabItem item) => item.reviewState.due ?? '~';

  /// 读词库 + 文章列表（进页面调一次）。
  Future<void> bootstrap() async {
    await _guard(() async {
      _library = await _vocabRepo.load() ?? createLibrary();
      final rows = await _articlesRepo.list();
      _articles = [
        for (final r in rows) BrowseArticleRef(id: r.id, title: r.title),
      ];
      // 选中的篇被删了：退回全部，别停在空列表上。
      if (_scope == BrowseScope.article && _articles.isEmpty) {
        _scope = BrowseScope.all;
      }
      _picked = {
        for (final id in _picked)
          if (_articles.any((a) => a.id == id)) id,
      };
      if (_picked.isEmpty && _scope == BrowseScope.picked) {
        _scope = BrowseScope.all;
      }
    });
  }

  void setScope(BrowseScope value) {
    if (_scope == value) return;
    _scope = value;
    notifyListeners();
  }

  void setKind(BrowseKind value) {
    if (_kind == value) return;
    _kind = value;
    notifyListeners();
  }

  void setStatus(BrowseStatus value) {
    if (_status == value) return;
    _status = value;
    notifyListeners();
  }

  void setSort(BrowseSort value) {
    if (_sort == value) return;
    _sort = value;
    notifyListeners();
  }

  void setQuery(String value) {
    if (_query == value) return;
    _query = value;
    notifyListeners();
  }

  void toggleDay(String day) {
    final next = Set<String>.of(_days);
    if (!next.remove(day)) next.add(day);
    _days = next;
    notifyListeners();
  }

  void clearDays() {
    if (_days.isEmpty) return;
    _days = const <String>{};
    notifyListeners();
  }

  void togglePicked(String articleId) {
    final next = Set<String>.of(_picked);
    if (!next.remove(articleId)) next.add(articleId);
    _picked = next;
    notifyListeners();
  }

  void setIncludeMastered(bool value) {
    if (_includeMastered == value) return;
    _includeMastered = value;
    notifyListeners();
  }

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
