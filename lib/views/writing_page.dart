/// 仿写：仿写训练 + 历史。
///
/// 两页一屏：仿写（范句 → AI 出题 → 我写 → AI 批改 → 落库）、历史（按来源 /
/// 范围筛选、载入回看、清空）。
///
/// 为什么是两页而不是一条长列表：出题与历史筛选的写入方不同 —— 仿写页改的是
/// 草稿，历史页改的是筛选条件与记录集合；混在一屏会让「换范句」顺手把筛选也
/// 重置掉。
library;

import 'package:flutter/material.dart';
import '../widgets/status_bar.dart';
import 'package:provider/provider.dart';

import '../viewmodels/writing_view_model.dart';
import 'writing_history_view.dart';
import 'writing_panel.dart';

/// 仿写页。
class WritingPage extends StatefulWidget {
  const WritingPage({super.key});

  @override
  State<WritingPage> createState() => _WritingPageState();
}

class _WritingPageState extends State<WritingPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<WritingViewModel>().bootstrap();
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<WritingViewModel>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('仿写'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const <Widget>[
            Tab(text: '仿写'),
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
                children: const <Widget>[
                  WritingPanel(),
                  WritingHistoryView(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
