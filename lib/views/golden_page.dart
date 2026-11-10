import 'package:flutter/material.dart';
import '../widgets/status_bar.dart';
import 'package:provider/provider.dart';

import '../viewmodels/golden_view_model.dart';
import 'golden_bank_view.dart';
import 'golden_drill_view.dart';
import 'golden_history_view.dart';
import 'golden_plan_view.dart';

/// D老师小课堂（金句课）：挑句 → 逐句拷打 → 小结 → 金句本 / 历史。
///
/// 为什么是 Tab 而不是一条长列表：挑句、练习、复习是三种写入方
/// （改课程 / 记进度 / 只读），混一屏会让「换设置」和「换句子」互相踩。
class GoldenPage extends StatefulWidget {
  const GoldenPage({super.key});

  @override
  State<GoldenPage> createState() => _GoldenPageState();
}

class _GoldenPageState extends State<GoldenPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<GoldenViewModel>().bootstrap();
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _goDrill() {
    if (_tabs.index != 1) _tabs.animateTo(1);
  }

  void _goPlan() {
    if (_tabs.index != 0) _tabs.animateTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<GoldenViewModel>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('D老师小课堂'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const <Widget>[
            Tab(text: '挑句'),
            Tab(text: '练习'),
            Tab(text: '金句本'),
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
                  GoldenPlanView(onStarted: _goDrill),
                  GoldenDrillView(onGoPlan: _goPlan),
                  const GoldenBankView(),
                  const GoldenHistoryView(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
