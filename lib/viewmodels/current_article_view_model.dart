/// 全局「当前文章」：哪个模块要用「本篇」，都读这一份。
///
/// 由来（用户 2026-11-12 提的结构问题）：以前「本篇」是各模块自己的临时状态 ——
/// 背单词靠精读页的帧后回调推、产出训练与仿写的 `setArticleContext` 是死接口、
/// 速读和跟读各记各的。用户的心智模型是 Web 版：**主页面选中的那篇文章决定一切**。
///
/// 约定：
///   - 只有这一处能改「当前文章」（精读页的文章选择器、粘贴新建、删篇时的回落）；
///   - 其余模块只读，页内可以临时换一篇但不回写（读了速读顺带把背单词的本篇换掉很惊悚）；
///   - 默认 null（可能一篇都没有），不假装选了第一篇；
///   - 文章被删 / 库为空时读出来自动当没选，不返回悬空 id。
library;

import 'package:flutter/foundation.dart';

import '../core/current_article.dart';
import '../data/prefs_store.dart';
import '../data/repositories/article_repository.dart';

/// 当前文章 + 文章列表的唯一持有者。
class CurrentArticleViewModel extends ChangeNotifier {
  CurrentArticleViewModel({
    required ArticleRepository articlesRepo,
    PrefsStore? prefsStore,
  })  : _articles = articlesRepo,
        _store = prefsStore;


  final ArticleRepository _articles;
  final PrefsStore? _store;

  List<ArticleRow> _list = const <ArticleRow>[];
  String? _articleId;
  bool _busy = false;
  String? _error;

  /// 文章列表（按更新时间倒序，仓储保证）。
  List<ArticleRow> get articles => _list;

  /// 当前文章的 id；没选 / 那篇被删 / 库为空时都是 null。
  String? get articleId => _articleId;

  /// 当前那篇文章（列表里找不到时 null）。
  ArticleRow? get article {
    final id = _articleId;
    if (id == null) return null;
    for (final row in _list) {
      if (row.id == id) return row;
    }
    return null;
  }

  /// 当前文章标题；没选时给一句「还没选文章」（界面直接显示）。
  String get title => article?.title ?? '还没选文章';

  /// 有没有选中一篇（界面据此决定显示正文还是空态）。
  bool get hasArticle => article != null;

  bool get busy => _busy;
  String? get error => _error;

  /// 首屏：读列表 + 读回上次选的那篇。
  ///
  /// 先读列表再校验 id —— 反过来会把「文章被删了」误判成「没选过」。
  Future<void> bootstrap() async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      _list = await _articles.list();
      final saved = _store?.loadCurrentArticleId();
      final resolved = resolveCurrentArticleId(
        saved,
        _list.map((row) => row.id),
      );
      _articleId = resolved;
      // 脏 id（那篇被删了）顺手清掉，免得下次启动又白校验一遍。
      if (saved != null && resolved == null) {
        await _store?.saveCurrentArticleId(null);
      }
    } catch (e) {
      _error = '读文章列表失败：$e';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// 换一篇（null = 清掉当前文章）。
  ///
  /// 返回是否真的换了：同 id 重复调用不写盘、不通知。
  Future<bool> select(String? id) async {
    final next = parseCurrentArticleId(id);
    if (next == _articleId) return false;
    _articleId = next;
    notifyListeners();
    // 先改内存再落盘：选了就应该立刻生效，写偏好慢不该卡界面。
    await _store?.saveCurrentArticleId(next);
    return true;
  }

  /// 重新拉一次列表（新建 / 删除文章后调）。
  ///
  /// 当前那篇不在了就回落成 null —— **不自动选第一篇**（用户明确要 null）。
  Future<void> refresh() async {
    try {
      _list = await _articles.list();
      final resolved = resolveCurrentArticleId(
        _articleId,
        _list.map((row) => row.id),
      );
      if (resolved != _articleId) {
        _articleId = resolved;
        await _store?.saveCurrentArticleId(resolved);
      }
      _error = null;
    } catch (e) {
      _error = '读文章列表失败：$e';
    }
    notifyListeners();
  }
}
