import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../viewmodels/current_article_view_model.dart';
import '../viewmodels/study_view_model.dart';
import 'ai_batch_page.dart';
import 'articles_page.dart';
import 'drill_page.dart';
import 'golden_page.dart';
import 'intensive_page.dart';
import 'production_page.dart';
import 'settings_page.dart';
import 'shadowing_page.dart';
import 'speed_read_page.dart';
import 'study_page.dart';
import 'study_quick_sheet.dart' show showStudyQuickSheet;
import 'vocab_browse_page.dart';

/// 首页：九条主链路的入口 + 左侧抽屉（设置）。
///
/// 全部接通；「词库」是看收录情况的旁路页，「速读」是一句一句计时读、超时就地拷打，
/// 「D老师小课堂」是挑句、填空拼句与金句本，
/// 「跟读」是听标准音 + 自己读 + 当场判，
/// 「AI 跑批」是拿本机 key 批量补齐词库里缺的释义。
/// 备份不在这里 —— 它是低频操作，收在「左侧抽屉 → 设置 → 备份」。
/// 仿写也不在这里 —— 它是精读工作流的第 6 步，挂在「精读」卡片右边的按钮里。
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    // 首页要显示「候选 N 个」，所以进来先读一次词库。
    // 用可空查法：单独的 smoke 测试只挂 HomePage 时没有 Provider，不该炸。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final vm = context.read<StudyViewModel?>();
      if (vm != null && !vm.busy) vm.bootstrap();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final counts = context.select<StudyViewModel?, int>(
      (vm) => vm?.pools.counts.learn ?? 0,
    );
    // 没有注入时（纯组件测试）按「还没选文章」显示，不炸。
    final current = context.watch<CurrentArticleViewModel?>();
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(title: const Text('D哥帮你办')),
      drawer: const _HomeDrawer(),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('今天想练什么？', style: theme.textTheme.titleLarge),
          const SizedBox(height: 16),
          _EntryCard(
            icon: Icons.menu_book_outlined,
            title: '精读',
            subtitle: '逐句读、选词、看语言点',
            // 全局当前篇：标题太长就省略号，别把右边箭头挤走。
            note: (current?.articleId == null) ? '还没有选文章' : current!.title,
            onTap: () => _open(const ArticlesPage()),
            // 工作流（含仿写）收在精读里：它是「按篇」的一条流水线，不占首页一张卡。
            action: IconButton(
              key: const ValueKey('home-intensive'),
              tooltip: '精读工作流',
              icon: const Icon(Icons.route_outlined, size: 20),
              onPressed: () => _open(const IntensivePage()),
            ),
          ),
          _EntryCard(
            icon: Icons.style_outlined,
            title: '背单词',
            subtitle: '单词与搭配分开背',
            note: counts > 0 ? '可学 $counts 个' : null,
            onTap: () => _open(const StudyPage()),
            // 牌组每天可能换，留在这一行直接改，不必进设置页。
            action: IconButton(
              tooltip: '牌组',
              icon: const Icon(Icons.tune, size: 20),
              onPressed: () => showStudyQuickSheet(context),
            ),
          ),
          _EntryCard(
            icon: Icons.folder_open_outlined,
            title: '词库',
            subtitle: '按范围 / 状态 / 日期筛，看全部收录',
            onTap: () => _open(const VocabBrowsePage()),
          ),
          _EntryCard(
            icon: Icons.speed_outlined,
            title: '速读',
            subtitle: '一句一句计时读，超时就地拷打',
            onTap: () => _open(const SpeedReadPage()),
          ),
          _EntryCard(
            icon: Icons.edit_note_outlined,
            title: 'D老师奶牛工棚',
            subtitle: '全脂 / 脱脂 / 风味酸奶，AI 出题与批改',
            onTap: () => _open(const ProductionPage()),
          ),
          _EntryCard(
            icon: Icons.sports_mma_outlined,
            title: '拷打',
            subtitle: '拼写 / 选义 / 搭配，按本篇的词出题',
            onTap: () => _open(const DrillPage()),
          ),
          _EntryCard(
            icon: Icons.school_outlined,
            title: 'D老师小课堂',
            subtitle: '挑金句、填空拼句、全库金句本',
            onTap: () => _open(const GoldenPage()),
          ),
          _EntryCard(
            icon: Icons.record_voice_over_outlined,
            title: '跟读',
            subtitle: '听标准音、自己读、当场判一下',
            onTap: () => _open(const ShadowingPage()),
          ),
          _EntryCard(
            icon: Icons.smart_toy_outlined,
            title: 'AI 跑批',
            subtitle: '批量补齐词库里缺的释义',
            onTap: () => _open(const AiBatchPage()),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  void _open(Widget page) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }
}

/// 左侧抽屉：设置入口 + 以后的「所有设置都放这里」。
///
/// 照 patrol_helper 的写法：**不先关抽屉**，直接把设置页压在抽屉上。
/// 这样从设置页返回时抽屉还在原处，用户能接着点别的，而不是被打回首页重开。
class _HomeDrawer extends StatelessWidget {
  const _HomeDrawer();

  void _openSettings(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const SettingsPage()));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(color: scheme.primaryContainer),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text('D哥帮你办', style: theme.textTheme.titleLarge),
                      const SizedBox(height: 4),
                      Text(
                        '精读 · 背单词 · 速读 · 产出',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '设置',
                  icon: const Icon(Icons.settings),
                  onPressed: () => _openSettings(context),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('设置'),
            onTap: () => _openSettings(context),
          ),
          const Divider(height: 1),
        ],
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.note,
    this.onTap,
    this.action,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  /// 小字备注（比如「候选 10892 个」）。
  final String? note;

  /// 接通了才给：未接通的入口点了没反应比显示「开发中」更糟。
  final VoidCallback? onTap;

  /// 右侧额外的小按键（目前只有背单词用：范围与牌组）。
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final enabled = onTap != null;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(icon, color: enabled ? theme.colorScheme.primary : muted),
        title: Row(
          children: [
            Text(title),
            if (note != null) ...[
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  note!,
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
        subtitle: Text(subtitle),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ?action,
            if (enabled)
              const Icon(Icons.chevron_right)
            else
              Text('开发中', style: TextStyle(color: muted)),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}
