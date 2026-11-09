import 'package:flutter/material.dart';
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
            if (vm.error != null) _ErrorBar(message: vm.error!),
            if (vm.busy) const LinearProgressIndicator(),
            if (vm.notice.isNotEmpty)
              _NoticeBar(message: vm.notice, onClose: vm.clearNotice),
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

/// 本页自己的错误条（`_ErrorBar` 是各文件私有类，跨文件复用不了）。
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

/// 一次性提示，可关掉。
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
