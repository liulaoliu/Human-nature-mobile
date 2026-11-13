/// 把全局「当前文章」推给需要它的模块（背单词 / 产出训练 / 小课堂仿写）。
///
/// 为什么要有这一层：以前只有精读页 `reader_page.dart` 在帧后回调里把文章
/// 推给 `StudyViewModel`，于是「不打开精读页，背单词的『本篇』永远是空的」；
/// 而产出训练与小课堂的 `setArticleContext` 根本没人调（死接口）。
/// 用户（2026-11-12）的心智模型是 Web 版：**主页面选的那篇决定一切**，
/// 所以这份推送必须挂在 App 根上，跟当前在哪个页面无关。
///
/// 写法上是「读全局 → 推给各模块」，不是让各模块互相持有：
/// 模块之间仍然互不认识，只有这里知道谁需要哪份上下文。
///
/// 为什么要 addListener 而不是 `context.watch`：这里要在**状态变化后**做 IO
/// （读那篇文章拿正文词集合），不能在 build 里发起；挂在 VM 的监听上最直接。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/production.dart' show productionDocLemmas;
import '../data/repositories/article_repository.dart';
import '../viewmodels/current_article_view_model.dart';
import '../viewmodels/production_view_model.dart';
import '../viewmodels/study_view_model.dart';
import '../viewmodels/writing_view_model.dart';

/// 挂在 `MaterialApp` 之上、所有 Provider 之内。
class ArticleContextSync extends StatefulWidget {
  const ArticleContextSync({super.key, required this.child});

  final Widget child;

  @override
  State<ArticleContextSync> createState() => _ArticleContextSyncState();
}

class _ArticleContextSyncState extends State<ArticleContextSync> {
  /// 上次推下去的文章 id（判重：同一篇不重复写）。
  String? _synced;

  /// 正在做 IO；期间又来一次变更就排队重跑一次（用户连点两篇）。
  bool _running = false;
  bool _dirty = false;

  CurrentArticleViewModel? _current;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final vm = context.read<CurrentArticleViewModel>();
    if (identical(vm, _current)) return;
    _current?.removeListener(_onChanged);
    _current = vm..addListener(_onChanged);
    // 开机就要把「上次那篇」读回来：只靠精读页 `initState` 里的 bootstrap，
    // 首页在没进过精读页之前会一直显示「还没有选文章」（2026-11-13 实测踩到）。
    // 必须帧后调：`didChangeDependencies` 在 build 期间，VM 里第一句就
    // `notifyListeners()`，直接调会撞 `setState() called during build`。
    if (!vm.busy && vm.articleId == null && vm.articles.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(vm.bootstrap());
      });
    }
    _onChanged();
  }

  void _onChanged() {
    if (_running) {
      _dirty = true;
      return;
    }
    _running = true;
    // 帧后跑：监听回调可能来自 build 期间的另一处 notifyListeners。
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        do {
          _dirty = false;
          await _sync();
        } while (_dirty && mounted);
      } finally {
        _running = false;
      }
    });
  }

  Future<void> _sync() async {
    if (!mounted) return;
    final id = _current?.articleId;
    if (id == _synced) return;
    _synced = id;

    // 没选文章：把三个模块的上下文一起清掉，界面显示「还没选文章」而不是留着上一篇。
    if (id == null) {
      context.read<StudyViewModel?>()?.setArticleContext(null);
      context.read<ProductionViewModel?>()?.setArticleContext(null);
      context.read<WritingViewModel?>()?.setArticleContext(null);
      return;
    }

    // 正文词集合（正文词 + 语言点词）：产出训练与背单词的「本篇」都认这个。
    Set<String> docLemmas = const <String>{};
    var title = '';
    try {
      final article = await context.read<ArticleRepository>().load(id);
      if (article != null) {
        title = article.title;
        docLemmas = productionDocLemmas(article.sentences);
      }
    } catch (_) {
      // 读不到就当没有 docLemmas：各模块还有 articleEntries 那条路。
    }
    if (!mounted) return;

    context.read<StudyViewModel?>()?.setArticleContext(id, docLemmas: docLemmas);
    context.read<ProductionViewModel?>()?.setArticleContext(
          id,
          articleTitle: title,
          docLemmas: docLemmas,
        );
    context.read<WritingViewModel?>()?.setArticleContext(
          id,
          articleTitle: title,
        );
  }

  @override
  void dispose() {
    _current?.removeListener(_onChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
