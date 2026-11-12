/// 词库浏览页的 ViewModel：把筛选条件攒成一个 [VocabBrowseInput]，
/// 结果全交给 `core/vocab_browse.dart` 算 —— 这里只做「读库 / 传条件 / 排序」。
///
/// 为什么筛选不放界面：`browseVocab` 的口径（已掌握怎么算、日期怎么分天、
/// 本篇怎么认别名）都有测试兜着，界面自己再拼一遍布尔就必然漂移。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/article_vocab.dart' show articleEntries;
import '../core/vocab/library.dart';
import '../core/vocab_browse.dart';
import '../core/vocab_browse_prefs.dart';
import '../data/prefs_store.dart';
import '../data/repositories/article_repository.dart';
import '../data/repositories/vocab_repository.dart';
import '../models/vocab.dart';
import 'current_article_view_model.dart';

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
  BrowseStatus.due: '复习',
  BrowseStatus.fresh: '未学习',
  BrowseStatus.lapsed: '忘记',
  BrowseStatus.mastered: '已掌握',
};

/// 排序名 → 枚举；认不出就按「最近」。
///
/// 放在文件级而不是类方法里：`VocabBrowseViewModel` 的方法数贴着 40 的门禁，
/// 「字符串转枚举」这种纯换算不该占名额，也不值得再开一个 core 模块。
BrowseSort browseSortOf(String name) {
  for (final s in BrowseSort.values) {
    if (s.name == name) return s;
  }
  return BrowseSort.recent;
}

/// 到期排序的键：没有 due 的排最后，其余按时间升序。
///
/// 同样放文件级：纯换算，不占 ViewModel 的方法数（那个类贴着 40 的门禁）。
String browseDueKey(VocabItem item) => item.reviewState.due ?? '~';

/// 按 [sort] 排一份新列表（不改入参）。
///
/// 放文件级的理由同上；也方便单测直接盯排序口径。
List<VocabItem> sortBrowseItems(List<VocabItem> source, BrowseSort sort) {
  final list = List<VocabItem>.of(source);
  switch (sort) {
    case BrowseSort.recent:
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    case BrowseSort.alphabet:
      list.sort((a, b) => a.lemma.compareTo(b.lemma));
    case BrowseSort.due:
      list.sort((a, b) => browseDueKey(a).compareTo(browseDueKey(b)));
  }
  return list;
}

/// 词库浏览页的状态。
class VocabBrowseViewModel extends ChangeNotifier {
  VocabBrowseViewModel({
    required VocabRepository vocab,
    required ArticleRepository articles,
    CurrentArticleViewModel? currentArticle,
    PrefsStore? prefsStore,
  })  : _vocabRepo = vocab,
        _articlesRepo = articles,
        _store = prefsStore {
    // 本篇 = 全局当前文章（精读页选的那篇）。没注入就是「没有本篇」。
    _current = currentArticle;
    _current?.addListener(_onCurrentChanged);
    // 面板条件跨会话记住：进页面看到的就是上次那套。
    // 没存过 → 保持 `VocabBrowsePrefs()` 的默认值（本篇 / 单词 / 复习）。
    final saved = _store?.loadVocabBrowsePrefs();
    if (saved != null) _applyPrefs(saved);
  }

  final VocabRepository _vocabRepo;
  final ArticleRepository _articlesRepo;
  final PrefsStore? _store;

  /// 全局当前文章（只读）。
  CurrentArticleViewModel? _current;

  VocabLibrary _library = createLibrary();
  List<BrowseArticleRef> _articles = const [];
  bool _busy = false;
  String? _error;

  BrowseScope _scope = const VocabBrowsePrefs().scope;
  BrowseKind _kind = const VocabBrowsePrefs().kind;
  BrowseStatus _status = const VocabBrowsePrefs().status;
  BrowseSort _sort = BrowseSort.recent;
  String _query = '';
  Set<String> _days = const <String>{};

  /// 「选篇」临时看的那一篇（null = 没选）。
  ///
  /// 只影响词库页的浏览范围，**不回写全局当前文章** —— 用户（2026-11-12）
  /// 的心智模型是「精读页选的那篇决定一切」，词库这里只是临时换个视角。
  String? _pickedId;

  bool _includeMastered = false;

  /// 上次算好的筛选结果与排序后的列表。
  ///
  /// `build()` 里 `items`（标题条数、空态、列表长度）与 `scopeCount` /
  /// `dayOptions` / `articleCounts` 会各取一次，词库几千条时等于**每帧整库扫七八遍**、
  /// 还要额外排序两次。条件只在 setter 里改，所以按「条件变了才重算」缓存。
  ///
  /// 返回的是同一个列表实例，调用方只读，别原地排序 / 增删。
  VocabBrowseResult? _cachedResult;
  List<VocabItem>? _cachedItems;

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

  /// 「选篇」看的那一篇（null = 没选）。
  String? get pickedArticleId => _pickedId;

  bool get includeMastered => _includeMastered;

  /// 当前筛选结果（已排序）。
  ///
  /// 同一组条件下返回同一个列表实例（缓存），调用方只读。
  List<VocabItem> get items => _cachedItems ??= sortBrowseItems(_result.items, _sort);

  /// 未排序的筛选结果（日期 / 每篇条数也在这里）。
  VocabBrowseResult get result => _result;

  /// 当前范围里出现过的入库日（倒序）+ 条数。
  List<({String day, int count})> get dayOptions => _result.days;

  /// 选篇列表每篇的条数。
  Map<String, int> get articleCounts => _result.articleCounts;

  /// 范围 + 含已掌握之后的条数（筛选前）。
  int get scopeCount => _result.scopeCount;

  VocabBrowseResult get _result => _cachedResult ??= _compute();

  VocabBrowseResult _compute() {
    debugComputeCount += 1;
    return browseVocab(_input);
  }

  /// 算过几次筛选（只给测试用：验证同一组条件不会重复整库扫）。
  @visibleForTesting
  int debugComputeCount = 0;

  /// 条件变了就丢缓存 —— 所有改**筛选条件**的 setter 与 `bootstrap()` 都走这一句。
  ///
  /// [keepResult] 给「只改排序」用：筛选结果没变，没必要整库重扫，
  /// 丢掉排好序的那份重新排一次就够。
  void _invalidate({bool keepResult = false}) {
    if (!keepResult) _cachedResult = null;
    _cachedItems = null;
  }

  VocabBrowseInput get _input => VocabBrowseInput(
        items: _library.items,
        scope: _scope,
        articleId: _scope == BrowseScope.article ? currentArticleId : null,
        articleEntries: articleEntries(_library),
        articles: _articles,
        // 核心层按「集合」取并集；界面上已经收成单选，这里只传一个。
        pickedArticleIds: _pickedId == null ? const <String>{} : {_pickedId!},
        kind: _kind,
        query: _query.trim().toLowerCase(),
        days: _days,
        status: _status,
        includeMastered: _includeMastered,
      );

  /// 当前指向的篇。
  ///
  /// 「本篇」= **全局当前文章**（精读页选的那一篇），这里只读不写：
  /// 用户（2026-11-12）明确「主页面选的那篇决定一切」，词库不该有第二份「哪一篇」。
  String? get currentArticleId => _current?.articleId;

  /// 全局当前文章的标题（没选文章时 null）。
  String? get currentArticleTitle => _current?.article?.title;

  /// 全局那篇变了：筛选结果要重算（词库页可能正停在「本篇」）。
  void _onCurrentChanged() {
    _invalidate();
    notifyListeners();
  }

  /// 读词库 + 文章列表（进页面调一次）。
  Future<void> bootstrap() async {
    await _guard(() async {
      _library = await _vocabRepo.load() ?? createLibrary();
      final rows = await _articlesRepo.list();
      _articles = [
        for (final r in rows) BrowseArticleRef(id: r.id, title: r.title),
      ];
      // 没选文章（或那篇被删了）时「本篇」没东西可看：退回全部，别停在空列表上。
      if (_scope == BrowseScope.article && currentArticleId == null) {
        _scope = BrowseScope.all;
      }
      // 选篇选的那篇被删了：清掉，退回全部。
      if (_pickedId != null &&
          !_articles.any((a) => a.id == _pickedId)) {
        _pickedId = null;
      }
      if (_scope == BrowseScope.picked && _pickedId == null) {
        _scope = BrowseScope.all;
      }
      // 库 / 文章列表换了，缓存一律作废。
      _invalidate();
      // 剔掉已删的篇之后的选择也要落盘，不然下次启动又要重剔一遍。
      _persist();
    });
  }

  void setScope(BrowseScope value) {
    if (_scope == value) return;
    _scope = value;
    _invalidate();
    _persist();
    notifyListeners();
  }

  void setKind(BrowseKind value) {
    if (_kind == value) return;
    _kind = value;
    _invalidate();
    _persist();
    notifyListeners();
  }

  void setStatus(BrowseStatus value) {
    if (_status == value) return;
    _status = value;
    _invalidate();
    _persist();
    notifyListeners();
  }

  void setSort(BrowseSort value) {
    if (_sort == value) return;
    _sort = value;
    // 排序不影响筛选结果，别为了换个顺序把整库重扫一遍。
    _invalidate(keepResult: true);
    _persist();
    notifyListeners();
  }

  void setQuery(String value) {
    if (_query == value) return;
    _query = value;
    _invalidate();
    notifyListeners();
  }

  void toggleDay(String day) {
    final next = Set<String>.of(_days);
    if (!next.remove(day)) next.add(day);
    _days = next;
    _invalidate();
    _persist();
    notifyListeners();
  }

  void clearDays() {
    if (_days.isEmpty) return;
    _days = const <String>{};
    _invalidate();
    _persist();
    notifyListeners();
  }

  /// 选篇：临时挑另一篇看（null = 没选）。
  void setPickedArticle(String? articleId) {
    final next = (articleId ?? '').trim();
    final normalized = next.isEmpty ? null : next;
    if (_pickedId == normalized) return;
    _pickedId = normalized;
    _invalidate();
    _persist();
    notifyListeners();
  }

  void setIncludeMastered(bool value) {
    if (_includeMastered == value) return;
    _includeMastered = value;
    _invalidate();
    _persist();
    notifyListeners();
  }

  /// 一次换成一组日期（下拉里选「最近 7 天」这类预设时用）。
  void setDays(Set<String> value) {
    if (_days.length == value.length && _days.containsAll(value)) return;
    _days = Set<String>.of(value);
    _invalidate();
    _persist();
    notifyListeners();
  }

  /// 把面板上的条件读回内存（构造时用；也会作废缓存）。
  void _applyPrefs(VocabBrowsePrefs prefs) {
    _scope = prefs.scope;
    _kind = prefs.kind;
    _status = prefs.status;
    _sort = browseSortOf(prefs.sort);
    _includeMastered = prefs.includeMastered;
    _pickedId = prefs.pickedArticleId;
    _days = prefs.days;
    _invalidate();
  }

  /// 当前条件（写回 `shared_preferences` 的形状）。
  VocabBrowsePrefs get prefs => VocabBrowsePrefs(
        scope: _scope,
        kind: _kind,
        status: _status,
        sort: _sort.name,
        includeMastered: _includeMastered,
        pickedArticleId: _pickedId,
        days: _days,
      );

  /// 每次条件变了就写盘。**不 await**：写偏好失败不该卡住界面，
  /// 丢了最多下次重选一遍。
  void _persist() {
    final store = _store;
    if (store == null) return;
    unawaited(store.saveVocabBrowsePrefs(prefs));
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

  @override
  void dispose() {
    _current?.removeListener(_onCurrentChanged);
    super.dispose();
  }
}
