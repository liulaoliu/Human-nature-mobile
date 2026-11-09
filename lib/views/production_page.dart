import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../viewmodels/production_view_model.dart';
import 'production_history_view.dart';
import 'production_run.dart';
import 'production_setup.dart';

/// 产出训练（奶牛工棚）：全脂 / 脱脂奶 / 风味酸奶三种吃法。
///
/// 三页一屏：出题（设置 + 粘回）→ 练习（作答 + 批改）→ 历史（统计 + 错因）。
/// 为什么分页而不是一条长列表：出题和作答的写入方不同，混在一屏会让
/// 「换设置」和「换题」互相踩；分页后每页只读自己那一组状态。
class ProductionPage extends StatefulWidget {
  const ProductionPage({super.key});

  @override
  State<ProductionPage> createState() => _ProductionPageState();
}

class _ProductionPageState extends State<ProductionPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ProductionViewModel>().bootstrap();
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _goRun() {
    if (_tabs.index != 1) _tabs.animateTo(1);
  }

  void _goSetup() {
    if (_tabs.index != 0) _tabs.animateTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ProductionViewModel>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('产出训练'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const <Widget>[
            Tab(text: '出题'),
            Tab(text: '练习'),
            Tab(text: '历史'),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            if (vm.error != null) _ErrorBar(message: vm.error!),
            if (vm.busy) const LinearProgressIndicator(),
            if (vm.notice.isNotEmpty)
              _NoticeBar(message: vm.notice, onClose: vm.clearNotice),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: <Widget>[
                  ProductionSetupView(onStarted: _goRun),
                  ProductionRunView(onGoSetup: _goSetup),
                  const ProductionHistoryView(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 本页自己的错误条（各页各写一版：`_ErrorBar` 是私有类，跨文件复用不了）。
class _ErrorBar extends StatelessWidget {
  const _ErrorBar({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.errorContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Text(message, style: TextStyle(color: scheme.onErrorContainer)),
    );
  }
}

/// 一次性提示（选块回退、句数不一致、草稿已存），可关掉。
class _NoticeBar extends StatelessWidget {
  const _NoticeBar({required this.message, required this.onClose});

  final String message;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.secondaryContainer,
      padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: scheme.onSecondaryContainer),
            ),
          ),
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.close, size: 18),
            tooltip: '知道了',
          ),
        ],
      ),
    );
  }
}
