import 'package:flutter/material.dart';
import '../widgets/status_bar.dart';
import 'package:provider/provider.dart';

import '../viewmodels/production_view_model.dart';
import 'production_history_view.dart';
import 'production_run.dart';
import 'production_setup.dart';

/// D老师奶牛工棚：全脂 / 脱脂奶 / 风味酸奶三种吃法。
///
/// 三页一屏：出题（设置 + AI 出题）→ 练习（作答 + AI 批改）→ 历史（统计 + 错因）。
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
        title: const Text('D老师奶牛工棚'),
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
            if (vm.error != null) StatusBar.error(message: vm.error!),
            if (vm.busy) const LinearProgressIndicator(),
            if (vm.notice.isNotEmpty)
              StatusBar.notice(message: vm.notice, onClose: vm.clearNotice),
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
