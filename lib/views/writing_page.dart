/// 小课堂：仿写训练 + 历史。
///
/// 两页一屏：仿写（范句 → AI 出题 → 我写 → AI 批改 → 落库）、历史（按来源 /
/// 范围筛选、载入回看、清空）。
///
/// 为什么是两页而不是一条长列表：出题与历史筛选的写入方不同 —— 仿写页改的是
/// 草稿，历史页改的是筛选条件与记录集合；混在一屏会让「换范句」顺手把筛选也
/// 重置掉。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../viewmodels/writing_view_model.dart';
import 'writing_history_view.dart';
import 'writing_panel.dart';

/// 小课堂页。
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
        title: const Text('小课堂'),
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
            if (vm.error != null) _ErrorBar(message: vm.error!),
            if (vm.busy) const LinearProgressIndicator(),
            if (vm.notice.isNotEmpty)
              _NoticeBar(message: vm.notice, onClose: vm.clearNotice),
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

/// 本页自己的错误条（`_ErrorBar` 是私有类，跨文件复用不了）。
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
